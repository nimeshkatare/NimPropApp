@IsTest
private class PropertyListControllerTest {

    @TestSetup
    static void setup() {
        // 30 properties, 1 km apart heading north from BASE_LAT/BASE_LNG.
        REMS_TestDataFactory.createProperties(30, true, true);
    }

    private static String filters(Map<String, Object> values) {
        return JSON.serialize(values);
    }

    @IsTest
    static void paginatesServerSideAt25PerPage() {
        PropertyListController.PageResult page1 = PropertyListController.search(null, 1);
        PropertyListController.PageResult page2 = PropertyListController.search(null, 2);

        Assert.areEqual(30, page1.totalCount);
        Assert.areEqual(2, page1.totalPages);
        Assert.areEqual(25, page1.records.size());
        Assert.areEqual(25, page1.pageSize);
        Assert.areEqual(5, page2.records.size());
        Assert.areEqual('Test Property 0000', page1.records[0].name, 'Default sort by Name');
        Assert.areEqual('Test Property 0025', page2.records[0].name);
    }

    @IsTest
    static void invalidPageNumbersDefaultToFirstPage() {
        Assert.areEqual(1, PropertyListController.search('', null).pageNumber);
        Assert.areEqual(1, PropertyListController.search('{}', 0).pageNumber);
    }

    @IsTest
    static void filtersByStatusFurnishingTypeAndRent() {
        PropertyListController.PageResult occupied = PropertyListController.search(filters(new Map<String, Object>{ 'status' => 'Occupied' }), 1);
        Assert.areEqual(15, occupied.totalCount);
        for (PropertyListController.PropertyRow r : occupied.records) {
            Assert.areEqual('Occupied', r.status);
        }

        PropertyListController.PageResult furnished = PropertyListController.search(filters(new Map<String, Object>{ 'furnishing' => 'Furnished' }), 1);
        Assert.areEqual(10, furnished.totalCount);

        PropertyListController.PageResult commercial = PropertyListController.search(filters(new Map<String, Object>{ 'propertyType' => 'Commercial' }), 1);
        Assert.areEqual(15, commercial.totalCount);

        // Rent = 10000 + i*1000 -> 12000..15000 inclusive is i = 2..5 => 4 records
        PropertyListController.PageResult rent = PropertyListController.search(filters(new Map<String, Object>{ 'minRent' => 12000, 'maxRent' => 15000 }), 1);
        Assert.areEqual(4, rent.totalCount);

        // Combined: Occupied (odd i) AND Furnished (i % 3 == 0) => i in {3,9,15,21,27} => 5
        PropertyListController.PageResult combined = PropertyListController.search(filters(new Map<String, Object>{ 'status' => 'Occupied', 'furnishing' => 'Furnished' }), 1);
        Assert.areEqual(5, combined.totalCount);
    }

    @IsTest
    static void filtersBySearchText() {
        PropertyListController.PageResult r = PropertyListController.search(filters(new Map<String, Object>{ 'searchText' => 'Property 0007' }), 1);
        Assert.areEqual(1, r.totalCount);
        Assert.areEqual('Test Property 0007', r.records[0].name);
    }

    @IsTest
    static void filtersByDistanceAndOrdersNearestFirst() {
        // Properties sit at 0,1,2,...29 km north of the base point. Radius 5.5 km => 6 records (0..5 km).
        String f = filters(new Map<String, Object>{
            'radiusKm' => 5.5,
            'latitude' => REMS_TestDataFactory.BASE_LAT,
            'longitude' => REMS_TestDataFactory.BASE_LNG
        });
        PropertyListController.PageResult r = PropertyListController.search(f, 1);

        Assert.areEqual(6, r.totalCount, 'Six properties lie within 5.5 km');
        Assert.areEqual('Test Property 0000', r.records[0].name, 'Nearest first');
        Assert.areEqual(0, r.records[0].distanceKm);
        Decimal previous = -1;
        for (PropertyListController.PropertyRow row : r.records) {
            Assert.isNotNull(row.distanceKm);
            Assert.isTrue(row.distanceKm >= previous, 'Results must be sorted by distance');
            Assert.isTrue(row.distanceKm <= 5.5, 'Every result must be inside the radius');
            previous = row.distanceKm;
        }
    }

    @IsTest
    static void rejectsPagesBeyondOffsetLimit() {
        try {
            PropertyListController.search(null, 500);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void haversineMatchesKnownDistance() {
        // Bengaluru -> Chennai is roughly 290 km.
        Decimal d = PropertyListController.haversineKm(12.9716, 77.5946, 13.0827, 80.2707);
        Assert.isTrue(d > 280 && d < 300, 'Got ' + d);
        Assert.areEqual(0, PropertyListController.haversineKm(1, 1, 1, 1).setScale(3));
    }
}