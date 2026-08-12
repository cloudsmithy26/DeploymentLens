@isTest
private class ConvertDocToPdfServiceTest {

    // Simulates a successful Cloudmersive response: raw PDF bytes in the body.
    private class ConversionSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/pdf');
            res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 fake-pdf-bytes'));
            return res;
        }
    }

    // Simulates the provider returning an error.
    private class ConversionFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"conversion engine unavailable"}');
            return res;
        }
    }

    @isTest
    static void testDoPost_success() {
        Test.setMock(HttpCalloutMock.class, new ConversionSuccessMock());

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/convertDocToPdf';
        req.httpMethod = 'POST';

        Map<String, String> payload = new Map<String, String>{
            'fileName' => 'Proposal.docx',
            'base64Content' => EncodingUtil.base64Encode(Blob.valueOf('fake-docx-bytes'))
        };
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        ConvertDocToPdfService.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> resBody =
            (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals(true, resBody.get('success'));
        System.assertEquals('Proposal.pdf', resBody.get('fileName'));
        System.assertNotEquals(null, resBody.get('base64Pdf'));
    }

    @isTest
    static void testDoPost_providerFailure() {
        Test.setMock(HttpCalloutMock.class, new ConversionFailureMock());

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/convertDocToPdf';
        req.httpMethod = 'POST';

        Map<String, String> payload = new Map<String, String>{
            'fileName' => 'Proposal.docx',
            'base64Content' => EncodingUtil.base64Encode(Blob.valueOf('fake-docx-bytes'))
        };
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        ConvertDocToPdfService.doPost();
        Test.stopTest();

        System.assertEquals(502, RestContext.response.statusCode);
        Map<String, Object> resBody =
            (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals(false, resBody.get('success'));
        System.assertNotEquals(null, resBody.get('errorMessage'));
    }

    @isTest
    static void testDoPost_missingBase64() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/convertDocToPdf';
        req.httpMethod = 'POST';

        Map<String, String> payload = new Map<String, String>{
            'fileName' => 'Proposal.docx'
        };
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        ConvertDocToPdfService.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }
}
