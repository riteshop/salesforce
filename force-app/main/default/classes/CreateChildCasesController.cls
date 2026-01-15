public with sharing class CreateChildCasesController { // v2
    
    @AuraEnabled
    public static String createChildCases(Id parentCaseId) {
        try {
            // Get Record Type IDs
            Map<String, Id> recordTypeMap = new Map<String, Id>();
            for (RecordType rt : [
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE SObjectType = 'Case'
                AND DeveloperName IN ('Pre_authorization', 'Radiopharmaceutical_Order')
            ]) {
                recordTypeMap.put(rt.DeveloperName, rt.Id);
            }

            Id preAuthRtId = recordTypeMap.get('Pre_authorization');
            Id radioRtId = recordTypeMap.get('Radiopharmaceutical_Order');

            if (preAuthRtId == null || radioRtId == null) {
                throw new AuraHandledException('Required record types not found.');
            }

            // Get parent case info
            Case parentCase = [
                SELECT Id, Subject, AccountId, ContactId
                FROM Case 
                WHERE Id = :parentCaseId 
                LIMIT 1
            ];

            // Create child cases
            List<Case> childCases = new List<Case>{
                new Case(
                    RecordTypeId = preAuthRtId,
                    ParentId = parentCase.Id,
                    Subject = parentCase.Subject,
                    Status = 'New',
                    Origin = 'Internal',
                    AccountId = parentCase.AccountId,
                    ContactId = parentCase.ContactId
                ),
                new Case(
                    RecordTypeId = radioRtId,
                    ParentId = parentCase.Id,
                    Subject = parentCase.Subject,
                    Status = 'New',
                    Origin = 'Internal',
                    AccountId = parentCase.AccountId,
                    ContactId = parentCase.ContactId
                )
            };

            insert childCases;
            return 'Success';

        } catch (DmlException e) {
            // Return detailed DML error information
            String errorMsg = 'DML Error: ' + e.getMessage() + '\n';
            for (Integer i = 0; i < e.getNumDml(); i++) {
                errorMsg += 'Record ' + i + ': ' + e.getDmlMessage(i) + '\n';
                errorMsg += 'Field: ' + e.getDmlFieldNames(i) + '\n';
            }
            System.debug('DML Exception Details: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
            
        } catch (QueryException e) {
            String errorMsg = 'Query Error: ' + e.getMessage() + ' at line ' + e.getLineNumber();
            System.debug('Query Exception: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
            
        } catch (Exception e) {
            String errorMsg = 'Error: ' + e.getMessage() + ' | Type: ' + e.getTypeName() + ' | Line: ' + e.getLineNumber();
            System.debug('General Exception: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        }
    }
}