import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { updateRecord } from 'lightning/uiRecordApi';

import NAME_FIELD from '@salesforce/schema/Document_Request__c.Name';
import REQUEST_TYPE_FIELD from '@salesforce/schema/Document_Request__c.Request_Type__c';
import DESCRIPTION_FIELD from '@salesforce/schema/Document_Request__c.Request_Description__c';
import DUE_DATE_FIELD from '@salesforce/schema/Document_Request__c.Due_Date__c';
import CREATED_BY_FIELD from '@salesforce/schema/Document_Request__c.CreatedBy.Name';
import LAST_MODIFIED_BY_FIELD from '@salesforce/schema/Document_Request__c.LastModifiedBy.Name';
import ID_FIELD from '@salesforce/schema/Document_Request__c.Id';

const FIELDS = [
    NAME_FIELD,
    REQUEST_TYPE_FIELD,
    DESCRIPTION_FIELD,

    DUE_DATE_FIELD,
    CREATED_BY_FIELD,
    LAST_MODIFIED_BY_FIELD
];

export default class DocumentRequestDetailPanel extends LightningElement {
    @api recordId;

    @track data;

    // Local draft & original values
    @track descriptionDraft = '';
    @track descriptionOriginal = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.data = data;

            const value = getFieldValue(data, DESCRIPTION_FIELD) || '';

            // Set original + draft
            this.descriptionOriginal = value;
            this.descriptionDraft = value;
        } else if (error) {
            console.error('Error loading record details', error);
        }
    }

    // --- FIELD GETTERS ---

    get name() {
        return getFieldValue(this.data, NAME_FIELD);
    }

    get requestType() {
        return getFieldValue(this.data, REQUEST_TYPE_FIELD);
    }

    get description() {
        return this.descriptionDraft;
    }

    get dueDate() {
        const raw = getFieldValue(this.data, DUE_DATE_FIELD);
        if (!raw) return '';

        const dateObj = new Date(raw);
        return dateObj.toLocaleString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    get createdBy() {
        return getFieldValue(this.data, CREATED_BY_FIELD);
    }

    get lastModifiedBy() {
        return getFieldValue(this.data, LAST_MODIFIED_BY_FIELD);
    }

    // --- USER TYPING (does NOT save yet) ---
    handleDescriptionTyping(event) {
        this.descriptionDraft = event.target.value;
    }

    // --- SHOW SAVE BUTTON ONLY IF UPDATED ---
    get showSaveButton() {
        return this.descriptionDraft !== this.descriptionOriginal;
    }

    // --- SAVE DESCRIPTION ---
    saveDescription() {
        const fields = {};
        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[DESCRIPTION_FIELD.fieldApiName] = this.descriptionDraft;

        updateRecord({ fields })
            .then(() => {
                // Update original so the save button hides again
                this.descriptionOriginal = this.descriptionDraft;
                console.log('Description updated successfully');
            })
            .catch(error => {
                console.error('Error updating description:', JSON.stringify(error));
            });
    }
}