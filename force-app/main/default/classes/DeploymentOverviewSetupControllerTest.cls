@IsTest
private class DeploymentOverviewSetupControllerTest {

    private class CodeMock implements HttpCalloutMock {
        Integer code; String loc;
        CodeMock(Integer code, String loc) { this.code = code; this.loc = loc; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            if (loc != null) { res.setHeader('Location', loc); }
            res.setBody('{}');
            return res;
        }
    }

    @IsTest
    static void setupInfoReturnsOrgValues() {
        Map<String, String> info = DeploymentOverviewSetupController.getSetupInfo();
        System.assert(info.get('orgUrl').startsWith('https://'));
        System.assert(info.get('tokenEndpoint').endsWith('/services/oauth2/token'));
        System.assertEquals('Deployment_Overview_Self', info.get('namedCredential'));
    }

    @IsTest
    static void testConnectionSuccess() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(200, null));
        Map<String, String> r = DeploymentOverviewSetupController.testConnection();
        System.assertEquals('Success', r.get('status'));
    }

    @IsTest
    static void testConnectionDiagnoses302() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(302, 'https://correct.my.salesforce.com'));
        Map<String, String> r = DeploymentOverviewSetupController.testConnection();
        System.assertEquals('Failed', r.get('status'));
        System.assert(r.get('detail').contains('302'));
        System.assert(r.get('hint').contains('Named Credential URL'));
    }

    @IsTest
    static void testConnectionDiagnoses401And403() {
        Test.setMock(HttpCalloutMock.class, new CodeMock(401, null));
        System.assert(DeploymentOverviewSetupController.testConnection().get('hint').contains('consumer key'));
        Test.setMock(HttpCalloutMock.class, new CodeMock(403, null));
        System.assert(DeploymentOverviewSetupController.testConnection().get('hint').contains('Run-As'));
    }
}
