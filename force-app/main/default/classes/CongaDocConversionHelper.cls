/**
 * CongaDocConversionHelper
 * -------------------------
 * Performs the outbound callout to Conga to convert a .docx file to PDF.
 *
 * SETUP REQUIRED BEFORE USE:
 * 1. Named Credential called "Conga_API" pointing to your Conga tenant's base URL,
 *    e.g. https://api.congamerge.com or https://coda.congacloud.com (varies by
 *    Conga product/edition: Conga Composer API, Conga Digital Document
 *    Automation / Conga X-Author, or Conga Batch — check your Conga tenant docs
 *    for the exact conversion endpoint and payload shape).
 * 2. Auth on the Named Credential: Conga typically uses OAuth 2.0 client
 *    credentials or an API key/session token. Configure this as an
 *    "External Credential" (Named Credential 2.0) with the Conga-issued
 *    client id/secret, OR store an API key in a Custom Metadata / Protected
 *    Custom Setting and set it as a header below if Conga uses key-based auth.
 * 3. Remote Site Setting is NOT needed when using Named Credentials.
 * 4. Adjust CONGA_CONVERT_PATH and the request/response JSON shape to match
 *    the exact Conga API you're licensed for — the structure below follows
 *    the common pattern of "POST base64 in, get base64 (or a document id) out"
 *    used by Conga's conversion/merge endpoints.
 *
 * If your org uses Conga Composer's classic "solution" pattern (redirect-based,
 * not JSON API) instead of a true REST conversion API, this class isn't the
 * right shape — Conga Composer solutions are typically invoked via URL
 * parameters from the UI, not a stateless server-to-server callout. Let me
 * know which Conga product you're licensed for and I can adjust this.
 */
public with sharing class CongaDocConversionHelper {

    // Named Credential name (without callout:) as set up in Setup > Named Credentials.
    private static final String NAMED_CREDENTIAL = 'callout:Conga_API';

    // Adjust to the actual Conga conversion endpoint path for your tenant/product.
    private static final String CONGA_CONVERT_PATH = '/api/v1/documents/convert';

    private static final Integer TIMEOUT_MS = 120000; // Conga conversions can be slow; give it headroom

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

    /**
     * Sends the source .docx (base64) to Conga and returns the resulting PDF (base64).
     */
    public static ConversionResult convertDocxToPdf(String sourceFileName, String base64Docx) {
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'fileName' => sourceFileName,
                'outputFormat' => 'PDF',
                'sourceFormat' => 'DOCX',
                'fileData' => base64Docx
            };

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(NAMED_CREDENTIAL + CONGA_CONVERT_PATH);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setHeader('Accept', 'application/json');
            httpReq.setTimeout(TIMEOUT_MS);
            httpReq.setBody(JSON.serialize(payload));

            Http httpClient = new Http();
            HttpResponse httpRes = httpClient.send(httpReq);

            if (httpRes.getStatusCode() == 200) {
                Map<String, Object> responseMap =
                    (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());

                // Adjust these keys to match Conga's actual response payload.
                String base64Pdf = (String) responseMap.get('fileData');
                String returnedName = (String) responseMap.get('fileName');

                if (String.isBlank(base64Pdf)) {
                    return new ConversionResult(
                        false, null, null,
                        'Conga returned 200 but no fileData was present in the response.'
                    );
                }

                String pdfFileName = String.isNotBlank(returnedName)
                    ? returnedName
                    : stripExtension(sourceFileName) + '.pdf';

                return new ConversionResult(true, pdfFileName, base64Pdf, null);

            } else {
                return new ConversionResult(
                    false, null, null,
                    'Conga API returned HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getBody()
                );
            }

        } catch (System.CalloutException calloutEx) {
            return new ConversionResult(false, null, null, 'Callout error: ' + calloutEx.getMessage());
        } catch (Exception ex) {
            return new ConversionResult(false, null, null, 'Unexpected error during conversion: ' + ex.getMessage());
        }
    }

    private static String stripExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'document';
        }
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }
}
