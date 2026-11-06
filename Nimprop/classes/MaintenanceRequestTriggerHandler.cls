/**
 * @description Handler for MaintenanceRequestTrigger.
 *  REMS-MR-002: on insert, assigns each request without a Vendor to the vendor with the fewest
 *  Open / In Progress requests. Ties are broken by Vendor Name (then Id) for determinism.
 *
 *  Runs without sharing on purpose: workload must be computed across ALL requests in the org,
 *  not just those visible to the inserting user, otherwise assignments would be skewed.
 */
public without sharing class MaintenanceRequestTriggerHandler {

    private static final Set<String> ACTIVE_STATUSES = new Set<String>{ 'Open', 'In Progress' };

    public static void beforeInsert(List<Maintenance_Request__c> newList) {
        assignLeastLoadedVendor(newList);
    }

    @TestVisible
    private static void assignLeastLoadedVendor(List<Maintenance_Request__c> newList) {
        List<Maintenance_Request__c> unassigned = new List<Maintenance_Request__c>();
        for (Maintenance_Request__c mr : newList) {
            if (mr.Vendor__c == null) {
                unassigned.add(mr);
            }
        }
        if (unassigned.isEmpty()) {
            return;
        }

        List<Vendor__c> vendors = [SELECT Id, Name FROM Vendor__c ORDER BY Name ASC, Id ASC];
        if (vendors.isEmpty()) {
            return; // No vendors to assign; Vendor__c stays blank.
        }

        Map<Id, Integer> workload = new Map<Id, Integer>();
        for (Vendor__c v : vendors) {
            workload.put(v.Id, 0);
        }
        for (AggregateResult ar : [
            SELECT Vendor__c vendorId, COUNT(Id) total
            FROM Maintenance_Request__c
            WHERE Vendor__c != null AND Status__c IN :ACTIVE_STATUSES
            GROUP BY Vendor__c
        ]) {
            workload.put((Id) ar.get('vendorId'), (Integer) ar.get('total'));
        }

        // Greedy assignment; the in-memory workload is incremented so a bulk insert spreads evenly.
        for (Maintenance_Request__c mr : unassigned) {
            Vendor__c best;
            Integer bestLoad;
            for (Vendor__c v : vendors) {
                Integer load = workload.get(v.Id);
                if (best == null || load < bestLoad) {
                    best = v;
                    bestLoad = load;
                }
            }
            mr.Vendor__c = best.Id;
            if (mr.Status__c == null || ACTIVE_STATUSES.contains(mr.Status__c)) {
                workload.put(best.Id, bestLoad + 1);
            }
        }
    }
}