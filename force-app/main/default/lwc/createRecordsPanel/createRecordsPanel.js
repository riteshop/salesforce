import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class CreateRecordsPanel extends NavigationMixin(LightningElement) {
    @track showAccountOptions = false;

    // Handle creating Contact
    handleCreateContact() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Contact',
                actionName: 'new'
            }
        });
    }

    // Toggle options for New Account
    toggleAccountOptions() {
        this.showAccountOptions = !this.showAccountOptions;
    }

    // Handle Account Type selection
    handleSelectAccountType(event) {
        const selectedType = event.target.dataset.type;

        // 🔹 Replace with your actual record type IDs for Account
        const recordTypeMap = {
            'Referring Provider': '012a5000004Vs9tAAC',
            'Office': '012dm000000iz1NAAQ',
            'Organization': '012dm000000iyQHAAY'
        };

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Account',
                actionName: 'new'
            },
            state: {
                recordTypeId: recordTypeMap[selectedType],
                defaultFieldValues: `Type__c=${selectedType}`
            }
        });

        this.showAccountOptions = false;
    }

    // Create Note
    handleCreateNote() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'ContentNote',
                actionName: 'home'
            }
        });
    }
}