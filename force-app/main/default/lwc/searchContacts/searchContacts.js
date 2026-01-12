import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchContacts from '@salesforce/apex/ContactSearchController.searchContacts';

export default class ContactSearch extends NavigationMixin(LightningElement) {
    @track searchKey = '';
    @track results = [];

    // 🔍 Handle input change
    handleSearchChange(event) {
        this.searchKey = event.target.value;

        if (this.searchKey && this.searchKey.length > 1) {
            searchContacts({ searchKey: this.searchKey })
                .then((data) => {
                    this.results = data;
                })
                .catch((error) => {
                    console.error('Error searching contacts:', error);
                    this.results = [];
                });
        } else {
            this.results = [];
        }
    }

    // 🖱️ Navigate to Contact record when clicked
    handleSelect(event) {
        const contactId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contactId,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }
}