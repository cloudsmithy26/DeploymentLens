@IsTest
public with sharing class WT_BrokerSnapshotDocGenProvider_T {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(
            Name = 'Acme Test Agency',
            Website = 'https://acme-test.example.com',
            Funding_Method__c = 'Direct',
            WT_Policy_Commission_Funding__c = true,
            Individual_User_Log_ins__c = true,
            Allow_CRB_Quotes__c = false,
            E_Complete_Set_Up__c = true,
            Ecomplete_Quotes_YTD__c = 12,
            Pre_Paid_Income__c = 1000,
            Estimated_Bonus_Amount__c = 2500,
            WT_Number_Of_Referral__c = 4,
            Agency_Lending_Closed_with_Wintrust__c = true,
            Favorite_Team__c = 'Cubs',
            Est_Amount_Financed__c = 50000,
            TTM_Volume__c = 75000,
            YTD_Loans_Current_Year__c = 10,
            YTD_Vol_Variance__c = 0.15,
            Prior_Year_YE_Loans__c = 8
        );
        insert acc;

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Lost Deal 1',
                AccountId = acc.Id,
                Amount = 5000,
                CloseDate = Date.today(),
                Effective_Date__c = Date.today(),
                StageName = 'Lost',
                Lost_Reason__c = 'Rates'
            ),
            new Opportunity(
                Name = 'Top Opp 1',
                AccountId = acc.Id,
                Amount = 20000,
                CloseDate = Date.today(),
                Effective_Date__c = Date.today(),
                StageName = 'Closed Won',
                Loan_Value_Under_Threshold__c = false
            )
        };
        insert opps;
    }

    @IsTest
    static void shouldReturnAllSectionMaps_WhenAccountPopulated() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Test Agency' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = new WT_BrokerSnapshotDocGenProvider().getData(acc.Id);
        Test.stopTest();

        for (String sectionKey : new List<String>{
            'gen', 'scard', 'ecomp', 'comp', 'xsell', 'addval', 'prod', 'histprod', 'lostAccts', 'topOpps'
        }) {
            Assert.isTrue(result.containsKey(sectionKey), sectionKey + ' should be present in the data map');
        }

        Map<String, Object> mapGeneral = (Map<String, Object>) result.get('gen');
        Assert.areEqual('Acme Test Agency', mapGeneral.get('AcctName'), 'AcctName should match');
        Assert.areEqual('https://acme-test.example.com', mapGeneral.get('Web'), 'Web should match');
        Assert.isNull(mapGeneral.get('AcExecEmail'), 'AcExecEmail should be null when lookup chain is empty');

        Map<String, Object> mapScorecard = (Map<String, Object>) result.get('scard');
        Assert.areEqual('Direct', mapScorecard.get('FundMethod'), 'FundMethod should match');
        Assert.areEqual(true, mapScorecard.get('PolComFund'), 'PolComFund should match');

        Map<String, Object> mapProduction = (Map<String, Object>) result.get('prod');
        Assert.areEqual(50000, mapProduction.get('PotBusiness'), 'PotBusiness should match');
    }

    @IsTest
    static void shouldReturnLostAndTopOpportunityRecords_WhenPresent() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Test Agency' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = new WT_BrokerSnapshotDocGenProvider().getData(acc.Id);
        Test.stopTest();

        Map<String, Object> mapLostAccounts = (Map<String, Object>) result.get('lostAccts');
        List<Object> listLostOpportunityRows = (List<Object>) mapLostAccounts.get('records');
        Assert.areEqual(1, listLostOpportunityRows.size(), 'Should return one lost opportunity');
        Map<String, Object> mapLostOpportunityRow = (Map<String, Object>) listLostOpportunityRows.get(0);
        Assert.areEqual('Lost Deal 1', mapLostOpportunityRow.get('Name'), 'Lost opportunity name should match');
        Assert.areEqual('Rates', mapLostOpportunityRow.get('LostRsn'), 'Lost reason should match');

        Map<String, Object> mapTopOpportunities = (Map<String, Object>) result.get('topOpps');
        List<Object> listTopOpportunityRows = (List<Object>) mapTopOpportunities.get('records');
        Assert.areEqual(1, listTopOpportunityRows.size(), 'Should return one top opportunity');
        Map<String, Object> mapTopOpportunityRow = (Map<String, Object>) listTopOpportunityRows.get(0);
        Assert.areEqual('Top Opp 1', mapTopOpportunityRow.get('Name'), 'Top opportunity name should match');
    }

    @IsTest
    static void shouldReturnEmptyMap_WhenAccountNotFound() {
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        Map<String, Object> result = new WT_BrokerSnapshotDocGenProvider().getData(fakeId);
        Test.stopTest();

        Assert.isTrue(result.isEmpty(), 'Should return empty map when Account does not exist');
    }

    @IsTest
    static void shouldReturnFieldNames_FromGetFieldNames() {
        Test.startTest();
        List<String> fields = new WT_BrokerSnapshotDocGenProvider().getFieldNames();
        Test.stopTest();

        Assert.isTrue(fields.size() > 0, 'Should return merge tag names');
        Assert.isTrue(fields.contains('gen.AcctName'), 'gen.AcctName should be present');
        Assert.isTrue(fields.contains('#lostAccts'), 'lostAccts loop start marker should be present');
        Assert.isTrue(fields.contains('/lostAccts'), 'lostAccts loop end marker should be present');
        Assert.isTrue(fields.contains('#topOpps'), 'topOpps loop start marker should be present');
        Assert.isTrue(fields.contains('/topOpps'), 'topOpps loop end marker should be present');
    }
}
