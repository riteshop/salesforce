import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchAccounts from '@salesforce/apex/AccountSearchController.searchAccounts';

export default class AccountSearch extends NavigationMixin(LightningElement) {
    searchKey = '';
    accounts = [];

    // 🔍 Handle search input change
    handleSearchChange(event) {
        this.searchKey = event.target.value;

        if (this.searchKey && this.searchKey.length > 1) {
            searchAccounts({ searchKey: this.searchKey })
                .then((result) => {
                    this.accounts = result;
                })
                .catch((error) => {
                    console.error('Error searching accounts:', error);
                    this.accounts = [];
                });
        } else {
            this.accounts = [];
        }
    }

    // 🖱️ Navigate to Account record when clicked
    handleSelect(event) {
        const accountId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
}