import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getChildren from '@salesforce/apex/CaseChildrenController.getChildren';

export default class CaseChildren extends NavigationMixin(LightningElement) {
    @api recordId; // Case Id

    children = [];
    hasChildren = false;

    @wire(getChildren, { caseId: '$recordId' })
    wiredChildren({ error, data }) {
        if (data) {
            this.children = data;
            this.hasChildren = data.length > 0;
        } else if (error) {
            console.error('Error loading child tickets', error);
        }
    }

    navigate(event) {
        const recordId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'support_ticket__c', // Salesforce adjusts this automatically
                actionName: 'view'
            }
        });
    }
}