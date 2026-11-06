/**
 * @description Test data builders for the REMS test classes.
 */
@IsTest
public class REMS_TestDataFactory {

    /** Reference point used for geo tests: Bengaluru city centre. */
    public static final Decimal BASE_LAT = 12.971600;
    public static final Decimal BASE_LNG = 77.594600;

    public static Tenant__c createTenant(String name, Boolean doInsert) {
        Tenant__c t = new Tenant__c(Name = name, Phone__c = '+91 98765 43210', Email__c = name.deleteWhitespace().toLowerCase() + '@example.com');
        if (doInsert) {
            insert t;
        }
        return t;
    }

    public static Vendor__c createVendor(String name, Boolean doInsert) {
        Vendor__c v = new Vendor__c(Name = name, Phone__c = '+91 91234 56789', Email__c = name.deleteWhitespace().toLowerCase() + '@vendor.example.com');
        if (doInsert) {
            insert v;
        }
        return v;
    }

    /**
     * @description Builds count properties. When withCoordinates is true each property is placed
     *              roughly i*1 km north of BASE_LAT/BASE_LNG so distance filters are predictable
     *              (0.009 degrees latitude is about 1 km). Properties with coordinates skip geocoding.
     */
    public static List<Property__c> createProperties(Integer count, Boolean withCoordinates, Boolean doInsert) {
        List<Property__c> props = new List<Property__c>();
        for (Integer i = 0; i < count; i++) {
            Property__c p = new Property__c(
                Name = 'Test Property ' + String.valueOf(i).leftPad(4, '0'),
                Street__c = (100 + i) + ' MG Road',
                City__c = 'Bengaluru',
                State__c = 'Karnataka',
                Postal_Code__c = '560001',
                Country__c = 'India',
                Type__c = Math.mod(i, 2) == 0 ? 'Residential' : 'Commercial',
                Furnishing_Status__c = Math.mod(i, 3) == 0 ? 'Furnished' : (Math.mod(i, 3) == 1 ? 'Semi-Furnished' : 'Unfurnished'),
                Status__c = Math.mod(i, 2) == 0 ? 'Available' : 'Occupied',
                Rent__c = 10000 + (i * 1000),
                Description__c = 'Test property number ' + i
            );
            if (withCoordinates) {
                p.Location__Latitude__s = BASE_LAT + (0.009 * i);
                p.Location__Longitude__s = BASE_LNG;
            }
            props.add(p);
        }
        if (doInsert) {
            insert props;
        }
        return props;
    }

    public static Lease_Agreement__c createLease(Id propertyId, Id tenantId, Date startDate, Date endDate, Boolean doInsert) {
        Lease_Agreement__c la = new Lease_Agreement__c(
            Property__c = propertyId,
            Tenant__c = tenantId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Agreed_Monthly_Rent__c = 25000,
            Terms__c = 'Standard residential terms. Rent due on the 1st of each month.'
        );
        if (doInsert) {
            insert la;
        }
        return la;
    }

    public static Maintenance_Request__c createRequest(Id propertyId, Id vendorId, String status, Boolean doInsert) {
        Maintenance_Request__c mr = new Maintenance_Request__c(
            Property__c = propertyId,
            Vendor__c = vendorId,
            Status__c = status,
            Description__c = 'Test maintenance request'
        );
        if (doInsert) {
            insert mr;
        }
        return mr;
    }
}