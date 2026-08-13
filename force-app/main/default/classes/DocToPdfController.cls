/**
 * DocToPdfController
 * -------------------
 * Backs the docToPdfGenerator LWC. Two entry points:
 *   1. getWordFiles(recordId)   - lists .docx/.doc Files already on the record
 *   2. generatePdf(contentVersionId, recordId) - converts the selected file
 *      to PDF (via DocConversionProvider / Adobe PDF Services) and saves the
 *      result as a new File on the same record.
 *
 * Conversion logic itself lives in DocConversionProvider.cls (unchanged from
 * the earlier REST-based version) — this class only handles the
 * Salesforce-native plumbing: finding the file, running the conversion, and
 * filing the result back as a ContentVersion.
 */
public with sharing class DocToPdfController {

    public class WordFileWrapper {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;

        public WordFileWrapper(ContentVersion cv) {
            this.contentVersionId = cv.Id;
            this.contentDocumentId = cv.ContentDocumentId;
            this.title = cv.Title;
            this.fileExtension = cv.FileExtension;
        }
    }

    public class GeneratePdfResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id newContentDocumentId;
        @AuraEnabled public Id newContentVersionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String errorMessage;
    }

    /**
     * Returns the Word files (.docx/.doc) already attached to the given record,
     * most recently modified first, so the LWC can offer a picker.
     */
    @AuraEnabled(cacheable=true)
    public static List<WordFileWrapper> getWordFiles(Id recordId) {
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ]) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        List<WordFileWrapper> results = new List<WordFileWrapper>();
        if (contentDocumentIds.isEmpty()) {
            return results;
        }

        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
              AND IsLatest = true
              AND FileExtension IN ('docx', 'doc')
            ORDER BY LastModifiedDate DESC
        ]) {
            results.add(new WordFileWrapper(cv));
        }
        return results;
    }

    /**
     * Converts the selected Word file to PDF and saves the result as a new
     * File on the same record. Returns info the LWC needs to show/download it.
     */
    @AuraEnabled
    public static GeneratePdfResult generatePdf(Id contentVersionId, Id recordId) {
        GeneratePdfResult result = new GeneratePdfResult();

        try {
            ContentVersion sourceVersion = [
                SELECT Id, Title, FileExtension, VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            String base64Docx = EncodingUtil.base64Encode(sourceVersion.VersionData);
            String sourceFileName = sourceVersion.Title + '.' + sourceVersion.FileExtension;

            // Callout happens before any DML below — required ordering in Apex.
            DocConversionProvider.ConversionResult conversionResult =
                DocConversionProvider.convertDocxToPdf(sourceFileName, base64Docx);

            if (!conversionResult.success) {
                result.success = false;
                result.errorMessage = conversionResult.errorMessage;
                return result;
            }

            ContentVersion pdfVersion = new ContentVersion();
            pdfVersion.Title = conversionResult.outputFileName;
            pdfVersion.PathOnClient = conversionResult.outputFileName;
            pdfVersion.VersionData = EncodingUtil.base64Decode(conversionResult.base64Pdf);
            insert pdfVersion;

            // Re-query to get the ContentDocumentId Salesforce assigned to the new version.
            Id newContentDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
                LIMIT 1
            ].ContentDocumentId;

            insert new ContentDocumentLink(
                ContentDocumentId = newContentDocumentId,
                LinkedEntityId = recordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );

            result.success = true;
            result.newContentDocumentId = newContentDocumentId;
            result.newContentVersionId = pdfVersion.Id;
            result.fileName = conversionResult.outputFileName;
            return result;

        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + ex.getMessage();
            return result;
        }
    }
}
