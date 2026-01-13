import { LightningElement, api, track } from 'lwc';
import PDFJS from '@salesforce/resourceUrl/pdfjsLib';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getLatestTemplatePdfBase64 from '@salesforce/apex/PdfTemplateFileController.getLatestTemplatePdfBase64';
import getMappings from '@salesforce/apex/PdfMappingController.getMappings';
import saveMappings from '@salesforce/apex/PdfMappingController.saveMappings';
import getTemplateSourceObject from '@salesforce/apex/PdfMappingController.getTemplateSourceObject';
import getObjectFieldOptions from '@salesforce/apex/PdfMappingController.getObjectFieldOptions';

export default class PdfMappingEditorV2 extends LightningElement {
  @api recordId;

  @track fields = [];
  @track isLoading = true;
  
  // Cache field options by Object API Name to reduce Apex calls
  _fieldCache = new Map(); 

  pdf;
  pageScale = 1.25;
  selectedName;
  saving = false;
  initialized = false;
  sourceObjectApiName;
  sourceObjectLabel;

  _viewports = new Map(); 

  // --- RESIZE LOGIC ---
  @track leftWidthPct = 50;
  isResizing = false;

  get saveLabel() {
      return this.saving ? 'Saving...' : 'Save Mappings';
  }

  get headerTitle() {
      return this.sourceObjectLabel ? `${this.sourceObjectLabel} Field Mapping` : (this.sourceObjectApiName ? `${this.sourceObjectApiName} Field Mapping` : 'Field Mapping');
  }

  handleResizerMouseDown(event) {
      event.preventDefault();
      this.isResizing = true;
  }

  handleMouseMove(event) {
      if (!this.isResizing) return;
      const container = this.template.querySelector('.layout');
      if (!container) return;
      const rect = container.getBoundingClientRect();
      const x = event.clientX - rect.left;
      let newPct = (x / rect.width) * 100;
      if (newPct < 20) newPct = 20;
      if (newPct > 80) newPct = 80;
      this.leftWidthPct = newPct;
      this.updateLeftPaneWidth();
  }

  updateLeftPaneWidth() {
      const el = this.template.querySelector('.pdfStage');
      if (el) {
          el.style.width = `${this.leftWidthPct}%`;
          el.style.flexShrink = '0';
      }
  }

  handleMouseUp() {
      this.isResizing = false;
  }

  // --- INIT ---
  async renderedCallback() {
    if (this.initialized) return;
    this.initialized = true;
    this.updateLeftPaneWidth();

    try {
      await loadScript(this, PDFJS + '/pdfjs/pdf.js');
      // eslint-disable-next-line no-undef
      pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdfjs/pdf.worker.js';
      await this.init();
    } catch (e) {
      this.toast('Error', 'PDF viewer failed to initialize.', 'error');
    }
  }

  async init() {
    try {
      // 1. Fire off all requests in parallel
      const [sourceObjMeta, b64, existingMappings] = await Promise.all([
          getTemplateSourceObject({ templateId: this.recordId }),
          getLatestTemplatePdfBase64({ templateId: this.recordId }),
          getMappings({ templateId: this.recordId })
      ]);

      // 2. Handle Source Object & Fields
      if (!sourceObjMeta || !sourceObjMeta.apiName) {
        this.toast('Warning', 'This template has no Source Object defined.', 'warning');
      } else {
        this.sourceObjectApiName = sourceObjMeta.apiName;
        this.sourceObjectLabel = sourceObjMeta.label;
        // Pre-load fields
        this.loadFieldOptions(this.sourceObjectApiName).catch(e => console.error(e));
      }

      // 3. Handle PDF Loading
      if (!b64) {
        this.toast('Error', 'No PDF file found.', 'error');
        return;
      }
      const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
      // eslint-disable-next-line no-undef
      this.pdf = await pdfjsLib.getDocument({ data: bytes }).promise;

      // 4. Start Rendering & Extractor in Parallel
      const renderPromise = this.renderAllPages();

      const byName = new Map((existingMappings || []).map(m => [m.pdfFieldName, m]));
      const extractPromise = this.extractAndMapFields(byName);

      await Promise.all([renderPromise, extractPromise]);

    } catch (e) {
      console.error('Init failed:', e);
      this.toast('Error', 'Initialization failed: ' + (e.message || e), 'error');
    } finally {
      this.isLoading = false;
    }
  }

  // Helper to get options with caching
  async loadFieldOptions(objectName) {
      if (this._fieldCache.has(objectName)) {
          return this._fieldCache.get(objectName);
      }
      
      const promise = (async () => {
        try {
            const raw = await getObjectFieldOptions({ objectApiName: objectName });
            const options = (raw || []).map(o => ({
                label: `${o.label} [${o.value}]`, 
                value: o.value,
                type: o.type,
                referenceTo: o.referenceTo,
                relationshipName: o.relationshipName
            }));
            return options;
        } catch (e) {
            console.error(`Failed to load fields for ${objectName}`, e);
            this._fieldCache.delete(objectName); 
            return [];
        }
      })();

      this._fieldCache.set(objectName, promise);
      return promise;
  }

  async extractAndMapFields(byName) {
    const extracted = [];
    
    for (let p = 1; p <= this.pdf.numPages; p++) {
      const page = await this.pdf.getPage(p);
      const annots = await page.getAnnotations({ intent: 'display' });

      for (const a of annots) {
        if (a?.subtype === 'Widget' && a?.fieldName) {
            if (extracted.some(f => f.name === a.fieldName)) continue;

            const prior = byName.get(a.fieldName);
            const priorPath = prior?.fieldPath || ''; 
            
            const row = {
                name: a.fieldName,
                uniqueRadioName: 'valSource_' + a.fieldName,
                displayLabel: prior?.displayLabel || a.fieldName,
                page: p,
                rect: a.rect,
                mappingId: prior?.id || null,
                mappedValue: (prior?.valueSourceType === 'Constant' || prior?.valueSourceType === 'ContextVariable') ? (prior?.constantValue || '') : priorPath,
                showInSearch: prior?.showInSearch || false,
                valueSourceType: prior?.valueSourceType || 'FieldPath',
                constantValue: prior?.constantValue || '',
                isConstant: (prior?.valueSourceType === 'Constant'),
                isContextVariable: (prior?.valueSourceType === 'ContextVariable'),
                rowClass: 'fieldRow',
                expanded: false,
                levels: [] 
            };
            extracted.push(row);
        }
      }
    }

    this.fields = extracted;
    await Promise.all(this.fields.map(f => this.initMappingPath(f)));
  }

  // ------------------------------------------------------------------
  // MILLER COLUMN LOGIC
  // ------------------------------------------------------------------

  async onLevelItemClick(event) {
    // Prevent bubbling if needed, though usually fine
    event.stopPropagation();
    
    const fieldName = event.currentTarget.dataset.field; 
    const levelIndex = parseInt(event.currentTarget.dataset.levelIndex, 10);
    const itemValue = event.currentTarget.dataset.value;
    
    // Find the row
    const row = this.fields.find(f => f.name === fieldName);
    if (!row) return;

    // Clone levels 
    let newLevels = [...row.levels];

    // 1. Mark selection in this level
    const currentLevel = { ...newLevels[levelIndex] };
    
    if (currentLevel.selectedValue === itemValue) return; // already selected
    
    currentLevel.selectedValue = itemValue; 
    newLevels[levelIndex] = currentLevel;
    
    // 2. Remove any deeper levels (we changed parent)
    if (newLevels.length > levelIndex + 1) {
        newLevels = newLevels.slice(0, levelIndex + 1);
    }
    
    // 3. Find the selected option definition
    const selectedOption = currentLevel.options.find(o => o.value === itemValue);
    
    // 4. Update row logic: Check if Reference
    let isLeaf = true;
    if (selectedOption && (selectedOption.type === 'REFERENCE' || selectedOption.type === 'Reference')) {
        isLeaf = false;
        let targetObject = null;
        if (selectedOption.referenceTo && selectedOption.referenceTo.length > 0) {
            targetObject = selectedOption.referenceTo[0];
        }
        
        if (targetObject) {
            // Add loading placeholder for next level
            newLevels.push({
                id: `l${levelIndex + 1}`,
                index: levelIndex + 1,
                options: [],
                searchTerm: '',
                loading: true,
                selectedValue: null
            });
            
            // Async fetch
            this.fetchNextLevel(fieldName, levelIndex + 1, targetObject);
        }
    }
    
    // 5. Update the row state immediately
    const updatedRow = {
        ...row,
        levels: this.recalcItemClasses(newLevels),
        mappedValue: this.computePathFromLevels(newLevels)
    };
    
    this.updateFieldRow(updatedRow);
  }

  async fetchNextLevel(pdfFieldName, levelIndex, objectApiName) {
    try {
        const options = await this.loadFieldOptions(objectApiName);
        
        const row = this.fields.find(f => f.name === pdfFieldName);
        if (!row) return;

        // Check if user clicked something else while we were loading
        if (row.levels.length <= levelIndex) return; 

        const newLevels = [...row.levels];
        newLevels[levelIndex] = {
            id: `l${levelIndex}`,
            index: levelIndex,
            options: options,
            searchTerm: '',
            loading: false,
            selectedValue: null
        };
        
        this.updateFieldRow({
            ...row,
            levels: this.recalcItemClasses(newLevels)
        });

    } catch (e) {
        console.error('Fetch next level failed', e);
    }
  }

  computePathFromLevels(levels) {
      if (!levels || !levels.length) return '';
      const parts = [];
      for (const lvl of levels) {
          if (!lvl.selectedValue) break;
          const opt = lvl.options.find(o => o.value === lvl.selectedValue);
          if (!opt) {
              parts.push(lvl.selectedValue);
          } else {
             // Logic: If it's a reference AND there is a next level, use relationshipName. 
             const isLast = (levels.indexOf(lvl) === levels.length - 1);
             
             const isRef = (opt.type === 'REFERENCE' || opt.type === 'Reference');
             
             if (!isLast && isRef && opt.relationshipName) {
                 parts.push(opt.relationshipName); 
             } else {
                 parts.push(opt.value);
             }
          }
      }
      return parts.join('.');
  }

  onColumnSearch(event) {
      event.stopPropagation();
      const fieldName = event.target.dataset.field;
      const index = parseInt(event.target.dataset.levelIndex, 10);
      const val = event.target.value;

      const row = this.fields.find(f => f.name === fieldName);
      if (!row) return;

      const newLevels = [...row.levels];
      newLevels[index] = { ...newLevels[index], searchTerm: val };
      
      this.updateFieldRow({
          ...row,
          levels: this.recalcItemClasses(newLevels)
      });
  }

  recalcItemClasses(levels) {
      return levels.map(lvl => {
          // FILTER
          let visible = lvl.options || [];
          if (lvl.searchTerm) {
              const lower = lvl.searchTerm.toLowerCase();
              visible = visible.filter(o => o.label.toLowerCase().includes(lower) || o.value.toLowerCase().includes(lower));
          }

          // MAP for Display
          const displayOpts = visible.map(opt => {
              const isSel = (opt.value === lvl.selectedValue);
              return {
                  ...opt,
                  class: `finder-item ${isSel ? 'selected' : ''}`,
                  isRef: (opt.type === 'REFERENCE' || opt.type === 'Reference')
              };
          });
          return { ...lvl, displayOptions: displayOpts };
      });
  }

  updateFieldRow(updatedRow) {
      this.fields = this.fields.map(f => f.name === updatedRow.name ? updatedRow : f);
  }

  async initMappingPath(field) {
    const path = field.mappedValue;
    const rootOptions = await this.loadFieldOptions(this.sourceObjectApiName);
    
    // Initial Level 0
    let levels = [{
        id: 'l0',
        index: 0,
        options: rootOptions,
        searchTerm: '',
        selectedValue: null,
        loading: false
    }];

    if (!path) {
        field.levels = this.recalcItemClasses(levels);
        return;
    }

    const segments = path.split('.');
    let currentOptions = rootOptions;
    
    for (let i = 0; i < segments.length; i++) {
        const seg = segments[i];
        
        if (!levels[i]) { /* safety */ }
        
        const isLast = (i === segments.length - 1);
        
        let foundOpt = currentOptions.find(o => o.value === seg);
        if (!foundOpt) {
            foundOpt = currentOptions.find(o => o.relationshipName === seg);
        }

        if (foundOpt) {
            levels[i].selectedValue = foundOpt.value;
            
            if (!isLast && foundOpt.referenceTo && foundOpt.referenceTo.length) {
                const nextObj = foundOpt.referenceTo[0];
                const nextOpts = await this.loadFieldOptions(nextObj);
                
                levels.push({
                    id: `l${i+1}`,
                    index: i + 1,
                    options: nextOpts,
                    searchTerm: '',
                    selectedValue: null,
                    loading: false
                });
                currentOptions = nextOpts;
            }
        } else {
            break;
        }
    }
    
    field.levels = this.recalcItemClasses(levels);
  }

  onLabelChange(event) {
    const name = event.target.dataset.name;
    const value = event.target.value;
    this.fields = this.fields.map(f => f.name === name ? { ...f, displayLabel: value } : f);
  }

  onShowInSearchChange(event) {
    const name = event.target.dataset.name;
    const checked = event.target.checked;
    this.fields = this.fields.map(f => f.name === name ? { ...f, showInSearch: checked } : f);
  }

  onClearMapping(event) {
      event.stopPropagation();
      const name = event.target.dataset.name;
      
      this.fields = this.fields.map(f => {
          if (f.name === name) {
              return { 
                  ...f, 
                  mappedValue: '', 
                  valueSourceType: 'FieldPath',
                  isConstant: false,
                  isContextVariable: false,
                  constantValue: '',
                  levels: [] 
              };
          }
          return f;
      });
      
      const field = this.fields.find(f => f.name === name);
      if (field) {
          this.initMappingPath(field); 
      }
  }

  get sourceOptions() {
      return [
          { label: 'Salesforce Field', value: 'FieldPath' },
          { label: 'Constant Value', value: 'Constant' },
          { label: 'Context Variable', value: 'ContextVariable' }
      ];
  }

  get contextOptions() {
      return [
          { label: 'Current User Name', value: 'CurrentUserName' },
          { label: 'Current User Email', value: 'CurrentUserEmail' },
          { label: 'Current Date', value: 'CurrentDate' }
      ];
  }

  // --- SAVE ---
  async save() {
    this.saving = true;
    try {
      const rows = this.fields.map(f => ({
        id: f.mappingId,
        pdfFieldName: f.name,
        displayLabel: f.displayLabel,
        valueSourceType: f.valueSourceType,
        constantValue: f.constantValue,
        fieldPath: f.mappedValue,
        showInSearch: f.showInSearch,
        active: true
      }));
      await saveMappings({ templateId: this.recordId, rowsJson: JSON.stringify(rows) });
      this.toast('Success', 'Mappings saved.', 'success');
    } catch (e) {
      this.toast('Error', 'Save failed', 'error');
    } finally {
      this.saving = false;
    }
  }

  handleSourceTypeChange(event) {
      const name = event.target.dataset.name;
      const val = event.detail.value;
      this.fields = this.fields.map(f => {
          if (f.name === name) {
              const isConstant = (val === 'Constant');
              const isContext = (val === 'ContextVariable');
              return { 
                  ...f, 
                  valueSourceType: val,
                  isConstant: isConstant,
                  isContextVariable: isContext,
                  mappedValue: (isConstant || isContext) ? f.constantValue : this.computePathFromLevels(f.levels)
              };
          }
          return f;
      });
  }

  handleConstantValueChange(event) {
      const name = event.target.dataset.name;
      const val = event.target.value;
      this.fields = this.fields.map(f => {
          if (f.name === name) {
              return { 
                  ...f, 
                  constantValue: val,
                  mappedValue: val 
              };
          }
          return f;
      });
  }
  
  // Reusing same handler for context variable change (different event payload type if combobox)
  handleContextVarChange(event) {
      const name = event.target.dataset.name;
      const val = event.detail.value;
      this.fields = this.fields.map(f => {
          if (f.name === name) {
              return { 
                  ...f, 
                  constantValue: val,
                  mappedValue: val 
              };
          }
          return f;
      });
  }

  // --- VIEW HELPERS ---

  stopProp(event) {
      event.stopPropagation();
  }

  selectField(event) {
    const name = event.currentTarget.dataset.name;
    this.selectFieldByName(name);
  }

  selectFieldByName(name) {
    this.selectedName = name;
    this.fields = this.fields.map(f => ({
      ...f,
      rowClass: f.name === name ? 'fieldRow selected' : 'fieldRow',
      expanded: f.name === name // Only expand the selected one
    }));
    
    const field = this.fields.find(f => f.name === name);
    if (field) {
        this.highlight(field);
        this.scrollSelectedRowIntoView(name);
    }
  }

  scrollSelectedRowIntoView(name) {
    const pane = this.template.querySelector('.scrollable-list');
    if (!pane) return;
    const row = pane.querySelector(`.fieldRow[data-name="${name}"]`);
    if (row) {
        try { row.scrollIntoView({ behavior: 'smooth', block: 'center' }); } 
        catch (e) { row.scrollIntoView(); }
    }
  }

  highlight(field) {
    const overlays = this.template.querySelectorAll('.page-overlay');
    overlays.forEach(el => el.innerHTML = '');

    if (!field?.rect || field.rect.length < 4) return;
    const container = this.template.querySelector('.pdfInner');
    const wrapper = container.querySelector(`div[data-page-num="${field.page}"]`);
    if (!wrapper) return;
    const overlay = wrapper.querySelector('.page-overlay');
    const viewport = this._viewports.get(field.page);
    if (!overlay || !viewport) return;

    wrapper.scrollIntoView({ behavior: 'smooth', block: 'center' });
    const r = [Number(field.rect[0]), Number(field.rect[1]), Number(field.rect[2]), Number(field.rect[3])];
    const vr = viewport.convertToViewportRectangle(r);
    
    // Use min/max to normalize coordinates
    const left = Math.min(vr[0], vr[2]);
    const top = Math.min(vr[1], vr[3]);
    const width = Math.abs(vr[2] - vr[0]);
    const height = Math.abs(vr[3] - vr[1]);

    const box = document.createElement('div');
    // Draw box style
    box.style.cssText = `position:absolute;left:${left}px;top:${top}px;width:${width}px;height:${height}px;border:4px solid red;background:rgba(255,0,0,0.25);box-sizing:border-box;z-index:10;`;
    overlay.appendChild(box);
  }

  async renderAllPages() {
    const container = this.template.querySelector('.pdfInner');
    container.innerHTML = ''; 
    this._viewports.clear();

    const renderPromises = [];

    for (let p = 1; p <= this.pdf.numPages; p++) {
        const wrapper = document.createElement('div');
        wrapper.style.marginBottom = '20px';
        wrapper.style.position = 'relative';
        wrapper.dataset.pageNum = p;

        const canvas = document.createElement('canvas');
        canvas.style.display = 'block';
        
        const overlay = document.createElement('div');
        overlay.className = 'page-overlay'; 
        overlay.style.cssText = 'position:absolute;top:0;left:0;pointer-events:none;'; 

        wrapper.appendChild(canvas);
        wrapper.appendChild(overlay);
        container.appendChild(wrapper);

        renderPromises.push(this.renderPage(p, canvas, overlay, wrapper));
    }

    await Promise.all(renderPromises);
  }

  async renderPage(p, canvas, overlay, wrapper) {
      try {
          const page = await this.pdf.getPage(p);
          const viewport = page.getViewport({ scale: this.pageScale });
          this._viewports.set(p, viewport); 

          canvas.height = viewport.height;
          canvas.width = viewport.width;
          overlay.style.height = `${viewport.height}px`;
          overlay.style.width = `${viewport.width}px`;

          const ctx = canvas.getContext('2d');
          await page.render({ canvasContext: ctx, viewport }).promise;

          wrapper.addEventListener('click', (event) => {
             // Hit test logic
             const rect = canvas.getBoundingClientRect();
             const x = event.clientX - rect.left;
             const y = event.clientY - rect.top;
             
             // Simple Hit Test against valid rects
             const candidates = this.fields.filter(f => f.page === p && Array.isArray(f.rect));
             const hit = candidates.find(f => {
                 const r = f.rect.map(Number);
                 const vr = viewport.convertToViewportRectangle(r);
                 const l = Math.min(vr[0], vr[2]);
                 const t = Math.min(vr[1], vr[3]);
                 const w = Math.abs(vr[2] - vr[0]);
                 const h = Math.abs(vr[3] - vr[1]);
                 return (x >= l && x <= l+w && y >= t && y <= t+h);
             });
             if(hit) this.selectFieldByName(hit.name);
          });
      } catch (e) {
         console.warn(`Page ${p} render error`, e);
      }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}