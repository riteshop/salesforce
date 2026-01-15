String targetUserId = '005dm00000BUxqjAAD'; // Test Platform User ID

System.debug('=== DEBUGGING USER ===');
System.debug('Target User ID: ' + targetUserId);

// 1. Check Group Membership (Queue)
Set<Id> myQueueIds = new Set<Id>();
List<GroupMember> memberships = [
    SELECT GroupId, Group.Name, Group.Type 
    FROM GroupMember 
    WHERE UserOrGroupId = :targetUserId 
    AND Group.Type = 'Queue'
];

System.debug('Queue Memberships Found: ' + memberships.size());
for (GroupMember gm : memberships) {
    System.debug(' - Member of Queue: ' + gm.Group.Name + ' (' + gm.GroupId + ')');
    myQueueIds.add(gm.GroupId);
}

// 2. Check Visibility Query
String baseWhere = 'WHERE IsDeleted = false AND (' +
                   'OwnerId = :targetUserId ' + 
                   'OR Assigned_User__c = :targetUserId ' + 
                   'OR OwnerId IN :myQueueIds' +
                   ')';

String soql = 'SELECT Id, CaseNumber, Owner.Name, Subject FROM Case ' + baseWhere;
System.debug('Generated SOQL: ' + soql);

List<Case> visibleCases = Database.query(soql);
System.debug('Visible Cases Found: ' + visibleCases.size());
for (Case c : visibleCases) {
    System.debug(' - Case: ' + c.CaseNumber + ' | Subject: ' + c.Subject + ' | Owner: ' + c.Owner.Name);
}
