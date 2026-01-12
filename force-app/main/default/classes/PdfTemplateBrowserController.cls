public with sharing class PdfTemplateBrowserController {

    public class TemplateDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String sourceObjectApiName;
        @AuraEnabled public String createdByName;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<TemplateDTO> listTemplates() {
        List<TemplateDTO> out = new List<TemplateDTO>();

        for (PDF_Template__c t : [
            SELECT Id, Name, Active__c, Source_Object__c, CreatedBy.Name, CreatedDate
            FROM PDF_Template__c
            WHERE Active__c = true
            ORDER BY Name
        ]) {
            TemplateDTO d = new TemplateDTO();
            d.id = t.Id;
            d.name = t.Name;
            d.active = t.Active__c;
            d.sourceObjectApiName = t.Source_Object__c;
            d.createdByName = t.CreatedBy.Name;
            d.createdDate = t.CreatedDate;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllSObjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        
        List<String> labels = new List<String>();
        Map<String, String> labelToApi = new Map<String, String>();

        for (String key : gd.keySet()) {
            Schema.DescribeSObjectResult d = gd.get(key).getDescribe();
            if (!d.isCreateable() || d.isCustomSetting() || key.endsWith('__Tag') || key.endsWith('__Share') || key.endsWith('__History')) {
                continue; 
            }
            
            String label = d.getLabel();
            String sortKey = label + ' (' + key + ')';
            labels.add(sortKey);
            labelToApi.put(sortKey, key);
        }
        labels.sort();
        
        for (String s : labels) {
            String apiKey = labelToApi.get(s);
            options.add(new Map<String, String>{
                'label' => s,
                'value' => apiKey
            });
        }
        return options;
    }

    @AuraEnabled
    public static Id saveTemplateWithFile(String name, String sourceObject, String fileName, String base64Data) {
        PDF_Template__c t = new PDF_Template__c();
        t.Name = name;
        t.Source_Object__c = sourceObject;
        insert t;

        if (fileName != null && base64Data != null) {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.FirstPublishLocationId = t.Id;
            insert cv;
        }

        return t.Id;
    }

    @AuraEnabled(cacheable=true)
    public static TemplateDTO getTemplateDetails(Id templateId) {
        if (templateId == null) throw new AuraHandledException('templateId required.');

        PDF_Template__c t = [
            SELECT Id, Name, Active__c, Source_Object__c
            FROM PDF_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        TemplateDTO d = new TemplateDTO();
        d.id = t.Id;
        d.name = t.Name;
        d.active = t.Active__c;
        d.sourceObjectApiName = t.Source_Object__c;
        return d;
    }
}