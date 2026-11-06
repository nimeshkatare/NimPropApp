/**
 * @description REMS-PM-007. Geocodes Property addresses asynchronously via the Named Credential
 *              configured in Geocoding_Setting__mdt. Processes Batch_Size__c properties per execution
 *              and chains itself for the remainder so callout limits are respected under bulk load.
 *
 *              The endpoint host is never hardcoded: it lives in the Named Credential, and the
 *              provider-specific path / headers live in protected Custom Metadata.
 */
public with sharing class GeocodingService implements Queueable, Database.AllowsCallouts {

    private static final String STATUS_SUCCESS = 'Success';
    private static final String STATUS_FAILED  = 'Failed';
    private static final Integer DEFAULT_BATCH = 20;

    private List<Id> propertyIds;

    public GeocodingService(List<Id> propertyIds) {
        this.propertyIds = propertyIds;
    }

    /**
     * @description Enqueues a geocoding job for the given property Ids, if geocoding is active
     *              and a queueable slot is available in this transaction.
     * @return the AsyncApexJob Id, or null if nothing was enqueued
     */
    public static Id enqueue(Set<Id> propertyIds) {
        if (propertyIds == null || propertyIds.isEmpty()) {
            return null;
        }
        Geocoding_Setting__mdt settings = getSettings();
        if (settings == null || !settings.Active__c) {
            return null;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return null;
        }
        return System.enqueueJob(new GeocodingService(new List<Id>(propertyIds)));
    }

    public void execute(QueueableContext context) {
        Geocoding_Setting__mdt settings = getSettings();
        Integer batchSize = (settings == null || settings.Batch_Size__c == null)
            ? DEFAULT_BATCH : Integer.valueOf(settings.Batch_Size__c);

        List<Id> current = new List<Id>();
        List<Id> remainder = new List<Id>();
        for (Integer i = 0; i < propertyIds.size(); i++) {
            if (i < batchSize) {
                current.add(propertyIds[i]);
            } else {
                remainder.add(propertyIds[i]);
            }
        }

        List<Property__c> properties = [
            SELECT Id, Street__c, City__c, State__c, Postal_Code__c, Country__c
            FROM Property__c
            WHERE Id IN :current
        ];

        List<Property__c> updates = new List<Property__c>();
        for (Property__c p : properties) {
            GeocodeResult result = geocode(buildAddress(p), settings);
            Property__c u = new Property__c(Id = p.Id);
            if (result.success) {
                u.Location__Latitude__s = result.latitude;
                u.Location__Longitude__s = result.longitude;
                u.Geocoding_Status__c = STATUS_SUCCESS;
                u.Geocoding_Error__c = null;
            } else {
                u.Geocoding_Status__c = STATUS_FAILED;
                u.Geocoding_Error__c = result.error == null ? 'Unknown error' : result.error.abbreviate(255);
            }
            updates.add(u);
        }

        if (!updates.isEmpty()) {
            PropertyTriggerHandler.bypassGeocoding = true;
            try {
                Database.update(updates, false);
            } finally {
                PropertyTriggerHandler.bypassGeocoding = false;
            }
        }

        // Chaining is not permitted inside Apex tests.
        if (!remainder.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeocodingService(remainder));
        }
    }

    /**
     * @description Performs a single geocoding callout.
     */
    public static GeocodeResult geocode(String address, Geocoding_Setting__mdt settings) {
        GeocodeResult result = new GeocodeResult();
        if (String.isBlank(address)) {
            result.error = 'Address is empty';
            return result;
        }
        if (settings == null) {
            result.error = 'Geocoding_Setting__mdt.Default record is missing';
            return result;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + settings.Named_Credential__c + settings.Search_Path__c
                + EncodingUtil.urlEncode(address, 'UTF-8'));
            req.setMethod('GET');
            req.setTimeout(20000);
            req.setHeader('Accept', 'application/json');
            if (String.isNotBlank(settings.User_Agent__c)) {
                req.setHeader('User-Agent', settings.User_Agent__c);
            }
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                result.error = 'HTTP ' + res.getStatusCode() + ': ' + res.getStatus();
                return result;
            }
            parseNominatim(res.getBody(), result);
        } catch (Exception e) {
            result.error = e.getTypeName() + ': ' + e.getMessage();
        }
        return result;
    }

    /**
     * @description Parses a Nominatim-style JSON array response: [{"lat":"..","lon":".."}].
     */
    @TestVisible
    private static void parseNominatim(String body, GeocodeResult result) {
        Object parsed = JSON.deserializeUntyped(body);
        if (!(parsed instanceof List<Object>) || ((List<Object>) parsed).isEmpty()) {
            result.error = 'No results for address';
            return;
        }
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) parsed)[0];
        Object lat = first.get('lat');
        Object lon = first.get('lon');
        if (lat == null || lon == null) {
            result.error = 'Response missing lat/lon';
            return;
        }
        result.latitude = Decimal.valueOf(String.valueOf(lat));
        result.longitude = Decimal.valueOf(String.valueOf(lon));
        result.success = true;
    }

    @TestVisible
    private static String buildAddress(Property__c p) {
        List<String> parts = new List<String>();
        for (String s : new List<String>{ p.Street__c, p.City__c, p.State__c, p.Postal_Code__c, p.Country__c }) {
            if (String.isNotBlank(s)) {
                parts.add(s.trim());
            }
        }
        return String.join(parts, ', ');
    }

    @TestVisible
    private static Geocoding_Setting__mdt getSettings() {
        return Geocoding_Setting__mdt.getInstance('Default');
    }

    /** Result of one geocoding attempt. */
    public class GeocodeResult {
        public Boolean success = false;
        public Decimal latitude;
        public Decimal longitude;
        public String error;
    }
}