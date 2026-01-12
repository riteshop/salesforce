import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

// RESOURCES
import PDFJS from '@salesforce/resourceUrl/pdfjsLib';
import { loadScript } from 'lightning/platformResourceLoader';

// APEX IMPORTS
import listTemplates from '@salesforce/apex/PdfTemplateBrowserController.listTemplates';
import getLatestTemplatePdfBase64 from '@salesforce/apex/PdfTemplateFileController.getLatestTemplatePdfBase64';
import getMappings from '@salesforce/apex/PdfMappingController.getMappings';
import getObjectFieldOptions from '@salesforce/apex/PdfMappingController.getObjectFieldOptions';

import getObjectLabel from '@salesforce/apex/PdfFormFillController.getObjectLabel';
import getSearchColumns from '@salesforce/apex/PdfFormFillController.getSearchColumns'; 
import searchRecordsDynamic from '@salesforce/apex/PdfFormFillController.searchRecordsDynamic';
import getRecentRecordsDynamic from '@salesforce/apex/PdfFormFillController.getRecentRecordsDynamic';
import fillTemplate from '@salesforce/apex/PdfFormFillController.fillTemplate';

const MAPPING_COLS = [
    { label: 'PDF Field', fieldName: 'pdfLabel', type: 'text', wrapText: true, sortable: true, hideDefaultActions: true },
    { label: 'Mapped To', fieldName: 'displayLabel', type: 'text', wrapText: true, sortable: true, hideDefaultActions: true }
];

const TEMPLATE_COLS = [
    { 
        label: 'Template Name', 
        fieldName: 'name', 
        type: 'button', 
        typeAttributes: { 
            label: { fieldName: 'name' }, 
            name: 'select', 
            variant: 'base',
            title: 'Click to select'
        },
        sortable: true,
        cellAttributes: { alignment: 'left' }
    },
    { label: 'Source Object', fieldName: 'sourceObjectApiName', type: 'text', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Created By', fieldName: 'createdByName', type: 'text', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Created Date', fieldName: 'createdDate', type: 'date', 
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute:'2-digit' }, sortable: true, cellAttributes: { alignment: 'left' } }
];

export default class PdfFillWizard extends LightningElement {
  @track step = 'templates'; 
  @track templates = [];
  allTemplates = [];
  @track templateColumns = TEMPLATE_COLS;
  @track isLoadingTemplates = true;
  
  @track sortedBy;
  @track sortDirection;

  selectedTemplateId;
  selectedTemplateName;
  @track templateInitializing = false;
  
  @track objectApiName = ''; 
  @track objectLabel = ''; 

  // PREVIEW STATE
  pdfInitialized = false;
  previewLoading = false;
  previewError = '';
  pdfDocument = null; 
  @track isModalOpen = false;

  // COLUMN SELECTOR STATE
  @track isColumnModalOpen = false;
  @track allAvailableColumnOptions = []; 
  @track activeColumnValues = [];       
  _pendingColumnSelection = [];

  // MAPPING STATE
  @track mappingData = [];
  @track mappingColumns = MAPPING_COLS;
  
  // SEARCH / DATATABLE STATE
  @track recordSearch = '';
  @track searchResults = [];
  @track searchColumns = [];
  @track selectedRecordIds = []; 
  @track tableTitle = 'Recent Records';
  
  targetFieldsApiNames = []; 
  _searchTimer;
  filling = false;

  // METADATA CACHE (replaced objectMetadata)
  _fieldOptionsMap = new Map();

  get isStepTemplates() { return this.step === 'templates'; }
  get isStepRecords() { return this.step === 'records'; }
  get hasMappings() { return (this.mappingData || []).length > 0; }
  get fillDisabled() { return this.filling || !this.selectedRecordIds.length; }

  get searchLabel() {
      const name = this.objectLabel || this.objectApiName;
      return name ? `Search ${name} Records` : 'Search Records';
  }
  get activeMappingsLabel() {
      const name = this.objectLabel || this.objectApiName;
      return name ? `${name} Mappings` : 'Mappings';
  }

  async renderedCallback() {
    if (!this._loadedTemplates) {
      this._loadedTemplates = true;
      await this.loadTemplates();
    }
    if (!this.pdfInitialized) {
      this.pdfInitialized = true;
      try {
        await loadScript(this, PDFJS + '/pdfjs/pdf.js');
        // eslint-disable-next-line no-undef
        pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdfjs/pdf.worker.js';
      } catch (e) {
        this.toast('Warning', 'PDF preview failed (pdf.js).', 'warning');
      }
    }
  }

  async loadTemplates() {
    try {
      const rows = await listTemplates();
      this.allTemplates = rows || [];
      this.templates = this.allTemplates;
    } catch (e) {
      this.toast('Error', 'Failed to load templates', 'error');
    } finally {
      this.isLoadingTemplates = false;
    }
  }

  handleTemplateSearch(event) {
      const term = event.target.value ? event.target.value.toLowerCase() : '';
      if (!term) {
          this.templates = this.allTemplates;
          return;
      }
      this.templates = this.allTemplates.filter(row => {
          return row.name && row.name.toLowerCase().includes(term);
      });
  }

  async handleTemplateRowAction(event) {
    const action = event.detail.action;
    const row = event.detail.row;

    if (action.name !== 'select') return;

    this.templateInitializing = true;
    const id = row.id;
    // const row is already here
    this.selectedTemplateId = id;
    this.selectedTemplateName = row?.name || 'Template';
    this.step = 'records';

    this.recordSearch = '';
    this.searchResults = [];
    this.selectedRecordIds = [];
    this.mappingData = [];
    this.objectApiName = null; 
    this.targetFieldsApiNames = []; // reset
    this._fieldOptionsMap.clear();

    try {
        // Parallel Fetch 1: Basic Template Config & Visuals
        const [objMeta, searchCols] = await Promise.all([
            getObjectLabel({ templateId: id }),
            getSearchColumns({ templateId: id }),
            this.loadThumbnail(id)       
        ]);

        this.objectApiName = objMeta.apiName;
        this.objectLabel = objMeta.label;
        this.targetFieldsApiNames = searchCols || [];
        
        // Load Metadata via Apex (Reliable)
        await this.prepareColumnOptions();

        // Now load mappings (requires metadata for labels)
        await this.loadMappingSummary(id);

        this.activeColumnValues = [...this.targetFieldsApiNames];

        this.generateDatatableColumns();

        await this.runRecordSearch();

    } catch (e) {
        console.error(e);
        const msg = e.body?.message || e.message || 'Unknown error';
        this.toast('Error', 'Template Init Failed: ' + msg, 'error');
    } finally {
        this.templateInitializing = false;
    }
  }

  handleTemplateSort(event) {
      const { fieldName: sortedBy, sortDirection } = event.detail;
      const cloneData = [...this.templates];

      cloneData.sort(this.sortBy(sortedBy, sortDirection === 'asc' ? 1 : -1));
      
      this.templates = cloneData;
      this.sortedBy = sortedBy;
      this.sortDirection = sortDirection;
  }

  @track recordSortedBy;
  @track recordSortDirection;

  handleRecordSort(event) {
      const { fieldName: sortedBy, sortDirection } = event.detail;
      const cloneData = [...this.searchResults];

      cloneData.sort(this.sortBy(sortedBy, sortDirection === 'asc' ? 1 : -1));
      
      this.searchResults = cloneData;
      this.recordSortedBy = sortedBy;
      this.recordSortDirection = sortDirection;
  }

  @track mappingSortedBy;
  @track mappingSortDirection;

  handleMappingSort(event) {
      const { fieldName: sortedBy, sortDirection } = event.detail;
      const cloneData = [...this.mappingData];

      cloneData.sort(this.sortBy(sortedBy, sortDirection === 'asc' ? 1 : -1));
      
      this.mappingData = cloneData;
      this.mappingSortedBy = sortedBy;
      this.mappingSortDirection = sortDirection;
  }

  sortBy(field, reverse, primer) {
      const key = primer
          ? function(x) { return primer(x[field]); }
          : function(x) { return x[field]; };

      return function(a, b) {
          let valueA = key(a) ? key(a) : '';
          let valueB = key(b) ? key(b) : '';
          // Handle string case insensitivity
          if (typeof valueA === 'string') valueA = valueA.toLowerCase();
          if (typeof valueB === 'string') valueB = valueB.toLowerCase();

          return reverse * ((valueA > valueB) - (valueB > valueA));
      };
  }

  async prepareColumnOptions() {
    try {
        const apexOptions = await getObjectFieldOptions({ objectApiName: this.objectApiName });
        const allOptionsMap = new Map();

        // 1. From Apex Options
        (apexOptions || []).forEach(opt => {
            // opt structure: { label, value, type, relationshipName, referenceTo... }
            const key = opt.value.toLowerCase();
            allOptionsMap.set(key, opt);
        });
        
        // Store for other methods to use (replaces objectMetadata)
        this._fieldOptionsMap = allOptionsMap;

        // 2. Ensure targeted defaults are present (even if not in Apex result)
        this.targetFieldsApiNames.forEach(apiName => {
            const apiLower = apiName.toLowerCase();
            if (!allOptionsMap.has(apiLower)) {
                allOptionsMap.set(apiLower, { label: apiName, value: apiName, type: 'STRING' });
            }
        });

        this.allAvailableColumnOptions = Array.from(allOptionsMap.values()).sort((a, b) => 
            (a.label || '').localeCompare(b.label || '')
        );

        // Normalize active selection
        if (this.activeColumnValues && this.activeColumnValues.length > 0) {
            this.activeColumnValues = this.activeColumnValues.map(val => {
                const match = allOptionsMap.get(val.toLowerCase());
                return match ? match.value : val;
            });
        }
    } catch (e) {
        console.error('Failed to load field options', e);
    }
  }

  openColumnModal() { 
      this._pendingColumnSelection = [...this.activeColumnValues];
      this.isColumnModalOpen = true; 
  }
  
  closeColumnModal() { this.isColumnModalOpen = false; }
  
  handleColumnChange(event) {
      this._pendingColumnSelection = event.detail.value;
  }
  
  async saveColumnSelection() {
      this.activeColumnValues = [...this._pendingColumnSelection];
      this.generateDatatableColumns();
      this.isColumnModalOpen = false;
      // Fetch new data so lookup columns aren't blank
      await this.runRecordSearch(); 
  }

  generateDatatableColumns() {
      const fieldsToShow = this.activeColumnValues;
      if (!fieldsToShow || fieldsToShow.length === 0) {
          this.searchColumns = [];
          return;
      }
      
      const cols = [];

      fieldsToShow.forEach(rawApiName => {
          const lowerKey = rawApiName.toLowerCase();
          const fieldDef = this._fieldOptionsMap.get(lowerKey);
          
          let colFieldName = rawApiName;
          let colLabel = rawApiName; 

          if (fieldDef) {
              colLabel = fieldDef.label;
              if (fieldDef.type === 'REFERENCE' || fieldDef.type === 'Reference') {
                  colFieldName = fieldDef.value + '_Name';
              } else {
                  colFieldName = fieldDef.value;
              }
          } 
          
          // Always flatten dots to underscores for the valid key
          if (colFieldName.includes('.')) {
              colFieldName = colFieldName.split('.').join('_');
          }

          cols.push({ 
              label: colLabel, 
              fieldName: colFieldName, 
              type: 'text',
              sortable: true,
              hideDefaultActions: true
          });
      });
      
      console.log('Generated Columns:', JSON.parse(JSON.stringify(cols)));
      this.searchColumns = cols;
  }

  async runRecordSearch() {
    const searchKey = (this.recordSearch || '').trim();
    this._ignoreSelection = true;
    const savedSelection = [...this.selectedRecordIds];

    try {
        const fieldsToQuery = this.activeColumnValues.length ? this.activeColumnValues : ['Name'];

        let results = searchKey.length < 2 
            ? await getRecentRecordsDynamic({ objectApiName: this.objectApiName, fieldsToQuery })
            : await searchRecordsDynamic({ objectApiName: this.objectApiName, searchKey, fieldsToQuery });
        
        this.searchResults = (results || []).map(row => {
            let flatRow = { ...row }; 
            
            fieldsToQuery.forEach(rawApiName => {
                const lowerKey = rawApiName.toLowerCase();
                const fieldDef = this._fieldOptionsMap.get(lowerKey);

                // Handle Lookup Names
                if (fieldDef && (fieldDef.type === 'REFERENCE' || fieldDef.type === 'Reference')) {
                    const relName = fieldDef.relationshipName; 
                    if (relName && row[relName]) {
                        const key = fieldDef.value + '_Name';
                        flatRow[key] = row[relName].Name;
                    }
                }
                
                // Always flatten dots for consistency with column definition
                if (rawApiName.includes('.')) {
                    flatRow[rawApiName.split('.').join('_')] = this.resolveValue(row, rawApiName);
                }
            });
            return flatRow;
        });
        
        setTimeout(() => {
            this.selectedRecordIds = savedSelection;
            setTimeout(() => { this._ignoreSelection = false; }, 100);
        }, 100);

    } catch (e) {
        console.error('DEBUG WIZARD Search Error', e);
        this.toast('Error', 'Search failed', 'error');
        this._ignoreSelection = false;
    }
  }

  resolveValue(obj, path) {
    if (!obj || !path) return '';
    const parts = path.split('.');
    let current = obj;
    for (const part of parts) {
        if (current === null || current === undefined) return '';
        const key = Object.keys(current).find(k => k.toLowerCase() === part.toLowerCase());
        if (key) {
            current = current[key];
        } else {
            return '';
        }
    }
    return current;
  }

  handleRecordSearchChange(event) {
    this.recordSearch = event.target.value || '';
    if (this._searchTimer) clearTimeout(this._searchTimer);
    this._searchTimer = setTimeout(() => void this.runRecordSearch(), 300);
  }

  handleRowSelection(event) {
    if (this._ignoreSelection) return;
    const currentViewIds = new Set(event.detail.selectedRows.map(row => row.Id));
    const visibleIds = new Set(this.searchResults.map(row => row.Id));
    let updatedSelection = this.selectedRecordIds.filter(id => !visibleIds.has(id) || currentViewIds.has(id));
    event.detail.selectedRows.forEach(row => { if (!updatedSelection.includes(row.Id)) updatedSelection.push(row.Id); });
    this.selectedRecordIds = updatedSelection;
 }

  async loadMappingSummary(templateId) {
    try {
        const mappings = await getMappings({ templateId });
        this.mappingData = (mappings || []).filter(m => m.active && (m.fieldPath || m.constantValue)).map(m => ({
            id: m.id,
            pdfLabel: m.displayLabel || m.pdfFieldName,
            sourceApi: m.valueSourceType === 'Constant' ? null : m.fieldPath,
            displayLabel: m.valueSourceType === 'Constant' ? m.constantValue : m.fieldPath
        }));
        this.updateMappingLabels(); 
        this.prepareColumnOptions(); 
    } catch (e) { this.mappingData = []; }
 }

  updateMappingLabels() {
      // Use cached field options to improve labels if available
      if (!this.mappingData?.length || this._fieldOptionsMap.size === 0) return;
      
      this.mappingData = this.mappingData.map(row => {
          if (!row.sourceApi) return row;
          const lowerKey = row.sourceApi.toLowerCase();
          const def = this._fieldOptionsMap.get(lowerKey);
          return {
              ...row,
              displayLabel: def ? def.label : row.displayLabel
          };
      });
  }

  async loadThumbnail(templateId) {
    this.previewLoading = true;
    try {
      const b64 = await getLatestTemplatePdfBase64({ templateId });
      const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
      this.pdfDocument = await pdfjsLib.getDocument({ data: bytes }).promise;
      const page = await this.pdfDocument.getPage(1);
      const viewport = page.getViewport({ scale: 0.5 }); 
      const canvas = this.template.querySelector('canvas.thumbnailCanvas');
      if (canvas) {
          canvas.height = viewport.height; canvas.width = viewport.width;
          await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
      }
    } catch (e) { this.previewError = 'Preview failed.'; } finally { this.previewLoading = false; }
  }

  async openPdfModal() {
      if (!this.pdfDocument) return;
      this.isModalOpen = true;
      setTimeout(async () => {
          const container = this.template.querySelector('.fullPdfScrollContainer');
          if (!container) return;
          container.innerHTML = ''; 
          for (let p = 1; p <= this.pdfDocument.numPages; p++) {
              const page = await this.pdfDocument.getPage(p);
              const viewport = page.getViewport({ scale: 1.0 });
              const canvas = document.createElement('canvas');
              canvas.height = viewport.height; canvas.width = viewport.width;
              container.appendChild(canvas);
              await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
          }
      }, 100);
  }

  closePdfModal() { this.isModalOpen = false; }
  goBack() { this.step = 'templates'; this.isModalOpen = false; }

  async fillAndDownload() {
    this.filling = true;
    try {
      const results = await fillTemplate({ templateId: this.selectedTemplateId, recordIds: this.selectedRecordIds });
      results.forEach((r, idx) => { if (r?.downloadUrl) setTimeout(() => this.downloadByUrl(r.downloadUrl), 150 * idx); });
      this.toast('Done', `Created ${results.length} PDF(s).`, 'success');
    } catch (e) { 
        console.error(e);
        const msg = e.body?.message || e.message || 'Unknown error';
        this.toast('Fill failed', msg, 'error'); 
    } finally { this.filling = false; }
  }

  downloadByUrl(url) {
    const a = document.createElement('a'); a.href = url; a.target = '_blank'; a.click();
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}