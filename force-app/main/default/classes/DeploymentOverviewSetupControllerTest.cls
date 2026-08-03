@IsTest
private class DeploymentOverviewSetupControllerTest {

    private class CodeMock implements HttpCalloutMock {
        Integer statusCode; String redirectLocation;
        CodeMock(Integer statusCode, String redirectLocation) { this.statusCode = statusCode; this.redirectLocation = redirectLocation; }
        public HttpResponse respond(HttpRequest calloutRequest) {
            HttpResponse mockResponse = new HttpResponse();
            mockResponse.setStatusCode(statusCode);
            if (redirectLocation != null) { mockResponse.setHeader('Location', redirectLocation); }
            mockResponse.setBody('{}');
            return mockResponse;
        }
    }

    @IsTest
    static void setupInfoReturnsOrgValues() {
        Map<String, String> mapSetupInfo = DeploymentOverviewSetupController.getSetupInfo();
        System.assert(mapSetupInfo.get('orgUrl').startsWith('https://'));
        System.assert(mapSetupInfo.get('tokenEndpoint').endsWith('/services/oauth2/token'));
        System.assertEquals('Deployment_Overview_Self', mapSetupInfo.get('namedCredential'));
    }

    @IsTest
    static void testConnectionSuccess() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(200, null));
        Map<String, String> mapTestResult = DeploymentOverviewSetupController.testConnection();
        System.assertEquals('Success', mapTestResult.get('status'));
    }

    @IsTest
    static void testConnectionDiagnoses302() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(302, 'https://correct.my.salesforce.com'));
        Map<String, String> mapTestResult = DeploymentOverviewSetupController.testConnection();
        System.assertEquals('Failed', mapTestResult.get('status'));
        System.assert(mapTestResult.get('detail').contains('302'));
        System.assert(mapTestResult.get('hint').contains('Named Credential URL'));
    }

    @IsTest
    static void testConnectionDiagnoses401And403() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(401, null));
        System.assert(DeploymentOverviewSetupController.testConnection().get('hint').contains('consumer key'));
        Test.setMock(HttpCalloutMock.class, new CodeMock(403, null));
        System.assert(DeploymentOverviewSetupController.testConnection().get('hint').contains('Run-As'));
    }
}
