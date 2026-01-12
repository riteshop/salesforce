global class PendingReviewCaseMonitor implements Schedulable {

    /* =========================================================
       Entry point for scheduled execution
       ========================================================= */
    global void execute(SchedulableContext sc) {
        runJob();
    }

    /* =========================================================
       Core logic
       ========================================================= */
    public static void runJob() {

        /* ---------------------------------------------
           Org-Wide Email (force sender)
           --------------------------------------------- */
        OrgWideEmailAddress owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = 'dzheng@unithera.com'
            LIMIT 1
        ];

        /* ---------------------------------------------
           Find stale cases (Pending Review > 24 hrs)
           --------------------------------------------- */
        List<Case> staleCases = [
            SELECT Id,
                   OwnerId,
                   Subject,
                   Status,
                   CreatedDate
            FROM Case
            WHERE Status = 'Pending Review'
              AND CreatedDate <= :Datetime.now().addHours(-24)
            LIMIT 5000
        ];

        if (staleCases.isEmpty()) {
            return;
        }

        /* ---------------------------------------------
           Base URL (API 58+ SAFE)
           Works for Sandbox, Prod, My Domain
           --------------------------------------------- */
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        /* ---------------------------------------------
           Build emails
           --------------------------------------------- */
        for (Case c : staleCases) {

            User owner = [
                SELECT Id, Email, Name
                FROM User
                WHERE Id = :c.OwnerId
                LIMIT 1
            ];

            // 🔗 Dynamic Case Link
            String caseUrl = baseUrl + '/' + c.Id;

            Messaging.SingleEmailMessage msg =
                new Messaging.SingleEmailMessage();

            // Force Org-Wide Email
            msg.setOrgWideEmailAddressId(owea.Id);

            msg.setToAddresses(new String[] { owner.Email });

            msg.setSubject(
                'Reminder: Case Pending Review Over 24 Hours'
            );

            /* ---------------------------------------------
               HTML Email Body (clickable link)
               --------------------------------------------- */
            msg.setHtmlBody(
                '<p>Hello ' + owner.Name + ',</p>' +
                '<p>' +
                'The following case has been in ' +
                '<strong>Pending Review</strong> for more than 24 hours.' +
                '</p>' +
                '<p>' +
                '<strong>Case Subject:</strong> ' + c.Subject + '<br/>' +
                '<strong>Created On:</strong> ' +
                c.CreatedDate.format() +
                '</p>' +
                '<p>' +
                '<a href="' + caseUrl + '" target="_blank">' +
                'Click here to open the Case' +
                '</a>' +
                '</p>' +
                '<p>Please review and update the case.</p>' +
                '<p>Thank you.</p>'
            );

            emails.add(msg);
        }

        /* ---------------------------------------------
           Send all emails
           --------------------------------------------- */
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
}