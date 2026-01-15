import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';

import getCases from '@salesforce/apex/CaseListController.getCases';
import createCase from '@salesforce/apex/CaseListController.createCase';
import getCasePicklistValues from '@salesforce/apex/CaseListController.getCasePicklistValues';
import searchContacts from '@salesforce/apex/CaseListController.searchContacts';
import searchAccounts from '@salesforce/apex/CaseListController.searchAccounts';
import searchUsers from '@salesforce/apex/CaseListController.searchUsers';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PlatformCaseList extends NavigationMixin(LightningElement) {

    // ======================
    // PICKLISTS (APEX)
    // ======================
    @track statusOptions = [];
    @track originOptions = [];
    @track priorityOptions = [];
    @track reasonOptions = [];
    @track typeOptions = [];

    connectedCallback() {
        this.loadCases();
        this.loadPicklists();
    }

    loadPicklists() {
        getCasePicklistValues()
            .then(data => {
                this.statusOptions   = data.Status;
                this.originOptions   = data.Origin;
                this.priorityOptions = data.Priority;
                
                // Add none options for optional fields
                this.reasonOptions = [{ label: '-- None --', value: null }, ...data.Reason];
                this.typeOptions   = [{ label: '-- None --', value: null }, ...data.Type];
            })
            .catch(error => {
                console.error('Error fetching picklists', error);
            });
    }

    // ======================
    // TABLE STATE
    // ======================
    @track cases = [];
    @track error;
    @track isLoading = false;
    @track totalRecords = 0;
    @track totalPages = 0;
    
    // PAGINATION STATE
    pageSize = 50;
    pageNumber = 1;
    searchTerm = '';
    sortedBy = 'CreatedDate';
    sortedDirection = 'desc';

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

    // ======================
    // MODAL & FORM STATE
    // ======================
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

    // FIELDS
    @track newCaseStatus = "New";
    @track newCaseOrigin = "Web";
    @track newCasePriority = "Medium";
    @track newCaseReason = null;
    @track newCaseType = null;
    @track newCaseSubject = "";
    @track newCaseDescription = "";

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

    get offsetValue() {
        return (this.pageNumber - 1) * this.pageSize;
    }

    get isFirstPage() { return this.pageNumber === 1; }
    get isLastPage() { return this.pageNumber === this.totalPages; }

    // FILTERS
    @track currentFilter = 'MY_ASSIGNMENTS'; // 'MY_ASSIGNMENTS', 'DEPARTMENT', 'CREATED_BY_ME'
    @track isManager = false;

    // Filter Getters for UI state
    get isMyAssignments() { return this.currentFilter === 'MY_ASSIGNMENTS' ? 'brand' : 'neutral'; }
    get isDepartment() { return this.currentFilter === 'DEPARTMENT' ? 'brand' : 'neutral'; }
    get isCreatedByMe() { return this.currentFilter === 'CREATED_BY_ME' ? 'brand' : 'neutral'; }

    handleFilterChange(event) {
        const selected = event.target.dataset.filter;
        if (this.currentFilter !== selected) {
            this.currentFilter = selected;
            this.pageNumber = 1;
            this.loadCases();
        }
    }

    loadCases() {
        this.isLoading = true;

        getCases({
            pageSize: this.pageSize,
            offsetValue: this.offsetValue,
            sortField: this.sortedBy,
            sortDirection: this.sortedDirection,
            searchTerm: this.searchTerm,
            filterMode: this.currentFilter
        })
        .then(result => {
            this.cases = (result.records || []).map(c => {
                let rowCss = 'row-clickable ';
                switch(c.Status) {
                    case 'New': rowCss += 'row-new'; break;
                    case 'In Progress': rowCss += 'row-inprogress'; break;
                    case 'Closed': rowCss += 'row-closed'; break;
                    case 'Pending Review': rowCss += 'row-pending'; break;
                    default: rowCss += 'row-new';
                }

                // Priority Logic
                let pLoop = [];
                let pClass = 'priority-icon slds-m-right_xx-small ';
                
                if (c.Priority === 'High' || c.Priority === 'Critical') {
                    pLoop = [1, 2, 3];
                    pClass += 'priority-red';
                } else if (c.Priority === 'Medium') {
                    pLoop = [1, 2];
                    pClass += 'priority-orange';
                } else {
                    // Low or null
                    pLoop = [1];
                    pClass += 'priority-green';
                }
                
                return { 
                    ...c, 
                    rowClass: rowCss,
                    priorityLoop: pLoop,
                    priorityClass: pClass
                };
            });

            this.totalRecords = result.totalRecords;
            this.totalPages = Math.ceil(result.totalRecords / this.pageSize);
            this.isManager = result.isManager; // Update manager status
            this.isLoading = false;
        })
        .catch(err => {
            this.error = err.body ? err.body.message : err.message;
            this.isLoading = false;
        });
    }

    // ======================
    // CUSTOM TABLE HANDLERS
    // ======================
    handleRowClick(event) {
        const caseId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: "standard__navItemPage",
            attributes: { apiName: "Platform_Case_Detail" },
            state: { c__caseId: caseId }
        });
    }

    handleHeaderClick(event) {
        const field = event.currentTarget.dataset.field;
        
        // Toggle direction if same field, otherwise default to desc (or asc)
        if (this.sortedBy === field) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = field;
            this.sortedDirection = 'desc'; // Default new sorts to newest/highest
        }
        
        this.pageNumber = 1;
        this.loadCases();
    }
    
    // Icons for sort arrows (computed)
    get isSortCaseNumber() { return this.sortedBy === 'CaseNumber'; }
    get isSortSubject() { return this.sortedBy === 'Subject'; }
    get isSortStatus() { return this.sortedBy === 'Status'; }
    get isSortPriority() { return this.sortedBy === 'Priority'; }
    get isSortDate() { return this.sortedBy === 'CreatedDate'; }
    
    get sortIconName() {
        return this.sortedDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }
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
            OwnerId: this.selectedOwnerId,
            Assigned_User__c: this.selectedUserId
        };

        createCase({ caseRecord: record })
            .then((resultId) => {
                this.showNewCaseModal = false;
                
                // ASYNC PROXY HANDLING
                if (resultId) {
                    // Standard User (Success)
                     this.dispatchEvent(
                        new ShowToastEvent({
                            title: "Success",
                            message: "Case created successfully.",
                            variant: "success"
                        })
                    );
                    // Open the case? (Optional, maybe just reload)
                } else {
                    // Platform User (Event Published)
                     this.dispatchEvent(
                        new ShowToastEvent({
                            title: "Request Submitted",
                            message: "Ticket request sent. It may take a moment to appear in the list.",
                            variant: "info"
                        })
                    );
                }

                this.loadCases();
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