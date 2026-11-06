/**
 * @description Handler for PropertyTrigger.
 *  - REMS-TM-004: creates a "Generate lease agreement" Task when a Tenant is assigned to a Property.
 *  - REMS-PM-007: enqueues address geocoding when the address is created or changed.
 */
public with sharing class PropertyTriggerHandler {

    /** Set to true by GeocodingService while it writes coordinates back, so we do not re-enqueue. */
    public static Boolean bypassGeocoding = false;

    /** Guards against recursive execution within one transaction. */
    private static Boolean taskRunInProgress = false;

    public static void afterInsert(List<Property__c> newList) {
        createLeaseTasks(newList, null);
        enqueueGeocoding(newList, null);
    }

    public static void afterUpdate(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        createLeaseTasks(newList, oldMap);
        enqueueGeocoding(newList, oldMap);
    }

    /**
     * @description Creates one Task per property whose Current_Tenant__c was newly set or changed.
     */
    @TestVisible
    private static void createLeaseTasks(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        if (taskRunInProgress) {
            return;
        }
        List<Property__c> assigned = new List<Property__c>();
        Set<Id> tenantIds = new Set<Id>();
        for (Property__c p : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(p.Id);
            Boolean newlyAssigned = p.Current_Tenant__c != null
                && (old == null || old.Current_Tenant__c != p.Current_Tenant__c);
            if (newlyAssigned) {
                assigned.add(p);
                tenantIds.add(p.Current_Tenant__c);
            }
        }
        if (assigned.isEmpty()) {
            return;
        }
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new REMSException('Insufficient access to create Tasks.');
        }

        Map<Id, Tenant__c> tenants = new Map<Id, Tenant__c>(
            [SELECT Id, Name FROM Tenant__c WHERE Id IN :tenantIds]
        );

        List<Task> tasks = new List<Task>();
        for (Property__c p : assigned) {
            Tenant__c t = tenants.get(p.Current_Tenant__c);
            String tenantName = t == null ? 'the tenant' : t.Name;
            tasks.add(new Task(
                Subject = 'Generate lease agreement: ' + p.Name,
                Description = 'Property "' + p.Name + '" has been assigned to ' + tenantName
                    + '. Create the Lease Agreement record, then download and send the PDF to the tenant.',
                WhatId = p.Id,
                OwnerId = p.OwnerId,
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today().addDays(3)
            ));
        }
        taskRunInProgress = true;
        try {
            insert tasks;
        } finally {
            taskRunInProgress = false;
        }
    }

    /**
     * @description Collects properties whose address is new/changed and has no coordinates yet,
     *              then hands them to GeocodingService (one queueable per transaction).
     */
    @TestVisible
    private static void enqueueGeocoding(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        if (bypassGeocoding) {
            return;
        }
        Set<Id> toGeocode = new Set<Id>();
        for (Property__c p : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(p.Id);
            if (old == null) {
                // On insert, respect coordinates supplied by data loads / tests.
                if (p.Location__Latitude__s == null || p.Location__Longitude__s == null) {
                    toGeocode.add(p.Id);
                }
            } else if (addressChanged(p, old)) {
                toGeocode.add(p.Id);
            }
        }
        if (!toGeocode.isEmpty()) {
            GeocodingService.enqueue(toGeocode);
        }
    }

    @TestVisible
    private static Boolean addressChanged(Property__c p, Property__c old) {
        return p.Street__c != old.Street__c
            || p.City__c != old.City__c
            || p.State__c != old.State__c
            || p.Postal_Code__c != old.Postal_Code__c
            || p.Country__c != old.Country__c;
    }
}