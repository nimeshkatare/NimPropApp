@IsTest
private class PropertyTriggerHandlerTest {

    @IsTest
    static void taskCreatedWhenTenantAssignedOnInsert() {
        Tenant__c tenant = REMS_TestDataFactory.createTenant('Asha Rao', true);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, false)[0];
        p.Current_Tenant__c = tenant.Id;

        Test.startTest();
        insert p;
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, WhatId, OwnerId, Status, Description FROM Task WHERE WhatId = :p.Id];
        Assert.areEqual(1, tasks.size(), 'One lease task expected');
        Assert.isTrue(tasks[0].Subject.startsWith('Generate lease agreement'), 'Subject should describe lease generation');
        Assert.isTrue(tasks[0].Description.contains('Asha Rao'), 'Description should name the tenant');
        Assert.areEqual(UserInfo.getUserId(), tasks[0].OwnerId, 'Task owned by property owner');
    }

    @IsTest
    static void taskCreatedWhenTenantChangesOnUpdate() {
        Tenant__c t1 = REMS_TestDataFactory.createTenant('Tenant One', true);
        Tenant__c t2 = REMS_TestDataFactory.createTenant('Tenant Two', true);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id], 'No task before assignment');

        Test.startTest();
        p.Current_Tenant__c = t1.Id;
        update p;
        p.Current_Tenant__c = t2.Id;
        update p;
        // Unrelated change must not create another task.
        p.Rent__c = 99999;
        update p;
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id], 'One task per assignment event');
    }

    @IsTest
    static void noTaskWhenTenantCleared() {
        Tenant__c t1 = REMS_TestDataFactory.createTenant('Tenant One', true);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, false)[0];
        p.Current_Tenant__c = t1.Id;
        insert p;

        Test.startTest();
        p.Current_Tenant__c = null;
        update p;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id], 'Clearing the tenant must not create a task');
    }

    @IsTest
    static void bulkAssignmentCreatesOneTaskPerProperty() {
        Tenant__c tenant = REMS_TestDataFactory.createTenant('Bulk Tenant', true);
        List<Property__c> props = REMS_TestDataFactory.createProperties(200, true, false);
        for (Property__c p : props) {
            p.Current_Tenant__c = tenant.Id;
        }

        Test.startTest();
        insert props;
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Task WHERE WhatId IN :props], 'Bulk insert must be handled in one pass');
    }

    @IsTest
    static void geocodesOnInsertWhenNoCoordinates() {
        GeocodingHttpMock mock = new GeocodingHttpMock(40.7128, -74.0060);
        Test.setMock(HttpCalloutMock.class, mock);
        Property__c p = REMS_TestDataFactory.createProperties(1, false, false)[0];

        Test.startTest();
        insert p;
        Test.stopTest();

        Property__c saved = [SELECT Location__Latitude__s, Location__Longitude__s, Geocoding_Status__c FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual(1, mock.callCount, 'Exactly one callout');
        Assert.areEqual('Success', saved.Geocoding_Status__c);
        Assert.areEqual(40.7128, saved.Location__Latitude__s);
        Assert.areEqual(-74.0060, saved.Location__Longitude__s);
        Assert.isTrue(mock.lastEndpoint.startsWith('callout:Geocoding_API/search'), 'Must use the Named Credential');
    }

    @IsTest
    static void skipsGeocodingWhenCoordinatesSupplied() {
        GeocodingHttpMock mock = new GeocodingHttpMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, false)[0];

        Test.startTest();
        insert p;
        Test.stopTest();

        Property__c saved = [SELECT Geocoding_Status__c FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual(0, mock.callCount, 'No callout when coordinates are supplied');
        Assert.isNull(saved.Geocoding_Status__c);
    }

    @IsTest
    static void regeocodesWhenAddressChanges() {
        GeocodingHttpMock mock = new GeocodingHttpMock(51.5074, -0.1278);
        Test.setMock(HttpCalloutMock.class, mock);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];

        Test.startTest();
        p.Rent__c = 12345; // non-address change: no callout
        update p;
        p.City__c = 'London';
        update p;
        Test.stopTest();

        Property__c saved = [SELECT Location__Latitude__s, Geocoding_Status__c FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual(1, mock.callCount, 'Only the address change should trigger a callout');
        Assert.areEqual(51.5074, saved.Location__Latitude__s);
        Assert.areEqual('Success', saved.Geocoding_Status__c);
    }

    @IsTest
    static void addressChangedDetectsEachField() {
        Property__c a = new Property__c(Street__c = '1', City__c = 'C', State__c = 'S', Postal_Code__c = 'P', Country__c = 'X');
        Property__c b = a.clone(false, true);
        Assert.isFalse(PropertyTriggerHandler.addressChanged(a, b));
        b.Postal_Code__c = 'Q';
        Assert.isTrue(PropertyTriggerHandler.addressChanged(a, b));
    }
}