public with sharing class AccountSummaryController {
    @AuraEnabled(cacheable=true)
    public static Account getAccountSummary(Id accountId) {
        if (accountId == null) return null;

        return [
            SELECT Id, Name, Industry, AnnualRevenue, Phone, Website, AccountNumber, Site
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
    }
}