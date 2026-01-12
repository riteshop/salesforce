@RestResource(urlMapping='/NoteSummary/*')
global with sharing class NoteSummaryController {

    @HttpGet
    global static String getSummary() {
        try {
            // 1️⃣ Collect recent notes
            List<String> noteTexts = new List<String>();
            Set<Id> docIds = new Set<Id>();

            try {
                List<ContentVersion> versions = [
                    SELECT ContentDocumentId, VersionData, CreatedDate, ContentDocument.FileType
                    FROM ContentVersion
                    WHERE IsLatest = true
                      AND ContentDocument.FileType = 'SNOTE'
                    ORDER BY CreatedDate DESC
                    LIMIT 3
                ];

                for (ContentVersion v : versions) {
                    if (v.ContentDocumentId != null) docIds.add(v.ContentDocumentId);

                    if (v.VersionData != null) {
                        String noteText = v.VersionData.toString();

                        // 🧹 Clean HTML and entities
                        noteText = noteText.replaceAll('<[^>]+>', '');
                        noteText = noteText.replaceAll('&nbsp;', ' ');
                        noteText = noteText.replaceAll('&amp;', '&');
                        noteText = noteText.replaceAll('&lt;', '<');
                        noteText = noteText.replaceAll('&gt;', '>');
                        noteText = noteText.replaceAll('&quot;', '"');
                        noteText = noteText.replaceAll('&#39;', '\'');
                        noteText = noteText.trim();

                        if (String.isNotBlank(noteText)) {
                            noteTexts.add(noteText);
                        }
                    }
                }
            } catch (Exception innerErr) {
                System.debug('⚠️ Note retrieval failed: ' + innerErr.getMessage());
            }

            // 2️⃣ Build JSON payload for AWS
            Map<String, Object> noteBody = new Map<String, Object>{ 'notes' => noteTexts };
            String formattedBody = JSON.serialize(
                new Map<String, Object>{
                    'body' => JSON.serialize(noteBody)
                }
            );

            System.debug('📦 Sending to AWS: ' + formattedBody);

            // 3️⃣ Send POST request to AWS
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://wk666qu8jh.execute-api.us-east-1.amazonaws.com/dev/note');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(formattedBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            // 4️⃣ Handle AWS response
            if (res.getStatusCode() == 200) {
                String rawBody = res.getBody();
                System.debug('📨 Raw AWS Response: ' + rawBody);

                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
                String bodyText = (String) responseMap.get('body');

                if (bodyText != null) {
                    // 🧹 Remove braces, backslashes, and quotes
                    bodyText = bodyText.replaceAll('[{}"]', '');
                    bodyText = bodyText.replaceAll('\\\\', '');
                    bodyText = bodyText.replace('summary:', '');
                    bodyText = bodyText.trim();

                    return '🧠 Summary: ' + bodyText;
                } else {
                    return '⚠️ AWS returned no summary field.';
                }
            } else {
                return '⚠️ AWS Error: ' + res.getStatusCode() + ' - ' + res.getStatus();
            }

        } catch (Exception e) {
            return 'Error during AWS callout: ' + e.getMessage();
        }
    }
}