String targetUserId = '005dm00000BUxqjAAD'; // Test Platform User
Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];

System.debug('=== DEBUGGING CASE DETAIL ACCESS ===');
System.debug('Target User: ' + targetUserId);
System.debug('Test Case: ' + testCase.CaseNumber + ' (' + testCase.Id + ')');

System.runAs(new User(Id = targetUserId)) {
    try {
        Case c = CaseDetailController.getCaseDetails(testCase.Id);
        System.debug('SUCCESS: Retrieved Case: ' + c.CaseNumber);
        System.debug('Owner: ' + c.Owner.Name);
    } catch (Exception e) {
        System.debug('ERROR: ' + e.getMessage());
        System.debug('Stack: ' + e.getStackTraceString());
    }
}
