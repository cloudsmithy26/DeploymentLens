/**
 * @description DTO for the component-level drill-down of one deployment,
 * built from the Metadata REST API deployRequest "deployResult" payload.
 */
public with sharing class DeploymentDetail {
    @AuraEnabled public String id;
    @AuraEnabled public String status;
    @AuraEnabled public Boolean checkOnly;
    @AuraEnabled public Integer numberComponentsTotal;
    @AuraEnabled public Integer numberComponentErrors;
    @AuraEnabled public Integer numberTestsTotal;
    @AuraEnabled public Integer numberTestErrors;
    @AuraEnabled public List<ComponentResult> componentSuccesses = new List<ComponentResult>();
    @AuraEnabled public List<ComponentResult> componentFailures = new List<ComponentResult>();
    @AuraEnabled public List<TestResult> testSuccesses = new List<TestResult>();
    @AuraEnabled public List<TestResult> testFailures = new List<TestResult>();

    public class ComponentResult {
        @AuraEnabled public String componentType;
        @AuraEnabled public String fullName;
        @AuraEnabled public String fileName;
        @AuraEnabled public String problem;
        @AuraEnabled public String problemType;
        @AuraEnabled public Boolean created;
        @AuraEnabled public Boolean changed;
        @AuraEnabled public Boolean deleted;
    }

    public class TestResult {
        @AuraEnabled public String apexClassName;
        @AuraEnabled public String methodName;
        @AuraEnabled public String outcome;
        @AuraEnabled public String message;
        @AuraEnabled public String stackTrace;
        @AuraEnabled public Decimal timeMs;
    }

    public static DeploymentDetail fromDeployResult(Map<String, Object> mapDeployResult) {
        DeploymentDetail deploymentDetail = new DeploymentDetail();
        deploymentDetail.id = (String) mapDeployResult.get('id');
        deploymentDetail.status = (String) mapDeployResult.get('status');
        deploymentDetail.checkOnly = mapDeployResult.get('checkOnly') == true;
        deploymentDetail.numberComponentsTotal = toInteger(mapDeployResult.get('numberComponentsTotal'));
        deploymentDetail.numberComponentErrors = toInteger(mapDeployResult.get('numberComponentErrors'));
        deploymentDetail.numberTestsTotal = toInteger(mapDeployResult.get('numberTestsTotal'));
        deploymentDetail.numberTestErrors = toInteger(mapDeployResult.get('numberTestErrors'));

        Map<String, Object> mapDetails = (Map<String, Object>) mapDeployResult.get('details');
        if (mapDetails == null) { return deploymentDetail; }

        for (Object successItem : asList(mapDetails.get('componentSuccesses'))) {
            deploymentDetail.componentSuccesses.add(
                toComponentResult((Map<String, Object>) successItem));
        }
        for (Object failureItem : asList(mapDetails.get('componentFailures'))) {
            deploymentDetail.componentFailures.add(
                toComponentResult((Map<String, Object>) failureItem));
        }

        Map<String, Object> mapRunTestResult = (Map<String, Object>) mapDetails.get('runTestResult');
        if (mapRunTestResult != null) {
            for (Object testSuccessItem : asList(mapRunTestResult.get('successes'))) {
                deploymentDetail.testSuccesses.add(
                    toTestResult((Map<String, Object>) testSuccessItem, 'Pass'));
            }
            for (Object testFailureItem : asList(mapRunTestResult.get('failures'))) {
                deploymentDetail.testFailures.add(
                    toTestResult((Map<String, Object>) testFailureItem, 'Fail'));
            }
        }
        return deploymentDetail;
    }

    private static ComponentResult toComponentResult(Map<String, Object> mapComponentRecord) {
        ComponentResult componentResult = new ComponentResult();
        componentResult.componentType = (String) mapComponentRecord.get('componentType');
        componentResult.fullName = (String) mapComponentRecord.get('fullName');
        componentResult.fileName = (String) mapComponentRecord.get('fileName');
        componentResult.problem = (String) mapComponentRecord.get('problem');
        componentResult.problemType = (String) mapComponentRecord.get('problemType');
        componentResult.created = mapComponentRecord.get('created') == true;
        componentResult.changed = mapComponentRecord.get('changed') == true;
        componentResult.deleted = mapComponentRecord.get('deleted') == true;
        return componentResult;
    }

    private static TestResult toTestResult(Map<String, Object> mapTestRecord, String outcome) {
        TestResult testResult = new TestResult();
        testResult.apexClassName = (String) mapTestRecord.get('name');
        testResult.methodName = (String) mapTestRecord.get('methodName');
        testResult.message = (String) mapTestRecord.get('message');
        testResult.stackTrace = (String) mapTestRecord.get('stackTrace');
        testResult.outcome = outcome;
        Object testTimeValue = mapTestRecord.get('time');
        testResult.timeMs = testTimeValue == null ? 0
            : Decimal.valueOf(String.valueOf(testTimeValue));
        return testResult;
    }

    private static List<Object> asList(Object listValue) {
        return listValue == null ? new List<Object>() : (List<Object>) listValue;
    }

    private static Integer toInteger(Object fieldValue) {
        return fieldValue == null ? 0 : Integer.valueOf(String.valueOf(fieldValue));
    }
}
