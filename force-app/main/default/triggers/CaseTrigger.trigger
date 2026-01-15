trigger CaseTrigger on Case (before update, after update) {
    
    // --- BEFORE UPDATE AUTOMATION ---
    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Case c : Trigger.new) {
            Case oldCase = Trigger.oldMap.get(c.Id);

            // 1) Assignment Logic: Queue -> User = In Progress
            // Check if Owner changed from Queue (starts with 00G) to User (starts with 005)
            if (c.OwnerId != oldCase.OwnerId) {
                String oldOwnerId = (String)oldCase.OwnerId;
                String newOwnerId = (String)c.OwnerId;
                
                if (oldOwnerId != null && oldOwnerId.startsWith('00G') && 
                    newOwnerId != null && newOwnerId.startsWith('005')) {
                    
                    if (c.Status == 'New') {
                        c.Status = 'In Progress';
                    }
                }
            }

            // 2) Submission Logic: Submitted -> Pending Review OR Closed
            if (c.Status == 'Submitted' && oldCase.Status != 'Submitted') {
                if (c.Requires_Manager_Review__c == true) {
                    c.Status = 'Pending Review';
                } else {
                    c.Status = 'Closed';
                }
            }
        }
    }

    // --- AFTER UPDATE LOGIC (Existing) ---
    if (Trigger.isAfter && Trigger.isUpdate) {
        // 1) Get Record Type IDs once
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName IN ('Scheduling', 'Preauthorization', 'Radiopharmaceutical_Order')
        ]) {
            recordTypeMap.put(rt.DeveloperName, rt.Id);
        }

        Id schedulingRtId = recordTypeMap.get('Scheduling');
        Id preAuthRtId    = recordTypeMap.get('Preauthorization');
        Id radioRtId      = recordTypeMap.get('Radiopharmaceutical_Order');

        // Proceed only if Scheduling logic applies (dependant on IDs)
        if (schedulingRtId != null && preAuthRtId != null && radioRtId != null) {
            
            // 2) Identify Scheduling cases that changed status to the target statuses
            Set<Id> schedulingCaseIds = new Set<Id>();
            Map<Id, Case> schedById = new Map<Id, Case>();

            for (Case c : Trigger.new) {
                Case oldC = Trigger.oldMap.get(c.Id);

                // Only apply legacy logic to Scheduling record type
                if (c.RecordTypeId != schedulingRtId) continue;
                if (c.Status == oldC.Status) continue;

                // Only care about these transitions
                if (c.Status == 'In Progress' || c.Status == 'Scheduled') {
                    schedulingCaseIds.add(c.Id);
                    schedById.put(c.Id, c);
                }
            }

            if (!schedulingCaseIds.isEmpty()) {

                // 3) Query existing children to avoid duplicates
                Map<Id, Set<Id>> childRecordTypesByParent = new Map<Id, Set<Id>>();
                for (Case child : [
                    SELECT Id, ParentId, RecordTypeId
                    FROM Case
                    WHERE ParentId IN :schedulingCaseIds
                ]) {
                    if (!childRecordTypesByParent.containsKey(child.ParentId)) {
                        childRecordTypesByParent.put(child.ParentId, new Set<Id>());
                    }
                    childRecordTypesByParent.get(child.ParentId).add(child.RecordTypeId);
                }

                // 4) Create children as needed
                List<Case> casesToInsert = new List<Case>();

                for (Id parentId : schedById.keySet()) {
                    Case schedulingCase = schedById.get(parentId);

                    Set<Id> existingChildRts = childRecordTypesByParent.get(parentId);
                    if (existingChildRts == null) existingChildRts = new Set<Id>();

                    // When Scheduling hits In Progress -> create Pre-Authorization child (once)
                    if (schedulingCase.Status == 'In Progress'
                        && !existingChildRts.contains(preAuthRtId)) {

                        Case preAuth = new Case(
                            RecordTypeId = preAuthRtId,
                            ParentId     = schedulingCase.Id,
                            Subject      = schedulingCase.Subject + ' - Pre-Authorization',
                            Status       = 'New',
                            Origin       = 'Internal'
                        );

                        preAuth.AccountId = schedulingCase.AccountId;
                        preAuth.ContactId = schedulingCase.ContactId;
                        preAuth.Description = schedulingCase.Description;

                        casesToInsert.add(preAuth);
                    }

                    // When Scheduling hits Scheduled -> create Radiopharmaceutical Order child (once)
                    if (schedulingCase.Status == 'Scheduled'
                        && !existingChildRts.contains(radioRtId)) {

                        Case radioOrder = new Case(
                            RecordTypeId = radioRtId,
                            ParentId     = schedulingCase.Id,
                            Subject      = schedulingCase.Subject + ' - Radiopharmaceutical Order',
                            Status       = 'New',
                            Origin       = 'Internal'
                        );

                        radioOrder.AccountId = schedulingCase.AccountId;
                        radioOrder.ContactId = schedulingCase.ContactId;
                        radioOrder.Description = schedulingCase.Description;

                        casesToInsert.add(radioOrder);
                    }
                }

                if (!casesToInsert.isEmpty()) {
                    insert casesToInsert;
                }
            }
        }
    }
}