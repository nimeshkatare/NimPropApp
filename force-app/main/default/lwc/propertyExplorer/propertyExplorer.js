import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import PROPERTY_OBJECT from '@salesforce/schema/Property__c';
import STATUS_FIELD from '@salesforce/schema/Property__c.Status__c';
import FURNISHING_FIELD from '@salesforce/schema/Property__c.Furnishing_Status__c';
import TYPE_FIELD from '@salesforce/schema/Property__c.Type__c';
import search from '@salesforce/apex/PropertyListController.search';

const ANY = { label: 'Any', value: '' };

const COLUMNS = [
    {
        label: 'Property',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' },
        sortable: false
    },
    { label: 'City', fieldName: 'city' },
    { label: 'State', fieldName: 'state' },
    { label: 'Type', fieldName: 'propertyType', initialWidth: 120 },
    { label: 'Furnishing', fieldName: 'furnishing', initialWidth: 140 },
    {
        label: 'Status',
        fieldName: 'status',
        initialWidth: 110,
        cellAttributes: { class: { fieldName: 'statusClass' } }
    },
    {
        label: 'Rent',
        fieldName: 'rent',
        type: 'currency',
        typeAttributes: { currencyDisplayAs: 'code', minimumFractionDigits: 0 },
        cellAttributes: { alignment: 'left' },
        initialWidth: 130
    },
    { label: 'Tenant', fieldName: 'tenantName' }
];

const DISTANCE_COLUMN = {
    label: 'Distance (km)',
    fieldName: 'distanceKm',
    type: 'number',
    typeAttributes: { maximumFractionDigits: 1 },
    cellAttributes: { alignment: 'left' },
    initialWidth: 130
};

/**
 * REMS-PM-004/005/006: server-side paginated property list with price / availability /
 * furnishing / nearby-distance filters. Every page turn is a fresh Apex call.
 */
export default class PropertyExplorer extends NavigationMixin(LightningElement) {
    @track filters = {
        searchText: '',
        minRent: null,
        maxRent: null,
        status: '',
        furnishing: '',
        propertyType: '',
        radiusKm: null,
        latitude: null,
        longitude: null
    };

    pageNumber = 1;
    totalPages = 0;
    totalCount = 0;
    rows = [];
    loading = false;
    error;
    showCreateModal = false;
    showMap = false;
    locationStatus;
    locationDenied = false;

    statusOptions = [ANY];
    furnishingOptions = [ANY];
    typeOptions = [ANY];

    @wire(getObjectInfo, { objectApiName: PROPERTY_OBJECT })
    objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: STATUS_FIELD })
    wiredStatus({ data }) {
        if (data) this.statusOptions = [ANY, ...data.values];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: FURNISHING_FIELD })
    wiredFurnishing({ data }) {
        if (data) this.furnishingOptions = [ANY, ...data.values];
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: TYPE_FIELD })
    wiredType({ data }) {
        if (data) this.typeOptions = [ANY, ...data.values];
    }

    connectedCallback() {
        this.loadPage(1);
    }

    // ---------- data ----------

    get columns() {
        return this.geoActive ? [...COLUMNS.slice(0, 1), DISTANCE_COLUMN, ...COLUMNS.slice(1)] : COLUMNS;
    }

    get geoActive() {
        return !!(this.filters.radiusKm && this.filters.latitude !== null && this.filters.longitude !== null);
    }

    async loadPage(page) {
        this.loading = true;
        this.error = undefined;
        try {
            const result = await search({ filtersJson: JSON.stringify(this.filters), pageNumber: page });
            this.pageNumber = result.pageNumber;
            this.totalPages = result.totalPages;
            this.totalCount = result.totalCount;
            this.rows = result.records.map((r) => ({
                ...r,
                recordUrl: `/lightning/r/Property__c/${r.id}/view`,
                statusClass: r.status === 'Available' ? 'slds-text-color_success' : 'slds-text-color_weak'
            }));
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load properties.';
            this.rows = [];
        } finally {
            this.loading = false;
        }
    }

    // ---------- filters ----------

    handleFilterChange(event) {
        const { name, value } = event.target;
        const numeric = ['minRent', 'maxRent', 'radiusKm'];
        this.filters = { ...this.filters, [name]: numeric.includes(name) ? (value === '' ? null : Number(value)) : value };
    }

    handleSearchKey(event) {
        if (event.key === 'Enter') this.applyFilters();
    }

    applyFilters() {
        if (this.filters.radiusKm && this.filters.latitude === null) {
            this.requestLocation(() => this.loadPage(1));
            return;
        }
        this.loadPage(1);
    }

    clearFilters() {
        this.filters = {
            searchText: '',
            minRent: null,
            maxRent: null,
            status: '',
            furnishing: '',
            propertyType: '',
            radiusKm: null,
            latitude: this.filters.latitude,
            longitude: this.filters.longitude
        };
        this.loadPage(1);
    }

    handleUseMyLocation() {
        this.requestLocation(() => {
            if (this.filters.radiusKm) this.loadPage(1);
        });
    }

    requestLocation(onSuccess) {
        if (!navigator.geolocation) {
            this.locationDenied = true;
            this.locationStatus = 'Geolocation is not supported by this browser; the distance filter is disabled.';
            return;
        }
        this.locationStatus = 'Requesting your location...';
        navigator.geolocation.getCurrentPosition(
            (pos) => {
                this.filters = {
                    ...this.filters,
                    latitude: Number(pos.coords.latitude.toFixed(6)),
                    longitude: Number(pos.coords.longitude.toFixed(6))
                };
                this.locationDenied = false;
                this.locationStatus = `Using your location (${this.filters.latitude}, ${this.filters.longitude}).`;
                if (onSuccess) onSuccess();
            },
            (err) => {
                this.locationDenied = true;
                this.filters = { ...this.filters, radiusKm: null, latitude: null, longitude: null };
                this.locationStatus =
                    err.code === err.PERMISSION_DENIED
                        ? 'Location permission denied; the distance filter is disabled. Allow location access in your browser to use it.'
                        : `Could not determine your location (${err.message}).`;
                this.loadPage(1);
            },
            { enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 }
        );
    }

    get hasLocation() {
        return this.filters.latitude !== null && this.filters.longitude !== null;
    }

    get radiusDisabled() {
        return this.locationDenied;
    }

    // ---------- pagination ----------

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get pageSummary() {
        if (this.totalCount === 0) return 'No properties match the current filters.';
        const start = (this.pageNumber - 1) * 25 + 1;
        const end = Math.min(this.pageNumber * 25, this.totalCount);
        return `Showing ${start}-${end} of ${this.totalCount} properties · Page ${this.pageNumber} of ${this.totalPages}`;
    }

    previousPage() {
        if (!this.isFirstPage) this.loadPage(this.pageNumber - 1);
    }

    nextPage() {
        if (!this.isLastPage) this.loadPage(this.pageNumber + 1);
    }

    // ---------- map ----------

    toggleMap() {
        this.showMap = !this.showMap;
    }

    get mapMarkers() {
        const markers = this.rows
            .filter((r) => r.latitude !== null && r.latitude !== undefined && r.longitude !== null && r.longitude !== undefined)
            .map((r) => ({
                location: { Latitude: r.latitude, Longitude: r.longitude },
                title: r.name,
                description: `${r.city || ''} · ${r.status} · ${r.rent ?? ''}`,
                value: r.id
            }));
        if (this.hasLocation) {
            markers.unshift({
                location: { Latitude: this.filters.latitude, Longitude: this.filters.longitude },
                title: 'You are here',
                icon: 'utility:user'
            });
        }
        return markers;
    }

    get hasMarkers() {
        return this.mapMarkers.length > 0;
    }

    get mapToggleLabel() {
        return this.showMap ? 'Hide map' : 'Show map';
    }

    handleMarkerSelect(event) {
        const id = event.target.selectedMarkerValue;
        if (id) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: id, objectApiName: 'Property__c', actionName: 'view' }
            });
        }
    }

    // ---------- create ----------

    openCreateModal() {
        this.showCreateModal = true;
    }

    closeCreateModal() {
        this.showCreateModal = false;
    }

    handleCreated(event) {
        this.showCreateModal = false;
        this.loadPage(1);
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Property created',
                message: 'The new property appears in the list below.',
                variant: 'success'
            })
        );
        const recordId = event.detail?.recordId;
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId, objectApiName: 'Property__c', actionName: 'view' }
            });
        }
    }
}