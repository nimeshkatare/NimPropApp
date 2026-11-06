@IsTest
private class LeaseExpiryReminderBatchTest {

    private static final Date RUN_DATE = Date.newInstance(2026, 1, 15);

    @TestSetup
    static void setup() {
        List<Property__c> props = REMS_TestDataFactory.createProperties(6, true, true);
        Tenant__c t = REMS_TestDataFactory.createTenant('Reminder Tenant', true);
        Date start = Date.newInstance(2025, 1, 1);
        insert new List<Lease_Agreement__c>{
            // +30 days  -> 30-day reminder
            REMS_TestDataFactory.createLease(props[0].Id, t.Id, start, RUN_DATE.addDays(30), false),
            // +1 calendar month (Feb 15) -> 30-day reminder (month-length edge case)
            REMS_TestDataFactory.createLease(props[1].Id, t.Id, start, RUN_DATE.addMonths(1), false),
            // tomorrow -> 1-day reminder
            REMS_TestDataFactory.createLease(props[2].Id, t.Id, start, RUN_DATE.addDays(1), false),
            // far future -> nothing
            REMS_TestDataFactory.createLease(props[3].Id, t.Id, start, RUN_DATE.addDays(90), false),
            // already reminded -> nothing
            REMS_TestDataFactory.createLease(props[4].Id, t.Id, start, RUN_DATE.addDays(30), false),
            // yesterday (expired) -> nothing
            REMS_TestDataFactory.createLease(props[5].Id, t.Id, start, RUN_DATE.addDays(-1), false)
        };
        Lease_Agreement__c already = [SELECT Id FROM Lease_Agreement__c WHERE Property__c = :props[4].Id];
        already.Reminder_30_Day_Sent__c = true;
        update already;
    }

    @IsTest
    static void sendsCorrectRemindersAndFlagsLeases() {
        Test.startTest();
        LeaseExpiryReminderBatch batch = new LeaseExpiryReminderBatch(RUN_DATE);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        Map<Date, Lease_Agreement__c> byEnd = new Map<Date, Lease_Agreement__c>();
        for (Lease_Agreement__c la : [SELECT End_Date__c, Reminder_30_Day_Sent__c, Reminder_1_Day_Sent__c FROM Lease_Agreement__c]) {
            byEnd.put(la.End_Date__c, la);
        }
        Assert.isTrue(byEnd.get(RUN_DATE.addDays(30)).Reminder_30_Day_Sent__c, '+30 days lease flagged');
        Assert.isTrue(byEnd.get(RUN_DATE.addMonths(1)).Reminder_30_Day_Sent__c, '+1 month lease flagged');
        Assert.isTrue(byEnd.get(RUN_DATE.addDays(1)).Reminder_1_Day_Sent__c, 'tomorrow lease flagged');
        Assert.isFalse(byEnd.get(RUN_DATE.addDays(1)).Reminder_30_Day_Sent__c);
        Assert.isFalse(byEnd.get(RUN_DATE.addDays(90)).Reminder_30_Day_Sent__c);
        Assert.isFalse(byEnd.get(RUN_DATE.addDays(90)).Reminder_1_Day_Sent__c);
        Assert.isFalse(byEnd.get(RUN_DATE.addDays(-1)).Reminder_1_Day_Sent__c);
    }

    @IsTest
    static void rerunDoesNotSendDuplicates() {
        Test.startTest();
        Database.executeBatch(new LeaseExpiryReminderBatch(RUN_DATE), 50);
        Test.stopTest();
        // Everything due has been flagged; a second start() must select nothing.
        Database.QueryLocator ql = new LeaseExpiryReminderBatch(RUN_DATE).start(null);
        Database.QueryLocatorIterator it = ql.iterator();
        Assert.isFalse(it.hasNext(), 'No leases should be due after the first run');
    }

    @IsTest
    static void monthEndEdgeCaseUsesCalendarMonth() {
        // Jan 31 + 1 month = Feb 28 (2026 is not a leap year); Jan 31 + 30 days = Mar 2.
        Date jan31 = Date.newInstance(2026, 1, 31);
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        Tenant__c t = [SELECT Id FROM Tenant__c LIMIT 1];
        Lease_Agreement__c feb28 = REMS_TestDataFactory.createLease(p.Id, t.Id, Date.newInstance(2025, 1, 1), Date.newInstance(2026, 2, 28), true);

        Test.startTest();
        Database.executeBatch(new LeaseExpiryReminderBatch(jan31), 50);
        Test.stopTest();

        Assert.isTrue([SELECT Reminder_30_Day_Sent__c FROM Lease_Agreement__c WHERE Id = :feb28.Id].Reminder_30_Day_Sent__c);
    }

    @IsTest
    static void buildReminderProducesBothVariants() {
        Lease_Agreement__c la = [
            SELECT Id, Name, End_Date__c, Tenant__r.Name, Tenant__r.Email__c, Property__r.Name, Property__r.Street__c, Property__r.City__c
            FROM Lease_Agreement__c LIMIT 1
        ];
        Messaging.SingleEmailMessage m30 = LeaseExpiryReminderBatch.buildReminder(la, LeaseExpiryReminderBatch.TYPE_30_DAY);
        Messaging.SingleEmailMessage m1 = LeaseExpiryReminderBatch.buildReminder(la, LeaseExpiryReminderBatch.TYPE_1_DAY);
        Assert.isTrue(m30.getSubject().contains('30 days'));
        Assert.isTrue(m1.getSubject().contains('tomorrow'));
        Assert.areEqual(la.Tenant__r.Email__c, m30.getToAddresses()[0]);
        Assert.isTrue(m30.getHtmlBody().contains(la.Name));
    }

    @IsTest
    static void schedulerRegistersDailyJob() {
        Test.startTest();
        Id cronId = LeaseExpiryReminderScheduler.scheduleDaily();
        // Calling again must replace, not duplicate.
        Id cronId2 = LeaseExpiryReminderScheduler.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id, CronExpression FROM CronTrigger WHERE CronJobDetail.Name = :LeaseExpiryReminderScheduler.JOB_NAME];
        Assert.areEqual(1, jobs.size());
        Assert.areEqual(cronId2, jobs[0].Id);
        Assert.areEqual(LeaseExpiryReminderScheduler.CRON_DAILY_8AM, jobs[0].CronExpression);
        Assert.areNotEqual(cronId, cronId2);
    }

    @IsTest
    static void schedulerExecuteLaunchesBatch() {
        Test.startTest();
        new LeaseExpiryReminderScheduler().execute(null);
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'LeaseExpiryReminderBatch' AND JobType = 'BatchApex']);
    }
}