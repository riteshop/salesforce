trigger CaseToSupportTicket on Case (after insert) { // v2
 /*
    List<support_ticket__c> supportTickets = new List<support_ticket__c>();
    List<Salesforce__c> sfTickets = new List<Salesforce__c>();
    List<Status_Tracker__c> stTickets = new List<Status_Tracker__c>();

    for (Case c : Trigger.new) {

        // ---- CLEAN SUBJECT ----
        String cleanSubject = c.Subject;

        if (cleanSubject != null) {
            cleanSubject = cleanSubject
                .replaceAll('(?i)^\\s*FW:\\s*', '')
                .replaceAll('(?i)^\\s*FWD:\\s*', '')
                .replaceAll('(?i)^\\s*RE:\\s*', '')
                .trim();
        }

        // ------------------------------
        // CASE TYPE: TECHNICAL SUPPORT
        // ------------------------------
        if (c.Type == 'Technical Support') {

            support_ticket__c t = new support_ticket__c();

            t.Name           = cleanSubject;
            t.Subject__c     = cleanSubject;
            t.Description__c = c.Description;
            t.Priority__c    = c.Priority;
            t.Status__c      = 'New';
            t.Parent_Case__c = c.Id;

            // Owner logic
            if (c.Assigned_User__c != null) {
                t.OwnerId = c.Assigned_User__c; // platform user allowed
            } else {
                t.OwnerId = c.OwnerId;
            }

            supportTickets.add(t);
        }

        // ------------------------------
        // CASE TYPE: SALESFORCE
        // ------------------------------
        if (c.Type == 'Salesforce') {

            Salesforce__c s = new Salesforce__c();

            s.Name           = cleanSubject;
            s.Subject__c     = cleanSubject;
            s.Description__c = c.Description;
            s.Parent_Case__c = c.Id;

            // Owner logic
            if (c.Assigned_User__c != null) {
                s.OwnerId = c.Assigned_User__c;
            } else {
                s.OwnerId = c.OwnerId;
            }

            sfTickets.add(s);
        }
         // ------------------------------
        // CASE TYPE: Status Tracker
        // ------------------------------
        if (c.Type == 'Status Tracker') {

            Status_Tracker__c st = new Status_Tracker__c();

            st.Name           = cleanSubject;
            st.Subject__c     = cleanSubject;
            st.Description__c = c.Description;
            st.Parent_Case__c = c.Id;

            // Owner logic
            if (c.Assigned_User__c != null) {
                st.OwnerId = c.Assigned_User__c;
            } else {
                st.OwnerId = c.OwnerId;
            }

            stTickets.add(st);
        }
    }

    // Insert Technical Support tickets
    if (!supportTickets.isEmpty()) {
        insert supportTickets;
    }

    // Insert Salesforce tickets
    if (!sfTickets.isEmpty()) {
        insert sfTickets;
    }

    // Insert Status Tracker tickets
    if (!stTickets.isEmpty()) {
        insert stTickets;
    }
    */
}