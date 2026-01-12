public with sharing class ContactSearchController {
    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchKey) {
        if (String.isBlank(searchKey)) return new List<Contact>();

        String key = '%' + searchKey + '%';

        return [
            SELECT Id, Name
            FROM Contact
            WHERE Name LIKE :key
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ];
    }
}