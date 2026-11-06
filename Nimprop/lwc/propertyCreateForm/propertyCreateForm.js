import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import attachFile from '@salesforce/apex/PropertyFileController.attachFile';
import rollbackProperty from '@salesforce/apex/PropertyFileController.rollbackProperty';

const MAX_FILE_BYTES = 3 * 1024 * 1024; // keeps the base64 payload under the Apex request limit
const ACCEPTED = '.png,.jpg,.jpeg,.gif,.webp,.pdf';

/**
 * REMS-PM-002/003: creates a Property and requires at least one image/document.
 * The record is created through LDS, then files are uploaded one by one; if any upload fails
 * the record is rolled back so a property can never exist without an attachment.
 */
export default class PropertyCreateForm extends NavigationMixin(LightningElement) {
    /** When true (full-page override) navigate to the record after save; otherwise only fire `success`. */
    @api navigateOnSuccess = false;

    files = [];
    fileError;
    saving = false;
    progressLabel;

    get acceptedFormats() {
        return ACCEPTED;
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get fileHelpText() {
        return `At least one image is required. Up to 3 MB per file (${ACCEPTED}).`;
    }

    handleFilesChange(event) {
        const picked = Array.from(event.target.files || []);
        this.fileError = undefined;
        for (const f of picked) {
            if (f.size > MAX_FILE_BYTES) {
                this.fileError = `"${f.name}" is larger than 3 MB and was skipped.`;
                continue;
            }
            if (!this.files.some((x) => x.name === f.name && x.size === f.size)) {
                this.files = [...this.files, f];
            }
        }
        // Allow re-selecting the same file after removal.
        event.target.value = null;
    }

    handleRemoveFile(event) {
        const name = event.currentTarget.dataset.name;
        this.files = this.files.filter((f) => f.name !== name);
    }

    get fileRows() {
        return this.files.map((f) => ({
            name: f.name,
            label: `${f.name} (${(f.size / 1024).toFixed(0)} KB)`
        }));
    }

    handleSubmit(event) {
        event.preventDefault();
        if (!this.hasFiles) {
            this.fileError = 'Please attach at least one property image before saving.';
            return;
        }
        this.fileError = undefined;
        this.saving = true;
        this.progressLabel = 'Saving property...';
        this.template.querySelector('lightning-record-edit-form').submit(event.detail.fields);
    }

    async handleSuccess(event) {
        const recordId = event.detail.id;
        try {
            for (let i = 0; i < this.files.length; i++) {
                this.progressLabel = `Uploading file ${i + 1} of ${this.files.length}...`;
                const base64 = await this.readAsBase64(this.files[i]);
                // Sequential uploads keep each request small and respect the concurrent-request limit.
                // eslint-disable-next-line no-await-in-loop
                await attachFile({ recordId, fileName: this.files[i].name, base64Data: base64 });
            }
            this.saving = false;
            this.toast('Property created', `${this.files.length} file(s) attached.`, 'success');
            this.dispatchEvent(new CustomEvent('success', { detail: { recordId } }));
            if (this.navigateOnSuccess) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId, objectApiName: 'Property__c', actionName: 'view' }
                });
            }
        } catch (error) {
            // Enforce REMS-PM-003: no image, no property.
            try {
                await rollbackProperty({ propertyId: recordId });
            } catch (ignored) {
                // Rollback failure is surfaced through the primary error below.
            }
            this.saving = false;
            this.fileError = `File upload failed and the property was not saved: ${this.errorMessage(error)}`;
        }
    }

    handleError(event) {
        this.saving = false;
        const msg = event.detail?.detail || event.detail?.message || 'Unable to save the property.';
        this.toast('Save failed', msg, 'error');
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
        if (this.navigateOnSuccess) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Property__c', actionName: 'list' }
            });
        }
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = () => reject(new Error(`Could not read ${file.name}`));
            reader.readAsDataURL(file);
        });
    }

    errorMessage(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(', ');
        return error.body?.message || error.message || JSON.stringify(error);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}