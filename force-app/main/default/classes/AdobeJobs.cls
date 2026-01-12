public with sharing class AdobeJobs {

    public class JobResult {
        public String status; // "in progress" / "done" / "failed"
        public Map<String, Object> raw;
        public String downloadUri;
    }

    /**
     * Polls Adobe job status URL until it reaches done/failed or times out.
     * Handles redirects + empty body safely.
     */
    public static JobResult pollUntilDone(String statusUrl, Integer maxSeconds) {
        if (String.isBlank(statusUrl)) {
            throw new AuraHandledException('AdobeJobs.pollUntilDone: statusUrl is required.');
        }
        if (maxSeconds == null || maxSeconds <= 0) maxSeconds = 25;

        AdobeConfig.Settings cfg = AdobeConfig.get();
        String token = AdobeAuth.getAccessToken();

        Long startMs = DateTime.now().getTime();

        // Use a bounded loop so the compiler clearly sees an exit path (no “missing return”)
        while (((DateTime.now().getTime() - startMs) / 1000) < maxSeconds) {

            HttpRequest req = new HttpRequest();
            req.setEndpoint(statusUrl);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('X-API-Key', cfg.clientId);
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);

            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (Exception ex) {
                throw new AuraHandledException('Adobe status poll callout failed: ' + ex.getMessage());
            }

            Integer code = res.getStatusCode();

            // Follow redirects if Adobe returns 302/303 with a new Location
            if (code == 302 || code == 303) {
                String loc = res.getHeader('Location');
                if (String.isBlank(loc)) {
                    throw new AuraHandledException(
                        'Adobe status poll redirect (' + code + ') but no Location header. url=' + statusUrl
                    );
                }
                statusUrl = loc;
                continue;
            }

            // Some APIs return 202 with no body; treat as "still in progress"
            if (code == 202) {
                // keep looping
                continue;
            }

            // Anything non-2xx is a hard failure
            if (code < 200 || code >= 300) {
                throw new AuraHandledException('Adobe status poll failed: ' + code + ' ' + safeBody(res));
            }

            String body = res.getBody();

            // 🔥 This is what was causing your JSON error
            if (String.isBlank(body)) {
                throw new AuraHandledException(
                    'Adobe status poll returned empty body (cannot JSON parse). ' +
                    'code=' + code + ', url=' + statusUrl +
                    ', requestId=' + nullToEmpty(res.getHeader('x-request-id')) +
                    ', contentType=' + nullToEmpty(res.getHeader('Content-Type'))
                );
            }

            Object parsedObj;
            try {
                parsedObj = JSON.deserializeUntyped(body);
            } catch (Exception ex) {
                throw new AuraHandledException(
                    'Adobe status poll JSON parse failed: ' + ex.getMessage() +
                    ' | code=' + code +
                    ' | url=' + statusUrl +
                    ' | body=' + truncate(body, 1200)
                );
            }

            if (!(parsedObj instanceof Map<String, Object>)) {
                throw new AuraHandledException(
                    'Adobe status poll returned non-object JSON. code=' + code +
                    ' url=' + statusUrl + ' body=' + truncate(body, 1200)
                );
            }

            Map<String, Object> parsed = (Map<String, Object>) parsedObj;

            // Adobe responses may use "status" (common) or sometimes "state"
            String status = (String) parsed.get('status');
            if (String.isBlank(status)) status = (String) parsed.get('state');
            if (String.isBlank(status)) status = 'in progress';

            // Normalize common values
            String s = status.toLowerCase();
            Boolean isDone = (s == 'done' || s == 'succeeded' || s == 'success');
            Boolean isFailed = (s == 'failed' || s == 'error');

            if (isFailed) {
                throw new AuraHandledException('Adobe job failed: ' + truncate(body, 2000));
            }

            if (isDone) {
                JobResult jr = new JobResult();
                jr.status = status;
                jr.raw = parsed;
                jr.downloadUri = extractDownloadUri(parsed);

                if (String.isBlank(jr.downloadUri)) {
                    throw new AuraHandledException(
                        'Adobe job marked done but no downloadUri found. Body=' + truncate(body, 2000)
                    );
                }
                return jr;
            }

            // tiny CPU spin to reduce hammering (Apex has no sleep)
            Long spinStart = DateTime.now().getTime();
            while (DateTime.now().getTime() - spinStart < 200) { /* spin */ }
        }

        throw new AuraHandledException('Adobe job timed out after ' + maxSeconds + 's. Last statusUrl=' + statusUrl);
    }

    // ---------------- Helpers ----------------

    private static String extractDownloadUri(Map<String, Object> parsed) {
        // Most common: { asset: { downloadUri: "..." } }
        if (parsed != null && parsed.containsKey('asset')) {
            Object aObj = parsed.get('asset');
            if (aObj instanceof Map<String, Object>) {
                Map<String, Object> asset = (Map<String, Object>) aObj;
                if (asset != null && asset.containsKey('downloadUri')) {
                    return (String) asset.get('downloadUri');
                }
                if (asset != null && asset.containsKey('downloadURI')) {
                    return (String) asset.get('downloadURI');
                }
            }
        }

        // Sometimes nested: { result: { asset: { downloadUri } } }
        if (parsed != null && parsed.containsKey('result')) {
            Object rObj = parsed.get('result');
            if (rObj instanceof Map<String, Object>) {
                Map<String, Object> result = (Map<String, Object>) rObj;
                if (result != null && result.containsKey('asset')) {
                    Object aObj = result.get('asset');
                    if (aObj instanceof Map<String, Object>) {
                        Map<String, Object> asset = (Map<String, Object>) aObj;
                        if (asset != null && asset.containsKey('downloadUri')) {
                            return (String) asset.get('downloadUri');
                        }
                    }
                }
            }
        }

        return null;
    }

    private static String safeBody(HttpResponse res) {
        if (res == null) return '';
        String b = res.getBody();
        return String.isBlank(b) ? '' : truncate(b, 2000);
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) return null;
        if (maxLen == null || maxLen <= 0) return s;
        return (s.length() > maxLen) ? s.substring(0, maxLen) : s;
    }

    private static String nullToEmpty(String s) {
        return (s == null) ? '' : s;
    }
}