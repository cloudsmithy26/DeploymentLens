/**
 * @description DTO for a row in the recent-deployments table.
 */
public with sharing class DeploymentSummary {
    @AuraEnabled public String id;
    @AuraEnabled public String status;
    @AuraEnabled public Boolean checkOnly;
    @AuraEnabled public String createdByName;
    @AuraEnabled public String createdDate;
    @AuraEnabled public String startDate;
    @AuraEnabled public String completedDate;
    @AuraEnabled public Integer componentsTotal;
    @AuraEnabled public Integer componentsDeployed;
    @AuraEnabled public Integer componentErrors;
    @AuraEnabled public Integer testsTotal;
    @AuraEnabled public Integer testsCompleted;
    @AuraEnabled public Integer testErrors;

    public static DeploymentSummary fromToolingRecord(Map<String, Object> rec) {
        DeploymentSummary s = new DeploymentSummary();
        s.id = (String) rec.get('Id');
        s.status = (String) rec.get('Status');
        s.checkOnly = rec.get('CheckOnly') == true;
        s.createdDate = (String) rec.get('CreatedDate');
        s.startDate = (String) rec.get('StartDate');
        s.completedDate = (String) rec.get('CompletedDate');
        s.componentsTotal = toInt(rec.get('NumberComponentsTotal'));
        s.componentsDeployed = toInt(rec.get('NumberComponentsDeployed'));
        s.componentErrors = toInt(rec.get('NumberComponentErrors'));
        s.testsTotal = toInt(rec.get('NumberTestsTotal'));
        s.testsCompleted = toInt(rec.get('NumberTestsCompleted'));
        s.testErrors = toInt(rec.get('NumberTestErrors'));
        Object createdBy = rec.get('CreatedBy');
        if (createdBy instanceof Map<String, Object>) {
            s.createdByName = (String) ((Map<String, Object>) createdBy).get('Name');
        }
        return s;
    }

    private static Integer toInt(Object o) {
        return o == null ? 0 : Integer.valueOf(String.valueOf(o));
    }
}
