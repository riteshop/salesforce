public with sharing class DocumentRequestFileController {

    @AuraEnabled(cacheable=true)
    public static String getLatestFileForRecord(Id recordId) {
        ContentDocumentLink cdl = [
            SELECT ContentDocumentId, ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        return cdl.ContentDocumentId;
    }

    @AuraEnabled(cacheable=false)
    public static String getPdfBase64(String contentDocumentId) {
        if (contentDocumentId == null) return null;

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];

        return EncodingUtil.base64Encode(cv.VersionData);
    }
}