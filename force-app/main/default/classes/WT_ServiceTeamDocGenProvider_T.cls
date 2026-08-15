@IsTest
public with sharing class WT_ServiceTeamDocGenProvider_T {

    private static WT_Employee__c makeEmployee(String name, String jobTitle, String email, String phone) {
        return new WT_Employee__c(
            Name = name,
            WT_Job_Title__c = jobTitle,
            WT_Email__c = email,
            WT_Phone_Number__c = phone
        );
    }

    private static WT_Employee__c makeRmRpEmployee(String name, String jobTitle, String email, String phone, String imageId) {
        WT_Employee__c emp = makeEmployee(name, jobTitle, email, phone);
        emp.WT_Image_ContentVersion_Id__c = imageId;
        return emp;
    }

    @TestSetup
    static void setupTestData() {
        List<WT_Employee__c> employees = new List<WT_Employee__c>{
            makeEmployee('QP Employee', 'Quoting Primary Title', 'qp@test.com', '111-111-1111'),
            makeEmployee('QS Employee', 'Quoting Secondary Title', 'qs@test.com', '222-222-2222'),
            makeEmployee('LOP Employee', 'Loan Ops Primary Title', 'lop@test.com', '333-333-3333'),
            makeEmployee('LOS Employee', 'Loan Ops Secondary Title', 'los@test.com', '444-444-4444'),
            makeRmRpEmployee('RM Employee', 'RM Title', 'rm@test.com', '555-555-5555', 'rmImageId001'),
            makeRmRpEmployee('RP Employee', 'RP Title', 'rp@test.com', '666-666-6666', 'rpImageId001'),
            makeEmployee('AMP Employee', 'Asset Mgmt Primary Title', 'amp@test.com', '777-777-7777'),
            makeEmployee('AMS Employee', 'Asset Mgmt Secondary Title', 'ams@test.com', '888-888-8888')
        };
        insert employees;

        Map<String, Id> empIds = new Map<String, Id>();
        for (WT_Employee__c emp : [SELECT Id, Name FROM WT_Employee__c]) {
            empIds.put(emp.Name, emp.Id);
        }

        Servicing_Team__c team = new Servicing_Team__c(
            WT_Quoting_Primary__c    = empIds.get('QP Employee'),
            WT_Quoting_Secondary__c  = empIds.get('QS Employee'),
            WT_Loan_Ops_Primary__c   = empIds.get('LOP Employee'),
            WT_Loan_Ops_Secondary__c = empIds.get('LOS Employee'),
            WT_RM__c                 = empIds.get('RM Employee'),
            WT_RP__c                 = empIds.get('RP Employee'),
            WT_Asset_Mgmt_Primary__c   = empIds.get('AMP Employee'),
            WT_Asset_Mgmt_Secondary__c = empIds.get('AMS Employee')
        );
        insert team;

        insert new Servicing_Team__c();
    }

    @IsTest
    static void shouldReturnAllRoles_WhenAllEmployeesPopulated() {
        Servicing_Team__c team = [
            SELECT Id FROM Servicing_Team__c
            WHERE WT_RM__c != NULL
            LIMIT 1
        ];

        Test.startTest();
        WT_ServiceTeamDocGenProvider provider = new WT_ServiceTeamDocGenProvider();
        Map<String, Object> result = provider.getData(team.Id);
        Test.stopTest();

        Assert.isTrue(result.size() > 0, 'Should return multiple role keys');

        Map<String, Object> qp = (Map<String, Object>) result.get('qp');
        Assert.areEqual('QP EMPLOYEE', qp.get('Name'), 'QP Name should match');
        Assert.areEqual('Quoting Primary Title', qp.get('JobTitle'), 'QP JobTitle should match');
        Assert.areEqual('qp@test.com', qp.get('Email'), 'QP Email should match');
        Assert.areEqual('111-111-1111', qp.get('Phone'), 'QP Phone should match');

        Map<String, Object> qs = (Map<String, Object>) result.get('qs');
        Assert.areEqual('QS EMPLOYEE', qs.get('Name'), 'QS Name should match');

        Map<String, Object> lop = (Map<String, Object>) result.get('lop');
        Assert.areEqual('LOP EMPLOYEE', lop.get('Name'), 'LOP Name should match');

        Map<String, Object> los = (Map<String, Object>) result.get('los');
        Assert.areEqual('LOS EMPLOYEE', los.get('Name'), 'LOS Name should match');

        Map<String, Object> amp = (Map<String, Object>) result.get('amp');
        Assert.areEqual('AMP EMPLOYEE', amp.get('Name'), 'AMP Name should match');

        Map<String, Object> ams = (Map<String, Object>) result.get('ams');
        Assert.areEqual('AMS EMPLOYEE', ams.get('Name'), 'AMS Name should match');
    }

    @IsTest
    static void shouldReturnImageField_WhenRmEmployeePopulated() {
        Servicing_Team__c team = [SELECT Id FROM Servicing_Team__c WHERE WT_RM__c != NULL LIMIT 1];

        Test.startTest();
        Map<String, Object> result = new WT_ServiceTeamDocGenProvider().getData(team.Id);
        Test.stopTest();

        Map<String, Object> rm = (Map<String, Object>) result.get('rm');
        Assert.areEqual('RM EMPLOYEE', rm.get('Name'), 'RM Name should match');
        Assert.areEqual('RM Title', rm.get('JobTitle'), 'RM JobTitle should match');
        Assert.areEqual('rm@test.com', rm.get('Email'), 'RM Email should match');
        Assert.areEqual('555-555-5555', rm.get('Phone'), 'RM Phone should match');
        Assert.areEqual('rmImageId001', rm.get('Image'), 'RM Image should match');
    }

    @IsTest
    static void shouldReturnImageField_WhenRpEmployeePopulated() {
        Servicing_Team__c team = [SELECT Id FROM Servicing_Team__c WHERE WT_RP__c != NULL LIMIT 1];

        Test.startTest();
        Map<String, Object> result = new WT_ServiceTeamDocGenProvider().getData(team.Id);
        Test.stopTest();

        Map<String, Object> rp = (Map<String, Object>) result.get('rp');
        Assert.areEqual('RP EMPLOYEE', rp.get('Name'), 'RP Name should match');
        Assert.areEqual('rpImageId001', rp.get('Image'), 'RP Image should match');
    }

    @IsTest
    static void shouldReturnEmptyMaps_WhenEmployeeLookupsAreNull() {
        Servicing_Team__c emptyTeam = [SELECT Id FROM Servicing_Team__c WHERE WT_RM__c = NULL LIMIT 1];

        Test.startTest();
        Map<String, Object> result = new WT_ServiceTeamDocGenProvider().getData(emptyTeam.Id);
        Test.stopTest();

        Assert.isTrue(result.size()>0, 'Should still return multiple role keys for empty team');

        for (String key : new List<String>{'qp', 'qs', 'lop', 'los', 'rm', 'rp', 'amp', 'ams'}) {
            Map<String, Object> roleMap = (Map<String, Object>) result.get(key);
            Assert.isTrue(roleMap.isEmpty(), key + ' should be an empty map when lookup is null');
        }
    }

    @IsTest
    static void shouldReturnEmptyMap_WhenRecordIdNotFound() {
        Servicing_Team__c phantom = new Servicing_Team__c();
        Id fakeId = '0HoB00000000001AAA';

        Test.startTest();
        Map<String, Object> result = new WT_ServiceTeamDocGenProvider().getData(fakeId);
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Should return empty map when record does not exist');
    }

    @IsTest
    static void shouldReturnAllFieldNames_FromGetFieldNames() {
        Test.startTest();
        List<String> fields = new WT_ServiceTeamDocGenProvider().getFieldNames();
        Test.stopTest();

        Assert.isTrue(fields.size() > 0, 'Should return 35 field name entries');

        List<String> standardPrefixes = new List<String>{'qp', 'qs', 'lop', 'los', 'amp', 'ams'};
        for (String prefix : standardPrefixes) {
            Assert.isTrue(fields.contains(prefix + '.Name'), prefix + '.Name should be present');
            Assert.isTrue(fields.contains(prefix + '.JobTitle'), prefix + '.JobTitle should be present');
            Assert.isTrue(fields.contains(prefix + '.Email'), prefix + '.Email should be present');
            Assert.isTrue(fields.contains(prefix + '.Phone'), prefix + '.Phone should be present');
        }

        for (String prefix : new List<String>{'rm', 'rp'}) {
            Assert.isTrue(fields.contains(prefix + '.Name'), prefix + '.Name should be present');
            Assert.isTrue(fields.contains(prefix + '.JobTitle'), prefix + '.JobTitle should be present');
            Assert.isTrue(fields.contains(prefix + '.Email'), prefix + '.Email should be present');
            Assert.isTrue(fields.contains(prefix + '.Phone'), prefix + '.Phone should be present');
            Assert.isTrue(fields.contains(prefix + '.Image'), prefix + '.Image should be present');
        }
    }
}