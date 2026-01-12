public with sharing class AdobeAuth {
    private static String cachedToken;

    public static String getAccessToken() {
        if (!String.isBlank(cachedToken)) {
            return cachedToken;
        }

        AdobeConfig.Settings cfg = AdobeConfig.get();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.tokenUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body =
            'grant_type=client_credentials' +
            '&client_id=' + EncodingUtil.urlEncode(cfg.clientId, 'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(cfg.clientSecret, 'UTF-8') +
            '&scope=' + EncodingUtil.urlEncode(cfg.scope, 'UTF-8');

        req.setBody(body);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'Adobe token error: ' + res.getStatusCode() + ' ' + res.getBody()
            );
        }

        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        String token = (String) parsed.get('access_token');
        if (String.isBlank(token)) {
            throw new AuraHandledException('Adobe token response missing access_token.');
        }

        cachedToken = token;
        return token;
    }
}