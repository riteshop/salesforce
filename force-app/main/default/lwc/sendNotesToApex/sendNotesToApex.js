import { LightningElement, api, wire, track } from 'lwc';
import getRelatedNotes from '@salesforce/apex/ContactDisplayController.getRelatedNotes';
import processNotes from '@salesforce/apex/ContactDisplayController.processNotes';

export default class SendNotesToApex extends LightningElement {
    @api recordId;
    @track summaryText;
    @track notesString;

    @wire(getRelatedNotes, { contactId: '$recordId' })
    wiredNotes({ error, data }) {
        if (data) {
            console.log('Fetched Notes:', data);

            // 🧹 Clean HTML tags and normalize note bodies
            const cleaned = data.map(note => {
                const cleanBody = (note.Body || '')
                    .replace(/<[^>]+>/g, '') // remove HTML tags
                    .replace(/&nbsp;/g, ' ') // replace HTML spaces
                    .trim();

                return {
                    Id: note.Id || '',
                    Title: note.Title || '',
                    CreatedDate: note.CreatedDate || '',
                    Body: cleanBody
                };
            });

            this.notesString = JSON.stringify(cleaned);
            console.log('🧾 Cleaned Notes JSON:', this.notesString);

            this.sendNotesToApex(this.notesString);
        } else if (error) {
            console.error('⚠️ Error fetching notes:', error);
        }
    }

    sendNotesToApex(notesJson) {
        processNotes({ notesJson })
            .then((result) => {
                console.log('✅ Raw AWS Response:', result);
                this.summaryText = this.extractSummary(result);
            })
            .catch((error) => {
                console.error('⚠️ Error sending notes to AWS:', error);
                this.summaryText = 'Error: ' + JSON.stringify(error);
            });
    }

    // 🧩 Extract just the summary text from AWS JSON
    extractSummary(result) {
        try {
            const outer = JSON.parse(result);       // Parse outer response
            const inner = JSON.parse(outer.body);   // Parse inner JSON in "body"
            const summary = inner && typeof inner.summary !== 'undefined' && inner.summary !== null ? String(inner.summary).trim() : '';

            if (!summary) {
                return 'Summary: No Notes.';
            }
            return `Summary: ${summary}`;
        } catch (e) {
            console.error('⚠️ Error parsing AWS response:', e);
            return '⚠️ Unable to parse AWS response.';
        }
    }
}