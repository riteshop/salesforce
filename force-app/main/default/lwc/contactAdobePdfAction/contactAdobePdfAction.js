import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import JSZIP from '@salesforce/resourceUrl/jszip';

import getContactData from '@salesforce/apex/ContactAdobePdfController.getContactData';
import generatePdfFromZip from '@salesforce/apex/ContactAdobePdfController.generatePdfFromZip';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class ContactAdobePdfAction extends LightningElement {
  @api recordId;

  busy = false;
  error;
  jsZipReady = false;

  async renderedCallback() {
    if (this.jsZipReady) return;
    this.jsZipReady = true;
    try {
      await loadScript(this, JSZIP);
    } catch (e) {
      this.error = 'Failed to load JSZip static resource.';
    }
  }

  buildHtml(contact) {
    const esc = (v) => (v ?? '')
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

    return `
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <style>
    body { font-family: Arial, sans-serif; font-size: 12px; padding: 16px; }
    h1 { font-size: 18px; margin: 0 0 10px 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; }
    td { padding: 8px; border-bottom: 1px solid #ddd; vertical-align: top; }
    .label { width: 28%; font-weight: bold; }
  </style>
</head>
<body>
  <h1>Contact Details</h1>
  <table>
    <tr><td class="label">Name</td><td>${esc(contact.name)}</td></tr>
    <tr><td class="label">Email</td><td>${esc(contact.email)}</td></tr>
    <tr><td class="label">Phone</td><td>${esc(contact.phone)}</td></tr>
    <tr><td class="label">Title</td><td>${esc(contact.title)}</td></tr>
    <tr><td class="label">Account</td><td>${esc(contact.accountName)}</td></tr>
    <tr><td class="label">Owner</td><td>${esc(contact.ownerName)}</td></tr>
    <tr><td class="label">Mailing</td><td>${esc(contact.mailing)}</td></tr>
    <tr><td class="label">Description</td><td>${esc(contact.description)}</td></tr>
  </table>
</body>
</html>`;
  }

  async handleClick() {
    this.error = null;
    this.busy = true;

    try {
      // 1) Get contact data
      const data = await getContactData({ contactId: this.recordId });

      // 2) Build HTML
      const html = this.buildHtml(data);

      // 3) Zip as index.html (top-level). Many Adobe HTML-to-PDF integrations expect a zip with index.html. :contentReference[oaicite:27]{index=27}
      // JSZip is loaded as a static resource.
      // eslint-disable-next-line no-undef
      const zip = new JSZip();
      zip.file('index.html', html);

      const zipBase64 = await zip.generateAsync({ type: 'base64' });

      // 4) Ask Apex to send the ZIP to Adobe + return PDF
      const res = await generatePdfFromZip({
        contactId: this.recordId,
        zipBase64
      });

      // 5) Download PDF
      const byteChars = atob(res.base64Pdf);
      const bytes = new Uint8Array(byteChars.length);
      for (let i = 0; i < byteChars.length; i++) bytes[i] = byteChars.charCodeAt(i);

      const blob = new Blob([bytes], { type: 'application/pdf' });
      const url = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = url;
      a.download = res.fileName || 'Contact.pdf';
      a.click();

      URL.revokeObjectURL(url);
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      this.error = e?.body?.message || e?.message || 'Unknown error';
    } finally {
      this.busy = false;
    }
  }
}