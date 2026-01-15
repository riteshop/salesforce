@isTest
public class PlatformUserReadTest {
    @isTest
    static void testReadCaseAsPlatformUser() {
        // 1. Setup Data (System Admin creates it)
        Case c = new Case(Subject = 'Test Read', Status = 'New');
        insert c;
        
        // 2. Find Platform User
        User u = [SELECT Id FROM User WHERE Profile.Name = 'Standard Platform User' AND IsActive = true LIMIT 1];
        
        // 3. Run as Platform User
        System.runAs(u) {
            try {
                // Call the controller (without sharing)
                CaseDetailController.CaseDetailWrapper result = CaseDetailController.getCaseDetails(c.Id);
                
                System.debug('RESULT: ' + result);
                if (result != null) {
                    System.debug('Subject: ' + result.Subject);
                    System.assert(result.Subject == 'Test Read', 'Subject should be visible in Wrapper');
                    System.assert(result.Status == 'New', 'Status should be visible');
                } else {
                    System.assert(false, 'Result is null');
                }
            } catch (Exception e) {
                System.assert(false, 'Read Failed: ' + e.getMessage());
            }
        }
    }
}
