import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';

import getCases from '@salesforce/apex/CaseListController.getCases';
import createCase from '@salesforce/apex/CaseListController.createCase';
import searchContacts from '@salesforce/apex/CaseListController.searchContacts';
import searchAccounts from '@salesforce/apex/CaseListController.searchAccounts';
import searchUsers from '@salesforce/apex/CaseListController.searchUsers';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

//
// UI API imports for dynamic picklists
//
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import STATUS_FIELD from '@salesforce/schema/Case.Status';
import PRIORITY_FIELD from '@salesforce/schema/Case.Priority';
import ORIGIN_FIELD from '@salesforce/schema/Case.Origin';
import REASON_FIELD from '@salesforce/schema/Case.Reason';
import TYPE_FIELD from '@salesforce/schema/Case.Type';

export default class PlatformCaseList extends NavigationMixin(LightningElement) {

    // ======================
    // TABLE + STATE
    // ======================
    @track cases = [];
    @track error;
    @track isLoading = false;

    // SEARCH
    @track searchTerm = '';
    searchTimeout;

    // SORTING
    sortedBy = 'CreatedDate';
    sortedDirection = 'desc';

    // PAGINATION
    pageSize = 50;
    pageNumber = 1;
    totalRecords = 0;
    totalPages = 0;

    get offsetValue() {
        return (this.pageNumber - 1) * this.pageSize;
    }

    get isFirstPage() {
        return this.pageNumber === 1;
    }

    get isLastPage() {
        return this.pageNumber === this.totalPages;
    }

    // ======================
    // TABLE COLUMNS
    // ======================
    columns = [
        {
            label: "Case Number",
            type: "button",
            fieldName: "CaseNumber",
            sortable: true,
            typeAttributes: {
                label: { fieldName: "CaseNumber" },
                name: "open_case",
                variant: "base"
            }
        },
        { label: "Subject", fieldName: "Subject", type: "text", sortable: true },
        { label: "Status", fieldName: "Status", type: "text", sortable: true },
        { label: "Priority", fieldName: "Priority", type: "text", sortable: true },
        { label: "Created Date", fieldName: "CreatedDate", type: "date", sortable: true }
    ];

    connectedCallback() {
        this.loadCases();
    }

    loadCases() {
        this.isLoading = true;

        getCases({
            pageSize: this.pageSize,
            offsetValue: this.offsetValue,
            sortField: this.sortedBy,
            sortDirection: this.sortedDirection,
            searchTerm: this.searchTerm
        })
        .then(result => {
            this.cases = result.records;
            this.totalRecords = result.totalRecords;
            this.totalPages = Math.ceil(result.totalRecords / this.pageSize);
            this.isLoading = false;
        })
        .catch(err => {
            this.error = err.body ? err.body.message : err.message;
            this.isLoading = false;
        });
    }

    // ======================
    // SEARCH HANDLING
    // ======================
    handleSearchChange(event) {
        const value = event.target.value;

        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.searchTerm = value;
            this.pageNumber = 1;
            this.loadCases();
        }, 300);
    }

    // ======================
    // SORT HANDLER
    // ======================
    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.pageNumber = 1;
        this.loadCases();
    }

    // ======================
    // PAGINATION
    // ======================
    handleNext() {
        if (!this.isLastPage) {
            this.pageNumber++;
            this.loadCases();
        }
    }

    handlePrevious() {
        if (!this.isFirstPage) {
            this.pageNumber--;
            this.loadCases();
        }
    }

    // ======================
    // OPEN ROW
    // ======================
    handleRowAction(event) {
        if (event.detail.action.name === "open_case") {
            let caseId = event.detail.row.Id;

            this[NavigationMixin.Navigate]({
                type: "standard__navItemPage",
                attributes: { apiName: "Platform_Case_Detail" },
                state: { c__caseId: caseId }
            });
        }
    }

    // ======================================================
    // EVERYTHING BELOW THIS LINE = YOUR ORIGINAL CODE
    // LOOKUPS, MODAL, FIELD HANDLERS, NEW CASE CREATION
    // I DID NOT MODIFY ANYTHING
    // ======================================================

    @track showNewCaseModal = false;

    // LOOKUPS
    @track ownerSearchTerm = "You (Current User)";
    @track ownerOptions = [];
    @track ownerResultsVisible = false;
    @track selectedOwnerId = USER_ID;

    @track contactSearchTerm = "";
    @track contactOptions = [];
    @track contactResultsVisible = false;
    @track selectedContactId;

    @track accountSearchTerm = "";
    @track accountOptions = [];
    @track accountResultsVisible = false;
    @track selectedAccountId;

    @track userSearchTerm = "";
    @track userOptions = [];
    @track userResultsVisible = false;
    @track selectedUserId;

    // Fields
    @track newCaseStatus = "New";
    @track newCaseOrigin = "Web";
    @track newCasePriority = "Medium";
    @track newCaseReason = null;
    @track newCaseType = null;
    @track newCaseSubject = "";
    @track newCaseDescription = "";

    // ---- Your dynamic picklist wires unchanged ----
    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    caseInfo;

    @wire(getPicklistValues, {
        fieldApiName: STATUS_FIELD,
        recordTypeId: '$caseInfo.data.defaultRecordTypeId'
    })
    wiredStatus({ data }) { if (data) this.statusOptions = data.values; }

    @wire(getPicklistValues, {
        fieldApiName: ORIGIN_FIELD,
        recordTypeId: '$caseInfo.data.defaultRecordTypeId'
    })
    wiredOrigin({ data }) { if (data) this.originOptions = data.values;}

    @wire(getPicklistValues, {
        fieldApiName: PRIORITY_FIELD,
        recordTypeId: '$caseInfo.data.defaultRecordTypeId'
    })
    wiredPriority({ data }) { if (data) this.priorityOptions = data.values;}

    @wire(getPicklistValues, {
        fieldApiName: REASON_FIELD,
        recordTypeId: '$caseInfo.data.defaultRecordTypeId'
    })
    wiredReason({ data }) {
        if (data) this.reasonOptions = [{ label: '-- None --', value: null }, ...data.values];
    }

    @wire(getPicklistValues, {
        fieldApiName: TYPE_FIELD,
        recordTypeId: '$caseInfo.data.defaultRecordTypeId'
    })
    wiredType({ data }) {
        if (data) this.typeOptions = [{ label: '-- None --', value: null }, ...data.values];
    }

    // ======================
    // MODAL
    // ======================
    openNewCaseModal = () => {
        this.resetLookupFields();
        this.showNewCaseModal = true;
    };

    closeNewCaseModal = () => {
        this.showNewCaseModal = false;
    };

    resetLookupFields() {
        this.ownerSearchTerm = "You (Current User)";
        this.selectedOwnerId = USER_ID;
        this.ownerOptions = [];
        this.ownerResultsVisible = false;

        this.contactSearchTerm = "";
        this.contactOptions = [];
        this.contactResultsVisible = false;

        this.accountSearchTerm = "";
        this.accountOptions = [];
        this.accountResultsVisible = false;

        this.userSearchTerm = "";
        this.userOptions = [];
        this.userResultsVisible = false;

        this.selectedContactId = null;
        this.selectedAccountId = null;
        this.selectedUserId = null;
    }

    // Owner lookup
    handleOwnerSearchChange(event) {
        this.ownerSearchTerm = event.target.value;
        if (this.ownerSearchTerm.length < 2) {
            this.ownerResultsVisible = false;
            return;
        }
        searchUsers({ searchTerm: this.ownerSearchTerm })
            .then(results => {
                this.ownerOptions = results.map(u => ({ label: u.Name, value: u.Id }));
                this.ownerResultsVisible = this.ownerOptions.length > 0;
            });
    }

    handleOwnerSelect(event) {
        this.selectedOwnerId = event.currentTarget.dataset.id;
        this.ownerSearchTerm = event.currentTarget.dataset.name;
        this.ownerResultsVisible = false;
    }

    // Contact lookup
    handleContactSearchChange(event) {
        this.contactSearchTerm = event.target.value;
        if (this.contactSearchTerm.length < 2) {
            this.contactResultsVisible = false;
            return;
        }
        searchContacts({ searchTerm: this.contactSearchTerm })
            .then(results => {
                this.contactOptions = results.map(c => ({
                    label: c.Name,
                    value: c.Id
                }));
                this.contactResultsVisible = this.contactOptions.length > 0;
            });
    }

    handleContactSelect(event) {
        this.selectedContactId = event.currentTarget.dataset.id;
        this.contactSearchTerm = event.currentTarget.dataset.name;
        this.contactResultsVisible = false;
    }

    // Account lookup
    handleAccountSearchChange(event) {
        this.accountSearchTerm = event.target.value;
        if (this.accountSearchTerm.length < 2) {
            this.accountResultsVisible = false;
            return;
        }
        searchAccounts({ searchTerm: this.accountSearchTerm })
            .then(results => {
                this.accountOptions = results.map(a => ({
                    label: a.Name,
                    value: a.Id
                }));
                this.accountResultsVisible = this.accountOptions.length > 0;
            });
    }

    handleAccountSelect(event) {
        this.selectedAccountId = event.currentTarget.dataset.id;
        this.accountSearchTerm = event.currentTarget.dataset.name;
        this.accountResultsVisible = false;
    }

    // User lookup
    handleUserSearchChange(event) {
        this.userSearchTerm = event.target.value;
        if (this.userSearchTerm.length < 2) {
            this.userResultsVisible = false;
            return;
        }
        searchUsers({ searchTerm: this.userSearchTerm })
            .then(results => {
                this.userOptions = results.map(u => ({
                    label: u.Name,
                    value: u.Id
                }));
                this.userResultsVisible = this.userOptions.length > 0;
            });
    }

    handleUserSelect(event) {
        this.selectedUserId = event.currentTarget.dataset.id;
        this.userSearchTerm = event.currentTarget.dataset.name;
        this.userResultsVisible = false;
    }

    // Field handlers
    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;

        if (field === "Status") this.newCaseStatus = value;
        if (field === "Origin") this.newCaseOrigin = value;
        if (field === "Priority") this.newCasePriority = value;
        if (field === "Reason") this.newCaseReason = value;
        if (field === "Type") this.newCaseType = value;
    }

    handleSubjectChange(event) {
        this.newCaseSubject = event.target.value;
    }
    handleDescriptionChange(event) {
        this.newCaseDescription = event.target.value;
    }

    // Create Case
    handleCreateCase() {
        const record = {
            Subject: this.newCaseSubject,
            Description: this.newCaseDescription,
            Status: this.newCaseStatus,
            Origin: this.newCaseOrigin,
            Priority: this.newCasePriority,
            Reason: this.newCaseReason,
            Type: this.newCaseType,

            ContactId: this.selectedContactId,
            AccountId: this.selectedAccountId,
            OwnerId: this.selectedOwnerId
        };

        createCase({ caseRecord: record })
            .then(() => {
                this.showNewCaseModal = false;
                this.loadCases();

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: "Success",
                        message: "Case created successfully.",
                        variant: "success"
                    })
                );
            })
            .catch(err => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: "Error",
                        message: err.body.message,
                        variant: "error"
                    })
                );
            });
    }
}