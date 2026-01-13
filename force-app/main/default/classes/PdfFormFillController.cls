public with sharing class PdfFormFillController {

    // -----------------------------
    // DTOs
    // -----------------------------
    public class FillResult {
        @AuraEnabled public Id recordId; // was contactId in backup
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String downloadUrl;
    }

    public class RecordSuggestion {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
    }

    // -----------------------------
    // Template helpers
    // -----------------------------
    private static String getSourceObjectApiName(Id templateId) {
        if (templateId == null) return null;
        PDF_Template__c t = [
            SELECT Id, Source_Object__c
            FROM PDF_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];
        if (String.isBlank(t.Source_Object__c)) {
            throw new AuraHandledException('Template is missing Source Object API name.');
        }
        String obj = t.Source_Object__c.trim();
        if (!Schema.getGlobalDescribe().containsKey(obj)) {
            throw new AuraHandledException('Unknown Source Object: ' + obj);
        }
        return obj;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getObjectLabel(Id templateId) {
        String api = getSourceObjectApiName(templateId);
        String lbl = api;
        
        if (String.isNotBlank(api)) {
             Schema.SObjectType st = Schema.getGlobalDescribe().get(api);
             if (st != null) {
                 lbl = st.getDescribe().getLabel();
                 api = st.getDescribe().getName(); 
             }
        }
        return new Map<String, String>{ 'apiName' => api, 'label' => lbl };
    }
    
    // -----------------------------
    // SEARCH COLUMNS & DYNAMIC SEARCH
    // (Retained from "Current" because Backup didn't have this, but LWC needs it)
    // -----------------------------
    @AuraEnabled
    public static List<String> getSearchColumns(Id templateId) {
         // Minimal impl to satisfy LWC
         List<String> resultFields = new List<String>{'Name'};
         if (templateId == null) return resultFields;
         // Query mappings to see what fields are relevant
         for (PDF_Mapping__c m : [SELECT Field_Path__c, Value_Source_Type__c, Constant_Value__c FROM PDF_Mapping__c WHERE Template__c = :templateId AND Show_in_Search__c = TRUE AND Active__c = TRUE]) {
             if (String.isNotBlank(m.Field_Path__c)) {
                 resultFields.add(m.Field_Path__c);
             } else if ((m.Value_Source_Type__c == 'ContextVariable' || (m.Value_Source_Type__c != null && m.Value_Source_Type__c.contains('Context'))) && String.isNotBlank(m.Constant_Value__c)) {
                 resultFields.add(m.Constant_Value__c);
             }
         }
         return resultFields;
    }

    @AuraEnabled
    public static List<SObject> searchRecordsDynamic(String objectApiName, String searchKey, List<String> fieldsToQuery) {
        String searchTerm = '%' + String.escapeSingleQuotes(searchKey) + '%';
        
        Set<String> queryFields = new Set<String>{'Id', 'Name'};
        // Tracks lowercase to handle case-insensitivity deduplication
        Set<String> lowerCheck = new Set<String>{'id', 'name'};

        // 1. Get Schema for Relationship Detection and Type Checking
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        Map<String, Schema.SObjectField> fMap = (sType != null) ? sType.getDescribe().fields.getMap() : new Map<String, Schema.SObjectField>();

        // Collect fields compatible with LIKE operator
        Set<String> searchableFields = new Set<String>{'Name'}; 

        if(fieldsToQuery != null) {
            for(String f : fieldsToQuery) {
                if(String.isBlank(f)) continue;
                
                // SAFETY: Skip fields deeper than 5 relationships to avoid SOQL limits
                if(f.countMatches('.') >= 5) continue;

                String fLower = f.toLowerCase();
                if(lowerCheck.contains(fLower)) continue;
                
                queryFields.add(f);
                lowerCheck.add(fLower);

                // Check compatibility for Search (LIKE operator)
                // Direct field check
                if (fMap.containsKey(f)) {
                    Schema.DescribeFieldResult dfr = fMap.get(f).getDescribe();
                    Schema.DisplayType dtype = dfr.getType();
                    
                    // Allow text-based types
                    if (dtype == Schema.DisplayType.STRING || 
                        dtype == Schema.DisplayType.TEXTAREA || 
                        dtype == Schema.DisplayType.EMAIL || 
                        dtype == Schema.DisplayType.PHONE || 
                        dtype == Schema.DisplayType.PICKLIST || 
                        dtype == Schema.DisplayType.URL) {
                        searchableFields.add(f);
                    }

                    // Auto-add Relationship Name for Lookups
                    if (dtype == Schema.DisplayType.REFERENCE) {
                        String relName = dfr.getRelationshipName();
                        if (relName != null) {
                            String namePath = relName + '.Name';
                            if (!lowerCheck.contains(namePath.toLowerCase())) {
                                queryFields.add(namePath);
                                lowerCheck.add(namePath.toLowerCase());
                                // Assume Name on related object is searchable
                                searchableFields.add(namePath); 
                            }
                        }
                    }
                } else if (f.contains('.')) {
                    // For related fields (e.g. Account.Industry), we assume they are searchable 
                    // (simplification to avoid complex schema traversing here, 
                    // though deeper validaton would be robust, most visible cols are text)
                    if (f.endsWithIgnoreCase('Name') || !f.endsWithIgnoreCase('Id')) { 
                        searchableFields.add(f);
                    }
                }
            }
        }
        
        String selectClause = String.join(new List<String>(queryFields), ',');
        String objName = String.escapeSingleQuotes(objectApiName);

        // Build Multi-Field WHERE Clause
        List<String> whereParts = new List<String>();
        for (String sf : searchableFields) {
            whereParts.add(sf + ' LIKE :searchTerm');
        }
        String whereClause = '(' + String.join(whereParts, ' OR ') + ')';

        String query = 'SELECT ' + selectClause + ' FROM ' + objName + 
                       ' WHERE ' + whereClause + ' ORDER BY Name LIMIT 50';
        try {
             return Database.query(query);
        } catch (Exception e) {
             System.debug('Search failed with full fields: ' + e.getMessage());
             
             // Fallback: Name only
             return Database.query('SELECT Id, Name FROM ' + objName + ' WHERE Name LIKE :searchTerm ORDER BY Name LIMIT 50');
        }
    }
    
    @AuraEnabled
    public static List<SObject> getRecentRecordsDynamic(String objectApiName, List<String> fieldsToQuery) {
        Set<String> queryFields = new Set<String>{'Id', 'Name'};
        Set<String> lowerCheck = new Set<String>{'id', 'name'};

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        Map<String, Schema.SObjectField> fMap = (sType != null) ? sType.getDescribe().fields.getMap() : new Map<String, Schema.SObjectField>();

        if(fieldsToQuery != null) {
             for(String f : fieldsToQuery) {
                if(String.isBlank(f)) continue;

                // SAFETY: Skip fields deeper than 5 relationships to avoid SOQL limits
                if(f.countMatches('.') >= 5) continue;

                String fLower = f.toLowerCase();
                if(lowerCheck.contains(fLower)) continue;
                
                queryFields.add(f);
                lowerCheck.add(fLower);

                // Auto-add Relationship Name for Lookups
                if (fMap.containsKey(f)) {
                    Schema.DescribeFieldResult dfr = fMap.get(f).getDescribe();
                    if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                        String relName = dfr.getRelationshipName();
                        if (relName != null) {
                            String namePath = relName + '.Name';
                            if (!lowerCheck.contains(namePath.toLowerCase())) {
                                queryFields.add(namePath);
                                lowerCheck.add(namePath.toLowerCase());
                            }
                        }
                    }
                }
            }
        }
        String selectClause = String.join(new List<String>(queryFields), ',');
        String objName = String.escapeSingleQuotes(objectApiName);
        
        String query = 'SELECT ' + selectClause + ' FROM ' + objName + 
                       ' ORDER BY CreatedDate DESC LIMIT 20';
        try {
            return Database.query(query);
        } catch (Exception e) {
             System.debug('Recent records failed with full fields: ' + e.getMessage());
             
             // Retry 1: Moderate depth (max 2 dots)
             try {
                 Set<String> safeFields = new Set<String>{'Id', 'Name'};
                 for(String f : queryFields) {
                     if (f.countMatches('.') <= 2) safeFields.add(f);
                 }
                 String safeSelect = String.join(new List<String>(safeFields), ',');
                 return Database.query('SELECT ' + safeSelect + ' FROM ' + objName + ' ORDER BY CreatedDate DESC LIMIT 20');
             } catch (Exception e2) {
                 // Retry 2: Root fields only
                 try {
                     Set<String> rootFields = new Set<String>{'Id', 'Name'};
                     for(String f : queryFields) {
                         if (!f.contains('.')) rootFields.add(f);
                     }
                     String rootSelect = String.join(new List<String>(rootFields), ',');
                     return Database.query('SELECT ' + rootSelect + ' FROM ' + objName + ' ORDER BY CreatedDate DESC LIMIT 20');
                 } catch (Exception e3) {
                     return Database.query('SELECT Id, Name FROM ' + objName + ' ORDER BY CreatedDate DESC LIMIT 20');
                 }
             }
        }
    }

    // -----------------------------
    // Fill template (Logic matched to Backup)
    // -----------------------------
    @AuraEnabled
    public static List<FillResult> fillTemplate(Id templateId, List<Id> recordIds) {
        if (templateId == null) throw new AuraHandledException('templateId required.');
        if (recordIds == null || recordIds.isEmpty()) throw new AuraHandledException('Select at least one Record.');

        // Backup used: String b64 = PdfTemplateFileController.getLatestTemplatePdfBase64(templateId);
        String b64 = PdfTemplateFileController.getLatestTemplatePdfBase64(templateId);
        if (String.isBlank(b64)) throw new AuraHandledException('No PDF found for template.');
        Blob templatePdf = EncodingUtil.base64Decode(b64);

        // Backup used: [SELECT Pdf_Field_Name__c, Value_Source_Type__c, ... FROM PDF_Mapping__c ...]
        List<PDF_Mapping__c> maps = [
            SELECT Pdf_Field_Name__c, Value_Source_Type__c, Field_Path__c, Constant_Value__c, Active__c
            FROM PDF_Mapping__c
            WHERE Template__c = :templateId
              AND Active__c = true
        ];

        // Backup logic: Determine fields to query
        Set<String> fieldSelections = new Set<String>();
        for (PDF_Mapping__c m : maps) {
            if (m.Value_Source_Type__c == 'FieldPath' && !String.isBlank(m.Field_Path__c)) {
                fieldSelections.add(m.Field_Path__c.trim());
            }
        }

        // Backup logic: Build SOQL
        String objectApiName = getSourceObjectApiName(templateId);
        
        Set<String> queryFields = new Set<String>();
        queryFields.add('Id');
        // Retrieve Name if possible for filenaming
        queryFields.add('Name'); 

        for (String f : fieldSelections) {
            String clean = f.replace(' ', '');
            if (clean.equalsIgnoreCase('Id') || clean.equalsIgnoreCase('Name')) continue;
            
             // SAFETY: Skip fields deeper than 5 relationships
            if (clean.countMatches('.') >= 5) continue;

            queryFields.add(clean);
        }

        // VALIDATION: Remove fields that do not exist on the object to prevent "No such column" errors
        Set<String> validQueryFields = new Set<String>();
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType != null) {
            Map<String, Schema.SObjectField> fMap = sType.getDescribe().fields.getMap();
            for (String qf : queryFields) {
                // Handle dot notation: only validate the root field
                String root = qf.contains('.') ? qf.split('\\.')[0] : qf;
                
                // Special handling for standard relationships often misused as fields
                if (!fMap.containsKey(root)) {
                    // FIX: Check if it's a standard relationship (e.g. Account -> AccountId)
                    String potentialIdField = root + 'Id';
                    if (fMap.containsKey(potentialIdField)) {
                         // It's a valid standard relationship (Account -> AccountId)
                         if (!qf.contains('.')) {
                             // "SELECT Account" is invalid, must be "SELECT Account.Name"
                             System.debug('Removing invalid field (relationship without subfield): ' + qf);
                             continue; 
                         }
                         // valid, continue to add
                    }
                    else if (root.equalsIgnoreCase('CreatedBy') && fMap.containsKey('CreatedById')) {
                         // Correct user error transparently
                         if (!qf.contains('.')) {
                             System.debug('Removing invalid field: ' + qf);
                             continue; 
                         }
                    } else if (root.endsWith('__r')) {
                         // Custom relationship, assume valid if dot path
                         if (!qf.contains('.')) continue; // SELECT MyRel__r FROM... invalid
                    } else {
                         // It's just a random string that isn't a field
                         System.debug('Removing unknown field: ' + qf);
                         continue;
                    }
                }
                validQueryFields.add(qf);
            }
        }
        
        if (validQueryFields.isEmpty()) validQueryFields.add('Id'); // Failsafe
        
        String soql = 'SELECT ' + String.join(new List<String>(validQueryFields), ',') + 
               ' FROM ' + objectApiName + ' WHERE Id IN :recordIds';

        List<SObject> records;
        try {
             records = Database.query(soql);
        } catch (Exception e) {
             System.debug('Fill query failed: ' + e.getMessage() + ' | SOQL: ' + soql);
             // Fallback: Query only Id, Name to allow PDF generation to proceed (some fields will be blank)
             records = Database.query('SELECT Id, Name FROM ' + objectApiName + ' WHERE Id IN :recordIds');
        }

        // Backup logic: processing
        List<Blob> filledBlobs = new List<Blob>();
        List<String> titles = new List<String>();
        List<Id> filledRecordIds = new List<Id>();

        for (SObject r : records) {
            Map<String,Object> formData = new Map<String,Object>();

            for (PDF_Mapping__c m : maps) {
                System.debug('Mapping: ' + m.Pdf_Field_Name__c + ' | Type: ' + m.Value_Source_Type__c + ' | Const: ' + m.Constant_Value__c);
                if (String.isBlank(m.Pdf_Field_Name__c)) continue;

                if (m.Value_Source_Type__c == 'FieldPath') {
                    if (String.isBlank(m.Field_Path__c)) continue;

                    Object v = getValueByPath(r, m.Field_Path__c.trim());
                    // DEBUG TRACE
                    System.debug('[PdfFormFill] Field: ' + m.Pdf_Field_Name__c + ' | Path: ' + m.Field_Path__c + ' | Value: ' + v);

                    // ADOBE FIX: Do not send null OR empty strings to avoid default appearance errors
                    if (v == null) continue;
                    String sVal = String.valueOf(v);
                    if (String.isBlank(sVal)) continue; 

                    formData.put(m.Pdf_Field_Name__c, sVal);

                } else if (m.Value_Source_Type__c == 'Constant') {
                    if (String.isBlank(m.Constant_Value__c)) continue;
                    System.debug('[PdfFormFill] Field: ' + m.Pdf_Field_Name__c + ' | Constant: ' + m.Constant_Value__c);
                    formData.put(m.Pdf_Field_Name__c, m.Constant_Value__c);

                } else if (m.Value_Source_Type__c == 'ContextVariable') {
                    if (String.isBlank(m.Constant_Value__c)) continue;
                    String varName = m.Constant_Value__c;
                    Object val = null;

                    if (varName == 'CurrentUserName') {
                        val = UserInfo.getName();
                    } else if (varName == 'CurrentUserEmail') {
                        val = UserInfo.getUserEmail();
                    } else if (varName == 'CurrentDate') {
                        val = Date.today().format();
                    }

                    if (val != null) {
                         formData.put(m.Pdf_Field_Name__c, String.valueOf(val));
                    }
                }
            }

            if (formData.isEmpty()) {
                System.debug('[PdfFormFill] FormData is empty for record ' + r.Id);
                continue;
            }

            System.debug('[PdfFormFill] Sending FormData to Adobe: ' + JSON.serialize(formData));

            // CALL OUT
            Blob filled = AdobeForms.fillAcroForm(templatePdf, formData);

            filledBlobs.add(filled);
            
            // Backup used: (String)c.get('Name')
            Object nmVal = r.get('Name');
            titles.add('Filled - ' + (nmVal == null ? (String)r.get('Id') : (String)nmVal));
            String baseTitle = 'Filled - ' + (nmVal == null ? (String)r.get('Id') : (String)nmVal);
            filledRecordIds.add((Id)r.get('Id'));

            // SHAREPOINT UPLOAD
            try {
                // Upload to SharePoint but do NOT fail the transaction if it fails
                // Filename: Filled - RecordName.pdf
                SharePointService.uploadFile(baseTitle + '.pdf', filled);
            } catch (Exception spEx) {
                System.debug('SharePoint Upload Error: ' + spEx.getMessage());
            }
        }

        // DML AFTER
        List<ContentVersion> cvs = new List<ContentVersion>();
        for (Integer i = 0; i < filledBlobs.size(); i++) {
            ContentVersion cv = new ContentVersion();
            cv.Title = titles[i];
            cv.PathOnClient = titles[i] + '.pdf';
            cv.VersionData = filledBlobs[i];
            cvs.add(cv);
        }

        if (!cvs.isEmpty()) {
            insert cvs;
        }

        List<FillResult> results = new List<FillResult>();
        for (Integer i = 0; i < cvs.size(); i++) {
            FillResult fr = new FillResult();
            fr.recordId = filledRecordIds[i]; // was contactId
            fr.contentVersionId = cvs[i].Id;
            fr.title = cvs[i].Title;
            fr.downloadUrl = '/sfc/servlet.shepherd/version/download/' + String.valueOf(cvs[i].Id);
            results.add(fr);
        }

        return results;
    }

    // -----------------------------
    // Helper: supports dot paths (Matched to Backup)
    // -----------------------------
    private static Object getValueByPath(SObject root, String path) {
        if (root == null || String.isBlank(path)) return null;
        path = path.trim();

        if (!path.contains('.')) {
            try {
                return root.get(path);
            } catch (Exception e) {
                return null;
            }
        }

        List<String> parts = path.split('\\.');
        SObject curr = root;

        for (Integer i = 0; i < parts.size(); i++) {
            String key = parts[i];
            Boolean last = (i == parts.size() - 1);

            try {
                if (last) {
                    return (curr == null) ? null : curr.get(key);
                } else {
                    curr = (curr == null) ? null : curr.getSObject(key);
                }
            } catch (Exception e) {
                // Field not queried or invalid
                return null;
            }
        }
        return null;
    }
}