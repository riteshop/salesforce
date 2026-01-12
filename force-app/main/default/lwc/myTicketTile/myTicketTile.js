import { LightningElement, wire } from 'lwc';
import getCount from '@salesforce/apex/MySupportTicketCount.getCount';
import { NavigationMixin } from 'lightning/navigation';

export default class MyTicketTile extends NavigationMixin(LightningElement) {
    count = 0;

    @wire(getCount)
    wiredCount({ data }) {
        if (data !== undefined) {
            this.count = data;
        }
    }

    goToList() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'support_ticket__c',
                actionName: 'list'
            },
            state: {
                filterName: 'My_New_Tickets' // your list view API name
            }
        });
    }
}