public with sharing class AdobeConfig {
    public class Settings {
        public String clientId;
        public String clientSecret;
        public String pdfBaseUrl;   // e.g. https://pdf-services.adobe.io/
        public String tokenUrl;     // e.g. https://ims-na1.adobelogin.com/ims/token/v3
        public String scope;        // e.g. openid,AdobeID,DCAPI
    }

    public static Settings get() {
        Adobe_PDF_Settings__mdt s = Adobe_PDF_Settings__mdt.getInstance('Default');
        if (s == null) {
            throw new AuraHandledException('Missing Adobe_PDF_Settings__mdt record with DeveloperName "Default".');
        }

        Settings out = new Settings();
        out.clientId = (String)s.get('ClientId__c');
        out.clientSecret = (String)s.get('ClientSecret__c');

        out.pdfBaseUrl = (String)s.get('BaseUrl__c');
        if (String.isBlank(out.pdfBaseUrl)) out.pdfBaseUrl = 'https://pdf-services.adobe.io/';
        if (!out.pdfBaseUrl.endsWith('/')) out.pdfBaseUrl += '/';

        out.tokenUrl = (String)s.get('TokenUrl__c');
        // For OAuth Server-to-Server, this is usually the IMS token endpoint.
        if (String.isBlank(out.tokenUrl)) out.tokenUrl = 'https://ims-na1.adobelogin.com/ims/token/v3';

        out.scope = (String)s.get('Scope__c');
        // Default scope based on what your console shows
        if (String.isBlank(out.scope)) out.scope = 'openid,AdobeID,DCAPI';

        if (String.isBlank(out.clientId) || String.isBlank(out.clientSecret)) {
            throw new AuraHandledException('Adobe settings missing ClientId__c / ClientSecret__c.');
        }

        return out;
    }
}