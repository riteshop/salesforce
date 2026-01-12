public with sharing class ComplianceStageController {
    @AuraEnabled
    public static void updateStage(Id recordId, String newStage) {
        Compliance_Documents__c record = [
            SELECT Id, Stage__c 
            FROM Compliance_Documents__c 
            WHERE Id = :recordId
        ];
        record.Stage__c = newStage;
        update record;
    }
}