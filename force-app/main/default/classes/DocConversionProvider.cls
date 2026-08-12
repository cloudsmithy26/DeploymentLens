/**
 * DocConversionProvider
 * -----------------------
 * Performs the outbound callout to Cloudmersive's Convert API to turn a
 * .docx file into a PDF.
 *
 * SETUP REQUIRED BEFORE USE:
 * 1. Named Credential called "Cloudmersive_API":
 *      URL: https://api.cloudmersive.com
 *      Auth: Cloudmersive uses a simple API key in the "Apikey" header, not
 *      OAuth — so set the Named Credential's Identity Type to "Named Principal"
 *      with no auth protocol, and instead store the API key in a Protected
 *      Custom Setting / Custom Metadata Type and reference it in
 *      CLOUDMERSIVE_API_KEY_SETTING below, OR (simpler) add a custom header
 *      "Apikey" directly on the Named Credential if your org's Named
 *      Credential setup supports static headers.
 * 2. Cloudmersive endpoint used here: POST /convert/docx/to/pdf
 *    (takes the raw file bytes as the request body, returns PDF bytes).
 *    Docs: https://api.cloudmersive.com/docs/convert.asp
 * 3. Remote Site Setting is not needed when using a Named Credential.
 *
 * This class is intentionally isolated behind a single method so you can
 * swap Cloudmersive for another provider (Aspose Cloud, CloudConvert, etc.)
 * later without touching ConvertDocToPdfService.
 */
public with sharing class DocConversionProvider {

    private static final String NAMED_CREDENTIAL = 'callout:Cloudmersive_API';
    private static final String CONVERT_PATH = '/convert/docx/to/pdf';
    private static final Integer TIMEOUT_MS = 120000;

    // Custom Metadata Type record storing the Cloudmersive API key, e.g.
    // Api_Key__mdt.Cloudmersive_Key. Adjust to whatever you set up.
    // If you instead put the key as a static header on the Named Credential,
    // you can delete this constant and the header line that uses it below.
    private static final String CLOUDMERSIVE_API_KEY_SETTING = 'Cloudmersive_Key';

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
     * Sends the source .docx (base64) to Cloudmersive and returns the resulting
     * PDF (base64).
     */
    public static ConversionResult convertDocxToPdf(String sourceFileName, String base64Docx) {
        try {
            Blob docxBytes = EncodingUtil.base64Decode(base64Docx);

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(NAMED_CREDENTIAL + CONVERT_PATH);
            httpReq.setMethod('POST');
            httpReq.setTimeout(TIMEOUT_MS);

            // Cloudmersive's convert endpoints accept the raw file as
            // multipart/form-data with field name "inputFile".
            String boundary = '----SFBoundary' + String.valueOf(Crypto.getRandomLong());
            httpReq.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);

            String apiKey = getApiKey();
            if (String.isNotBlank(apiKey)) {
                httpReq.setHeader('Apikey', apiKey);
            }

            httpReq.setBodyAsBlob(buildMultipartBody(boundary, sourceFileName, docxBytes));

            Http httpClient = new Http();
            HttpResponse httpRes = httpClient.send(httpReq);

            if (httpRes.getStatusCode() == 200) {
                Blob pdfBytes = httpRes.getBodyAsBlob();
                String pdfFileName = stripExtension(sourceFileName) + '.pdf';
                return new ConversionResult(
                    true,
                    pdfFileName,
                    EncodingUtil.base64Encode(pdfBytes),
                    null
                );
            } else {
                return new ConversionResult(
                    false, null, null,
                    'Cloudmersive returned HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getBody()
                );
            }

        } catch (System.CalloutException calloutEx) {
            return new ConversionResult(false, null, null, 'Callout error: ' + calloutEx.getMessage());
        } catch (Exception ex) {
            return new ConversionResult(false, null, null, 'Unexpected error during conversion: ' + ex.getMessage());
        }
    }

    /**
     * Builds a minimal multipart/form-data body containing a single file part.
     * Cloudmersive's convert endpoints accept the file under the "inputFile" field.
     */
    private static Blob buildMultipartBody(String boundary, String fileName, Blob fileBytes) {
        String header = '--' + boundary + '\r\n'
            + 'Content-Disposition: form-data; name="inputFile"; filename="' + fileName + '"\r\n'
            + 'Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document\r\n\r\n';
        String footer = '\r\n--' + boundary + '--\r\n';

        Blob headerBlob = Blob.valueOf(header);
        Blob footerBlob = Blob.valueOf(footer);

        // Concatenate header + file bytes + footer as raw blob bytes.
        String headerHex = EncodingUtil.convertToHex(headerBlob);
        String fileHex = EncodingUtil.convertToHex(fileBytes);
        String footerHex = EncodingUtil.convertToHex(footerBlob);

        return EncodingUtil.convertFromHex(headerHex + fileHex + footerHex);
    }

    /**
     * Retrieves the Cloudmersive API key. Adjust this to match wherever you
     * actually store it (Custom Metadata Type shown here as an example).
     */
    private static String getApiKey() {
        // Example using a Custom Metadata Type "Api_Key__mdt" with fields
        // DeveloperName and Value__c. Replace with your actual storage.
        // Api_Key__mdt keySetting = Api_Key__mdt.getInstance(CLOUDMERSIVE_API_KEY_SETTING);
        // return keySetting != null ? keySetting.Value__c : null;

        // Placeholder: return null so it's obvious this needs wiring up.
        return null;
    }

    private static String stripExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return 'document';
        }
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }
}
