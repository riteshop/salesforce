public with sharing class GetUser {
    
    // Return the current user's full name
    @AuraEnabled(cacheable=true)
    public static String getUserName() {
        return [SELECT Name FROM User WHERE Id = :UserInfo.getUserId()].Name;
    }
    
    // OPTIONAL: return more user info for reuse in future LWCs
    @AuraEnabled(cacheable=true)
    public static User getUserInfo() {
        return [
            SELECT Id, Name, Email, Title, Department 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
        ];
    }
}