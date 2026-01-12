public with sharing class NoteSummaryBridge {
    @AuraEnabled(cacheable=true)
    public static String getSummary() {
        // Simply return the same static string for now
        return NoteSummaryController.getSummary();
    }
}