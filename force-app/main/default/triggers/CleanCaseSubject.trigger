trigger CleanCaseSubject on Case (before insert) {
    for (Case c : Trigger.new) {
        if (c.Subject != null) {
            c.Subject = c.Subject
                .replaceAll('(?i)^\\s*FW:\\s*', '')
                .replaceAll('(?i)^\\s*FWD:\\s*', '')
                .replaceAll('(?i)^\\s*RE:\\s*', '')
                .trim();
        }
    }
}