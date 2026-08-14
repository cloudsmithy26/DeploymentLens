/**
 * DocConversionProvider
 * -----------------------
 * Performs the conversion of a .docx file to PDF using Adobe's PDF Services
 * API (Create PDF operation). Same public interface as before
 * (convertDocxToPdf) so DocToPdfController.cls doesn't need to change.
 *
 * Adobe's flow is a multi-step ASYNC job, not a single request/response:
 *   1. Create an "asset" placeholder -> get back an assetID + a pre-signed
 *      uploadUri
 *   2. PUT the raw docx bytes to that uploadUri (direct to Adobe's storage,
 *      not the API domain)
 *   3. Submit a Create PDF job referencing the assetID -> get back a polling
 *      URL (Location header)
 *   4. Poll that URL until the job status is "done" (or "failed")
 *   5. GET the resulting PDF from the pre-signed downloadUri in the final
 *      poll response
 *
 * AUTH: token acquisition is handled by the Named Credential / External
 * Credential ("Adobe_PDF_Services", OAuth 2.0 Client Credentials with Client
 * Secret Flow) — Salesforce fetches, caches, and attaches the Bearer token
 * automatically to every callout made through callout:Adobe_PDF_Services,
 * so this class no longer calls /token or sets an Authorization header
 * itself. Adobe additionally requires an X-API-Key header set to the Client
 * ID (a separate, non-secret requirement on top of standard OAuth), which
 * this class still sets manually via getClientId().
 *
 * SETUP REQUIRED BEFORE USE:
 * 1. Get Adobe PDF Services credentials (client_id / client_secret) from
 *    https://developer.adobe.com/document-services/ -> "Get Credentials".
 * 2. External Credential "Adobe_PDF_Services": Authentication Protocol =
 *    OAuth 2.0, Authentication Flow Type = Client Credentials with Client
 *    Secret Flow, Identity Provider URL = https://ims-na1.adobelogin.com/ims/token/v3
 *    (Adobe's actual IMS token endpoint — NOT pdf-services.adobe.io/token),
 *    "Pass client credentials in request body" checked, and a Scope value
 *    set (required by Adobe's IMS token endpoint — check the "Generate
 *    access token" button on your credential's page in the Adobe Developer
 *    Console for the exact scope string your credential expects, commonly
 *    something like openid,AdobeID,DCAPI). Add a Principal with the Client
 *    ID / Client Secret, and grant access via External Credential Principal
 *    Access. ims-na1.adobelogin.com must also be reachable (Adobe lists it
 *    as a required allow-listed hostname).
 * 3. Named Credential "Adobe_PDF_Services": URL = https://pdf-services.adobe.io,
 *    linked to the External Credential above, "Generate Authorization Header"
 *    and "Enabled for Callouts" both checked.
 * 4. Store the Client ID somewhere Apex can read it (Custom Metadata Type is
 *    a good fit — it isn't secret the way the Client Secret is, since it's
 *    just an identifier sent as a plain header) and wire up getClientId()
 *    below.
 * 5. Remote Site Settings for the pre-signed upload/download URLs: these
 *    land on Adobe's storage domain, which varies per call and isn't known
 *    ahead of time, so a Named Credential can't pin to it. Add a Remote Site
 *    Setting covering Adobe's storage domain pattern (check the actual
 *    uploadUri/downloadUri host the first time you run this and allowlist
 *    it), or ask your Salesforce admin about wildcard Remote Site Settings.
 * 6. Apex has no synchronous sleep — the poll loop below retries immediately
 *    in a bounded loop rather than waiting between polls. That's fine for
 *    Adobe's typically-fast conversions, but for a more robust production
 *    setup, consider moving the poll step to a Queueable chain (or
 *    Continuation) instead of doing it inline in the response.
 */
public with sharing class DocConversionProvider {

    private static final String NAMED_CREDENTIAL = 'callout:Adobe_PDF_Services';
    private static final String DOCX_MIME_TYPE =
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    private static final Integer TIMEOUT_MS = 60000;
    private static final Integer MAX_POLL_ATTEMPTS = 10;

    public class ConversionResult {
        public Boolean success;
        public String outputFileName;
        public String base64Pdf;
        public String errorMessage;

        public ConversionResult(Boolean success, String outputFileName, String base64Pdf, String errorMessage) {
            this.success = success;
            this.outputFileName = outputFileName;
            this.base64Pdf = base64Pdf;
            this.errorMessage = errorMessage;
        }
    }

    public static ConversionResult convertDocxToPdf(String sourceFileName, String base64Docx) {
        try {
            // Step 1: create the asset placeholder
            Map<String, String> assetInfo = createAsset();
            String uploadUri = assetInfo.get('uploadUri');
            String assetId = assetInfo.get('assetID');
            if (String.isBlank(uploadUri) || String.isBlank(assetId)) {
                return new ConversionResult(false, null, null, 'Adobe did not return an uploadUri/assetID.');
            }

            // Step 2: upload the raw docx bytes to the pre-signed URL
            Blob docxBytes = EncodingUtil.base64Decode(base64Docx);
            uploadFile(uploadUri, docxBytes);

            // Step 3: submit the Create PDF job
            String pollingUrl = submitCreatePdfJob(assetId);
            if (String.isBlank(pollingUrl)) {
                return new ConversionResult(false, null, null, 'Adobe did not return a job polling URL.');
            }

            // Step 4: poll until done (or we run out of attempts)
            Map<String, Object> jobResult = pollJobUntilDone(pollingUrl);
            String status = (String) jobResult.get('status');

            if (status == 'done') {
                Map<String, Object> asset = (Map<String, Object>) jobResult.get('asset');
                String downloadUri = asset != null ? (String) asset.get('downloadUri') : null;
                if (String.isBlank(downloadUri)) {
                    return new ConversionResult(false, null, null, 'Adobe job completed but no downloadUri was returned.');
                }

                Blob pdfBytes = downloadFile(downloadUri);
                String pdfFileName = stripExtension(sourceFileName) + '.pdf';
                return new ConversionResult(true, pdfFileName, EncodingUtil.base64Encode(pdfBytes), null);

            } else if (status == 'failed') {
                return new ConversionResult(false, null, null, 'Adobe conversion job failed: ' + JSON.serialize(jobResult));
            } else {
                return new ConversionResult(false, null, null, 'Adobe job did not complete within the poll budget (last status: ' + status + ').');
            }

        } catch (System.CalloutException calloutEx) {
            return new ConversionResult(false, null, null, 'Callout error: ' + calloutEx.getMessage());
        } catch (Exception ex) {
            return new ConversionResult(false, null, null, 'Unexpected error during conversion: ' + ex.getMessage());
        }
    }

    /**
     * Creates an asset placeholder for the file we're about to upload.
     * POST /assets -> { uploadUri, assetID }
     * No manual Authorization header — the Named Credential attaches the
     * Bearer token automatically.
     */
    private static Map<String, String> createAsset() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/assets');
        req.setMethod('POST');
        req.setHeader('X-API-Key', getClientId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, String>{ 'mediaType' => DOCX_MIME_TYPE }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new CalloutException('Asset creation failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody());
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return new Map<String, String>{
            'uploadUri' => (String) parsed.get('uploadUri'),
            'assetID' => (String) parsed.get('assetID')
        };
    }

    /**
     * Uploads the raw file bytes to the pre-signed uploadUri. This is a
     * direct-to-storage PUT, not an Adobe API-domain call, so it doesn't go
     * through the Named Credential — see the Remote Site Setting note above.
     */
    private static void uploadFile(String uploadUri, Blob fileBytes) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(uploadUri);
        req.setMethod('PUT');
        req.setHeader('Content-Type', DOCX_MIME_TYPE);
        req.setTimeout(TIMEOUT_MS);
        req.setBodyAsBlob(fileBytes);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new CalloutException('File upload failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    /**
     * Submits the Create PDF job against the uploaded asset.
     * POST /operation/createpdf -> 201 with a Location header (polling URL).
     *
     * If Location comes back blank, that's surfaced as a loud error with a
     * full dump of every header Apex actually received — rather than a
     * generic "no polling URL" message — so you can tell whether Adobe
     * genuinely omitted it or it's arriving under different casing / being
     * stripped somewhere between Adobe and Apex.
     */
    private static String submitCreatePdfJob(String assetId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/operation/createpdf');
        req.setMethod('POST');
        req.setHeader('X-API-Key', getClientId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, String>{ 'assetID' => assetId }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) {
            throw new CalloutException('Create PDF job submission failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody());
        }

        String locationHeader = res.getHeader('Location');
        if (String.isBlank(locationHeader)) {
            List<String> headerDump = new List<String>();
            for (String key : res.getHeaderKeys()) {
                headerDump.add(key + '=' + res.getHeader(key));
            }
            throw new CalloutException(
                'Create PDF job returned HTTP 201 but no Location header was visible to Apex. '
                + 'Headers received: [' + String.join(headerDump, ', ') + ']. '
                + 'Body: ' + res.getBody()
            );
        }
        return locationHeader;
    }

    /**
     * Polls the job status URL in a bounded loop. Apex has no synchronous
     * sleep, so this retries immediately rather than waiting between polls —
     * fine for fast jobs, but see the class header note for a more robust
     * async alternative.
     */
    private static Map<String, Object> pollJobUntilDone(String pollingUrl) {
        Map<String, Object> lastResult = new Map<String, Object>{ 'status' => 'unknown' };

        for (Integer attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(pollingUrl);
            req.setMethod('GET');
            req.setHeader('X-API-Key', getClientId());
            req.setTimeout(TIMEOUT_MS);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                throw new CalloutException('Job status check failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody());
            }

            lastResult = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String status = (String) lastResult.get('status');
            if (status == 'done' || status == 'failed') {
                return lastResult;
            }
        }
        return lastResult; // exhausted attempts while still "in progress"
    }

    /**
     * Downloads the resulting PDF from the pre-signed downloadUri.
     */
    private static Blob downloadFile(String downloadUri) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(downloadUri);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException('File download failed: HTTP ' + res.getStatusCode());
        }
        return res.getBodyAsBlob();
    }

    /**
     * Retrieves the Adobe client_id, used only for the X-API-Key header
     * (Adobe's requirement on top of standard OAuth — not secret in the way
     * the Client Secret is, since Salesforce now manages that separately via
     * the Named/External Credential). Adjust to match wherever you store it
     * (Custom Metadata Type shown here as an example).
     */
    private static String getClientId() {
        // Example: Adobe_Api_Credential__mdt cred = Adobe_Api_Credential__mdt.getInstance('Default');
        // return cred != null ? cred.Client_Id__c : null;
        return null; // placeholder — wire this up before use
    }

    private static String stripExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'document';
        }
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }
}
