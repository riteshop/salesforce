import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import updateCaseStatus from '@salesforce/apex/CasePathController.updateCaseStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CaseModernPath extends LightningElement {
    @api recordId;

    @track stages = [];
    @track showConfirm = false;
    @track selectedStage = null;

    recordTypeId;
    currentStatus;
    orderedStatuses = [];

    /* =========================================================
       Load Case (Status + Record Type)
       ========================================================= */
    @wire(getRecord, {
        recordId: '$recordId',
        fields: ['Case.Status', 'Case.RecordTypeId']
    })
    wiredCase({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Status.value;
            this.recordTypeId = data.fields.RecordTypeId.value;
            this.buildStages();
        } else if (error) {
            console.error(error);
        }
    }

    /* =========================================================
       Load Status Picklist (ordered per Record Type)
       ========================================================= */
    @wire(getPicklistValuesByRecordType, {
        objectApiName: CASE_OBJECT,
        recordTypeId: '$recordTypeId'
    })
    wiredPicklists({ data, error }) {
        if (data) {
            this.orderedStatuses =
                data.picklistFieldValues.Status.values.map(v => v.label);
            this.buildStages();
        } else if (error) {
            console.error(error);
        }
    }

    /* =========================================================
       Build visual path
       ========================================================= */
    buildStages() {
        if (!this.currentStatus || !this.orderedStatuses.length) return;

        const currentIndex =
            this.orderedStatuses.indexOf(this.currentStatus);

        this.stages = this.orderedStatuses.map((label, index) => {
            let css = 'path-step path-step--upcoming';

            if (index < currentIndex) {
                css = 'path-step path-step--completed';
            } else if (index === currentIndex) {
                css = 'path-step path-step--current';
            }

            return {
                label,
                index,
                cssClass: css
            };
        });
    }

    /* =========================================================
       Handle clicking a step (UI-only enforcement)
       ========================================================= */
    handleStageClick(event) {
        const label = event.currentTarget.dataset.label;
        const stage = this.stages.find(s => s.label === label);
        if (!stage) return;

        const currentIndex =
            this.orderedStatuses.indexOf(this.currentStatus);

        const terminalStart = this.orderedStatuses.length - 2;

        const isNext = stage.index === currentIndex + 1;
        const isTerminalChoice =
            currentIndex === terminalStart - 1 &&
            stage.index >= terminalStart;

        if (!isNext && !isTerminalChoice) return;

        this.selectedStage = stage;
        this.showConfirm = true;

        this.stages = this.stages.map(s => ({
            ...s,
            cssClass:
                s.label === stage.label
                    ? s.cssClass + ' path-step--selected'
                    : s.cssClass
        }));
    }

    /* =========================================================
       Confirm forward change
       ========================================================= */
    async confirmChange() {
        if (!this.selectedStage) return;

        try {
            await updateCaseStatus({
                caseId: this.recordId,
                newStatus: this.selectedStage.label
            });

            this.currentStatus = this.selectedStage.label;
            this.selectedStage = null;
            this.showConfirm = false;

            this.buildStages();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Case status updated.',
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: e.body?.message || 'Status update failed',
                    variant: 'error'
                })
            );
        }
    }

    /* =========================================================
       Cancel selection (no status change)
       ========================================================= */
    cancelChange() {
        this.showConfirm = false;
        this.selectedStage = null;
        this.buildStages();
    }

    /* =========================================================
       ACTIONS MENU
       ========================================================= */
    handleActionSelect(event) {
        const action = event.detail.value;

        if (action === 'back') {
            this.goBackOneStep();
        } else if (action === 'close') {
            this.closeCase();
        }
    }

    /* =========================================================
       Go back exactly one step
       ========================================================= */
    async goBackOneStep() {
        const currentIndex =
            this.orderedStatuses.indexOf(this.currentStatus);

        if (currentIndex <= 0) return;

        const previousStatus =
            this.orderedStatuses[currentIndex - 1];

        try {
            await updateCaseStatus({
                caseId: this.recordId,
                newStatus: previousStatus
            });

            this.currentStatus = previousStatus;
            this.showConfirm = false;
            this.selectedStage = null;

            this.buildStages();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Updated',
                    message: 'Moved back one step.',
                    variant: 'info'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: e.body?.message || 'Update failed',
                    variant: 'error'
                })
            );
        }
    }

    /* =========================================================
       Close case (jump to final status)
       ========================================================= */
    async closeCase() {
        if (!this.orderedStatuses.length) return;

        const finalStatus =
            this.orderedStatuses[this.orderedStatuses.length - 1];

        try {
            await updateCaseStatus({
                caseId: this.recordId,
                newStatus: finalStatus
            });

            this.currentStatus = finalStatus;
            this.showConfirm = false;
            this.selectedStage = null;

            this.buildStages();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Closed',
                    message: 'Case moved to final status.',
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: e.body?.message || 'Close failed',
                    variant: 'error'
                })
            );
        }
    }
}