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

    public static DeploymentDetail fromDeployResult(Map<String, Object> deployResult) {
        DeploymentDetail d = new DeploymentDetail();
        d.id = (String) deployResult.get('id');
        d.status = (String) deployResult.get('status');
        d.checkOnly = deployResult.get('checkOnly') == true;
        d.numberComponentsTotal = toInt(deployResult.get('numberComponentsTotal'));
        d.numberComponentErrors = toInt(deployResult.get('numberComponentErrors'));
        d.numberTestsTotal = toInt(deployResult.get('numberTestsTotal'));
        d.numberTestErrors = toInt(deployResult.get('numberTestErrors'));

        Map<String, Object> details = (Map<String, Object>) deployResult.get('details');
        if (details == null) { return d; }

        for (Object o : asList(details.get('componentSuccesses'))) {
            d.componentSuccesses.add(toComponent((Map<String, Object>) o));
        }
        for (Object o : asList(details.get('componentFailures'))) {
            d.componentFailures.add(toComponent((Map<String, Object>) o));
        }

        Map<String, Object> runTestResult = (Map<String, Object>) details.get('runTestResult');
        if (runTestResult != null) {
            for (Object o : asList(runTestResult.get('successes'))) {
                d.testSuccesses.add(toTest((Map<String, Object>) o, 'Pass'));
            }
            for (Object o : asList(runTestResult.get('failures'))) {
                d.testFailures.add(toTest((Map<String, Object>) o, 'Fail'));
            }
        }
        return d;
    }

    private static ComponentResult toComponent(Map<String, Object> m) {
        ComponentResult c = new ComponentResult();
        c.componentType = (String) m.get('componentType');
        c.fullName = (String) m.get('fullName');
        c.fileName = (String) m.get('fileName');
        c.problem = (String) m.get('problem');
        c.problemType = (String) m.get('problemType');
        c.created = m.get('created') == true;
        c.changed = m.get('changed') == true;
        c.deleted = m.get('deleted') == true;
        return c;
    }

    private static TestResult toTest(Map<String, Object> m, String outcome) {
        TestResult t = new TestResult();
        t.apexClassName = (String) m.get('name');
        t.methodName = (String) m.get('methodName');
        t.message = (String) m.get('message');
        t.stackTrace = (String) m.get('stackTrace');
        t.outcome = outcome;
        Object timeVal = m.get('time');
        t.timeMs = timeVal == null ? 0 : Decimal.valueOf(String.valueOf(timeVal));
        return t;
    }

    private static List<Object> asList(Object o) {
        return o == null ? new List<Object>() : (List<Object>) o;
    }

    private static Integer toInt(Object o) {
        return o == null ? 0 : Integer.valueOf(String.valueOf(o));
    }
}
