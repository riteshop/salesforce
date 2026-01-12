public with sharing class AdobeAssets {

    public class AssetCreateResponse {
        public String assetID;
        public String uploadUri;
    }

    public static AssetCreateResponse createUploadAsset(String mediaType) {
        AdobeConfig.Settings cfg = AdobeConfig.get();
        String token = AdobeAuth.getAccessToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.pdfBaseUrl + 'assets');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('X-API-Key', cfg.clientId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{
            'mediaType' => mediaType
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException('Adobe create asset failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());

        AssetCreateResponse out = new AssetCreateResponse();
        out.assetID = (String) parsed.get('assetID');
        out.uploadUri = (String) parsed.get('uploadUri');

        if (String.isBlank(out.assetID) || String.isBlank(out.uploadUri)) {
            throw new AuraHandledException('Adobe create asset missing assetID/uploadUri.');
        }
        return out;
    }

    public static void putToPresignedUrl(String uploadUri, Blob fileBody, String mediaType) {
        HttpRequest putReq = new HttpRequest();
        putReq.setEndpoint(uploadUri);
        putReq.setMethod('PUT');
        putReq.setHeader('Content-Type', mediaType);
        putReq.setBodyAsBlob(fileBody);

        HttpResponse putRes = new Http().send(putReq);
        if (putRes.getStatusCode() != 200 && putRes.getStatusCode() != 201) {
            throw new AuraHandledException('Adobe upload PUT failed: ' + putRes.getStatusCode() + ' ' + putRes.getBody());
        }
    }

    public static Blob downloadFromPresignedUrl(String downloadUri) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(downloadUri);
        req.setMethod('GET');

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException('Download failed: ' + res.getStatusCode());
        }
        return res.getBodyAsBlob();
    }
}