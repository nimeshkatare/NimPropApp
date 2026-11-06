/**
 * @description Single trigger for Property__c. All logic is delegated to PropertyTriggerHandler.
 */
trigger PropertyTrigger on Property__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PropertyTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PropertyTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}