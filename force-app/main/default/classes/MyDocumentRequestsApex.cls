public with sharing class MyDocumentRequestsApex {
    @AuraEnabled(cacheable=true)
    public static Integer getPendingCount() {
        return [
            SELECT COUNT()
            FROM Document_Request__c
            WHERE Approver__c = :UserInfo.getUserId()
            AND Status__c = 'Pending'
        ];
    }
}