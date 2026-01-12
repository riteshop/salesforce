public with sharing class CaseChildrenController {

    @AuraEnabled(cacheable=true)
    public static List<ChildWrapper> getChildren(Id caseId) {

        List<ChildWrapper> results = new List<ChildWrapper>();

        // List of ALL child custom objects you want displayed
        List<String> childObjects = new List<String>{
            'support_ticket__c',
            'Salesforce__c',
            'Status_Tracker__c'
        };

        for (String objName : childObjects) {

            // --- GET OBJECT LABEL (e.g., 'Support Ticket', 'Salesforce', etc) ---
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objName);
            Schema.DescribeSObjectResult describe = sObjType.getDescribe();
            String objectLabel = describe.getLabel();

            String query =
                'SELECT Id, Name, CreatedDate ' +
                'FROM ' + objName +
                ' WHERE Parent_Case__c = :caseId ' +
                ' ORDER BY CreatedDate DESC';

            List<SObject> records = Database.query(query);

            for (SObject s : records) {
                ChildWrapper w = new ChildWrapper();
                w.Id = (String)s.get('Id');
                w.Name = (String)s.get('Name');
                w.ObjectType = objectLabel;   // ← NOW USING LABEL INSTEAD OF API NAME
                w.CreatedDate = String.valueOf(s.get('CreatedDate'));
                results.add(w);
            }
        }

        return results;
    }

    public class ChildWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String ObjectType;  // ← Human readable (“Support Ticket”)
        @AuraEnabled public String CreatedDate;
    }
}