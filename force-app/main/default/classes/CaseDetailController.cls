public without sharing class CaseDetailController { // v2

    // ============================================================
    // WRAPPER FOR TIMELINE ENTRIES
    // ============================================================
    public class TimelineEntry {
        @AuraEnabled public Id sourceId;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;

        @AuraEnabled public String type;
        @AuraEnabled public String typeLabel;

        @AuraEnabled public String title;
        @AuraEnabled public String body;
    }

    // ============================================================
    // SORT COMPARATOR — NEWEST FIRST
    // ============================================================
    public class TimelineComparator implements Comparator<TimelineEntry> {
        public Integer compare(TimelineEntry a, TimelineEntry b) {

            if (a.createdDate == null && b.createdDate == null) return 0;
            if (a.createdDate == null) return 1;
            if (b.createdDate == null) return -1;

            // Newest first
            if (a.createdDate > b.createdDate) return -1;
            if (a.createdDate < b.createdDate) return 1;

            return 0;
        }
    }

    // ============================================================
    // CASE WRAPPER (DTO) - BYPASS SOBJECT SECURITY SCRUBBING
    // ============================================================
    public class CaseDetailWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String CaseNumber;
        @AuraEnabled public String Subject;
        @AuraEnabled public String Description;
        @AuraEnabled public String Status;
        @AuraEnabled public String Priority;
        @AuraEnabled public String Origin;
        @AuraEnabled public String Type;
        @AuraEnabled public String Reason;
        @AuraEnabled public String RecordTypeId;
        @AuraEnabled public Datetime CreatedDate;
        @AuraEnabled public Datetime ClosedDate;
        
        // Flattened / Nested relationships 
        // (Keeping structure similar to SObject keys for potential easy JS mapping, 
        // but typically better to be explicit)
        @AuraEnabled public String OwnerId;
        @AuraEnabled public String OwnerName; // Flat
        
        @AuraEnabled public String AssignedUserId;
        @AuraEnabled public String AssignedUserName; // Flat

        @AuraEnabled public String ManagerId;
        @AuraEnabled public String ManagerName; // Flat
        @AuraEnabled public String EmployeeId;
        @AuraEnabled public String EmployeeName; // Flat

        @AuraEnabled public String CaseCreatorName; // Flat

        @AuraEnabled public String ContactId;
        @AuraEnabled public String ContactName; // Flat
        
        @AuraEnabled public String AccountId;
        @AuraEnabled public String AccountName; // Flat
        
        @AuraEnabled public Boolean RequiresManagerReview;

        @AuraEnabled public List<String> CurrentUserQueues; // List of Queue DeveloperNames the user is in

        // Constructor to map from SObject
        public CaseDetailWrapper(Case c) {
            this.Id = c.Id;
            this.CaseNumber = c.CaseNumber;
            this.Subject = c.Subject;
            this.Description = c.Description;
            this.Status = c.Status;
            this.Priority = c.Priority;
            this.Origin = c.Origin;
            this.Type = c.Type;
            this.Reason = c.Reason;
            this.RecordTypeId = c.RecordTypeId;
            this.CreatedDate = c.CreatedDate;
            this.ClosedDate = c.ClosedDate;
            this.RequiresManagerReview = c.Requires_Manager_Review__c;
            
            this.OwnerId = c.OwnerId;
            this.OwnerName = c.Owner != null ? c.Owner.Name : '';

            this.AssignedUserId = c.Assigned_User__c;
            this.AssignedUserName = c.Assigned_User__r != null ? c.Assigned_User__r.Name : '';

            this.ManagerId = c.Manager__c;
            this.ManagerName = c.Manager__r != null ? c.Manager__r.Name : '';
            this.EmployeeId = c.Employee__c;
            this.EmployeeName = c.Employee__r != null ? c.Employee__r.Name : '';
            
            this.ContactId = c.ContactId;
            this.ContactName = c.Contact != null ? c.Contact.Name : '';
            
            this.AccountId = c.AccountId;
            this.AccountName = c.Account != null ? c.Account.Name : '';

            this.CaseCreatorName = c.Case_Creator__r != null ? c.Case_Creator__r.Name : '';
        }
    }

    // ============================================================
    // GET CASE DETAILS
    // ============================================================
    @AuraEnabled
    public static CaseDetailWrapper getCaseDetails(Id caseId) {
        if (caseId == null) return null;

        List<Case> results = [
            SELECT 
                Id,
                CaseNumber,
                Subject,
                Description,
                Status,
                Priority,
                Origin,
                Type,
                Reason,
                RecordTypeId,
                CreatedDate,
                ClosedDate,
                Owner.Name,
                OwnerId,
                Assigned_User__c,
                Assigned_User__r.Name, 
                Manager__c,
                Manager__r.Name,
                Employee__c,
                Employee__r.Name,
                Requires_Manager_Review__c,
                Case_Creator__c,
                Case_Creator__r.Name,
                Contact.Name,
                ContactId,
                Account.Name,
                AccountId
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        
        if (results.isEmpty()) return null;
        
        CaseDetailWrapper wrapper = new CaseDetailWrapper(results[0]);

        // FETCH QUEUE MEMBERSHIP FOR CURRENT USER
        Id userId = UserInfo.getUserId();
        List<GroupMember> memberships = [
             SELECT Group.DeveloperName 
             FROM GroupMember 
             WHERE UserOrGroupId = :userId 
             AND Group.Type = 'Queue'
        ];
        
        wrapper.CurrentUserQueues = new List<String>();
        for(GroupMember gm : memberships) {
            wrapper.CurrentUserQueues.add(gm.Group.DeveloperName);
        }
        
        return wrapper;
    }

    // ============================================================
    // UPDATE CASE
    // ============================================================
    // ============================================================
    // UPDATE CASE (VIA MAP TO BYPASS SOBJECT SECURITY)
    // ============================================================
    @AuraEnabled
    public static void updateCaseRecord(Map<String, Object> updatedCase) {
        if (updatedCase == null || !updatedCase.containsKey('Id')) {
             throw new AuraHandledException('Case ID is required for update.');
        }

        Case c = new Case();
        c.Id = (Id) updatedCase.get('Id');
        
        if (updatedCase.containsKey('Subject')) c.Subject = (String) updatedCase.get('Subject');
        if (updatedCase.containsKey('Description')) c.Description = (String) updatedCase.get('Description');
        if (updatedCase.containsKey('Status')) c.Status = (String) updatedCase.get('Status');
        if (updatedCase.containsKey('Priority')) c.Priority = (String) updatedCase.get('Priority');
        if (updatedCase.containsKey('Type')) c.Type = (String) updatedCase.get('Type');
        if (updatedCase.containsKey('Reason')) c.Reason = (String) updatedCase.get('Reason');
        if (updatedCase.containsKey('OwnerId')) c.OwnerId = (Id) updatedCase.get('OwnerId');
        if (updatedCase.containsKey('Assigned_User__c')) c.Assigned_User__c = (Id) updatedCase.get('Assigned_User__c');
        if (updatedCase.containsKey('Manager__c')) c.Manager__c = (Id) updatedCase.get('Manager__c');
        if (updatedCase.containsKey('Employee__c')) c.Employee__c = (Id) updatedCase.get('Employee__c');
        
        // Handle custom boolean for Manager Review
        if (updatedCase.containsKey('Requires_Manager_Review__c')) {
            c.Requires_Manager_Review__c = (Boolean) updatedCase.get('Requires_Manager_Review__c');
        }

        update c;
    }

    // ============================================================
    // GET EMAIL HISTORY (NOW INCLUDES CC, BCC, THREAD ID)
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static List<EmailMessage> getEmailMessages(Id caseId) {
        if (caseId == null) return new List<EmailMessage>();

        return [
            SELECT 
                Id,
                Subject,
                FromAddress,
                ToAddress,
                CcAddress,
                BccAddress,
                TextBody,
                MessageIdentifier,
                CreatedDate
            FROM EmailMessage
            WHERE ParentId = :caseId
            ORDER BY CreatedDate DESC
        ];
    }

    // ============================================================
    // ADD CASE COMMENT
    // ============================================================
    @AuraEnabled
    public static void addCaseComment(Id caseId, String commentBody) {
        if (caseId == null || String.isBlank(commentBody)) {
            throw new AuraHandledException('Comment body cannot be empty.');
        }

        CaseComment cc = new CaseComment();
        cc.ParentId = caseId;
        cc.CommentBody = commentBody;

        insert cc;
    }

    // ============================================================
    // FULL CASE TIMELINE (Status, Priority, Owner Changes + Comments)
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static List<TimelineEntry> getCaseTimeline(Id caseId) {
        List<TimelineEntry> output = new List<TimelineEntry>();
        if (caseId == null) return output;

        // ---- FIELD HISTORY ----
        for (CaseHistory ch : [
            SELECT Id, CreatedDate, Field, OldValue, NewValue, CreatedBy.Name
            FROM CaseHistory
            WHERE CaseId = :caseId
              AND Field IN ('Status','Priority','Owner')
        ]) {
            TimelineEntry t = new TimelineEntry();
            t.sourceId      = ch.Id;
            t.createdDate   = ch.CreatedDate;
            t.createdByName = ch.CreatedBy.Name;

            if (ch.Field == 'Status') {
                t.type = 'StatusChange';
                t.typeLabel = 'Status Change';
                t.title = 'Status changed';
            } 
            else if (ch.Field == 'Priority') {
                t.type = 'PriorityChange';
                t.typeLabel = 'Priority Change';
                t.title = 'Priority changed';
            } 
            else if (ch.Field == 'Owner') {
                t.type = 'OwnerChange';
                t.typeLabel = 'Owner Change';
                t.title = 'Owner changed';
            }

            t.body = 'From "' + ch.OldValue + '" to "' + ch.NewValue + '"';
            output.add(t);
        }

        // ---- CASE COMMENTS ----
        for (CaseComment cc : [
            SELECT Id, CreatedDate, CommentBody, CreatedBy.Name
            FROM CaseComment
            WHERE ParentId = :caseId
        ]) {
            TimelineEntry t = new TimelineEntry();
            t.sourceId      = cc.Id;
            t.createdDate   = cc.CreatedDate;
            t.createdByName = cc.CreatedBy.Name;

            t.type          = 'CaseComment';
            t.typeLabel     = 'Case Comment';
            t.title         = 'Comment added';
            t.body          = cc.CommentBody;

            output.add(t);
        }

        output.sort(new TimelineComparator());
        return output;
    }

    // ============================================================
    // GET ORG-WIDE EMAIL ADDRESSES
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static List<OrgWideEmailAddress> getOrgWideEmails() {
        return [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            ORDER BY DisplayName
        ];
    }

    // ============================================================
    // GET ASSIGNABLE USERS (FOR CASE OWNER DROPDOWN)
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static List<User> getAssignableUsers() {

        return [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            AND UserType IN ('Standard', 'CsnOnly') // Filter out technical users if needed
            ORDER BY Name
            LIMIT 200
        ];
    }

    // ============================================================
    // SEND EMAIL (NOW SUPPORTS CC + BCC)
    // ============================================================
    @AuraEnabled
    public static void sendCaseEmail(
        Id caseId,
        Id orgWideEmailId,
        String toAddress,
        String ccAddress,
        String bccAddress,
        String subject,
        String body
    ) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required.');
        }
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException('Recipient email is required.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { toAddress });

        if (!String.isBlank(ccAddress))
            mail.setCcAddresses(new String[] { ccAddress });

        if (!String.isBlank(bccAddress))
            mail.setBccAddresses(new String[] { bccAddress });

        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        mail.setWhatId(caseId);

        if (orgWideEmailId != null)
            mail.setOrgWideEmailAddressId(orgWideEmailId);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // ============================================================
    // DYNAMIC PICKLIST VALUES (Status, Priority, Type, Reason)
    // ============================================================
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getCasePicklists(Id recordTypeId) {
        Map<String, List<String>> results = new Map<String, List<String>>();

        // STATUS
        List<String> statuses = new List<String>();
        for (Schema.PicklistEntry pe : Case.Status.getDescribe().getPicklistValues()) {
            if (pe.isActive()) statuses.add(pe.getValue());
        }
        results.put('Status', statuses);

        // PRIORITY
        List<String> priorities = new List<String>();
        for (Schema.PicklistEntry pe : Case.Priority.getDescribe().getPicklistValues()) {
            if (pe.isActive()) priorities.add(pe.getValue());
        }
        results.put('Priority', priorities);

        // TYPE
        List<String> types = new List<String>();
        for (Schema.PicklistEntry pe : Case.Type.getDescribe().getPicklistValues()) {
            if (pe.isActive()) types.add(pe.getValue());
        }
        results.put('Type', types);

        // REASON
        List<String> reasons = new List<String>();
        for (Schema.PicklistEntry pe : Case.Reason.getDescribe().getPicklistValues()) {
            if (pe.isActive()) reasons.add(pe.getValue());
        }
        results.put('Reason', reasons);

        return results;
    }
}