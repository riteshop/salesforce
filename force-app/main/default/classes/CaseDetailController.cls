public with sharing class CaseDetailController {

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
    // GET CASE DETAILS
    // ============================================================
    @AuraEnabled
    public static Case getCaseDetails(Id caseId) {
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
                Contact.Name,
                ContactId,
                Account.Name,
                AccountId
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        return results.isEmpty() ? null : results[0];
    }

    // ============================================================
    // UPDATE CASE
    // ============================================================
    @AuraEnabled
    public static void updateCaseRecord(Case updatedCase) {
        update updatedCase;
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
            WHERE Id IN (
                SELECT UserId
                FROM UserLogin
                WHERE IsFrozen = false
            )
            AND IsActive = true
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