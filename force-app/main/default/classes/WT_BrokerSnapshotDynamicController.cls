/**
* --------------------------------------------------------------------------------------------------------------------------------------------------------
* @Name             WT_BrokerSnapshotDynamicController
----------------------------------------------------------------------------------------------------------------------------------------------------------
* Description:      This class is a custom Visualforce controller designed to dynamically generate a "Broker Snapshot" for an Account record. 
                    This is achieved by querying custom metadata records to determine which fields should be displayed and fetching their values 
                    dynamically from the Account object.
**/
public with sharing class WT_BrokerSnapshotDynamicController
{
    public List<FieldWrapper> listOfFieldWrappers { get; set; }
    public Account accountRecord { get; set; }
    public Id accountId { get; set; }
    public List<Opportunity> listLostAccount { get; set; }
    public List<Opportunity> listTopOpportunity { get; set; }
    public String pageURL;
    public Date startOfYear;
    public Date endOfYear;
    public WT_BrokerSnapshotDynamicController(ApexPages.StandardController standardController) 
    {
        startOfYear = Date.newInstance(Date.today().year(), 1, 1);
        endOfYear = Date.newInstance(Date.today().year(), 12, 31);
        pageURL = ApexPages.currentPage().getUrl();
        accountId = (Id)standardController.getId();
        loadDynamicFields();
        listLostAccount = getLostOpportunities();
        listTopOpportunity = getTopOpportunities();
    }
    
    public PageReference createBrokerSnapshotExternalUsageRecord()
    {
        if(pageURL.toLowerCase().contains('wt_brokersnapshotexternal'))
        {
            Broker_Snapshot_External_Usage__c brokerSnapshotExternalUsage = new Broker_Snapshot_External_Usage__c();
            brokerSnapshotExternalUsage.Executed_By__c = UserInfo.getUserId();
            brokerSnapshotExternalUsage.Executed_on_Agent_Broker__c = accountId;
            try
            {
                INSERT as User brokerSnapshotExternalUsage;
            }
            catch(Exception ex)
            {
                System.debug('Error while insert Broker_Snapshot_External_Usage__c: ' + ex.getMessage());
            	return null;
            }
        }
        return null;
    }
    
    public void loadDynamicFields() 
    {
        // Step 1: Get metadata configuration
        List<WT_Broker_Snapshot__mdt> metadataList = getVisibleMetadata();
        
        // Step 2: Query Account with dynamic fields
        Set<String> fieldAPINames = extractFieldAPINames(metadataList);
        accountRecord = queryAccount(fieldAPINames);
        
        // Step 3: Build display wrappers
        listOfFieldWrappers = buildFieldWrappers(metadataList);
    }
    
    private List<Opportunity> getLostOpportunities() { 
        return [SELECT Id, Name, Amount, Effective_Date__c, StageName, Lost_Reason__c
                FROM Opportunity 
                WHERE (StageName = 'Lost' OR StageName = 'Lost - No Follow up') 
                AND (Lost_Reason__c = 'Rates' OR Lost_Reason__c = 'Terms') 
                AND accountId =: accountId
                WITH USER_MODE
                ORDER BY Amount DESC
                LIMIT 3];
    }
    
    private List<Opportunity> getTopOpportunities() { 
        return [SELECT Id, Name, Amount, Effective_Date__c, StageName 
                FROM Opportunity 
                WHERE Loan_Value_Under_Threshold__c = false 
                AND (( CloseDate >=: startOfYear AND CloseDate <=: endOfYear ) 
                     OR (Effective_Date__c >=: startOfYear AND Effective_Date__c <=: endOfYear))
                AND Amount != NULL
                AND accountId =: accountId
                WITH USER_MODE 
                ORDER BY Amount DESC
                LIMIT 5];
    }
    
    private List<WT_Broker_Snapshot__mdt> getVisibleMetadata() 
    {
        return [SELECT WT_Field_Label__c, WT_Field_API__c 
                FROM WT_Broker_Snapshot__mdt 
                WHERE WT_Is_Visible__c = true                                                                         
                WITH USER_MODE
                ORDER BY MasterLabel DESC];
    }
    
    private Set<String> extractFieldAPINames(List<WT_Broker_Snapshot__mdt> metadataList) 
    {
        Set<String> fieldAPINames = new Set<String>();
        for (WT_Broker_Snapshot__mdt metadata : metadataList) 
        {
            // Escape single quotes to prevent SOQL injection
            fieldAPINames.add(String.escapeSingleQuotes(metadata.WT_Field_API__c));
        }
        return fieldAPINames;
    }
    
    private Account queryAccount(Set<String> fieldAPINames) 
    {
        if (fieldAPINames.isEmpty()) {
            return null;
        }        
        String fieldsClause = String.escapeSingleQuotes(String.join(new List<String>(fieldAPINames), ', '));
        String query = 'SELECT Id, ' + fieldsClause + ' FROM Account WHERE Id = :accountId ' +
                      'ORDER BY CreatedDate Desc';        
        try {
            return Database.query(query,AccessLevel.USER_MODE);
        }
        catch (Exception ex) {
            System.debug('Error querying Account: ' + ex.getMessage());
            return null;
        }
    }
    
    private List<FieldWrapper> buildFieldWrappers(List<WT_Broker_Snapshot__mdt> metadataList) 
    {
        List<FieldWrapper> wrappers = new List<FieldWrapper>();
        
        for (WT_Broker_Snapshot__mdt metadata : metadataList)
        {
            Object fieldValue = getFieldValue(metadata.WT_Field_API__c);
            wrappers.add(new FieldWrapper(metadata.WT_Field_Label__c, fieldValue));
        }
        
        return wrappers;
    }
    
    private Object getFieldValue(String fieldAPI) 
    {
        if (accountRecord == null) {
            return 'No data';
        }
        
        try {
            Object rawValue = accountRecord.get(fieldAPI);
            if (rawValue == null) {
                return '';
            }
            return formatValue(rawValue);
        }
        catch (Exception ex){
            return 'Field not found or inaccessible';
        }
    }
    
    private Object formatValue(Object value) 
    {
        String strValue = String.valueOf(value);
        try {
            if (strValue.contains('.')) {
                return Decimal.valueOf(strValue).format();
            } 
            else {
                return Integer.valueOf(strValue).format();
            }
        }
        catch (Exception e) {
            return value;
        }
    }
    public class FieldWrapper
    {
        public String label { get; set; }
        public Object value { get; set; }
        public Boolean isDollarField { get; set; }
        public FieldWrapper(String label, Object value)
        {
            this.label = label;
            this.value = value;
            this.isDollarField = label.contains('Income'); 
        }
    }
}