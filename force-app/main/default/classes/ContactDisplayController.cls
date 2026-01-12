public with sharing class ContactDisplayController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRelatedNotes(Id contactId) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        if (contactId == null) return results;

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title,
                   ContentDocument.LatestPublishedVersion.VersionData,
                   ContentDocument.LatestPublishedVersion.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contactId
              AND ContentDocument.FileType = 'SNOTE'
            ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
            LIMIT 10
        ];

        for (ContentDocumentLink link : links) {
            Map<String, Object> item = new Map<String, Object>();
            item.put('Id', link.ContentDocumentId);
            item.put('Title', link.ContentDocument.Title);
            item.put('CreatedDate', link.ContentDocument.LatestPublishedVersion.CreatedDate);
            item.put('Body', link.ContentDocument.LatestPublishedVersion.VersionData != null ?
                link.ContentDocument.LatestPublishedVersion.VersionData.toString() : '');
            results.add(item);
        }

        return results;
    }

    // ✅ FIXED: make this callable from LWC
    @AuraEnabled
    public static String processNotes(String notesJson) {
        if (String.isBlank(notesJson)) {
            return '⚠️ No notes provided.';
        }

        try {
            // Parse incoming notes
            List<Object> notesList = (List<Object>) JSON.deserializeUntyped(notesJson);

            // Extract note bodies
            List<String> noteBodies = new List<String>();
            for (Object obj : notesList) {
                Map<String, Object> note = (Map<String, Object>) obj;
                String body = (String) note.get('Body');
                if (!String.isBlank(body)) noteBodies.add(body);
            }

            // Build AWS-style JSON payload
            Map<String, Object> innerMap = new Map<String, Object>{ 'notes' => noteBodies };
            String innerJson = JSON.serialize(innerMap);
            Map<String, Object> outerMap = new Map<String, Object>{ 'body' => innerJson };
            String payload = JSON.serialize(outerMap);

            // Prepare HTTP callout
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://wk666qu8jh.execute-api.us-east-1.amazonaws.com/dev/note');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(payload);

            Http http = new Http();
            HttpResponse res = http.send(req);

            // Return AWS response
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                System.debug('✅ AWS Response: ' + res.getBody());
                return res.getBody();
            } else {
                System.debug('❌ AWS Error: ' + res.getBody());
                return 'Error: ' + res.getStatusCode() + ' - ' + res.getBody();
            }
        } catch (Exception e) {
            System.debug('❌ Error sending to AWS: ' + e.getMessage());
            throw new AuraHandledException('Error sending to AWS: ' + e.getMessage());
        }
    }
}