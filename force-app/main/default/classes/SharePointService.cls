public with sharing class SharePointService {
    
    // Graph API endpoints
    private static final String GRAPH_AUTH_URL = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/token';
    
    public class SharePointException extends Exception {}

    /**
     * Uploads a file to SharePoint using Graph API.
     * @param fileName The name of the file (including .pdf extension)
     * @param fileContent The binary content of the file
     */
    public static void uploadFile(String fileName, Blob fileContent) {
        String token = getAccessToken();
        
        String driveId = SharePointConfig.getDriveId();
        String folderPath = SharePointConfig.getRootFolderPath();
        
        // Clean folder path: ensure no leading slash, require trailing slash
        // Graph API format for folder path: root:/Path/To/Folder
        
        // Remove leading slash if present
        if (folderPath.startsWith('/')) {
            folderPath = folderPath.substring(1);
        }
        // Ensure trailing slash
        if (!folderPath.endsWith('/')) {
            folderPath += '/';
        }
        
        // URL Encode the filename to handle spaces and special chars
        String encodedName = EncodingUtil.urlEncode(fileName, 'UTF-8').replace('+', '%20');
        
        // Construct Endpoint
        // Pattern: https://graph.microsoft.com/v1.0/drives/{drive-id}/root:/{path-to-parent}/{filename}:/content
        String endpoint = 'https://graph.microsoft.com/v1.0/drives/' + driveId + 
                          '/root:/' + folderPath + encodedName + ':/content';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PUT');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/pdf'); 
        req.setBodyAsBlob(fileContent);
        req.setTimeout(60000); // 60 sec timeout for upload
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            System.debug('SharePoint Upload Success: ' + res.getBody());
        } else {
            System.debug('SharePoint Upload Failed: ' + res.getBody());
            System.debug('Endpoint attempted: ' + endpoint);
            throw new SharePointException('Upload failed: ' + res.getStatus() + ' ' + res.getBody());
        }
    }

    private static String getAccessToken() {
        String tenantId = SharePointConfig.getTenantId();
        String clientId = SharePointConfig.getClientId();
        String clientSecret = SharePointConfig.getClientSecret();
        
        if (String.isBlank(tenantId) || String.isBlank(clientId) || String.isBlank(clientSecret)) {
            throw new SharePointException('Missing SharePoint Credentials in Custom Metadata');
        }
        
        String authUrl = GRAPH_AUTH_URL.replace('{0}', tenantId);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(authUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        // payload must be URL encoded
        String payload = 'grant_type=client_credentials' +
                         '&client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                         '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
                         '&scope=' + EncodingUtil.urlEncode('https://graph.microsoft.com/.default', 'UTF-8');
        
        req.setBody(payload);
        req.setTimeout(30000);
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) body.get('access_token');
        } else {
            throw new SharePointException('Auth Failed: ' + res.getBody());
        }
    }
}