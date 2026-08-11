/**
 * ConvertDocToPdfService
 * -----------------------
 * Exposes a REST endpoint that a REMOTE Salesforce org (or any external client)
 * can call to convert a Word document (.docx) into a PDF using Conga.
 *
 * Endpoint (once deployed):
 *   POST https://<your-domain>.my.salesforce.com/services/apexrest/convertDocToPdf
 *
 * Auth: the calling org authenticates like any External Client App / Connected App
 * call (OAuth 2.0 access token in the Authorization header, e.g. via a Named
 * Credential + External Client App set up on the CALLING org, or a simple
 * session/OAuth token if you prefer). This class itself doesn't handle inbound
 * auth beyond what the Salesforce REST API layer already enforces.
 *
 * Request body (JSON):
 * {
 *   "fileName": "MyProposal.docx",
 *   "base64Content": "<base64-encoded .docx bytes>"
 * }
 *
 * Response body (JSON):
 * {
 *   "success": true,
 *   "fileName": "MyProposal.pdf",
 *   "base64Pdf": "<base64-encoded PDF bytes>",
 *   "errorMessage": null
 * }
 */
@RestResource(urlMapping='/convertDocToPdf/*')
global with sharing class ConvertDocToPdfService {

    global class ConvertRequest {
        global String fileName;
        global String base64Content; // the source .docx, base64-encoded
    }

    global class ConvertResponse {
        global Boolean success;
        global String fileName;
        global String base64Pdf;
        global String errorMessage;

        global ConvertResponse(Boolean success, String fileName, String base64Pdf, String errorMessage) {
            this.success = success;
            this.fileName = fileName;
            this.base64Pdf = base64Pdf;
            this.errorMessage = errorMessage;
        }
    }

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        ConvertResponse result;
        try {
            String rawBody = req.requestBody.toString();
            ConvertRequest input = (ConvertRequest) JSON.deserialize(rawBody, ConvertRequest.class);

            if (String.isBlank(input.base64Content)) {
                res.statusCode = 400;
                result = new ConvertResponse(false, input.fileName, null, 'base64Content is required.');
                res.responseBody = Blob.valueOf(JSON.serialize(result));
                return;
            }

            String sourceFileName = String.isNotBlank(input.fileName) ? input.fileName : 'document.docx';

            // Delegate the actual Conga callout to the helper class.
            CongaDocConversionHelper.ConversionResult conversionResult =
                CongaDocConversionHelper.convertDocxToPdf(sourceFileName, input.base64Content);

            if (conversionResult.success) {
                res.statusCode = 200;
                result = new ConvertResponse(
                    true,
                    conversionResult.outputFileName,
                    conversionResult.base64Pdf,
                    null
                );
            } else {
                res.statusCode = 502; // upstream (Conga) failure
                result = new ConvertResponse(false, sourceFileName, null, conversionResult.errorMessage);
            }

        } catch (Exception ex) {
            res.statusCode = 500;
            result = new ConvertResponse(false, null, null, 'Unexpected error: ' + ex.getMessage());
        }

        res.responseBody = Blob.valueOf(JSON.serialize(result));
    }
}
