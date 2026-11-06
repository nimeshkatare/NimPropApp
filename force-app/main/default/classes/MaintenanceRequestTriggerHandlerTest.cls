@IsTest
private class MaintenanceRequestTriggerHandlerTest {

    @TestSetup
    static void setup() {
        REMS_TestDataFactory.createProperties(2, true, true);
    }

    private static Id propertyId() {
        return [SELECT Id FROM Property__c LIMIT 1].Id;
    }

    @IsTest
    static void assignsVendorWithFewestActiveRequests() {
        Id propId = propertyId();
        Vendor__c busy = REMS_TestDataFactory.createVendor('Busy Vendor', true);
        Vendor__c idle = REMS_TestDataFactory.createVendor('Idle Vendor', true);
        Vendor__c medium = REMS_TestDataFactory.createVendor('Medium Vendor', true);
        insert new List<Maintenance_Request__c>{
            REMS_TestDataFactory.createRequest(propId, busy.Id, 'Open', false),
            REMS_TestDataFactory.createRequest(propId, busy.Id, 'In Progress', false),
            REMS_TestDataFactory.createRequest(propId, medium.Id, 'Open', false)
        };

        Test.startTest();
        Maintenance_Request__c mr = REMS_TestDataFactory.createRequest(propId, null, 'Open', true);
        Test.stopTest();

        Assert.areEqual(idle.Id, [SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :mr.Id].Vendor__c);
    }

    @IsTest
    static void completedAndCancelledDoNotCountAsWorkload() {
        Id propId = propertyId();
        Vendor__c a = REMS_TestDataFactory.createVendor('Alpha', true);
        Vendor__c b = REMS_TestDataFactory.createVendor('Beta', true);
        insert new List<Maintenance_Request__c>{
            REMS_TestDataFactory.createRequest(propId, a.Id, 'Completed', false),
            REMS_TestDataFactory.createRequest(propId, a.Id, 'Completed', false),
            REMS_TestDataFactory.createRequest(propId, a.Id, 'Cancelled', false),
            REMS_TestDataFactory.createRequest(propId, b.Id, 'Open', false)
        };

        Maintenance_Request__c mr = REMS_TestDataFactory.createRequest(propId, null, 'Open', true);

        Assert.areEqual(a.Id, [SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :mr.Id].Vendor__c,
            'Alpha has zero active requests and must win');
    }

    @IsTest
    static void tieBrokenByVendorName() {
        Id propId = propertyId();
        REMS_TestDataFactory.createVendor('Zulu Services', true);
        Vendor__c alpha = REMS_TestDataFactory.createVendor('Alpha Services', true);
        REMS_TestDataFactory.createVendor('Mike Services', true);

        Maintenance_Request__c mr = REMS_TestDataFactory.createRequest(propId, null, 'Open', true);

        Assert.areEqual(alpha.Id, [SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :mr.Id].Vendor__c);
    }

    @IsTest
    static void bulkInsertSpreadsLoadEvenly() {
        Id propId = propertyId();
        List<Vendor__c> vendors = new List<Vendor__c>{
            REMS_TestDataFactory.createVendor('V1', false),
            REMS_TestDataFactory.createVendor('V2', false),
            REMS_TestDataFactory.createVendor('V3', false)
        };
        insert vendors;
        List<Maintenance_Request__c> requests = new List<Maintenance_Request__c>();
        for (Integer i = 0; i < 150; i++) {
            requests.add(REMS_TestDataFactory.createRequest(propId, null, 'Open', false));
        }

        Test.startTest();
        insert requests;
        Test.stopTest();

        for (AggregateResult ar : [SELECT Vendor__c v, COUNT(Id) c FROM Maintenance_Request__c GROUP BY Vendor__c]) {
            Assert.areEqual(50, (Integer) ar.get('c'), 'Each vendor should receive an equal share');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Maintenance_Request__c WHERE Vendor__c = null]);
    }

    @IsTest
    static void leavesVendorBlankWhenNoVendorsExist() {
        Maintenance_Request__c mr = REMS_TestDataFactory.createRequest(propertyId(), null, 'Open', true);
        Assert.isNull([SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :mr.Id].Vendor__c);
    }

    @IsTest
    static void respectsPreassignedVendor() {
        Id propId = propertyId();
        Vendor__c chosen = REMS_TestDataFactory.createVendor('Chosen', true);
        REMS_TestDataFactory.createVendor('Alpha Idle', true);

        Maintenance_Request__c mr = REMS_TestDataFactory.createRequest(propId, chosen.Id, 'Open', true);

        Assert.areEqual(chosen.Id, [SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :mr.Id].Vendor__c);
    }
}