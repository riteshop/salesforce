public without sharing class DocumentRequestUserSearchController {

    public class UserOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;

        public UserOption(String id, String name, String email) {
            this.id = id;
            this.name = name;
            this.email = email;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> searchUsers(String searchTerm) {
        // basic guard
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<UserOption>();
        }

        String likeTerm = '%' + searchTerm.trim() + '%';

        List<User> users = [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = TRUE
              AND (Name LIKE :likeTerm OR Email LIKE :likeTerm)
            ORDER BY Name
            LIMIT 20
        ];

        List<UserOption> results = new List<UserOption>();
        for (User u : users) {
            results.add(new UserOption(u.Id, u.Name, u.Email));
        }
        return results;
    }
}