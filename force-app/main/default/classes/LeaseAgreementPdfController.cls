/**
 * @description Backs the leaseAgreementActions LWC (REMS-LA-003/004). The PDF itself is rendered
 *              client-side with jsPDF; this class supplies the data and emails the finished PDF.
 */
public with sharing class LeaseAgreementPdfController {

    public class LeaseData {
        @AuraEnabled public Id id;
        @AuraEnabled public String leaseNumber;
        @AuraEnabled public String terms;
        @AuraEnabled public Decimal monthlyRent;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String tenantName;
        @AuraEnabled public String tenantEmail;
        @AuraEnabled public String tenantPhone;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String organizationName;
    }

    /**
     * @description All fields needed to render the lease PDF.
     */
    @AuraEnabled(cacheable=true)
    public static LeaseData getLeaseData(Id leaseId) {
        try {
            Lease_Agreement__c la = queryLease(leaseId);
            LeaseData d = new LeaseData();
            d.id = la.Id;
            d.leaseNumber = la.Name;
            d.terms = la.Terms__c;
            d.monthlyRent = la.Agreed_Monthly_Rent__c;
            d.startDate = la.Start_Date__c;
            d.endDate = la.End_Date__c;
            d.propertyName = la.Property__r.Name;
            d.propertyType = la.Property__r.Type__c;
            d.propertyAddress = String.join(new List<String>{
                la.Property__r.Street__c, la.Property__r.City__c, la.Property__r.State__c,
                la.Property__r.Postal_Code__c, la.Property__r.Country__c
            }, ', ');
            d.tenantName = la.Tenant__r.Name;
            d.tenantEmail = la.Tenant__r.Email__c;
            d.tenantPhone = la.Tenant__r.Phone__c;
            d.currencyCode = UserInfo.getDefaultCurrency();
            d.ownerName = resolveOwnerName(la.OwnerId);
            d.organizationName = UserInfo.getOrganizationName();
            return d;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Stores the PDF as a File on the lease and emails it to the tenant.
     * @return the recipient email address
     */
    @AuraEnabled
    public static String sendPdfToTenant(Id leaseId, String base64Pdf, String fileName) {
        try {
            if (String.isBlank(base64Pdf)) {
                throw new REMSException('No PDF content was supplied.');
            }
            Lease_Agreement__c la = queryLease(leaseId);
            String toAddress = la.Tenant__r.Email__c;
            if (String.isBlank(toAddress)) {
                throw new REMSException('The tenant has no email address on file.');
            }
            String safeName = String.isBlank(fileName) ? la.Name + '.pdf' : fileName;
            Blob pdf = EncodingUtil.base64Decode(base64Pdf);

            if (Schema.sObjectType.ContentVersion.isCreateable()) {
                insert new ContentVersion(
                    Title = safeName.removeEnd('.pdf'),
                    PathOnClient = safeName,
                    VersionData = pdf,
                    FirstPublishLocationId = la.Id
                );
            }

            Messaging.SingleEmailMessage mail = REMS_EmailUtil.newMessage();
            mail.setToAddresses(new List<String>{ toAddress });
            mail.setSubject('Your Lease Agreement ' + la.Name + ' - ' + la.Property__r.Name);
            mail.setHtmlBody(buildEmailBody(la));
            Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
            att.setFileName(safeName);
            att.setBody(pdf);
            att.setContentType('application/pdf');
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
            if (!results[0].isSuccess()) {
                throw new REMSException('Email failed: ' + results[0].getErrors()[0].getMessage());
            }
            return toAddress;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Lease_Agreement__c queryLease(Id leaseId) {
        List<Lease_Agreement__c> rows = [
            SELECT Id, Name, Terms__c, Agreed_Monthly_Rent__c, Start_Date__c, End_Date__c, OwnerId,
                   Property__r.Name, Property__r.Type__c, Property__r.Street__c, Property__r.City__c,
                   Property__r.State__c, Property__r.Postal_Code__c, Property__r.Country__c,
                   Tenant__r.Name, Tenant__r.Email__c, Tenant__r.Phone__c
            FROM Lease_Agreement__c
            WHERE Id = :leaseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new REMSException('Lease Agreement not found or not accessible.');
        }
        return rows[0];
    }

    /**
     * @description Owner may be a User or a Queue; return the User's name when applicable.
     */
    private static String resolveOwnerName(Id ownerId) {
        if (ownerId == null || ownerId.getSobjectType() != Schema.User.SObjectType) {
            return UserInfo.getOrganizationName();
        }
        List<User> users = [SELECT Name FROM User WHERE Id = :ownerId LIMIT 1];
        return users.isEmpty() ? UserInfo.getName() : users[0].Name;
    }

    @TestVisible
    private static String buildEmailBody(Lease_Agreement__c la) {
        return '<p>Dear ' + la.Tenant__r.Name.escapeHtml4() + ',</p>'
            + '<p>Please find attached your lease agreement <b>' + la.Name + '</b> for '
            + '<b>' + la.Property__r.Name.escapeHtml4() + '</b>.</p>'
            + '<ul>'
            + '<li>Start Date: ' + REMS_EmailUtil.formatDate(la.Start_Date__c) + '</li>'
            + '<li>End Date: ' + REMS_EmailUtil.formatDate(la.End_Date__c) + '</li>'
            + '<li>Monthly Rent: ' + REMS_EmailUtil.formatMoney(la.Agreed_Monthly_Rent__c) + '</li>'
            + '</ul>'
            + '<p>Please review and reply to this email with any questions.</p>'
            + '<p>Regards,<br/>' + UserInfo.getOrganizationName().escapeHtml4() + ' Property Operations</p>';
    }
}