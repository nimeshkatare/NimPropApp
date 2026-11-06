/**
 * @description REMS-LA-005/006. Sends the 30-day and 1-day lease expiry reminders to tenants.
 *
 *  Runs daily via LeaseExpiryReminderScheduler. A lease qualifies for the 30-day reminder when
 *  End_Date__c equals today+30 days OR today+1 calendar month (covers short/long month edge cases),
 *  and for the 1-day reminder when End_Date__c equals tomorrow. Per-lease checkboxes prevent
 *  duplicate sends if the job is re-run.
 */
public with sharing class LeaseExpiryReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final String TYPE_30_DAY = '30';
    public static final String TYPE_1_DAY  = '1';

    public Integer sent30Day = 0;
    public Integer sent1Day = 0;
    public Integer failures = 0;

    private final Date runDate;

    public LeaseExpiryReminderBatch() {
        this(Date.today());
    }

    /** @param runDate the "today" used for window calculation - injectable for tests */
    public LeaseExpiryReminderBatch(Date runDate) {
        this.runDate = runDate;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date in30Days = runDate.addDays(30);
        Date inOneMonth = runDate.addMonths(1);
        Date tomorrow = runDate.addDays(1);
        return Database.getQueryLocator([
            SELECT Id, Name, Start_Date__c, End_Date__c, Agreed_Monthly_Rent__c,
                   Reminder_30_Day_Sent__c, Reminder_1_Day_Sent__c,
                   Tenant__r.Name, Tenant__r.Email__c,
                   Property__r.Name, Property__r.Street__c, Property__r.City__c
            FROM Lease_Agreement__c
            WHERE ((End_Date__c = :in30Days OR End_Date__c = :inOneMonth) AND Reminder_30_Day_Sent__c = false)
               OR (End_Date__c = :tomorrow AND Reminder_1_Day_Sent__c = false)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lease_Agreement__c> scope) {
        Date in30Days = runDate.addDays(30);
        Date inOneMonth = runDate.addMonths(1);
        Date tomorrow = runDate.addDays(1);

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<Lease_Agreement__c> mailLease = new List<Lease_Agreement__c>();
        List<String> mailType = new List<String>();

        for (Lease_Agreement__c la : scope) {
            if (String.isBlank(la.Tenant__r?.Email__c)) {
                failures++;
                continue;
            }
            Boolean due30 = !la.Reminder_30_Day_Sent__c && (la.End_Date__c == in30Days || la.End_Date__c == inOneMonth);
            Boolean due1 = !la.Reminder_1_Day_Sent__c && la.End_Date__c == tomorrow;
            if (due30) {
                mails.add(buildReminder(la, TYPE_30_DAY));
                mailLease.add(la);
                mailType.add(TYPE_30_DAY);
            }
            if (due1) {
                mails.add(buildReminder(la, TYPE_1_DAY));
                mailLease.add(la);
                mailType.add(TYPE_1_DAY);
            }
        }
        if (mails.isEmpty()) {
            return;
        }

        Map<Id, Lease_Agreement__c> updates = new Map<Id, Lease_Agreement__c>();
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(mails, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failures++;
                continue;
            }
            Id leaseId = mailLease[i].Id;
            Lease_Agreement__c u = updates.containsKey(leaseId) ? updates.get(leaseId) : new Lease_Agreement__c(Id = leaseId);
            if (mailType[i] == TYPE_30_DAY) {
                u.Reminder_30_Day_Sent__c = true;
                sent30Day++;
            } else {
                u.Reminder_1_Day_Sent__c = true;
                sent1Day++;
            }
            updates.put(leaseId, u);
        }
        if (!updates.isEmpty()) {
            Database.update(updates.values(), false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'LeaseExpiryReminderBatch finished. 30-day: ' + sent30Day
            + ', 1-day: ' + sent1Day + ', failures: ' + failures);
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildReminder(Lease_Agreement__c la, String type) {
        Boolean is30 = type == TYPE_30_DAY;
        Messaging.SingleEmailMessage mail = REMS_EmailUtil.newMessage();
        mail.setToAddresses(new List<String>{ la.Tenant__r.Email__c });
        mail.setSubject((is30 ? 'Your lease expires in 30 days - ' : 'Your lease expires tomorrow - ') + la.Property__r.Name);
        mail.setHtmlBody(
            '<p>Dear ' + la.Tenant__r.Name.escapeHtml4() + ',</p>'
            + '<p>This is a reminder that your lease agreement <b>' + la.Name + '</b> for '
            + '<b>' + la.Property__r.Name.escapeHtml4() + '</b>'
            + (String.isBlank(la.Property__r.Street__c) ? '' : ' (' + la.Property__r.Street__c.escapeHtml4() + ', ' + String.valueOf(la.Property__r.City__c).escapeHtml4() + ')')
            + ' will end on <b>' + REMS_EmailUtil.formatDate(la.End_Date__c) + '</b>'
            + (is30 ? ' - in about one month.' : ' - tomorrow.') + '</p>'
            + '<p>' + (is30
                ? 'If you would like to renew, please contact your property manager at your earliest convenience.'
                : 'Please ensure the property is ready for hand-over and contact your property manager with any questions.')
            + '</p>'
            + '<p>Regards,<br/>' + UserInfo.getOrganizationName().escapeHtml4() + ' Property Operations</p>'
        );
        return mail;
    }
}