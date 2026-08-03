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

    public static DeploymentSummary fromToolingRecord(Map<String, Object> mapDeployRecord) {
        DeploymentSummary deploymentSummary = new DeploymentSummary();
        deploymentSummary.id = (String) mapDeployRecord.get('Id');
        deploymentSummary.status = (String) mapDeployRecord.get('Status');
        deploymentSummary.checkOnly = mapDeployRecord.get('CheckOnly') == true;
        deploymentSummary.createdDate = (String) mapDeployRecord.get('CreatedDate');
        deploymentSummary.startDate = (String) mapDeployRecord.get('StartDate');
        deploymentSummary.completedDate = (String) mapDeployRecord.get('CompletedDate');
        deploymentSummary.componentsTotal = toInteger(mapDeployRecord.get('NumberComponentsTotal'));
        deploymentSummary.componentsDeployed = toInteger(mapDeployRecord.get('NumberComponentsDeployed'));
        deploymentSummary.componentErrors = toInteger(mapDeployRecord.get('NumberComponentErrors'));
        deploymentSummary.testsTotal = toInteger(mapDeployRecord.get('NumberTestsTotal'));
        deploymentSummary.testsCompleted = toInteger(mapDeployRecord.get('NumberTestsCompleted'));
        deploymentSummary.testErrors = toInteger(mapDeployRecord.get('NumberTestErrors'));
        Object createdByValue = mapDeployRecord.get('CreatedBy');
        if (createdByValue instanceof Map<String, Object>) {
            deploymentSummary.createdByName =
                (String) ((Map<String, Object>) createdByValue).get('Name');
        }
        return deploymentSummary;
    }

    private static Integer toInteger(Object fieldValue) {
        return fieldValue == null ? 0 : Integer.valueOf(String.valueOf(fieldValue));
    }
}
