public with sharing class CaseListController {

    // ============================================
    // UPDATED getCases WITH:
    // - sorting
    // - searching
    // - pagination
    // ============================================
    @AuraEnabled(cacheable=true)
    public static CaseListResult getCases(
        Integer pageSize,
        Integer offsetValue,
        String sortField,
        String sortDirection,
        String searchTerm
    ) {
        if (pageSize == null || pageSize <= 0) pageSize = 50;
        if (offsetValue == null || offsetValue < 0) offsetValue = 0;

        // Default sorting
        if (String.isBlank(sortField))     sortField = 'CreatedDate';
        if (String.isBlank(sortDirection)) sortDirection = 'DESC';

        // Prevent SOQL injection by whitelisting
        String orderByField;

        switch on sortField {
            when 'CaseNumber'  { orderByField = 'CaseNumber'; }
            when 'Subject'     { orderByField = 'Subject'; }
            when 'Status'      { orderByField = 'Status'; }
            when 'Priority'    { orderByField = 'Priority'; }
            when 'CreatedDate' { orderByField = 'CreatedDate'; }
            when else          { orderByField = 'CreatedDate'; }
        }

        String direction = (sortDirection != null && sortDirection.toLowerCase() == 'asc')
            ? 'ASC'
            : 'DESC';

        // Base WHERE
        String baseWhere = 'WHERE IsDeleted = false';
        String likeTerm;

        // Add search filter
        if (!String.isBlank(searchTerm)) {
            likeTerm = '%' + searchTerm + '%';
            baseWhere += ' AND Subject LIKE :likeTerm';
        }

        // Main query
        String soql =
            'SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate ' +
            'FROM Case ' +
            baseWhere +
            ' ORDER BY ' + orderByField + ' ' + direction +
            ' LIMIT :pageSize OFFSET :offsetValue';

        List<Case> records = Database.query(soql);

        // Total count
        String countSoql = 'SELECT COUNT() FROM Case ' + baseWhere;
        Integer totalCount = (Integer)Database.countQuery(countSoql);

        return new CaseListResult(records, totalCount);
    }

    // ============================================
    // WRAPPER CLASS — unchanged
    // ============================================
    public class CaseListResult {
        @AuraEnabled public List<Case> records;
        @AuraEnabled public Integer totalRecords;

        public CaseListResult(List<Case> records, Integer totalRecords) {
            this.records = records;
            this.totalRecords = totalRecords;
        }
    }

    // ============================================
    // CREATE CASE — unchanged
    // ============================================
    @AuraEnabled
    public static Id createCase(Case caseRecord) {
        if (caseRecord.OwnerId == null) {
            caseRecord.OwnerId = UserInfo.getUserId();
        }

        insert caseRecord;
        return caseRecord.Id;
    }

    // ============================================
    // LOOKUP SEARCH HELPERS — unchanged
    // ============================================
    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchContacts(String searchTerm) {
        if (String.isBlank(searchTerm)) return new List<LookupResult>();

        List<Contact> contacts = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Name LIKE :('%' + searchTerm + '%')
            ORDER BY Name
            LIMIT 20
        ];

        List<LookupResult> results = new List<LookupResult>();
        for (Contact c : contacts) {
            results.add(new LookupResult(c.Id, c.Name));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchAccounts(String searchTerm) {
        if (String.isBlank(searchTerm)) return new List<LookupResult>();

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :('%' + searchTerm + '%')
            ORDER BY Name
            LIMIT 20
        ];

        List<LookupResult> results = new List<LookupResult>();
        for (Account a : accounts) {
            results.add(new LookupResult(a.Id, a.Name));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchUsers(String searchTerm) {
        if (String.isBlank(searchTerm)) return new List<LookupResult>();

        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE Name LIKE :('%' + searchTerm + '%')
            ORDER BY Name
            LIMIT 20
        ];

        List<LookupResult> results = new List<LookupResult>();
        for (User u : users) {
            results.add(new LookupResult(u.Id, u.Name));
        }
        return results;
    }

    // Lookup wrapper
    public class LookupResult {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;

        public LookupResult(Id id, String name) {
            this.Id = id;
            this.Name = name;
        }
    }
}