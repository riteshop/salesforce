public without sharing class CaseListController {

    // ============================================
    // UPDATED getCases WITH:
    // - sorting
    // - searching
    // - pagination
    // - SYSTEM MODE ACCESS (Platform User Support)
    // ============================================
    @AuraEnabled(cacheable=true)
    public static CaseListResult getCases(
        Integer pageSize,
        Integer offsetValue,
        String sortField,
        String sortDirection,
        String searchTerm,
        String filterMode // 'MY_ASSIGNMENTS', 'DEPARTMENT', 'CREATED_BY_ME'
    ) {
        if (pageSize == null || pageSize <= 0) pageSize = 50;
        if (offsetValue == null || offsetValue < 0) offsetValue = 0;

        // Default sorting
        if (String.isBlank(sortField))     sortField = 'CreatedDate';
        if (String.isBlank(sortDirection)) sortDirection = 'DESC';
        if (String.isBlank(filterMode))    filterMode = 'MY_ASSIGNMENTS';

        // Prevent SOQL injection
        String orderByField;
        switch on sortField {
            when 'CaseNumber'  { orderByField = 'CaseNumber'; }
            when 'Subject'     { orderByField = 'Subject'; }
            when 'Status'      { orderByField = 'Status'; }
            when 'Priority'    { orderByField = 'Priority'; }
            when 'CreatedDate' { orderByField = 'CreatedDate'; }
            when else          { orderByField = 'CreatedDate'; }
        }

        String direction = (sortDirection != null && sortDirection.toLowerCase() == 'asc') ? 'ASC' : 'DESC';

        String userId = UserInfo.getUserId();

        // 1. Find Queues this user is a member of (for Department visibility)
        Set<Id> myQueueIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId 
            FROM GroupMember 
            WHERE UserOrGroupId = :userId 
            AND Group.Type = 'Queue'
        ]) {
            myQueueIds.add(gm.GroupId);
        }

        // 2. Identify IT/RCM membership specific logic
        Boolean isManager = !myQueueIds.isEmpty();
        
        // 3. Build WHERE Query based on Filter Mode
        String whereClause = 'WHERE IsDeleted = false ';

        if (filterMode == 'MY_ASSIGNMENTS') {
            // Show cases Assigned to Me OR Owned by Me (standard standard users)
            whereClause += 'AND (Assigned_User__c = :userId OR OwnerId = :userId) ';
        } 
        else if (filterMode == 'DEPARTMENT') {
            // Show cases Owned by my Queues
            if (myQueueIds.isEmpty()) {
                // If not in a queue, return nothing for this view
                whereClause += 'AND (Id = null) '; 
            } else {
                whereClause += 'AND (OwnerId IN :myQueueIds) ';
            }
        } 
        else if (filterMode == 'CREATED_BY_ME') {
            // Show cases Created by Me (Tracked via standard field OR our custom proxy)
            whereClause += 'AND (CreatedById = :userId OR Case_Creator__c = :userId) ';
        }

        // Add search filter
        if (!String.isBlank(searchTerm)) {
            String likeTerm = '%' + searchTerm + '%';
            whereClause += 'AND (Subject LIKE :likeTerm OR CaseNumber LIKE :likeTerm) ';
        }

        // Main query
        String soql =
            'SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate, Assigned_User__c ' +
            'FROM Case ' +
            whereClause +
            ' ORDER BY ' + orderByField + ' ' + direction +
            ' LIMIT :pageSize OFFSET :offsetValue';

        List<Case> records = Database.query(soql);

        // Total count
        String countSoql = 'SELECT COUNT() FROM Case ' + whereClause;
        Integer totalCount = (Integer)Database.countQuery(countSoql);

        return new CaseListResult(records, totalCount, isManager);
    }

    public class CaseListResult {
        @AuraEnabled public List<Case> records;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Boolean isManager;

        public CaseListResult(List<Case> records, Integer totalRecords, Boolean isManager) {
            this.records = records;
            this.totalRecords = totalRecords;
            this.isManager = isManager;
        }
    }

    // ============================================
    // CREATE CASE — unchanged
    // ============================================
    // ============================================
    // CREATE CASE — UPDATED
    // ============================================
    // ============================================
    // CREATE CASE — UPDATED
    // ============================================
    @AuraEnabled
    public static Id createCase(Case caseRecord) {
        try {
            Id currentUserId = UserInfo.getUserId();

            // ============================================================
            // PLATFORM USER WORKAROUND (LICENSE PROXY)
            // ============================================================
            // We cannot insert Case directly if User License is "Salesforce Platform".
            // Instead, we publish a Platform Event. A trigger (running as System) creates the Case.
            
            Case_Creation_Request__e request = new Case_Creation_Request__e();
            request.Subject__c = caseRecord.Subject;
            request.Description__c = caseRecord.Description;
            request.Status__c = 'New'; // Default
            request.Origin__c = 'Web'; // Default
            request.Priority__c = caseRecord.Priority;
            request.Type__c = caseRecord.Type;
            request.Requestor_User_Id__c = currentUserId;
            
            // Publish the event
            EventBus.publish(request);
            
            // Return null because we don't have the Case ID yet (Async)
            return null; 
            
        } catch (Exception e) {
            throw new AuraHandledException('Create Error: ' + e.getMessage());
        }
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

    // ============================================
    // PICKLIST VALUES (Bypass UI API for Platform Users)
    // ============================================
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getCasePicklistValues() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        
        result.put('Status',   getOptionsForField(Case.Status));
        result.put('Origin',   getOptionsForField(Case.Origin));
        result.put('Priority', getOptionsForField(Case.Priority));
        result.put('Reason',   getOptionsForField(Case.Reason));
        result.put('Type',     getOptionsForField(Case.Type));

        return result;
    }

    private static List<PicklistOption> getOptionsForField(Schema.SObjectField field) {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult describe = field.getDescribe();
        List<Schema.PicklistEntry> entries = describe.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }


    public class LookupResult {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;

        public LookupResult(Id id, String name) {
            this.Id = id;
            this.Name = name;
        }
    }
}