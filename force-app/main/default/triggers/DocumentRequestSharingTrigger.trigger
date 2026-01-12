trigger DocumentRequestSharingTrigger on Document_Request__c (after insert, after update) {
    if (Trigger.isInsert) {
        DocumentRequestSharingHandler.applySharing(
            new List<Document_Request__c>(),
            Trigger.new
        );
    }

    if (Trigger.isUpdate) {
        DocumentRequestSharingHandler.applySharing(
            Trigger.old,
            Trigger.new
        );
    }
}