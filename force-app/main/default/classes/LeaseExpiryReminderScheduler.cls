/**
 * @description Daily scheduler for LeaseExpiryReminderBatch. Schedule once with:
 *              LeaseExpiryReminderScheduler.scheduleDaily();
 */
public with sharing class LeaseExpiryReminderScheduler implements Schedulable {

    public static final String JOB_NAME = 'REMS Lease Expiry Reminders';
    /** Every day at 08:00 in the org's default time zone. */
    public static final String CRON_DAILY_8AM = '0 0 8 * * ?';
    /** Batch size of 50 keeps each execute() at or below 100 outbound emails. */
    public static final Integer BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LeaseExpiryReminderBatch(), BATCH_SIZE);
    }

    /**
     * @description Schedules the daily job (idempotent - aborts an existing job with the same name first).
     * @return CronTrigger Id
     */
    public static Id scheduleDaily() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME]) {
            System.abortJob(ct.Id);
        }
        return System.schedule(JOB_NAME, CRON_DAILY_8AM, new LeaseExpiryReminderScheduler());
    }
}