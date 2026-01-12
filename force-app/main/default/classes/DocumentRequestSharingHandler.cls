public class DocumentRequestSharingHandler {

    public static void applySharing(List<Document_Request__c> docsOld, List<Document_Request__c> docsNew) {

        Map<Id, Id> oldApprovers = new Map<Id, Id>();
        for (Document_Request__c d : docsOld) {
            oldApprovers.put(d.Id, d.Approver__c);
        }

        List<Document_Request__Share> sharesToInsert = new List<Document_Request__Share>();
        List<Document_Request__Share> sharesToDelete = new List<Document_Request__Share>();

        // Query existing manual shares for the records being updated
        Set<Id> docIds = new Set<Id>();
        for (Document_Request__c d : docsNew) {
            docIds.add(d.Id);
        }

        Map<Id, List<Document_Request__Share>> existingShares = new Map<Id, List<Document_Request__Share>>();

        for (Document_Request__Share s : [
            SELECT Id, ParentId, UserOrGroupId, RowCause
            FROM Document_Request__Share
            WHERE ParentId IN :docIds
            AND RowCause = 'Manual'
        ]) {
            if (!existingShares.containsKey(s.ParentId)) {
                existingShares.put(s.ParentId, new List<Document_Request__Share>());
            }
            existingShares.get(s.ParentId).add(s);
        }

        // Apply delete + insert logic
        for (Document_Request__c d : docsNew) {

            Id oldApprover = oldApprovers.get(d.Id);
            Id newApprover = d.Approver__c;

            // DELETE old share if approver changed
            if (oldApprover != null && oldApprover != newApprover) {
                if (existingShares.containsKey(d.Id)) {
                    for (Document_Request__Share s : existingShares.get(d.Id)) {
                        if (s.UserOrGroupId == oldApprover) {
                            sharesToDelete.add(s);
                        }
                    }
                }
            }

            // ADD new share
            if (newApprover != null) {
                Document_Request__Share newShare = new Document_Request__Share(
                    ParentId = d.Id,
                    UserOrGroupId = newApprover,
                    AccessLevel = 'Edit',
                    RowCause = Schema.Document_Request__Share.RowCause.Manual
                );
                sharesToInsert.add(newShare);
            }
        }

        // Execute DML
        if (!sharesToDelete.isEmpty()) {
            delete sharesToDelete;
        }

        if (!sharesToInsert.isEmpty()) {
            insert sharesToInsert;
        }
    }
}