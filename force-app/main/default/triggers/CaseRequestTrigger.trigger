trigger CaseRequestTrigger on Case_Creation_Request__e (after insert) {
    List<Case> casesToInsert = new List<Case>();
    
    // FETCH QUEUE MAP once for bulk processing
    Map<String, Id> queueMap = new Map<String, Id>();
    for (Group q : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN ('IT', 'RCM')]) {
        queueMap.put(q.DeveloperName, q.Id);
    }
    
    // FETCH DEFAULT QUEUE FALLBACK
    Id fallbackQueueId;
    List<QueueSobject> validQueues = [SELECT QueueId FROM QueueSobject WHERE SobjectType = 'Case' LIMIT 1];
    if (!validQueues.isEmpty()) {
        fallbackQueueId = validQueues[0].QueueId;
    }

    for (Case_Creation_Request__e req : Trigger.New) {
        Case c = new Case();
        c.Subject = req.Subject__c;
        c.Description = req.Description__c;
        c.Status = req.Status__c;
        c.Origin = req.Origin__c;
        c.Priority = req.Priority__c;
        c.Type = req.Type__c;
        
        // Handling created by / requestor
        if (req.Requestor_User_Id__c != null) {
            c.Case_Creator__c = req.Requestor_User_Id__c;
        }
        
        // AUTO-ASSIGN OWNER LOGIC (Replicated from Controller)
        if (req.Type__c == 'IT' && queueMap.containsKey('IT')) {
            c.OwnerId = queueMap.get('IT');
        } 
        else if (req.Type__c == 'RCM' && queueMap.containsKey('RCM')) {
            c.OwnerId = queueMap.get('RCM');
        } 
        else if (fallbackQueueId != null) {
            c.OwnerId = fallbackQueueId;
        }
        
        casesToInsert.add(c);
    }
    
    if (!casesToInsert.isEmpty()) {
        // This runs as Automated Process, so it has FULL ACCESS.
        insert casesToInsert;
    }
}
