import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import JSPDF from '@salesforce/resourceUrl/jsPDF';
import getLeaseData from '@salesforce/apex/LeaseAgreementPdfController.getLeaseData';
import sendPdfToTenant from '@salesforce/apex/LeaseAgreementPdfController.sendPdfToTenant';

/**
 * REMS-LA-003/004: generates the lease agreement PDF client-side with jsPDF and either
 * downloads it or posts it back to Apex to be emailed to the tenant.
 */
export default class LeaseAgreementActions extends LightningElement {
    @api recordId;

    libraryReady = false;
    busy = false;
    error;

    async connectedCallback() {
        try {
            await loadScript(this, JSPDF);
            this.libraryReady = true;
        } catch (e) {
            this.error = 'Could not load the PDF library: ' + (e?.message || e);
        }
    }

    get disabled() {
        return !this.libraryReady || this.busy;
    }

    async handleDownload() {
        await this.run(async () => {
            const { doc, fileName } = await this.buildPdf();
            doc.save(fileName);
            this.toast('PDF downloaded', fileName, 'success');
        });
    }

    async handleSend() {
        await this.run(async () => {
            const { doc, fileName } = await this.buildPdf();
            const dataUri = doc.output('datauristring');
            const base64Pdf = dataUri.substring(dataUri.indexOf(',') + 1);
            const sentTo = await sendPdfToTenant({ leaseId: this.recordId, base64Pdf, fileName });
            this.toast('Lease agreement sent', `Emailed to ${sentTo} and saved under Files.`, 'success');
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        });
    }

    async run(fn) {
        this.busy = true;
        this.error = undefined;
        try {
            await fn();
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unexpected error';
            this.toast('Action failed', this.error, 'error');
        } finally {
            this.busy = false;
        }
    }

    /**
     * Renders the lease agreement. Returns the jsPDF document plus a suggested file name.
     */
    async buildPdf() {
        const data = await getLeaseData({ leaseId: this.recordId });
        // eslint-disable-next-line no-undef
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF({ unit: 'mm', format: 'a4' });

        const marginX = 20;
        const pageWidth = doc.internal.pageSize.getWidth();
        const contentWidth = pageWidth - marginX * 2;
        let y = 20;

        const line = (gap = 7) => {
            y += gap;
        };
        const heading = (text) => {
            doc.setFont('helvetica', 'bold');
            doc.setFontSize(12);
            doc.text(text, marginX, y);
            doc.setFont('helvetica', 'normal');
            doc.setFontSize(10.5);
            line(6);
        };
        const row = (label, value) => {
            doc.setFont('helvetica', 'bold');
            doc.text(`${label}:`, marginX, y);
            doc.setFont('helvetica', 'normal');
            doc.text(String(value ?? '—'), marginX + 48, y);
            line();
        };
        const paragraph = (text) => {
            const lines = doc.splitTextToSize(text || '—', contentWidth);
            for (const l of lines) {
                if (y > 275) {
                    doc.addPage();
                    y = 20;
                }
                doc.text(l, marginX, y);
                line(5.5);
            }
        };

        // Header band
        doc.setFillColor(0, 112, 210);
        doc.rect(0, 0, pageWidth, 14, 'F');
        doc.setTextColor(255, 255, 255);
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(13);
        doc.text(data.organizationName || 'Property Operations', marginX, 9.5);
        doc.setTextColor(0, 0, 0);

        doc.setFontSize(18);
        doc.text('Residential Lease Agreement', marginX, y);
        line(8);
        doc.setFontSize(10.5);
        doc.setFont('helvetica', 'normal');
        doc.text(`Agreement No. ${data.leaseNumber}    ·    Generated ${this.formatDate(new Date())}`, marginX, y);
        line(10);

        heading('Property');
        row('Name', data.propertyName);
        row('Type', data.propertyType);
        row('Address', data.propertyAddress);
        line(3);

        heading('Tenant');
        row('Name', data.tenantName);
        row('Email', data.tenantEmail);
        row('Phone', data.tenantPhone);
        line(3);

        heading('Term & Rent');
        row('Start Date', this.formatDate(data.startDate));
        row('End Date', this.formatDate(data.endDate));
        row('Monthly Rent', this.formatMoney(data.monthlyRent, data.currencyCode));
        line(3);

        heading('Terms & Conditions');
        paragraph(data.terms);
        line(8);

        if (y > 240) {
            doc.addPage();
            y = 20;
        }
        heading('Signatures');
        doc.text('Landlord / Agent: ______________________________', marginX, y);
        doc.text(`(${data.ownerName || ''})`, marginX + 100, y);
        line(12);
        doc.text('Tenant: ________________________________________', marginX, y);
        doc.text(`(${data.tenantName || ''})`, marginX + 100, y);
        line(12);
        doc.text('Date: ____________________', marginX, y);

        // Footer page numbers
        const pages = doc.getNumberOfPages();
        for (let i = 1; i <= pages; i++) {
            doc.setPage(i);
            doc.setFontSize(8);
            doc.setTextColor(120, 120, 120);
            doc.text(`${data.leaseNumber} · Page ${i} of ${pages}`, pageWidth - marginX, 290, { align: 'right' });
            doc.setTextColor(0, 0, 0);
        }

        return { doc, fileName: `Lease-Agreement-${data.leaseNumber}.pdf` };
    }

    formatDate(value) {
        if (!value) return '—';
        const d = typeof value === 'string' ? new Date(`${value}T00:00:00`) : value;
        return d.toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' });
    }

    formatMoney(amount, code) {
        if (amount === null || amount === undefined) return '—';
        try {
            return new Intl.NumberFormat(undefined, { style: 'currency', currency: code || 'USD', currencyDisplay: 'code' }).format(amount);
        } catch (e) {
            return `${code || ''} ${Number(amount).toFixed(2)}`;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}