public with sharing class AdobeForms {

    /**
     * Fill an AcroForm using Adobe PDF Services "setformdata".
     * - inputPdf: original PDF bytes
     * - jsonFormFieldsData: Map of { pdfFieldName => value } (ONLY the fields you want to fill)
     * Returns: filled PDF bytes (Blob)
     */
    public static Blob fillAcroForm(Blob inputPdf, Map<String, Object> jsonFormFieldsData) {
        if (inputPdf == null) {
            throw new AuraHandledException('inputPdf is required.');
        }
        if (jsonFormFieldsData == null) {
            jsonFormFieldsData = new Map<String, Object>();
        }

        AdobeConfig.Settings cfg = AdobeConfig.get();
        String token = AdobeAuth.getAccessToken();

        // 1) Create upload asset + upload original PDF to Adobe
        AdobeAssets.AssetCreateResponse asset = AdobeAssets.createUploadAsset('application/pdf');
        AdobeAssets.putToPresignedUrl(asset.uploadUri, inputPdf, 'application/pdf');

        // 2) Start "setformdata" operation
        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.pdfBaseUrl + 'operation/setformdata');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('X-API-Key', cfg.clientId);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        Map<String, Object> body = new Map<String, Object>{
            'assetID' => asset.assetID,
            'jsonFormFieldsData' => jsonFormFieldsData
        };
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);

        Integer sc = res.getStatusCode();
        String bodyStr = res.getBody();

        // Adobe often returns 201 Created for async start; treat any 2xx as success.
        if (sc < 200 || sc >= 300) {
            throw new AuraHandledException(
                'Adobe setformdata start failed: ' + sc + ' ' + bodyStr
            );
        }

        // 3) Determine status URL (Adobe may use different header keys)
        String location = res.getHeader('Location');
        if (String.isBlank(location)) location = res.getHeader('location');
        if (String.isBlank(location)) location = res.getHeader('Operation-Location');
        if (String.isBlank(location)) location = res.getHeader('operation-location');
        if (String.isBlank(location)) location = res.getHeader('Content-Location');
        if (String.isBlank(location)) location = res.getHeader('content-location');

        // If still blank, dump all headers for debugging
        if (String.isBlank(location)) {
            List<String> headerDump = new List<String>();
            try {
                for (String k : res.getHeaderKeys()) {
                    headerDump.add(k + '=' + res.getHeader(k));
                }
            } catch (Exception e) {
                headerDump.add('Could not read headers: ' + e.getMessage());
            }

            System.debug('Adobe setformdata headers: ' + String.join(headerDump, ' | '));

            throw new AuraHandledException(
                'Adobe setformdata returned no Location header and no usable body. ' +
                'Status=' + sc + ' Body=' + (String.isBlank(bodyStr) ? '(empty body)' : bodyStr) +
                ' Headers=' + String.join(headerDump, ' | ')
            );
        }

        // Normalize relative location if needed
        if (location.startsWith('/')) {
            String base = cfg.pdfBaseUrl;
            if (base.endsWith('/')) base = base.substring(0, base.length() - 1);
            location = base + location;
        }

        // 4) Poll until done; get downloadUri
        AdobeJobs.JobResult done = AdobeJobs.pollUntilDone(location, 25);

        // 5) Download the filled PDF from the presigned download URL
        return AdobeAssets.downloadFromPresignedUrl(done.downloadUri);
    }
}