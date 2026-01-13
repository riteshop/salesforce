public with sharing class PdfMappingController {

    // ---------- DTOs ----------
    public class SfFieldOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    // V2 option: includes metadata needed for lookup chaining
    public class SfFieldOptionV2 {
        @AuraEnabled public String label;
        @AuraEnabled public String value;            // field API name (e.g., Study__c)
        @AuraEnabled public String type;             // DescribeFieldResult.getType() as String
        @AuraEnabled public List<String> referenceTo; // e.g., ["Study__c"]
        @AuraEnabled public String relationshipName;  // e.g., "Study__r" or "Account"
    }

    public class MappingRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String pdfFieldName;

        // display label shown in UI
        @AuraEnabled public String displayLabel;

        @AuraEnabled public String valueSourceType;
        @AuraEnabled public String fieldPath;        // can be "Email" OR "Study__r.Name"
        @AuraEnabled public String constantValue;
        @AuraEnabled public Boolean active;
        
        // NEW: Checkbox for Search Results
        @AuraEnabled public Boolean showInSearch; 
    }

    // ---------- Helper to get Source Object from Template ----------
    // ---------- Helper to get Source Object from Template ----------
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getTemplateSourceObject(Id templateId) {
        if (templateId == null) return null;
        PDF_Template__c t = [SELECT Source_Object__c FROM PDF_Template__c WHERE Id = :templateId LIMIT 1];
        
        String api = t.Source_Object__c;
        String lbl = api;
        
        if (String.isNotBlank(api)) {
             Schema.SObjectType st = Schema.getGlobalDescribe().get(api);
             if (st != null) {
                 lbl = st.getDescribe().getLabel();
                 api = st.getDescribe().getName(); // Canonical casing (e.g. 'Contact' instead of 'contact')
             }
        }
        
        return new Map<String, String>{ 'apiName' => api, 'label' => lbl };
    }

    // ---------- Salesforce field options (legacy) ----------
    @AuraEnabled(cacheable=true)
    public static List<SfFieldOption> getContactFieldOptions() {
        return getSObjectFieldOptionsInternalLegacy('Contact');
    }
    
    // Internal legacy helper to keep code clean if you still use getContactFieldOptions
    private static List<SfFieldOption> getSObjectFieldOptionsInternalLegacy(String objName) {
         Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objName).getDescribe().fields.getMap();
         List<String> labels = new List<String>();
         Map<String, String> labelToApi = new Map<String, String>();
 
         for (String apiName : fields.keySet()) {
             Schema.DescribeFieldResult d = fields.get(apiName).getDescribe();
             if (!d.isAccessible()) continue;
             String label = d.getLabel();
             String sortKey = label + ' [' + apiName + ']';
             labels.add(sortKey);
             labelToApi.put(sortKey, apiName);
         }
         labels.sort();
         List<SfFieldOption> options = new List<SfFieldOption>();
         for (String sortKey : labels) {
             SfFieldOption opt = new SfFieldOption();
             opt.label = sortKey.substring(0, sortKey.indexOf(' ['));
             opt.value = labelToApi.get(sortKey);
             options.add(opt);
         }
         return options;
    }

    // ---------- Salesforce field options (V2 with lookup metadata) ----------
    @AuraEnabled(cacheable=true)
    public static List<SfFieldOptionV2> getContactFieldOptionsV2() {
        return getSObjectFieldOptionsInternal('Contact');
    }

    // Used for the 2nd dropdown (fields of the referenced object) OR the main object
    @AuraEnabled(cacheable=true)
    public static List<SfFieldOptionV2> getObjectFieldOptions(String objectApiName) {
        if (String.isBlank(objectApiName)) return new List<SfFieldOptionV2>();
        return getSObjectFieldOptionsInternal(objectApiName.trim());
    }

    private static List<SfFieldOptionV2> getSObjectFieldOptionsInternal(String objectApiName) {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType sType = gd.get(objectApiName);
        if (sType == null) {
            throw new AuraHandledException('Unknown sObject: ' + objectApiName);
        }

        Map<String, Schema.SObjectField> fields = sType.getDescribe().fields.getMap();

        // stable sort by label
        List<String> sortKeys = new List<String>();
        Map<String, SfFieldOptionV2> bySortKey = new Map<String, SfFieldOptionV2>();

        for (String apiName : fields.keySet()) {
            Schema.DescribeFieldResult d = fields.get(apiName).getDescribe();
            if (!d.isAccessible()) continue;

            SfFieldOptionV2 opt = new SfFieldOptionV2();
            opt.label = d.getLabel();
            opt.value = d.getName(); // Use canonical API name casing
            opt.type = String.valueOf(d.getType());

            if (d.getType() == Schema.DisplayType.REFERENCE) {
                opt.referenceTo = new List<String>();
                for (Schema.SObjectType rt : d.getReferenceTo()) {
                    if (rt != null) opt.referenceTo.add(rt.getDescribe().getName());
                }
                opt.relationshipName = d.getRelationshipName(); 
            } else {
                opt.referenceTo = new List<String>();
                opt.relationshipName = null;
            }

            String sk = opt.label + ' [' + apiName + ']';
            sortKeys.add(sk);
            bySortKey.put(sk, opt);
        }

        sortKeys.sort();

        List<SfFieldOptionV2> out = new List<SfFieldOptionV2>();
        for (String sk : sortKeys) out.add(bySortKey.get(sk));
        return out;
    }

    // ---------- Load existing mappings ----------
    @AuraEnabled(cacheable=true)
    public static List<MappingRow> getMappings(Id templateId) {
        List<MappingRow> rows = new List<MappingRow>();

        // UPDATED: Added Show_in_Search__c to query
        for (PDF_Mapping__c m : [
            SELECT Id, Pdf_Field_Name__c, Display_Label__c,
                   Value_Source_Type__c, Field_Path__c, Constant_Value__c, Active__c,
                   Show_in_Search__c
            FROM PDF_Mapping__c
            WHERE Template__c = :templateId
            ORDER BY CreatedDate
        ]) {
            MappingRow r = new MappingRow();
            r.id = m.Id;
            r.pdfFieldName = m.Pdf_Field_Name__c;
            r.displayLabel = m.Display_Label__c;
            r.valueSourceType = m.Value_Source_Type__c;
            r.fieldPath = m.Field_Path__c;
            r.constantValue = m.Constant_Value__c;
            r.active = m.Active__c;
            
            // UPDATED: Map database field to DTO property
            r.showInSearch = (m.Show_in_Search__c == true);
            
            rows.add(r);
        }
        return rows;
    }

    // ---------- Save mappings ----------
    @AuraEnabled
    public static Map<String, Object> saveMappings(Id templateId, String rowsJson) {
        if (templateId == null) {
            throw new AuraHandledException('templateId is required.');
        }

        List<Object> rawRows = new List<Object>();
        if (!String.isBlank(rowsJson)) {
            Object parsed = JSON.deserializeUntyped(rowsJson);
            if (parsed instanceof List<Object>) {
                rawRows = (List<Object>)parsed;
            }
        }

        Map<String, Id> existingByPdfName = new Map<String, Id>();
        for (PDF_Mapping__c m : [
            SELECT Id, Pdf_Field_Name__c
            FROM PDF_Mapping__c
            WHERE Template__c = :templateId
        ]) {
            if (String.isBlank(m.Pdf_Field_Name__c)) continue;
            existingByPdfName.put(m.Pdf_Field_Name__c.trim(), m.Id);
        }

        List<PDF_Mapping__c> toInsert = new List<PDF_Mapping__c>();
        List<PDF_Mapping__c> toUpdate = new List<PDF_Mapping__c>();
        Integer normalized = 0;

        for (Object o : rawRows) {
            if (!(o instanceof Map<String, Object>)) continue;
            Map<String, Object> r = (Map<String, Object>)o;

            String pdfFieldName = (String)r.get('pdfFieldName');
            if (String.isBlank(pdfFieldName)) continue;
            pdfFieldName = pdfFieldName.trim();

            String displayLabel = (String)r.get('displayLabel');
            if (displayLabel != null) displayLabel = displayLabel.trim();

            String valueSourceType = (String)r.get('valueSourceType');
            if (String.isBlank(valueSourceType)) valueSourceType = 'FieldPath';

            String fieldPath = (String)r.get('fieldPath');
            String constantValue = (String)r.get('constantValue');
            Boolean active = r.containsKey('active') ? (Boolean)r.get('active') : true;

            // UPDATED: Extract checkbox value from JSON
            Boolean showInSearch = r.containsKey('showInSearch') ? (Boolean)r.get('showInSearch') : false;

            Id incomingId = null;
            if (r.get('id') != null) {
                try { incomingId = (Id)r.get('id'); } catch (Exception ex) { /* ignore */ }
            }
            Id existingId = existingByPdfName.get(pdfFieldName);
            Id finalId = (incomingId != null) ? incomingId : existingId;

            if (finalId == null) {
                // INSERT NEW MAPPING
                PDF_Mapping__c m = new PDF_Mapping__c();
                m.Template__c = templateId;
                String baseName = pdfFieldName;
                if (baseName.length() > 80) baseName = baseName.substring(0, 80);
                m.Name = baseName;
                m.Pdf_Field_Name__c = pdfFieldName;
                m.Display_Label__c = displayLabel;
                m.Value_Source_Type__c = valueSourceType;
                // Robust check: ContextVariable OR Context Variable
                if (valueSourceType == 'Constant' || valueSourceType.contains('Context')) {
                    m.Constant_Value__c = constantValue;
                    m.Field_Path__c = null;
                } else {
                    m.Field_Path__c = fieldPath;
                    m.Constant_Value__c = null;
                }
                m.Active__c = (active == null) ? true : active;
                
                // UPDATED: Set the new field on Insert
                m.Show_in_Search__c = showInSearch;

                toInsert.add(m);
                existingByPdfName.put(pdfFieldName, null);
            } else {
                // UPDATE EXISTING MAPPING
                PDF_Mapping__c m = new PDF_Mapping__c(Id = finalId);
                m.Pdf_Field_Name__c = pdfFieldName;
                m.Display_Label__c = displayLabel;
                m.Value_Source_Type__c = valueSourceType;
                // Robust check: ContextVariable OR Context Variable
                if (valueSourceType == 'Constant' || valueSourceType.contains('Context')) {
                    m.Constant_Value__c = constantValue;
                    m.Field_Path__c = null;
                } else {
                    m.Field_Path__c = fieldPath;
                    m.Constant_Value__c = null;
                }
                m.Active__c = (active == null) ? true : active;
                
                // UPDATED: Set the new field on Update
                m.Show_in_Search__c = showInSearch;

                String baseName2 = pdfFieldName;
                if (baseName2.length() > 80) baseName2 = baseName2.substring(0, 80);
                m.Name = baseName2;
                toUpdate.add(m);
            }
            normalized++;
        }

        Integer insOk = 0, updOk = 0;
        List<String> errors = new List<String>();
        
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] resIns = Database.insert(toInsert, false);
            for (Database.SaveResult sr : resIns) {
                if (sr.isSuccess()) insOk++;
                else for (Database.Error e : sr.getErrors()) errors.add(e.getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] resUpd = Database.update(toUpdate, false);
            for (Database.SaveResult sr : resUpd) {
                if (sr.isSuccess()) updOk++;
                else for (Database.Error e : sr.getErrors()) errors.add(e.getMessage());
            }
        }

        Map<String, Object> out = new Map<String, Object>();
        out.put('templateId', String.valueOf(templateId));
        out.put('inserted', insOk);
        out.put('updated', updOk);
        out.put('dmlSuccess', insOk + updOk);
        if (!errors.isEmpty()) out.put('dmlErrors', errors);

        return out;
    }
}