public with sharing class PdfTemplateFileController {

    /**
     * Returns the latest PDF file attached to a PDF_Template__c record
     * as a Base64-encoded string so it can be rendered by PDF.js in LWC.
     */
    @AuraEnabled(cacheable=true)
    public static String getLatestTemplatePdfBase64(Id templateId) {
        if (templateId == null) {
            return null;
        }

        // Find the most recently linked file
        ContentDocumentLink cdl = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :templateId
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];

        // Get the latest version of that file
        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :cdl.ContentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];

        // Return Base64 PDF bytes
        return EncodingUtil.base64Encode(cv.VersionData);
    }

}