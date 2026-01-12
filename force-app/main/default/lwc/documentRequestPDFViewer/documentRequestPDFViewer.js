import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';

import pdfjsStatic from '@salesforce/resourceUrl/pdfjsLib';
import getLatestFileForRecord from '@salesforce/apex/DocumentRequestFileController.getLatestFileForRecord';
import getPdfBase64 from '@salesforce/apex/DocumentRequestFileController.getPdfBase64';

export default class DocumentRequestPdfJsViewer extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track errorMessage;
    @track fileId;

    // PDF.js state
    pdfjsLib;
    pdfDoc = null;
    pageNumber = 1;
    pageCount = 0;
    scale = 1.0;
    pdfInitialized = false;

    // Wire to get latest ContentDocumentId
    @wire(getLatestFileForRecord, { recordId: '$recordId' })
    wiredFile({ data, error }) {
        if (data === null || data === undefined) {
            // No document attached
            this.fileId = null;
            this.errorMessage = null; // Clear errors
            this.isLoading = false;
            return;
        }

        if (data) {
            this.fileId = data;
            this.errorMessage = null;
            this.initPdfJsIfReady();
        } 
        else if (error) {
            this.errorMessage = 'Error retrieving attached file.';
            console.error(error);
            this.isLoading = false;
        }
    }

    // Load PDF.js library
    renderedCallback() {
        if (this.pdfInitialized) return;
        this.pdfInitialized = true;

        this.isLoading = true;

        loadScript(this, pdfjsStatic + '/pdfjs/pdf.js')
            .then(() => {
                console.log('Script loaded successfully');
                this.pdfjsLib =
                    window.pdfjsLib ||
                    window['pdfjs-dist/build/pdf'] ||
                    window.pdfjsDistBuildPdf;

                if (!this.pdfjsLib) {
                    throw new Error('pdfjsLib not found');
                }

                this.pdfjsLib.GlobalWorkerOptions.workerSrc =
                    pdfjsStatic + '/pdfjs/pdf.worker.js';

                this.initPdfJsIfReady();
            })
            .catch(err => {
                console.error('PDF.js load error:', err);
                this.errorMessage = 'Error loading PDF.js library.';
                this.isLoading = false;
            });
    }

    //----------------------------------------------------------
    //  NEW: Inline PDF loader using Base64 from Apex
    //----------------------------------------------------------
    initPdfJsIfReady() {
        if (!this.pdfjsLib || !this.fileId) return;

        this.isLoading = true;

        console.log('Fetching Base64 PDF for:', this.fileId);

        getPdfBase64({ contentDocumentId: this.fileId })
            .then(base64 => {
                if (!base64) {
                    this.errorMessage = 'No PDF attached.';
                    this.isLoading = false;
                    return;
                }

                console.log('Base64 PDF received, converting to bytes…');

                const binary = atob(base64);
                const len = binary.length;
                const bytes = new Uint8Array(len);

                for (let i = 0; i < len; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }

                console.log('Loading PDF with PDF.js');

                return this.pdfjsLib.getDocument({ data: bytes }).promise;
            })
            .then(pdf => {
                if (!pdf) return;
                this.pdfDoc = pdf;
                this.pageCount = pdf.numPages;
                this.pageNumber = 1;
                this.renderPage(1);
            })
            .catch(err => {
                console.error('PDF load error:', err);
                this.errorMessage = 'Failed to load PDF.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    //----------------------------------------------------------
    // Rendering Helpers
    //----------------------------------------------------------

    get hasPdf() {
        return !!this.fileId && !this.errorMessage;
    }

    get zoomDisplay() {
        return Math.round(this.scale * 100) + '%';
    }

    renderPage(pageNum) {
        this.isLoading = true;

        this.pdfDoc.getPage(pageNum).then(page => {
            const canvas = this.template.querySelector('canvas.pdf-canvas');
            const ctx = canvas.getContext('2d');

            const viewport = page.getViewport({ scale: this.scale });

            canvas.height = viewport.height;
            canvas.width = viewport.width;

            page.render({ canvasContext: ctx, viewport })
                .promise.then(() => {
                    this.isLoading = false;
                });
        });
    }

    //----------------------------------------------------------
    // Controls
    //----------------------------------------------------------

    handlePrev() {
        if (this.pageNumber <= 1) return;
        this.pageNumber--;
        this.renderPage(this.pageNumber);
    }

    handleNext() {
        if (this.pageNumber >= this.pageCount) return;
        this.pageNumber++;
        this.renderPage(this.pageNumber);
    }

    handleZoomIn() {
        this.scale = Math.min(this.scale + 0.1, 3.0);
        this.renderPage(this.pageNumber);
    }

    handleZoomOut() {
        this.scale = Math.max(this.scale - 0.1, 0.5);
        this.renderPage(this.pageNumber);
    }
}