/**
 * @description Single trigger for Maintenance_Request__c. Logic delegated to MaintenanceRequestTriggerHandler.
 */
trigger MaintenanceRequestTrigger on Maintenance_Request__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        MaintenanceRequestTriggerHandler.beforeInsert(Trigger.new);
    }
}