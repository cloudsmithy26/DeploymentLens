/**
 * @Description: Apex controller behind the wt_BrokerSnapshotExternalDocGen LWC — the
 * "External" counterpart to WT_BrokerSnapshotDocGenController, mirroring the logic that used
 * to live in WT_BrokerSnapshotExternal.page (which reused WT_BrokerSnapshotDynamicController
 * but rendered a trimmed field set and logged a Broker_Snapshot_External_Usage__c record on
 * every render). This controller is intentionally self-contained (its own template setting
 * field, its own document title, its own retention/lookup logic) rather than sharing code
 * with WT_BrokerSnapshotDocGenController, so the two document variants can be configured and
 * maintained independently.
 *
 * Reuses WT_BrokerSnapshotDocGenProvider as the Portwood data provider — the External
 * template needs a subset of the same Account/Opportunity data the Dynamic template uses (no
 * new Apex query logic), it simply references fewer of the provider's merge tags. Only the
 * template layout and the usage-tracking side effect are specific to "External".
 */
public with sharing class WT_BrokerSnapshotExternalDocGenController {
    // Developer Name of the single WT_Broker_Snapshot_DocGen_Setting__mdt record. Shares the
    // same Custom Metadata Type record as the Dynamic controller, but reads a different field
    // (External_Template_Id__c) so the two document variants can point at different Portwood
    // templates without needing two Custom Metadata Types.
    private static final String DOCGEN_SETTING_DEVELOPER_NAME = 'Default';

    // Distinct from WT_BrokerSnapshotDocGenController.DOCUMENT_TITLE ("Broker Snapshot") on
    // purpose: both controllers can attach files to the same Account, and each one's
    // "latest snapshot" lookup and 2-document retention policy must only ever see the files
    // it created itself, never the other variant's.
    private static final String DOCUMENT_TITLE = 'Broker Snapshot External';

    private static final Integer MAX_RETAINED_DOCUMENTS = 2;

    @TestVisible
    private static Integer inlineDownloadMaxBytes = 3500000; // ~3.5 MB

    public class WT_BrokerSnapshotExternalDocGenException extends Exception {
    }

    /** Client-facing result shape — deliberately the same field set as
     *  WT_BrokerSnapshotDocGenController.BrokerSnapshotDocumentResult, defined separately so
     *  this controller has no compile-time dependency on the Dynamic controller. */
    public class BrokerSnapshotDocumentResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public String mimeType;
        @AuraEnabled
        public String base64Data;
        @AuraEnabled
        public String downloadUrl;
        @AuraEnabled
        public Id contentDocumentId;
        @AuraEnabled
        public Id contentVersionId;
        @AuraEnabled
        public Datetime generatedDate;
    }

    // Test-only seam: lets tests skip the real Portwood template lookup + generation call and
    // instead point generate() at a ContentDocument the test already created.
    @TestVisible
    private static Id generatedContentDocumentIdOverride;

    // Test-only seam: Custom Metadata Type records are visible in Apex tests by default, so
    // without this override a test would depend on whatever External_Template_Id__c happens
    // to be configured in the org the test runs in.
    @TestVisible
    private static WT_Broker_Snapshot_DocGen_Setting__mdt docGenSettingOverride;

    /** Generates a new "Broker Snapshot External" PDF for the given Account, attaches it to
     *  that Account's Files, logs a Broker_Snapshot_External_Usage__c audit record (mirroring
     *  WT_BrokerSnapshotDynamicController.createBrokerSnapshotExternalUsageRecord, which fired
     *  on every render of the legacy external page), prunes older generated External
     *  snapshots down to MAX_RETAINED_DOCUMENTS, and returns the new file for the LWC to
     *  preview/download. */
    @AuraEnabled
    public static BrokerSnapshotDocumentResult generate(Id recordId) {
        BrokerSnapshotDocumentResult documentResult = new BrokerSnapshotDocumentResult();
        try {
            if (recordId == null) {
                throw new WT_BrokerSnapshotExternalDocGenException('No Account record was provided.');
            }

            Id generatedContentDocumentId;
            if (generatedContentDocumentIdOverride != null) {
                generatedContentDocumentId = generatedContentDocumentIdOverride;
            } else {
                Id templateId = resolveTemplateId();
                // attachmentRecordId = recordId links the generated file to the Account's
                // Files related list (rather than creating a standalone, unattached file).
                generatedContentDocumentId = portwoodglobal.DocGenService.generateDocument(
                    templateId,
                    recordId,
                    'PDF',
                    DOCUMENT_TITLE,
                    recordId
                );
            }

            if (generatedContentDocumentId == null) {
                throw new WT_BrokerSnapshotExternalDocGenException('Portwood did not return a document.');
            }

            documentResult = buildResultFromContentDocument(generatedContentDocumentId);

            // Every successful External generation is audited — this is the one piece of
            // "External" logic the legacy page had that Dynamic never did. A logging failure
            // must not hide the fact that the PDF itself was generated successfully, so it is
            // caught and logged rather than surfaced as an error (same non-blocking behavior
            // as the legacy page's own try/catch around this insert).
            logExternalUsage(recordId);

            // Cleanup runs after a successful generation so the user always gets their new
            // file even if the retention pass hits an unexpected error.
            retainOnlyLatestDocuments(recordId);

            return documentResult;
        } catch (Exception generationException) {
            documentResult.success = false;
            documentResult.errorMessage = generationException.getMessage();
            return documentResult;
        }
    }

    /** Returns the most recently generated "Broker Snapshot External" already attached to
     *  this Account, or a result with success = false when none exists yet. */
    @AuraEnabled
    public static BrokerSnapshotDocumentResult getLatestBrokerSnapshot(Id recordId) {
        BrokerSnapshotDocumentResult documentResult = new BrokerSnapshotDocumentResult();
        try {
            if (recordId == null) {
                throw new WT_BrokerSnapshotExternalDocGenException('No Account record was provided.');
            }

            List<ContentDocumentLink> listBrokerSnapshotLinks = queryBrokerSnapshotLinks(recordId);
            if (listBrokerSnapshotLinks.isEmpty()) {
                throw new WT_BrokerSnapshotExternalDocGenException(
                    'No Broker Snapshot External has been generated for this Account yet.'
                );
            }

            // queryBrokerSnapshotLinks() orders newest first, so the first row is the most
            // recently generated snapshot.
            documentResult = buildResultFromContentDocument(listBrokerSnapshotLinks.get(0).ContentDocumentId);
            return documentResult;
        } catch (Exception lookupException) {
            documentResult.success = false;
            documentResult.errorMessage = lookupException.getMessage();
            return documentResult;
        }
    }

    /** Inserts the audit record tracking who generated an External Broker Snapshot and for
     *  which Account — mirrors createBrokerSnapshotExternalUsageRecord() on the legacy
     *  WT_BrokerSnapshotDynamicController, minus the page-URL check (that existed only to let
     *  one Apex controller serve two Visualforce pages; this controller only ever backs the
     *  External LWC, so every call here is, by definition, an External generation). */
    private static void logExternalUsage(Id recordId) {
        try {
            Broker_Snapshot_External_Usage__c usageRecord = new Broker_Snapshot_External_Usage__c(
                Executed_By__c = UserInfo.getUserId(),
                Executed_on_Agent_Broker__c = recordId
            );
            insert as user usageRecord;
        } catch (Exception usageLoggingException) {
            System.debug(
                LoggingLevel.WARN,
                'WT_BrokerSnapshotExternalDocGenController.logExternalUsage failed for Account ' +
                    recordId +
                    ': ' +
                    usageLoggingException.getMessage()
            );
        }
    }

    /** Reads a ContentVersion back for the given ContentDocument and builds the DTO the LWC
     *  consumes — shared by generate() and getLatestBrokerSnapshot() so both code paths stay
     *  in sync. */
    private static BrokerSnapshotDocumentResult buildResultFromContentDocument(Id contentDocumentId) {
        BrokerSnapshotDocumentResult documentResult = new BrokerSnapshotDocumentResult();

        List<ContentVersion> listMatchingContentVersions = [
            SELECT Id, Title, FileExtension, ContentSize, ContentDocumentId, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (listMatchingContentVersions.isEmpty()) {
            throw new WT_BrokerSnapshotExternalDocGenException(
                'The document could not be read back. Check file sharing/visibility.'
            );
        }
        ContentVersion latestContentVersion = listMatchingContentVersions[0];

        documentResult.success = true;
        documentResult.contentVersionId = latestContentVersion.Id;
        documentResult.contentDocumentId = latestContentVersion.ContentDocumentId;
        documentResult.generatedDate = latestContentVersion.CreatedDate;
        documentResult.fileName = buildFileName(latestContentVersion);
        documentResult.mimeType = mimeTypeForExtension(latestContentVersion.FileExtension);
        documentResult.downloadUrl = '/sfc/servlet.shepherd/version/download/' + latestContentVersion.Id;

        if (latestContentVersion.ContentSize != null && latestContentVersion.ContentSize <= inlineDownloadMaxBytes) {
            List<ContentVersion> listContentVersionsWithData = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Id = :latestContentVersion.Id
                WITH USER_MODE
                LIMIT 1
            ];
            if (!listContentVersionsWithData.isEmpty() && listContentVersionsWithData[0].VersionData != null) {
                documentResult.base64Data = EncodingUtil.base64Encode(listContentVersionsWithData[0].VersionData);
            }
        }

        return documentResult;
    }

    /** Deletes the oldest generated External snapshots on the Account once more than
     *  MAX_RETAINED_DOCUMENTS exist. Only ContentDocuments titled exactly DOCUMENT_TITLE
     *  ("Broker Snapshot External") are touched, so this never removes a Dynamic-variant
     *  snapshot (titled "Broker Snapshot") or any file the user attached manually. Swallows
     *  its own errors (logging only) so a cleanup failure never hides the fact that the new
     *  PDF was generated successfully. */
    private static void retainOnlyLatestDocuments(Id recordId) {
        try {
            List<ContentDocumentLink> listBrokerSnapshotLinks = queryBrokerSnapshotLinks(recordId);
            if (listBrokerSnapshotLinks.size() <= MAX_RETAINED_DOCUMENTS) {
                return;
            }

            Set<Id> setContentDocumentIdsToDelete = new Set<Id>();
            // queryBrokerSnapshotLinks() orders newest first, so everything from
            // MAX_RETAINED_DOCUMENTS onward is older than the snapshots we want to keep.
            for (Integer linkIndex = MAX_RETAINED_DOCUMENTS; linkIndex < listBrokerSnapshotLinks.size(); linkIndex++) {
                setContentDocumentIdsToDelete.add(listBrokerSnapshotLinks[linkIndex].ContentDocumentId);
            }

            List<ContentDocument> listContentDocumentsToDelete = [
                SELECT Id FROM ContentDocument WHERE Id IN :setContentDocumentIdsToDelete WITH USER_MODE
            ];
            // Deleting the ContentDocument cascades to its ContentVersion(s) and
            // ContentDocumentLink(s) — no separate delete needed for those.
            delete as user listContentDocumentsToDelete;
        } catch (Exception cleanupException) {
            System.debug(
                LoggingLevel.WARN,
                'WT_BrokerSnapshotExternalDocGenController.retainOnlyLatestDocuments failed for Account ' +
                    recordId +
                    ': ' +
                    cleanupException.getMessage()
            );
        }
    }

    /** Broker Snapshot External files linked to the given Account, newest first. Shared by
     *  the "find the latest one" and "prune everything past the keep-limit" code paths so
     *  both agree on which files count as generated External snapshots. */
    private static List<ContentDocumentLink> queryBrokerSnapshotLinks(Id recordId) {
        return [
            SELECT ContentDocumentId, ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND ContentDocument.Title = :DOCUMENT_TITLE
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
        ];
    }

    /** Looks up the active Portwood template Id from
     *  WT_Broker_Snapshot_DocGen_Setting__mdt.External_Template_Id__c — the same Custom
     *  Metadata Type record WT_BrokerSnapshotDocGenController reads, but a different field,
     *  so the Dynamic and External document variants can point at two different Portwood
     *  templates from one settings record. */
    private static Id resolveTemplateId() {
        WT_Broker_Snapshot_DocGen_Setting__mdt docGenSetting = (docGenSettingOverride != null)
            ? docGenSettingOverride
            : WT_Broker_Snapshot_DocGen_Setting__mdt.getInstance(DOCGEN_SETTING_DEVELOPER_NAME);

        if (docGenSetting == null || String.isBlank(docGenSetting.External_Template_Id__c)) {
            throw new WT_BrokerSnapshotExternalDocGenException(
                'No Portwood template Id configured on WT_Broker_Snapshot_DocGen_Setting__mdt.' +
                    DOCGEN_SETTING_DEVELOPER_NAME +
                    '.External_Template_Id__c. Set it to the Id of the "Broker Snapshot External" template after creating it in the Portwood app.'
            );
        }

        try {
            return (Id) docGenSetting.External_Template_Id__c;
        } catch (Exception invalidIdException) {
            throw new WT_BrokerSnapshotExternalDocGenException(
                'WT_Broker_Snapshot_DocGen_Setting__mdt.' +
                    DOCGEN_SETTING_DEVELOPER_NAME +
                    '.External_Template_Id__c is not a valid Salesforce Id: "' +
                    docGenSetting.External_Template_Id__c +
                    '".'
            );
        }
    }

    private static String buildFileName(ContentVersion contentVersionRecord) {
        String baseFileName = String.isNotBlank(contentVersionRecord.Title) ? contentVersionRecord.Title : DOCUMENT_TITLE;
        String fileExtension = String.isNotBlank(contentVersionRecord.FileExtension)
            ? contentVersionRecord.FileExtension.toLowerCase()
            : 'pdf';
        return baseFileName.endsWithIgnoreCase('.' + fileExtension) ? baseFileName : baseFileName + '.' + fileExtension;
    }

    private static String mimeTypeForExtension(String fileExtension) {
        String normalizedExtension = (fileExtension == null) ? '' : fileExtension.toLowerCase();
        Map<String, String> mapExtensionToMimeType = new Map<String, String>{
            'pdf' => 'application/pdf',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'doc' => 'application/msword'
        };
        return mapExtensionToMimeType.containsKey(normalizedExtension)
            ? mapExtensionToMimeType.get(normalizedExtension)
            : 'application/octet-stream';
    }
}
