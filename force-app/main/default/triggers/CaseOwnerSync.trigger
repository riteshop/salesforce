trigger CaseOwnerSync on Case (after update) {

    // Step 1: Collect cases whose assignment changed
    Map<Id, Id> desiredOwners = new Map<Id, Id>();

    for (Case c : Trigger.new) {
        Case oldC = Trigger.oldMap.get(c.Id);

        Boolean assignedChanged = c.Assigned_User__c != oldC.Assigned_User__c;
        Boolean ownerChanged    = c.OwnerId != oldC.OwnerId;

        if (assignedChanged || ownerChanged) {
            if (c.Assigned_User__c != null) {
                desiredOwners.put(c.Id, c.Assigned_User__c);
            } else {
                desiredOwners.put(c.Id, c.OwnerId);
            }
        }
    }

    if (desiredOwners.isEmpty()) {
        return;
    }

    // Step 2: Define child objects + their Case lookup fields
    Map<String, String> childObjects = new Map<String, String>{
        'support_ticket__c' => 'Parent_Case__c',
        'Salesforce__c'     => 'Parent_Case__c',
        'Status_Tracker__c' => 'Parent_Case__c'
        // add more objects later…
    };

    // PREP: extract Case Ids into a bindable variable
    Set<Id> caseIds = desiredOwners.keySet();

    // Step 3: Loop through each child object
    for (String childObj : childObjects.keySet()) {

        String caseField = childObjects.get(childObj);

        // Build valid dynamic SOQL
        String soql =
            'SELECT Id, OwnerId, ' + caseField +
            ' FROM ' + childObj +
            ' WHERE ' + caseField + ' IN :caseIds';

        List<SObject> children = Database.query(soql);
        List<SObject> updates  = new List<SObject>();

        for (SObject rec : children) {
            Id parentCaseId = (Id) rec.get(caseField);
            Id newOwner     = desiredOwners.get(parentCaseId);

            if (newOwner != null && rec.get('OwnerId') != newOwner) {
                rec.put('OwnerId', newOwner);
                updates.add(rec);
            }
        }

        if (!updates.isEmpty()) {
            Database.DMLOptions opts = new Database.DMLOptions();
            opts.EmailHeader.triggerUserEmail  = true;
            opts.EmailHeader.triggerOtherEmail = true;

            Database.update(updates, opts);
        }
    }
}