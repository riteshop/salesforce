public with sharing class MySupportTicketCount {
    
    @AuraEnabled(cacheable=true)
    public static Integer getCount() {
        return [
            SELECT COUNT()
            FROM support_ticket__c
            WHERE Status__c = 'New'
            AND OwnerId = :UserInfo.getUserId()
        ];
    }
}