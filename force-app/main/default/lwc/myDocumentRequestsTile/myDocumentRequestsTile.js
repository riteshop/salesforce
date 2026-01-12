import { LightningElement, wire } from 'lwc';
import getPendingCount from '@salesforce/apex/MyDocumentRequestsApex.getPendingCount';
import { NavigationMixin } from 'lightning/navigation';

export default class MyDocumentRequestsTile extends NavigationMixin(LightningElement) {
    count = 0;

    @wire(getPendingCount)
    wiredCount({data}) {
        if (data !== undefined) {
            this.count = data;
        }
    }

    goToList() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Document_Request__c',
                actionName: 'list'
            },
            state: {
                filterName: 'My_Pending_Documents' // (create list view)
            }
        });
    }
}