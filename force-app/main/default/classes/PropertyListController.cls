/**
 * @description Server-side paginated, filterable Property search for the propertyExplorer LWC
 *              (REMS-PM-004/005/006). Every page turn issues a fresh SOQL query; nothing is cached
 *              client-side beyond the current page.
 */
public with sharing class PropertyListController {

    public static final Integer PAGE_SIZE = 25;
    /** SOQL OFFSET hard limit. */
    private static final Integer MAX_OFFSET = 2000;
    private static final Decimal EARTH_RADIUS_KM = 6371.0;

    /** Filter payload sent from the LWC as JSON. */
    public class Filters {
        @AuraEnabled public String searchText;
        @AuraEnabled public Decimal minRent;
        @AuraEnabled public Decimal maxRent;
        @AuraEnabled public String status;
        @AuraEnabled public String furnishing;
        @AuraEnabled public String propertyType;
        @AuraEnabled public Decimal radiusKm;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
    }

    public class PropertyRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String furnishing;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal rent;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Decimal distanceKm;
        @AuraEnabled public String tenantName;
    }

    public class PageResult {
        @AuraEnabled public List<PropertyRow> records = new List<PropertyRow>();
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Integer pageNumber = 1;
        @AuraEnabled public Integer pageSize = PAGE_SIZE;
        @AuraEnabled public Integer totalPages = 0;
    }

    /**
     * @description Returns one page of properties matching the filters.
     * @param filtersJson JSON-serialised Filters
     * @param pageNumber 1-based page number
     *
     * Deliberately NOT cacheable: REMS-PM-004 requires a server round-trip on every page turn.
     */
    @AuraEnabled
    public static PageResult search(String filtersJson, Integer pageNumber) {
        try {
            Filters f = String.isBlank(filtersJson) ? new Filters() : (Filters) JSON.deserialize(filtersJson, Filters.class);
            Integer page = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
            Integer offset = (page - 1) * PAGE_SIZE;
            if (offset > MAX_OFFSET) {
                throw new REMSException('Page ' + page + ' is beyond the maximum supported offset. Narrow your filters.');
            }

            Map<String, Object> binds = new Map<String, Object>();
            List<String> conditions = new List<String>();
            Boolean geoFilter = f.radiusKm != null && f.radiusKm > 0 && f.latitude != null && f.longitude != null;

            if (String.isNotBlank(f.searchText)) {
                binds.put('searchText', '%' + f.searchText.trim() + '%');
                conditions.add('(Name LIKE :searchText OR City__c LIKE :searchText OR Street__c LIKE :searchText)');
            }
            if (f.minRent != null) {
                binds.put('minRent', f.minRent);
                conditions.add('Rent__c >= :minRent');
            }
            if (f.maxRent != null) {
                binds.put('maxRent', f.maxRent);
                conditions.add('Rent__c <= :maxRent');
            }
            if (String.isNotBlank(f.status)) {
                binds.put('status', f.status);
                conditions.add('Status__c = :status');
            }
            if (String.isNotBlank(f.furnishing)) {
                binds.put('furnishing', f.furnishing);
                conditions.add('Furnishing_Status__c = :furnishing');
            }
            if (String.isNotBlank(f.propertyType)) {
                binds.put('propertyType', f.propertyType);
                conditions.add('Type__c = :propertyType');
            }

            String geoPoint;
            if (geoFilter) {
                // Numeric literals only - no user-supplied strings are concatenated.
                geoPoint = 'GEOLOCATION(' + f.latitude.setScale(6).toPlainString() + ',' + f.longitude.setScale(6).toPlainString() + ')';
                binds.put('radiusKm', f.radiusKm);
                conditions.add('DISTANCE(Location__c, ' + geoPoint + ', \'km\') < :radiusKm');
            }

            String whereClause = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
            String orderBy = geoFilter
                ? ' ORDER BY DISTANCE(Location__c, ' + geoPoint + ', \'km\') ASC'
                : ' ORDER BY Name ASC';

            String countSoql = 'SELECT COUNT() FROM Property__c' + whereClause;
            String dataSoql = 'SELECT Id, Name, Street__c, City__c, State__c, Type__c, Furnishing_Status__c, Status__c, Rent__c, '
                + 'Location__Latitude__s, Location__Longitude__s, Current_Tenant__r.Name '
                + 'FROM Property__c' + whereClause + orderBy
                + ' LIMIT ' + PAGE_SIZE + ' OFFSET ' + offset;

            PageResult result = new PageResult();
            result.pageNumber = page;
            result.totalCount = Database.countQueryWithBinds(countSoql, binds, AccessLevel.USER_MODE);
            result.totalPages = result.totalCount == 0 ? 0 : (Integer) Math.ceil((Decimal) result.totalCount / PAGE_SIZE);

            for (Property__c p : (List<Property__c>) Database.queryWithBinds(dataSoql, binds, AccessLevel.USER_MODE)) {
                PropertyRow row = new PropertyRow();
                row.id = p.Id;
                row.name = p.Name;
                row.street = p.Street__c;
                row.city = p.City__c;
                row.state = p.State__c;
                row.propertyType = p.Type__c;
                row.furnishing = p.Furnishing_Status__c;
                row.status = p.Status__c;
                row.rent = p.Rent__c;
                row.latitude = p.Location__Latitude__s;
                row.longitude = p.Location__Longitude__s;
                row.tenantName = p.Current_Tenant__r == null ? null : p.Current_Tenant__r.Name;
                if (geoFilter && row.latitude != null && row.longitude != null) {
                    row.distanceKm = haversineKm(f.latitude, f.longitude, row.latitude, row.longitude).setScale(1);
                }
                result.records.add(row);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Great-circle distance in km (used for display only; filtering is done in SOQL).
     */
    @TestVisible
    private static Decimal haversineKm(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double dLat = toRadians((Double) (lat2 - lat1));
        Double dLon = toRadians((Double) (lon2 - lon1));
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(toRadians((Double) lat1)) * Math.cos(toRadians((Double) lat2))
            * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_KM * c;
    }

    private static Double toRadians(Double degrees) {
        return degrees * Math.PI / 180;
    }
}