import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

// APEX
import getCaseDetails from '@salesforce/apex/CaseDetailController.getCaseDetails';
import updateCaseRecord from '@salesforce/apex/CaseDetailController.updateCaseRecord';
import getEmailMessages from '@salesforce/apex/CaseDetailController.getEmailMessages';
import getCaseTimeline from '@salesforce/apex/CaseDetailController.getCaseTimeline';
import addCaseComment from '@salesforce/apex/CaseDetailController.addCaseComment';
import sendCaseEmail from '@salesforce/apex/CaseDetailController.sendCaseEmail';
import getOrgWideEmails from '@salesforce/apex/CaseDetailController.getOrgWideEmails';
import getCasePicklists from '@salesforce/apex/CaseDetailController.getCasePicklists';
import getAssignableUsers from '@salesforce/apex/CaseDetailController.getAssignableUsers';

export default class PlatformCaseDetail extends NavigationMixin(LightningElement) {

    // CASE DATA
    @track caseRecord;
    @track isLoading = true;
    @track isSaving = false;
    caseId;
    currentUserId = USER_ID;

    // WORKFLOW STATE
    @track selectedAssignee = '';
    @track requiresReview = false;

    // PICKLISTS
    @track statusOptions = [];
    @track priorityOptions = [];
    @track typeOptions = [];
    @track reasonOptions = [];

    // OWNER
    @track ownerOptions = [];
    @track ownerSearchTerm = '';
    @track ownerSearchResults = [];
    @track showOwnerDropdown = false;

    // EMAIL HISTORY
    @track emailEntries = [];
    @track isLoadingEmails = false;

    // CASE HISTORY
    @track caseHistoryEntries = [];
    @track isLoadingCaseHistory = false;

    // ORG-WIDE EMAILS
    @track fromAddressOptions = [];
    @track selectedFromAddress = null;
    orgWideEmailAddresses = [];

    // EMAIL COMPOSER - TO / CC / BCC
    @track emailToList = [];
    @track emailToInput = '';

    @track emailCCList = [];
    @track emailCCInput = '';

    @track emailBCCList = [];
    @track emailBCCInput = '';

    @track emailSubject = '';
    @track emailBody = '';

    // CC/BCC toggle
    @track showCcBcc = false;

    // COMMENTS
    @track newComment = '';
    @track isAddingComment = false;

    // ======== GETTERS ========
    get isSendDisabled() {
        const hasTo =
            (this.emailToList && this.emailToList.length > 0) ||
            (this.emailToInput && this.emailToInput.trim());
        return !hasTo || !this.emailSubject || !this.emailBody;
    }

    get isAddCommentDisabled() {
        return this.isAddingComment || !this.newComment?.trim();
    }

    get accountName() {
        return this.caseRecord?.AccountName || '';
    }

    get contactName() {
        return this.caseRecord?.ContactName || '';
    }

    get assignedUserName() {
        return this.caseRecord?.AssignedUserName || '(Unassigned)';
    }

    get ccBccButtonLabel() {
        return this.showCcBcc ? 'Hide CC / BCC' : 'Show CC / BCC';
    }

    // ======== WORKFLOW GETTERS ========
    get isQueueOwned() {
        return this.caseRecord?.OwnerId?.startsWith('00G');
    }

    get isInProgress() {
        if (!this.caseRecord) return false;
        
        // "In Progress" actions (Submit) are available if:
        // 1. The case is Open (not Closed, Submitted, or Pending Review)
        // 2. AND You are the Assigned User (Assigned_User__c)
        // OR 3. You are the actual Owner (fallback for standard cases)
        
        const isOpen = !['Submitted', 'Closed', 'Pending Review'].includes(this.caseRecord.Status);
        
        const isAssignedToMe = this.caseRecord.AssignedUserId === this.currentUserId;
        const isOwnerCurrentUser = this.caseRecord.OwnerId === this.currentUserId;
        
        return isOpen && (isAssignedToMe || isOwnerCurrentUser);
    }

    get managerName() {
        return this.caseRecord?.ManagerName || '(None)';
    }

    get employeeName() {
        return this.caseRecord?.EmployeeName || '(None)';
    }
 
    get isManager() {
        if (!this.caseRecord) return false;
        const myQueues = this.caseRecord.CurrentUserQueues || [];
        return myQueues.includes(this.caseRecord.Type);
    }
 
    get isReviewing() {
        if (!this.caseRecord) return false;
        const isPending = this.caseRecord.Status === 'Pending Review';
        
        // You can review if:
        // 1. You are specifically assigned (Assigned_User__c)
        // 2. You are the tracked Manager (Manager__c)
        // 3. You are a member of the Department Queue for this Case Type
        
        const isAssignedToMe = (this.caseRecord.AssignedUserId === this.currentUserId) || 
                               (this.caseRecord.ManagerId === this.currentUserId);
                               
        return isPending && (isAssignedToMe || this.isManager); // Reusing isManager logic
    }

    get showAssignmentPanel() {
        // 1. Must be a Manager to see this panel
        // 2. Must NOT be assigned yet (once assigned, panel disappears)
        return this.isManager && !this.caseRecord?.AssignedUserId;
    }

    get userOptions() {
        return this.ownerOptions || []; // Reuse existing options loaded from Apex
    }

    // ======== WORKFLOW ACTIONS ========
    handleAssigneeChange(e) {
        this.selectedAssignee = e.detail.value;
    }

    handleReviewChange(e) {
        this.requiresReview = e.target.checked;
    }

    handleAssign() {
        if (!this.selectedAssignee) {
             this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select a user to assign.',
                variant: 'error'
            }));
            return;
        }

        this.isSaving = true;
        const updates = { 
            Id: this.caseRecord.Id,
            OwnerId: this.caseRecord.OwnerId, // Keep Queue as Owner (per user request)
            Assigned_User__c: this.selectedAssignee, // The Employee visible on list
            Manager__c: this.currentUserId, // I am the Manager assigning this
            Employee__c: this.selectedAssignee, // Track who the worker is
            Requires_Manager_Review__c: this.requiresReview,
            Status: 'In Progress' 
        };

        this.performUpdate(updates, 'Case Assigned Successfully');
    }

    handleSubmit() {
        this.isSaving = true;

        const needsReview = this.caseRecord.RequiresManagerReview;

        let ud = {
            Id: this.caseRecord.Id,
            Assigned_User__c: this.caseRecord.ManagerId // Default: Return to Manager
        };

        if (needsReview) {
            ud.Status = 'Pending Review';
        } else {
            ud.Status = 'Closed';
        }

        this.performUpdate(ud, needsReview ? 'Case Submitted for Review' : 'Case Closed');
    }

    handleApprove() {
        this.isSaving = true;
        const updates = {
            Id: this.caseRecord.Id,
            Status: 'Closed'
        };
        this.performUpdate(updates, 'Case Approved and Closed');
    }

    handleReject() {
        this.isSaving = true;
        // Assign back to Employee
        const updates = {
            Id: this.caseRecord.Id,
            Status: 'In Progress',
            Assigned_User__c: this.caseRecord.EmployeeId // Return to Worker
        };
        this.performUpdate(updates, 'Case Returned to Employee');
    }

    performUpdate(fields, successMessage) {
        // Optimistic Update: Update UI immediately
        this.caseRecord = { ...this.caseRecord, ...fields };

        this.isSaving = true;

        updateCaseRecord({ updatedCase: fields })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                }));
                // Reload full case to ensure server-side calculated fields (formulas, names) are fresh
                this.loadCase();
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Update failed.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    // ======== PAGE REF / INIT ========
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef?.state?.c__caseId) {
            this.caseId = pageRef.state.c__caseId;
            this.loadCase();
            this.loadOrgWideEmails();
        }
    }

    // ======== ORG-WIDE EMAILS ========
    loadOrgWideEmails() {
        getOrgWideEmails().then(list => {
            this.fromAddressOptions = list.map(i => ({
                label: `${i.DisplayName} (${i.Address})`,
                value: i.Id
            }));

            this.orgWideEmailAddresses = list.map(
                i => (i.Address || '').toLowerCase()
            );

            if (this.fromAddressOptions.length > 0) {
                this.selectedFromAddress = this.fromAddressOptions[0].value;
            }
        });
    }

    // ======== LOAD CASE / PICKLISTS / OWNERS ========
    loadCase() {
        this.isLoading = true;

        getCaseDetails({ caseId: this.caseId })
            .then(result => {
                this.caseRecord = { ...result };
                return getCasePicklists({ recordTypeId: this.caseRecord.RecordTypeId });
            })
            .then(pick => {
                this.statusOptions = pick.Status.map(v => ({ label: v, value: v }));
                this.priorityOptions = pick.Priority.map(v => ({ label: v, value: v }));
                this.typeOptions = pick.Type.map(v => ({ label: v, value: v }));
                this.reasonOptions = pick.Reason.map(v => ({ label: v, value: v }));
            })
            .then(() => getAssignableUsers())
            .then(users => {
                this.ownerOptions = users.map(u => ({
                    label: u.Name,
                    value: u.Id
                }));

                // Prefill owner search term
                if (this.caseRecord?.OwnerId) {
                    const current = this.ownerOptions.find(
                        o => o.value === this.caseRecord.OwnerId
                    );
                    this.ownerSearchTerm =
                        current?.label || this.caseRecord?.OwnerName || '';
                }
            })
            .then(() => {
                this.loadEmailHistory();
                this.loadCaseHistory();
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ======== EMAIL HISTORY + PREFILL ========
    loadEmailHistory() {
        this.isLoadingEmails = true;

        getEmailMessages({ caseId: this.caseId })
            .then(result => {
                const raw = result || [];

                this.emailEntries = raw.map(m => {
                    const inbound = !this.orgWideEmailAddresses.includes(
                        (m.FromAddress || '').toLowerCase()
                    );
                    return {
                        ...m,
                        directionLabel: inbound ? 'Incoming' : 'Outgoing',
                        bubbleClass: inbound ? 'email-bubble inbound' : 'email-bubble outbound'
                    };
                });

                // Prefill TO / CC / BCC / Subject using latest email
                this.emailToList = [];
                this.emailToInput = '';
                this.emailCCList = [];
                this.emailBCCList = [];

                if (this.emailEntries.length > 0) {
                    let inboundMsg = this.emailEntries.find(
                        m => m.directionLabel === 'Incoming'
                    );
                    let ref = inboundMsg || this.emailEntries[0];

                    // TO list
                    const toAddrs = inboundMsg
                        ? this.splitAddresses(inboundMsg.FromAddress)
                        : this.splitAddresses(
                              ref.ToAddress || ref.FromAddress || ''
                          );

                    this.emailToList = toAddrs;
                    this.emailToInput = '';

                    // CC/BCC
                    this.emailCCList = this.splitAddresses(ref.CcAddress);
                    this.emailBCCList = this.splitAddresses(ref.BccAddress);

                    // Show CC/BCC if they actually have values
                    this.showCcBcc =
                        (this.emailCCList && this.emailCCList.length > 0) ||
                        (this.emailBCCList && this.emailBCCList.length > 0);

                    // Subject
                    if (ref.Subject) {
                        this.emailSubject = `Re: ${ref.Subject}`;
                    }
                }
            })
            .finally(() => {
                this.isLoadingEmails = false;
            });
    }

    splitAddresses(str) {
        if (!str) return [];
        return str
            .split(/[;, \n\r\t]+/)
            .map(s => s.trim())
            .filter(Boolean);
    }

    // ======== CASE HISTORY ========
    loadCaseHistory() {
        this.isLoadingCaseHistory = true;

        getCaseTimeline({ caseId: this.caseId })
            .then(res => {
                this.caseHistoryEntries = res || [];
            })
            .finally(() => {
                this.isLoadingCaseHistory = false;
            });
    }

    // ======== CASE FIELD SAVE ========
    handleChange(event) {
        const field = event.target.dataset.field;
        this.caseRecord = { ...this.caseRecord, [field]: event.target.value };
    }

    saveCase() {
        this.isSaving = true;

        updateCaseRecord({ updatedCase: this.caseRecord })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Case Saved',
                        message: 'Your changes were saved successfully.',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Save Failed',
                        message: error.body?.message || 'Unable to save.',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    // ======== COMMENTS ========
    handleCommentChange(e) {
        this.newComment = e.target.value;
    }

    handleAddComment() {
        this.isAddingComment = true;

        addCaseComment({
            caseId: this.caseId,
            commentBody: this.newComment
        })
            .then(() => {
                this.newComment = '';
                this.loadCaseHistory();
            })
            .finally(() => {
                this.isAddingComment = false;
            });
    }

    // ======== TO / CC / BCC UTILS ========
    isCommitKey(key) {
        return ['Enter', 'Tab', ',', ';'].includes(key);
    }

    // --- TO ---
    handleToInputChange(e) {
        this.emailToInput = e.target.value;
    }

    commitToChip() {
        const input = (this.emailToInput || '').trim();
        if (!input) return;

        this.splitAddresses(input).forEach(addr => {
            if (addr && !this.emailToList.includes(addr)) {
                this.emailToList = [...this.emailToList, addr];
            }
        });

        this.emailToInput = '';
    }

    handleToKeydown(e) {
        if (this.isCommitKey(e.key)) {
            e.preventDefault();
            this.commitToChip();
        } else if (e.key === 'Backspace' && !this.emailToInput) {
            // Gmail-style: pull last pill back into the input
            if (this.emailToList.length > 0) {
                const last = this.emailToList[this.emailToList.length - 1];
                this.emailToList = this.emailToList.slice(0, -1);
                this.emailToInput = last;
            }
        }
    }

    removeTo(e) {
        const addr = e.detail.name;
        this.emailToList = this.emailToList.filter(a => a !== addr);
    }

    // --- CC/BCC shared helper ---
    commitChip(which) {
        let input, list;
        if (which === 'cc') {
            input = (this.emailCCInput || '').trim();
            list = [...this.emailCCList];
        } else {
            input = (this.emailBCCInput || '').trim();
            list = [...this.emailBCCList];
        }

        if (!input) return;

        this.splitAddresses(input).forEach(addr => {
            if (addr && !list.includes(addr)) {
                list.push(addr);
            }
        });

        if (which === 'cc') {
            this.emailCCList = list;
            this.emailCCInput = '';
        } else {
            this.emailBCCList = list;
            this.emailBCCInput = '';
        }
    }

    // --- CC ---
    handleCCInputChange(e) {
        this.emailCCInput = e.target.value;
    }

    handleCCKeydown(e) {
        if (this.isCommitKey(e.key)) {
            e.preventDefault();
            this.commitChip('cc');
        } else if (e.key === 'Backspace' && !this.emailCCInput) {
            if (this.emailCCList.length > 0) {
                const last = this.emailCCList[this.emailCCList.length - 1];
                this.emailCCList = this.emailCCList.slice(0, -1);
                this.emailCCInput = last;
            }
        }
    }

    removeCC(e) {
        const addr = e.detail.name;
        this.emailCCList = this.emailCCList.filter(a => a !== addr);
    }

    // --- BCC ---
    handleBCCInputChange(e) {
        this.emailBCCInput = e.target.value;
    }

    handleBCCKeydown(e) {
        if (this.isCommitKey(e.key)) {
            e.preventDefault();
            this.commitChip('bcc');
        } else if (e.key === 'Backspace' && !this.emailBCCInput) {
            if (this.emailBCCList.length > 0) {
                const last = this.emailBCCList[this.emailBCCList.length - 1];
                this.emailBCCList = this.emailBCCList.slice(0, -1);
                this.emailBCCInput = last;
            }
        }
    }

    removeBCC(e) {
        const addr = e.detail.name;
        this.emailBCCList = this.emailBCCList.filter(a => a !== addr);
    }

    // ======== SEND EMAIL ========
    handleFromAddressChange(event) {
        this.selectedFromAddress = event.detail?.value || event.target.value;
    }

    handleEmailSubjectChange(e) {
        this.emailSubject = e.target.value;
    }

    handleEmailBodyChange(e) {
        this.emailBody = e.target.value;
    }

    toggleCcBcc() {
        this.showCcBcc = !this.showCcBcc;
    }

    handleSendEmail() {
        // finalize chips
        this.commitToChip();
        this.commitChip('cc');
        this.commitChip('bcc');

        // "Current behavior": treat To as a single logical address
        const toAddress =
            (this.emailToList && this.emailToList[0]) ||
            (this.emailToInput && this.emailToInput.trim());

        if (!toAddress) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Recipient',
                    message: 'Please add at least one recipient in the To field.',
                    variant: 'error'
                })
            );
            return;
        }

        sendCaseEmail({
            caseId: this.caseId,
            orgWideEmailId: this.selectedFromAddress,
            toAddress: toAddress,
            ccAddress: this.emailCCList.join(';'),
            bccAddress: this.emailBCCList.join(';'),
            subject: this.emailSubject,
            body: this.emailBody
        })
            .then(() => {
                this.emailBody = '';
                this.loadEmailHistory();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Email Failed',
                        message: error.body?.message || 'Unable to send email.',
                        variant: 'error'
                    })
                );
            });
    }

    // ======== BACK NAV ========
    goBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Platform_Case_Dashboard' }
        });
    }

    // ======== OWNER LOOKUP ========
    handleOwnerTyping(event) {
        const term = event.target.value || '';
        this.ownerSearchTerm = term;

        if (!term) {
            this.ownerSearchResults = [];
            this.showOwnerDropdown = false;
            return;
        }

        const lower = term.toLowerCase();
        this.ownerSearchResults = this.ownerOptions
            .filter(o => o.label.toLowerCase().includes(lower))
            .slice(0, 20);

        this.showOwnerDropdown = this.ownerSearchResults.length > 0;
    }

    handleOwnerSelect(event) {
        const id = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;

        this.caseRecord = {
            ...this.caseRecord,
            OwnerId: id
        };

        this.ownerSearchTerm = label;
        this.showOwnerDropdown = false;
    }
}