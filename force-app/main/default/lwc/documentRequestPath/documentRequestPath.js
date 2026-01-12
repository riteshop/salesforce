import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';

import DOCUMENT_REQUEST_OBJECT from '@salesforce/schema/Document_Request__c';
import STATUS_FIELD from '@salesforce/schema/Document_Request__c.Status__c';
import ID_FIELD from '@salesforce/schema/Document_Request__c.Id';

const RECORD_FIELDS = [STATUS_FIELD];

export default class DocumentRequestPath extends LightningElement {
    @api recordId;

    @track stages = [];
    @track selectedStage = null;
    @track showConfirm = false;

    currentStatus;
    statusPicklist = [];
    recordTypeId;

    /* ============================================================
       Load current record (Status)
       ============================================================ */
    @wire(getRecord, { recordId: '$recordId', fields: RECORD_FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.currentStatus = getFieldValue(data, STATUS_FIELD);
            this.buildStages();
        } else if (error) {
            console.error('Error loading Document Request record', error);
        }
    }

    /* ============================================================
       Load Object Info (Record Type)
       ============================================================ */
    @wire(getObjectInfo, { objectApiName: DOCUMENT_REQUEST_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error loading object info', error);
        }
    }

    /* ============================================================
       Load Status picklist values (dynamic stages)
       ============================================================ */
    @wire(getPicklistValuesByRecordType, {
        objectApiName: DOCUMENT_REQUEST_OBJECT,
        recordTypeId: '$recordTypeId'
    })
    wiredPicklists({ data, error }) {
        if (data && data.picklistFieldValues && data.picklistFieldValues.Status__c) {
            this.statusPicklist = data.picklistFieldValues.Status__c.values;
            this.buildStages();
        } else if (error) {
            console.error('Error loading Status picklist', error);
        }
    }

    /* ============================================================
       Build Path Stages
       ============================================================ */
    buildStages() {
        if (!this.currentStatus || !this.statusPicklist.length) return;

        const labels = this.statusPicklist.map(v => v.value);

        let currentIndex = labels.indexOf(this.currentStatus);
        if (currentIndex === -1) currentIndex = 0;

        const stages = [];

        labels.forEach((label, index) => {
            const isCurrent = index === currentIndex;
            let state;

            // ---- Terminal states (by value) ----
            if (label === 'Rejected') {
                state = isCurrent ? 'rejected' : 'upcoming-rejected';
            }
            else if (label === 'Approved') {
                state = isCurrent ? 'approved' : 'upcoming-approved';
            }
            // ---- Non-terminal ----
            else if (isCurrent) {
                state = 'current';
            }
            else if (index < currentIndex) {
                state = 'completed';
            }
            else {
                state = 'upcoming';
            }

            stages.push({
                label,
                state,
                cssClass:
                    `path-step path-step--${state}` +
                    (this.selectedStage === label ? ' path-step--selected' : '')
            });
        });

        this.stages = stages;
    }

    /* ============================================================
       Handle stage click
       ============================================================ */
    handleStageClick(event) {
        const label = event.currentTarget.dataset.label;

        // Prevent selecting current status
        if (label === this.currentStatus) return;

        this.selectedStage = label;
        this.showConfirm = true;

        this.buildStages();
    }

    /* ============================================================
       Confirm status change
       ============================================================ */
    confirmChange() {
        const fields = {};
        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[STATUS_FIELD.fieldApiName] = this.selectedStage;

        updateRecord({ fields })
            .then(() => {
                this.currentStatus = this.selectedStage;
                this.selectedStage = null;
                this.showConfirm = false;
                this.buildStages();
            })
            .catch(error => {
                console.error('Error updating status', error);
            });
    }
}