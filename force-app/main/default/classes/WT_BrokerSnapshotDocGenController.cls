/**
 * @Description: Apex controller behind the wt_BrokerSnapshotDocGen LWC. Resolves the
 * "Broker Snapshot" Portwood template Id from WT_Broker_Snapshot_DocGen_Setting__mdt (a
 * single-record Custom Metadata Type an admin fills in after creating the template in the
 * Portwood app — see docs/templates/README.md), generates the document through
 * portwoodglobal.DocGenService.generateDocument — the same global entry point the Portwood
 * Runner/Button components use — attaches it to the Account, and returns the file for
 * client-side preview/download. Also exposes the most recently generated snapshot so the LWC
 * can show "last generated on ..." without forcing a fresh PDF render.
 *
 * portwoodglobal.DocGenButtonController is not usable directly here: it is `public`, not
 * `global`, so it is only callable from Apex inside the managed package (e.g. by the
 * docGenButton quick action, which ships in that same package). A record-page LWC living in
 * this org's own namespace can only call the package's `global` surface, which is
 * portwoodglobal.DocGenService's generateDocument / generatePdfBlob family of methods.
 */
public with sharing class WT_BrokerSnapshotDocGenController {
    // Developer Name of the single WT_Broker_Snapshot_DocGen_Setting__mdt record that holds
    // the Portwood template Id. Using Custom Metadata (rather than a hard-coded template API
    // Name or a cross-package dynamic SOQL lookup) means an admin can repoint this at a
    // different template Id per sandbox/production straight from Setup, with no Apex change
    // and no dependency on portwoodglobal's schema being directly queryable from this org.
    private static final String DOCGEN_SETTING_DEVELOPER_NAME = 'Default';

    // The exact ContentVersion/ContentDocument Title every generated snapshot is saved
    // under. Doubles as the marker used to find/prune this org's Broker Snapshot files
    // among an Account's other Files without touching anything the user uploaded manually.
    private static final String DOCUMENT_TITLE = 'Broker Snapshot';

    // How many generated snapshots to keep attached to an Account. Every successful
    // generate() call re-applies this limit, so older files are removed automatically —
    // there is no separate scheduled cleanup job.
    private static final Integer MAX_RETAINED_DOCUMENTS = 2;

    // Files at/under this byte size are returned inline as base64 so the LWC can preview
    // and download them without a second server round trip; larger files fall back to the
    // file-servlet download URL below.
    @TestVisible
    private static Integer inlineDownloadMaxBytes = 3500000; // ~3.5 MB

    public class WT_BrokerSnapshotDocGenException extends Exception {
    }

    /** Client-facing result shape, shared by generate() and getLatestBrokerSnapshot() so the
     *  LWC can render either one (a freshly generated file, or a previously generated file
     *  loaded on page load) through the same preview/download UI. */
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

    // Test-only seam: lets tests skip the real Portwood template lookup + generation call
    // (which needs a live Portwood template that Apex tests cannot see/insert) and instead
    // point generate() at a ContentDocument the test already created.
    @TestVisible
    private static Id generatedContentDocumentIdOverride;

    /** Generates a new Broker Snapshot PDF for the given Account, attaches it to that
     *  Account's Files, prunes older generated snapshots down to MAX_RETAINED_DOCUMENTS,
     *  and returns the new file for the LWC to preview/download. */
    @AuraEnabled
    public static BrokerSnapshotDocumentResult generate(Id recordId) {
        BrokerSnapshotDocumentResult documentResult = new BrokerSnapshotDocumentResult();
        try {
            if (recordId == null) {
                throw new WT_BrokerSnapshotDocGenException('No Account record was provided.');
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
                throw new WT_BrokerSnapshotDocGenException('Portwood did not return a document.');
            }

            documentResult = buildResultFromContentDocument(generatedContentDocumentId);

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

    /** Returns the most recently generated Broker Snapshot already attached to this
     *  Account, or a result with success = false when none exists yet. Lets the LWC show
     *  "last generated on ..." (and a preview) on page load without generating a new PDF. */
    @AuraEnabled
    public static BrokerSnapshotDocumentResult getLatestBrokerSnapshot(Id recordId) {
        BrokerSnapshotDocumentResult documentResult = new BrokerSnapshotDocumentResult();
        try {
            if (recordId == null) {
                throw new WT_BrokerSnapshotDocGenException('No Account record was provided.');
            }

            List<ContentDocumentLink> listBrokerSnapshotLinks = queryBrokerSnapshotLinks(recordId);
            if (listBrokerSnapshotLinks.isEmpty()) {
                throw new WT_BrokerSnapshotDocGenException('No Broker Snapshot has been generated for this Account yet.');
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

    /** Reads a ContentVersion back for the given ContentDocument and builds the DTO the LWC
     *  consumes — shared by generate() (right after creating a new file) and
     *  getLatestBrokerSnapshot() (for a file created by an earlier click) so both code paths
     *  stay in sync. */
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
            throw new WT_BrokerSnapshotDocGenException(
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

    /** Deletes the oldest generated Broker Snapshot files on the Account once more than
     *  MAX_RETAINED_DOCUMENTS exist, so Files only ever shows the most recent snapshots
     *  instead of accumulating one per click forever. Only ContentDocuments titled exactly
     *  DOCUMENT_TITLE are touched — any other file the user attached to the Account is left
     *  alone. Swallows its own errors (logging only) so a cleanup failure never hides the
     *  fact that the new PDF was generated successfully. */
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
                'WT_BrokerSnapshotDocGenController.retainOnlyLatestDocuments failed for Account ' +
                    recordId +
                    ': ' +
                    cleanupException.getMessage()
            );
        }
    }

    /** Broker Snapshot files linked to the given Account, newest first. Shared by the
     *  "find the latest one" and "prune everything past the keep-limit" code paths so both
     *  agree on which files count as generated Broker Snapshots. */
    private static List<ContentDocumentLink> queryBrokerSnapshotLinks(Id recordId) {
        return [
            SELECT ContentDocumentId, ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND ContentDocument.Title = :DOCUMENT_TITLE
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
        ];
    }

    // Test-only seam: Custom Metadata Type records are visible in Apex tests by default
    // (unlike normal custom object rows), so without this override a test would depend on
    // whatever Template_Id__c happens to be configured in the org the test runs in. This
    // lets tests control the "is a template configured" outcome deterministically instead.
    @TestVisible
    private static WT_Broker_Snapshot_DocGen_Setting__mdt docGenSettingOverride;

    /** Looks up the active Portwood template Id from WT_Broker_Snapshot_DocGen_Setting__mdt.
     *  Custom Metadata Type records are always readable by any authenticated user (no CRUD/FLS
     *  or cross-package schema-visibility concerns), so this avoids both the earlier hard-coded
     *  template API Name and the uncertainty of querying portwoodglobal's own schema directly. */
    private static Id resolveTemplateId() {
        WT_Broker_Snapshot_DocGen_Setting__mdt docGenSetting = (docGenSettingOverride != null)
            ? docGenSettingOverride
            : WT_Broker_Snapshot_DocGen_Setting__mdt.getInstance(DOCGEN_SETTING_DEVELOPER_NAME);

        if (docGenSetting == null || String.isBlank(docGenSetting.Template_Id__c)) {
            throw new WT_BrokerSnapshotDocGenException(
                'No Portwood template Id configured on WT_Broker_Snapshot_DocGen_Setting__mdt.' +
                    DOCGEN_SETTING_DEVELOPER_NAME +
                    '. Set Template_Id__c to the Id of the "Broker Snapshot" template after creating it in the Portwood app.'
            );
        }

        try {
            return (Id) docGenSetting.Template_Id__c;
        } catch (Exception invalidIdException) {
            throw new WT_BrokerSnapshotDocGenException(
                'WT_Broker_Snapshot_DocGen_Setting__mdt.' +
                    DOCGEN_SETTING_DEVELOPER_NAME +
                    '.Template_Id__c is not a valid Salesforce Id: "' +
                    docGenSetting.Template_Id__c +
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
