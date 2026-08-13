@isTest
private class DocToPdfControllerTest {

    private class AdobeFlowSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (endpoint.endsWith('/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"fake-token","expires_in":3600}');
            } else if (endpoint.endsWith('/assets')) {
                res.setStatusCode(200);
                res.setBody('{"uploadUri":"https://fake-storage.example.com/upload/abc123","assetID":"urn:aaid:AS:fake-asset-id"}');
            } else if (endpoint.contains('fake-storage.example.com/upload')) {
                res.setStatusCode(200);
            } else if (endpoint.endsWith('/operation/createpdf')) {
                res.setStatusCode(201);
                res.setHeader('Location', 'https://pdf-services.adobe.io/operation/createpdf/status/fake-job-id');
            } else if (endpoint.contains('/operation/createpdf/status/')) {
                res.setStatusCode(200);
                res.setBody('{"status":"done","asset":{"downloadUri":"https://fake-storage.example.com/download/xyz789"}}');
            } else if (endpoint.contains('fake-storage.example.com/download')) {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 fake-pdf-bytes'));
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":"unexpected endpoint in mock: ' + endpoint + '"}');
            }
            return res;
        }
    }

    private class AdobeJobFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (endpoint.endsWith('/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"fake-token","expires_in":3600}');
            } else if (endpoint.endsWith('/assets')) {
                res.setStatusCode(200);
                res.setBody('{"uploadUri":"https://fake-storage.example.com/upload/abc123","assetID":"urn:aaid:AS:fake-asset-id"}');
            } else if (endpoint.contains('fake-storage.example.com/upload')) {
                res.setStatusCode(200);
            } else if (endpoint.endsWith('/operation/createpdf')) {
                res.setStatusCode(201);
                res.setHeader('Location', 'https://pdf-services.adobe.io/operation/createpdf/status/fake-job-id');
            } else if (endpoint.contains('/operation/createpdf/status/')) {
                res.setStatusCode(200);
                res.setBody('{"status":"failed","error":{"message":"corrupt input file"}}');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }

    private static Account createAccountWithWordFile() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        ContentVersion cv = new ContentVersion();
        cv.Title = 'Proposal';
        cv.PathOnClient = 'Proposal.docx';
        cv.VersionData = Blob.valueOf('fake-docx-bytes');
        insert cv;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        return acc;
    }

    @isTest
    static void testGetWordFiles_returnsAttachedDocx() {
        Account acc = createAccountWithWordFile();

        Test.startTest();
        List<DocToPdfController.WordFileWrapper> files = DocToPdfController.getWordFiles(acc.Id);
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals('Proposal', files[0].title);
        System.assertEquals('docx', files[0].fileExtension);
    }

    @isTest
    static void testGetWordFiles_noFiles() {
        Account acc = new Account(Name = 'Empty Account');
        insert acc;

        Test.startTest();
        List<DocToPdfController.WordFileWrapper> files = DocToPdfController.getWordFiles(acc.Id);
        Test.stopTest();

        System.assertEquals(0, files.size());
    }

    @isTest
    static void testGeneratePdf_success() {
        Account acc = createAccountWithWordFile();
        Id sourceVersionId = [SELECT Id FROM ContentVersion WHERE Title = 'Proposal' LIMIT 1].Id;

        Test.setMock(HttpCalloutMock.class, new AdobeFlowSuccessMock());

        Test.startTest();
        DocToPdfController.GeneratePdfResult result = DocToPdfController.generatePdf(sourceVersionId, acc.Id);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.newContentDocumentId);
        System.assertEquals('Proposal.pdf', result.fileName);

        // Confirm the new PDF is actually linked to the record.
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :result.newContentDocumentId AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(1, links.size());
    }

    @isTest
    static void testGeneratePdf_conversionFailure() {
        Account acc = createAccountWithWordFile();
        Id sourceVersionId = [SELECT Id FROM ContentVersion WHERE Title = 'Proposal' LIMIT 1].Id;

        Test.setMock(HttpCalloutMock.class, new AdobeJobFailureMock());

        Test.startTest();
        DocToPdfController.GeneratePdfResult result = DocToPdfController.generatePdf(sourceVersionId, acc.Id);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertNotEquals(null, result.errorMessage);
    }
}
