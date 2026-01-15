List<User> users = [
    SELECT Id, Name, Username, Profile.Name, UserType, Profile.UserLicense.Name 
    FROM User 
    WHERE IsActive = true 
    ORDER BY CreatedDate DESC 
    LIMIT 5
];

for(User u : users) {
    System.debug('User: ' + u.Name + ' | Profile: ' + u.Profile.Name + ' | License: ' + u.Profile.UserLicense.Name);
}
