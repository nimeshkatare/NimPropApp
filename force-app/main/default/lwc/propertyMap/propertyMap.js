import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME from '@salesforce/schema/Property__c.Name';
import STREET from '@salesforce/schema/Property__c.Street__c';
import CITY from '@salesforce/schema/Property__c.City__c';
import STATE from '@salesforce/schema/Property__c.State__c';
import POSTAL from '@salesforce/schema/Property__c.Postal_Code__c';
import COUNTRY from '@salesforce/schema/Property__c.Country__c';
import LAT from '@salesforce/schema/Property__c.Location__c';
import LNG from '@salesforce/schema/Property__c.Location__c';
import GEO_STATUS from '@salesforce/schema/Property__c.Geocoding_Status__c';
import GEO_ERROR from '@salesforce/schema/Property__c.Geocoding_Error__c';

const FIELDS = [NAME, STREET, CITY, STATE, POSTAL, COUNTRY, LAT, LNG, GEO_STATUS, GEO_ERROR];

/** REMS-PM-008: shows the geocoded property location on a map. */
export default class PropertyMap extends LightningElement {
    @api recordId;
    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        this.record = data;
        this.error = error;
    }

    get latitude() {
        return this.record ? getFieldValue(this.record, LAT) : undefined;
    }

    get longitude() {
        return this.record ? getFieldValue(this.record, LNG) : undefined;
    }

    get hasLocation() {
        return this.latitude !== undefined && this.latitude !== null && this.longitude !== undefined && this.longitude !== null;
    }

    get geocodingStatus() {
        return this.record ? getFieldValue(this.record, GEO_STATUS) : undefined;
    }

    get statusMessage() {
        if (!this.record) return '';
        const status = this.geocodingStatus;
        if (status === 'Failed') {
            return `Geocoding failed: ${getFieldValue(this.record, GEO_ERROR) || 'unknown error'}. Edit the address to retry.`;
        }
        return 'Location is being geocoded. Refresh this page in a few seconds.';
    }

    get mapMarkers() {
        if (!this.hasLocation) return [];
        return [
            {
                location: { Latitude: this.latitude, Longitude: this.longitude },
                title: getFieldValue(this.record, NAME),
                description: [STREET, CITY, STATE, POSTAL, COUNTRY]
                    .map((f) => getFieldValue(this.record, f))
                    .filter(Boolean)
                    .join(', ')
            }
        ];
    }

    get mapOptions() {
        return { draggable: true, zoomControl: true, scrollwheel: false };
    }

    get errorMessage() {
        return this.error?.body?.message || this.error?.message;
    }
}