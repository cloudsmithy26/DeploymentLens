/**
 * @description Unit tests for DeploymentOverviewController.
 * Uses HttpCalloutMock; no org data dependencies.
 */
@IsTest
private class DeploymentOverviewControllerTest {

    private static final String DEPLOY_ID = '0Af000000000001AAA';

    static {
        // Tests run without the permission set assigned; bypass the gate and
        // verify the gate itself in accessCheckBlocksUnpermittedUsers().
        DeploymentOverviewController.bypassAccessCheck = true;
    }

    private class ApiMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        ApiMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    private static String toolingQueryBody() {
        return '{"size":1,"records":[{"Id":"' + DEPLOY_ID + '","Status":"Succeeded",'
            + '"CheckOnly":false,"CreatedDate":"2026-08-01T10:00:00.000+0000",'
            + '"StartDate":"2026-08-01T10:00:05.000+0000",'
            + '"CompletedDate":"2026-08-01T10:02:00.000+0000",'
            + '"NumberComponentsTotal":12,"NumberComponentsDeployed":12,'
            + '"NumberComponentErrors":0,"NumberTestsTotal":8,'
            + '"NumberTestsCompleted":8,"NumberTestErrors":0,'
            + '"CreatedBy":{"Name":"Ven Reddy"}}]}';
    }

    private static String deployRequestBody() {
        return '{"deployResult":{"id":"' + DEPLOY_ID + '","status":"Succeeded","checkOnly":false,'
            + '"numberComponentsTotal":2,"numberComponentErrors":1,'
            + '"numberTestsTotal":2,"numberTestErrors":1,'
            + '"details":{'
            + '"componentSuccesses":[{"componentType":"ApexClass","fullName":"MyService",'
            + '"fileName":"classes/MyService.cls","created":false,"changed":true,"deleted":false}],'
            + '"componentFailures":[{"componentType":"ApexTrigger","fullName":"MyTrigger",'
            + '"fileName":"triggers/MyTrigger.trigger","problem":"Compile error",'
            + '"problemType":"Error","created":false,"changed":false,"deleted":false}],'
            + '"runTestResult":{"numTestsRun":2,'
            + '"successes":[{"name":"MyServiceTest","methodName":"testHappyPath","time":123.4}],'
            + '"failures":[{"name":"MyServiceTest","methodName":"testEdge",'
            + '"message":"Assertion failed","stackTrace":"line 42","time":88.0}]}}}}';
    }

    @IsTest
    static void recentDeploymentsParsesToolingResponse() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, toolingQueryBody()));
        Test.startTest();
        List<DeploymentSummary> rows = DeploymentOverviewController.getRecentDeployments(10);
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals('Succeeded', rows[0].status);
        System.assertEquals('Ven Reddy', rows[0].createdByName);
        System.assertEquals(12, rows[0].componentsTotal);
    }

    @IsTest
    static void recentDeploymentsClampsInvalidLimit() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, toolingQueryBody()));
        Test.startTest();
        List<DeploymentSummary> rows = DeploymentOverviewController.getRecentDeployments(9999);
        Test.stopTest();
        System.assertEquals(1, rows.size(), 'Clamped limit must still return data');
    }

    @IsTest
    static void findDeploymentByIdReturnsRow() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, toolingQueryBody()));
        Test.startTest();
        List<DeploymentSummary> rows = DeploymentOverviewController.findDeploymentById(DEPLOY_ID);
        Test.stopTest();
        System.assertEquals(DEPLOY_ID, rows[0].id);
    }

    @IsTest
    static void detailsParseDeployResultPayload() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(200, deployRequestBody()));
        Test.startTest();
        DeploymentDetail d = DeploymentOverviewController.getDeploymentDetails(DEPLOY_ID);
        Test.stopTest();
        System.assertEquals(1, d.componentSuccesses.size());
        System.assertEquals(1, d.componentFailures.size());
        System.assertEquals('Compile error', d.componentFailures[0].problem);
        System.assertEquals(1, d.testSuccesses.size());
        System.assertEquals(1, d.testFailures.size());
        System.assertEquals('Fail', d.testFailures[0].outcome);
    }

    @IsTest
    static void invalidDeploymentIdIsRejected() {
        Boolean threw = false;
        try {
            DeploymentOverviewController.getDeploymentDetails('001abcDEF');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Non-0Af Ids must be rejected before any callout');
    }

    @IsTest
    static void accessCheckBlocksUnpermittedUsers() {
        Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noPerm = new User(
            Alias = 'noperm', LastName = 'NoPerm',
            Email = 'noperm@example.com',
            Username = 'noperm' + DateTime.now().getTime() + '@example.com',
            ProfileId = std.Id, EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles');
        insert noPerm;

        Test.setMock(HttpCalloutMock.class, new ApiMock(200, toolingQueryBody()));
        Boolean threw = false;
        System.runAs(noPerm) {
            DeploymentOverviewController.bypassAccessCheck = false;
            try {
                DeploymentOverviewController.getRecentDeployments(5);
            } catch (AuraHandledException e) {
                threw = true;
            } finally {
                DeploymentOverviewController.bypassAccessCheck = true;
            }
        }
        System.assert(threw, 'Users without the custom permission must be blocked');
    }

    @IsTest
    static void non200ResponseThrowsHandledException() {
        Test.setMock(HttpCalloutMock.class, new ApiMock(500, '{"message":"boom"}'));
        Boolean threw = false;
        Test.startTest();
        try {
            DeploymentOverviewController.getRecentDeployments(5);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Non-200 responses must surface as AuraHandledException');
    }
}
