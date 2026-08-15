/**
 * @Description: ServiceTeam DocGen Provider, It is used for mapping Servicing_Team__c fields for Servicing Team document generation.
*/
global with sharing class WT_ServiceTeamDocGenProvider implements portwoodglobal.DocGenDataProvider {
    global Map<String, Object> getData(Id recordId) {
        // recordId is the ID of the Servicing_Team__c record.
        List<Servicing_Team__c> listServicingTeam  = [
                SELECT Id,Name, WT_Quoting_Primary__r.Name, WT_Quoting_Primary__r.WT_Job_Title__c, WT_Quoting_Primary__r.WT_Email__c,WT_Quoting_Primary__r.WT_Phone_Number__c, 
                WT_Quoting_Secondary__r.Name, WT_Quoting_Secondary__r.WT_Job_Title__c,WT_Quoting_Secondary__r.WT_Email__c, WT_Quoting_Secondary__r.WT_Phone_Number__c,
                WT_Loan_Ops_Primary__r.Name,WT_Loan_Ops_Primary__r.WT_Job_Title__c, WT_Loan_Ops_Primary__r.WT_Email__c, WT_Loan_Ops_Primary__r.WT_Phone_Number__c,
                WT_Loan_Ops_Secondary__r.Name, WT_Loan_Ops_Secondary__r.WT_Job_Title__c, WT_Loan_Ops_Secondary__r.WT_Email__c,WT_Loan_Ops_Secondary__r.WT_Phone_Number__c, 
                WT_RM__r.Name, WT_RM__r.WT_Job_Title__c, WT_RM__r.WT_Email__c,WT_RM__r.WT_Phone_Number__c, WT_RM__r.WT_Image_ContentVersion_Id__c, 
                WT_RP__r.Name, WT_RP__r.WT_Job_Title__c, WT_RP__r.WT_Email__c, WT_RP__r.WT_Phone_Number__c,WT_RP__r.WT_Image_ContentVersion_Id__c,
                WT_Asset_Mgmt_Primary__r.Name, WT_Asset_Mgmt_Primary__r.WT_Job_Title__c, WT_Asset_Mgmt_Primary__r.WT_Email__c,WT_Asset_Mgmt_Primary__r.WT_Phone_Number__c, 
                WT_Asset_Mgmt_Secondary__r.Name,WT_Asset_Mgmt_Secondary__r.WT_Job_Title__c, WT_Asset_Mgmt_Secondary__r.WT_Email__c,WT_Asset_Mgmt_Secondary__r.WT_Phone_Number__c                
                FROM Servicing_Team__c
                WHERE Id = :recordId                
                WITH USER_MODE                
            ];

        if (listServicingTeam == null || listServicingTeam.isEmpty()) {
            return new Map<String, Object>();
        }
        Servicing_Team__c servicingTeam = listServicingTeam.get(0);

        Map<String, Object> mapMergeTagAndServcingTeamData = new Map<String, Object>();
        mapMergeTagAndServcingTeamData.put('name', servicingTeam.Name);
        mapMergeTagAndServcingTeamData.put('qp', createEmployeeMap(servicingTeam.WT_Quoting_Primary__r));
        mapMergeTagAndServcingTeamData.put('qs', createEmployeeMap(servicingTeam.WT_Quoting_Secondary__r));
        mapMergeTagAndServcingTeamData.put('lop', createEmployeeMap(servicingTeam.WT_Loan_Ops_Primary__r));
        mapMergeTagAndServcingTeamData.put('los', createEmployeeMap(servicingTeam.WT_Loan_Ops_Secondary__r));
        mapMergeTagAndServcingTeamData.put('rm', createRM_RP_EmployeeMap(servicingTeam.WT_RM__r));
        mapMergeTagAndServcingTeamData.put('rp', createRM_RP_EmployeeMap(servicingTeam.WT_RP__r));
        mapMergeTagAndServcingTeamData.put('amp', createEmployeeMap(servicingTeam.WT_Asset_Mgmt_Primary__r));
        mapMergeTagAndServcingTeamData.put('ams', createEmployeeMap(servicingTeam.WT_Asset_Mgmt_Secondary__r));

        return mapMergeTagAndServcingTeamData;
    }

    private Map<String, Object> createEmployeeMap(WT_Employee__c emp) {
        if (emp == null) {
            return new Map<String, Object>();
        }
        return new Map<String, Object>{
            'Name' => emp.Name,
            'JobTitle' => emp.WT_Job_Title__c,
            'Email' => emp.WT_Email__c,
            'Phone' => emp.WT_Phone_Number__c
        };
    }

    private Map<String, Object> createRM_RP_EmployeeMap(WT_Employee__c emp) {
        if (emp == null) {
            return new Map<String, Object>();
        }
        return new Map<String, Object>{
            'Name' => emp.Name,
            'JobTitle' => emp.WT_Job_Title__c,
            'Email' => emp.WT_Email__c,
            'Phone' => emp.WT_Phone_Number__c,
            'Image' => emp.WT_Image_ContentVersion_Id__c
        };
    }

    global List<String> getFieldNames() {
        List<String> fields = new List<String>();
        String[] prefixes = new String[]{
            'qp',
            'qs',
            'lop',
            'los',
            'amp',
            'ams'
        };
        for (String prefix : prefixes) {
            fields.add(prefix + '.Name');
            fields.add(prefix + '.JobTitle');
            fields.add(prefix + '.Email');
            fields.add(prefix + '.Phone');
        }
        for (String prefix : new String[]{'rm', 'rp'}) {
            fields.add(prefix + '.Name');
            fields.add(prefix + '.JobTitle');
            fields.add(prefix + '.Email');
            fields.add(prefix + '.Phone');
            fields.add(prefix + '.Image');
        }
        fields.add('name');
        return fields;
    }
}