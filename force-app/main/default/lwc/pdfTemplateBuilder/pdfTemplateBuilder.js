import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getAllSObjectOptions from '@salesforce/apex/PdfTemplateBrowserController.getAllSObjectOptions';
import saveTemplateWithFile from '@salesforce/apex/PdfTemplateBrowserController.saveTemplateWithFile';

export default class PdfTemplateBuilder extends NavigationMixin(LightningElement) {
    @track name = '';
    
    // SEARCHABLE DROPDOWN STATE
    @track sourceObject = ''; // The selected API Name
    @track selectedObjectLabel = ''; // For display in input
    @track searchKey = '';
    @track isDropdownOpen = false;
    
    @track filteredOptions = [];
    allObjectOptions = [];
    
    fileData; 
    isLoading = false;

    @wire(getAllSObjectOptions)
    wiredOptions({ error, data }) {
        if (data) {
            this.allObjectOptions = data;
            this.filteredOptions = data;
        } else if (error) {
            this.showToast('Error', 'Failed to load objects.', 'error');
        }
    }

    handleNameChange(e) { this.name = e.target.value; }
    
    // Search Handler
    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.selectedObjectLabel = this.searchKey; // Allow typing
        this.isDropdownOpen = true;

        if (!this.searchKey) {
            this.filteredOptions = this.allObjectOptions;
        } else {
            const lower = this.searchKey.toLowerCase();
            this.filteredOptions = this.allObjectOptions.filter(opt => 
                opt.label.toLowerCase().includes(lower) || 
                opt.value.toLowerCase().includes(lower)
            );
        }
    }

    // Selection Handler
    handleOptionSelect(event) {
        const val = event.currentTarget.dataset.value;
        const lbl = event.currentTarget.dataset.label;
        
        this.sourceObject = val;
        this.selectedObjectLabel = lbl;
        this.searchKey = lbl;
        this.isDropdownOpen = false;
    }

    // Input Focus
    handleSearchFocus() {
        this.isDropdownOpen = true;
        // Reset filter if empty?
        if (!this.searchKey) this.filteredOptions = this.allObjectOptions;
    }
    
    // Close dropdown on blur (delayed to allow click)
    handleSearchBlur() {
        // Simple delay to allow click event to register
        setTimeout(() => { 
            this.isDropdownOpen = false; 
            // If invalid selection, maybe clear? Optional.
        }, 200);
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                this.fileData = {
                    fileName: file.name,
                    base64: base64
                };
            };
            reader.readAsDataURL(file);
        }
    }

    get isSaveDisabled() {
        return !this.name || !this.sourceObject || !this.fileData || this.isLoading;
    }

    async handleSave() {
        this.isLoading = true;
        try {
            const newId = await saveTemplateWithFile({
                name: this.name,
                sourceObject: this.sourceObject,
                fileName: this.fileData.fileName,
                base64Data: this.fileData.base64
            });

            this.showToast('Success', 'Template created!', 'success');
            
            // Navigate to the Record Page (standard)
            // If pdfMappingEditorV2 is supposed to be on this page, it will load there.
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: newId,
                    objectApiName: 'PDF_Template__c', // Adjust if needed
                    actionName: 'view'
                }
            });

            // Reset
            this.name = '';
            this.sourceObject = '';
            this.fileData = null;

        } catch (e) {
            console.error(e);
            this.showToast('Error', 'Creation failed: ' + (e.body?.message || e.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}