@IsTest
private class WT_BrokerSnapshotDocGenController_T {

    @TestSetup
    static void setupTestData() {
        insert new Account(Name = 'Broker Snapshot Test Account');
    }

    /** Inserts a ContentVersion titled "Broker Snapshot", links it to the given record via
     *  ContentDocumentLink (mirroring what portwoodglobal.DocGenService.generateDocument does
     *  when passed an attachmentRecordId), and optionally backdates it so retention-order
     *  tests can control which file looks "oldest". Returns the new ContentDocumentId. */
    private static Id insertLinkedBrokerSnapshotVersion(Id linkedRecordId, Datetime createdDateOverride) {
        ContentVersion newContentVersion = new ContentVersion(
            Title = 'Broker Snapshot',
            PathOnClient = 'Broker Snapshot.pdf',
            VersionData = Blob.valueOf('fake pdf bytes')
        );
        insert newContentVersion;

        Id newContentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :newContentVersion.Id
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = newContentDocumentId,
            LinkedEntityId = linkedRecordId,
            ShareType = 'V'
        );

        if (createdDateOverride != null) {
            Test.setCreatedDate(newContentVersion.Id, createdDateOverride);
            Test.setCreatedDate(newContentDocumentId, createdDateOverride);
        }

        return newContentDocumentId;
    }

    @IsTest
    static void shouldFail_WhenRecordIdIsNull() {
        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.generate(
            null
        );
        Test.stopTest();

        Assert.isFalse(result.success, 'Should not succeed with a null recordId');
        Assert.areEqual('No Account record was provided.', result.errorMessage, 'Error message should match');
    }

    @IsTest
    static void shouldFail_WhenDocGenSettingHasNoTemplateId() {
        // Custom Metadata Type records ARE visible in Apex tests (unlike normal custom
        // object rows), so the override seam is used here to control the outcome
        // deterministically instead of depending on what is actually configured in the org.
        WT_BrokerSnapshotDocGenController.docGenSettingOverride = new WT_Broker_Snapshot_DocGen_Setting__mdt(
            Template_Id__c = null
        );
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.generate(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isFalse(result.success, 'Should fail when no template Id is configured');
        Assert.isTrue(
            result.errorMessage.contains('No Portwood template Id configured'),
            'Error message should explain the missing configuration'
        );
    }

    @IsTest
    static void shouldFail_WhenDocGenSettingTemplateIdIsInvalid() {
        WT_BrokerSnapshotDocGenController.docGenSettingOverride = new WT_Broker_Snapshot_DocGen_Setting__mdt(
            Template_Id__c = 'not-a-valid-id'
        );
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.generate(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isFalse(result.success, 'Should fail when the configured Template_Id__c is not a valid Id');
        Assert.isTrue(
            result.errorMessage.contains('is not a valid Salesforce Id'),
            'Error message should explain the invalid Id'
        );
    }

    @IsTest
    static void shouldReturnDownloadableResult_WhenDocumentAlreadyGenerated() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Id newContentDocumentId = insertLinkedBrokerSnapshotVersion(testAccount.Id, null);
        WT_BrokerSnapshotDocGenController.generatedContentDocumentIdOverride = newContentDocumentId;

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.generate(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Should succeed when a document is already available: ' + result.errorMessage);
        Assert.areEqual('Broker Snapshot.pdf', result.fileName, 'File name should include the extension');
        Assert.areEqual('application/pdf', result.mimeType, 'Mime type should resolve for pdf');
        Assert.isNotNull(result.base64Data, 'Small files should be returned inline as base64');
        Assert.isNotNull(result.generatedDate, 'generatedDate should be populated from the ContentVersion');
        Assert.isTrue(
            result.downloadUrl.contains(String.valueOf(result.contentVersionId)),
            'Download URL should reference the ContentVersion'
        );
    }

    @IsTest
    static void shouldPruneOldestDocuments_WhenMoreThanTwoBrokerSnapshotsExist() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Three pre-existing snapshots, oldest to newest, simulating three earlier clicks.
        insertLinkedBrokerSnapshotVersion(testAccount.Id, Datetime.now().addDays(-3));
        Id secondOldestContentDocumentId = insertLinkedBrokerSnapshotVersion(testAccount.Id, Datetime.now().addDays(-2));
        insertLinkedBrokerSnapshotVersion(testAccount.Id, Datetime.now().addDays(-1));

        // The "new" snapshot generate() is about to return, standing in for a real Portwood
        // generation via the test override seam.
        Id newestContentDocumentId = insertLinkedBrokerSnapshotVersion(testAccount.Id, null);
        WT_BrokerSnapshotDocGenController.generatedContentDocumentIdOverride = newestContentDocumentId;

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.generate(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Generation should succeed: ' + result.errorMessage);

        List<ContentDocumentLink> listRemainingLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testAccount.Id AND ContentDocument.Title = 'Broker Snapshot'
        ];
        Assert.areEqual(2, listRemainingLinks.size(), 'Only the two most recent Broker Snapshots should remain');

        Set<Id> setRemainingContentDocumentIds = new Set<Id>();
        for (ContentDocumentLink remainingLink : listRemainingLinks) {
            setRemainingContentDocumentIds.add(remainingLink.ContentDocumentId);
        }
        Assert.isTrue(
            setRemainingContentDocumentIds.contains(newestContentDocumentId),
            'The just-generated document should be retained'
        );
        Assert.isTrue(
            setRemainingContentDocumentIds.contains(secondOldestContentDocumentId),
            'The second-newest pre-existing document should be retained'
        );
    }

    @IsTest
    static void shouldFail_WhenNoBrokerSnapshotHasBeenGeneratedYet() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.getLatestBrokerSnapshot(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isFalse(result.success, 'Should fail when no Broker Snapshot exists yet');
        Assert.isTrue(
            result.errorMessage.contains('No Broker Snapshot has been generated'),
            'Error message should explain that nothing has been generated yet'
        );
    }

    @IsTest
    static void shouldReturnMostRecentDocument_WhenMultipleSnapshotsExist() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        insertLinkedBrokerSnapshotVersion(testAccount.Id, Datetime.now().addDays(-1));
        Id latestContentDocumentId = insertLinkedBrokerSnapshotVersion(testAccount.Id, null);

        Test.startTest();
        WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult result = WT_BrokerSnapshotDocGenController.getLatestBrokerSnapshot(
            testAccount.Id
        );
        Test.stopTest();

        Assert.isTrue(result.success, 'Should find the most recent Broker Snapshot: ' + result.errorMessage);
        Assert.areEqual(latestContentDocumentId, result.contentDocumentId, 'Should return the newest document');
        Assert.isNotNull(result.generatedDate, 'generatedDate should be populated');
    }
}
