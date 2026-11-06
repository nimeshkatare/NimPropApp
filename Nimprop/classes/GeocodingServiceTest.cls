@IsTest
private class GeocodingServiceTest {

    private static Geocoding_Setting__mdt settings() {
        return Geocoding_Setting__mdt.getInstance('Default');
    }

    @IsTest
    static void parsesSuccessfulResponse() {
        GeocodingService.GeocodeResult r = new GeocodingService.GeocodeResult();
        GeocodingService.parseNominatim('[{"lat":"12.97","lon":"77.59"}]', r);
        Assert.isTrue(r.success);
        Assert.areEqual(12.97, r.latitude);
        Assert.areEqual(77.59, r.longitude);
    }

    @IsTest
    static void parsesEmptyAndMalformedResponses() {
        GeocodingService.GeocodeResult r1 = new GeocodingService.GeocodeResult();
        GeocodingService.parseNominatim('[]', r1);
        Assert.isFalse(r1.success);
        Assert.areEqual('No results for address', r1.error);

        GeocodingService.GeocodeResult r2 = new GeocodingService.GeocodeResult();
        GeocodingService.parseNominatim('[{"display_name":"x"}]', r2);
        Assert.isFalse(r2.success);
        Assert.areEqual('Response missing lat/lon', r2.error);
    }

    @IsTest
    static void geocodeHandlesHttpError() {
        Test.setMock(HttpCalloutMock.class, GeocodingHttpMock.error(503));
        Test.startTest();
        GeocodingService.GeocodeResult r = GeocodingService.geocode('Nowhere', settings());
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.isTrue(r.error.startsWith('HTTP 503'), r.error);
    }

    @IsTest
    static void geocodeHandlesCalloutException() {
        GeocodingHttpMock mock = new GeocodingHttpMock();
        mock.throwException = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        GeocodingService.GeocodeResult r = GeocodingService.geocode('Nowhere', settings());
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.isTrue(r.error.contains('Simulated callout failure'), r.error);
    }

    @IsTest
    static void geocodeGuardsBlankAddressAndMissingSettings() {
        Assert.areEqual('Address is empty', GeocodingService.geocode('  ', settings()).error);
        Assert.isTrue(GeocodingService.geocode('x', null).error.contains('missing'));
    }

    @IsTest
    static void buildAddressSkipsBlankParts() {
        Property__c p = new Property__c(Street__c = ' 1 Main St ', City__c = 'Pune', State__c = null, Postal_Code__c = '', Country__c = 'India');
        Assert.areEqual('1 Main St, Pune, India', GeocodingService.buildAddress(p));
    }

    @IsTest
    static void enqueueIgnoresEmptyInput() {
        Assert.isNull(GeocodingService.enqueue(null));
        Assert.isNull(GeocodingService.enqueue(new Set<Id>()));
    }

    @IsTest
    static void executeMarksFailedWhenNoResults() {
        Test.setMock(HttpCalloutMock.class, GeocodingHttpMock.empty());
        Property__c p = REMS_TestDataFactory.createProperties(1, false, false)[0];

        Test.startTest();
        insert p;
        Test.stopTest();

        Property__c saved = [SELECT Geocoding_Status__c, Geocoding_Error__c, Location__Latitude__s FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual('Failed', saved.Geocoding_Status__c);
        Assert.areEqual('No results for address', saved.Geocoding_Error__c);
        Assert.isNull(saved.Location__Latitude__s);
    }

    @IsTest
    static void executeRespectsBatchSizeAndDoesNotChainInTests() {
        Integer batchSize = Integer.valueOf(settings().Batch_Size__c);
        PropertyTriggerHandler.bypassGeocoding = true;
        List<Property__c> props = REMS_TestDataFactory.createProperties(batchSize + 5, false, true);
        PropertyTriggerHandler.bypassGeocoding = false;

        GeocodingHttpMock mock = new GeocodingHttpMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GeocodingService.enqueue(new Map<Id, Property__c>(props).keySet());
        Test.stopTest();

        Assert.areEqual(batchSize, mock.callCount, 'Only one batch is processed per execution');
        Assert.areEqual(batchSize, [SELECT COUNT() FROM Property__c WHERE Geocoding_Status__c = 'Success']);
        Assert.areEqual(5, [SELECT COUNT() FROM Property__c WHERE Geocoding_Status__c = null]);
    }
}