public with sharing class CasePathController {

    @AuraEnabled
    public static void updateCaseStatus(Id caseId, String newStatus) {
        update new Case(
            Id = caseId,
            Status = newStatus
        );
    }
}