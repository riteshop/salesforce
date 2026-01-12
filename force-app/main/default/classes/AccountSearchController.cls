global with sharing class AccountSearchController {
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchKey) {
        if (String.isBlank(searchKey)) {
            return new List<Account>();
        }
//test
        String key = '%' + searchKey + '%';
        return [
            SELECT Id, Name, Industry, Phone
            FROM Account
            WHERE Name LIKE :key
            ORDER BY Name
            LIMIT 10
        ];
    }
}