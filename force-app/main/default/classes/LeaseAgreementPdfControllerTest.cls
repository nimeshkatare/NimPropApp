@IsTest
private class LeaseAgreementPdfControllerTest {

    @TestSetup
    static void setup() {
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        Tenant__c t = REMS_TestDataFactory.createTenant('Priya Nair', true);
        REMS_TestDataFactory.createLease(p.Id, t.Id, Date.today(), Date.today().addYears(1), true);
    }

    @IsTest
    static void getLeaseDataReturnsAllFields() {
        Lease_Agreement__c la = [SELECT Id, Name FROM Lease_Agreement__c LIMIT 1];

        LeaseAgreementPdfController.LeaseData d = LeaseAgreementPdfController.getLeaseData(la.Id);

        Assert.areEqual(la.Name, d.leaseNumber);
        Assert.areEqual('Priya Nair', d.tenantName);
        Assert.areEqual('priyanair@example.com', d.tenantEmail);
        Assert.areEqual('Test Property 0000', d.propertyName);
        Assert.isTrue(d.propertyAddress.contains('Bengaluru'));
        Assert.areEqual(25000, d.monthlyRent);
        Assert.areEqual(Date.today(), d.startDate);
        Assert.isNotNull(d.currencyCode);
        Assert.isNotNull(d.ownerName);
    }

    @IsTest
    static void getLeaseDataFailsForUnknownId() {
        Lease_Agreement__c la = [SELECT Id FROM Lease_Agreement__c LIMIT 1];
        Id gone = la.Id;
        delete la;
        try {
            LeaseAgreementPdfController.getLeaseData(gone);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void sendPdfStoresFileAndEmailsTenant() {
        Lease_Agreement__c la = [SELECT Id, Name FROM Lease_Agreement__c LIMIT 1];
        String pdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 fake'));

        Test.startTest();
        String sentTo = LeaseAgreementPdfController.sendPdfToTenant(la.Id, pdf, la.Name + '.pdf');
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual('priyanair@example.com', sentTo);
        Assert.areEqual(1, invocations, 'One sendEmail call');
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :la.Id], 'PDF saved as a File on the lease');
    }

    @IsTest
    static void sendPdfRejectsEmptyContent() {
        Lease_Agreement__c la = [SELECT Id FROM Lease_Agreement__c LIMIT 1];
        try {
            LeaseAgreementPdfController.sendPdfToTenant(la.Id, '', null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void emailBodyContainsKeyFacts() {
        Lease_Agreement__c la = [
            SELECT Id, Name, Start_Date__c, End_Date__c, Agreed_Monthly_Rent__c, Tenant__r.Name, Property__r.Name
            FROM Lease_Agreement__c LIMIT 1
        ];
        String body = LeaseAgreementPdfController.buildEmailBody(la);
        Assert.isTrue(body.contains('Priya Nair'));
        Assert.isTrue(body.contains(la.Name));
        Assert.isTrue(body.contains(REMS_EmailUtil.formatDate(la.End_Date__c)));
    }

    @IsTest
    static void emailUtilHelpers() {
        Assert.areEqual('', REMS_EmailUtil.formatDate(null));
        Assert.areEqual('15 Dec 2026', REMS_EmailUtil.formatDate(Date.newInstance(2026, 12, 15)));
        Assert.areEqual('', REMS_EmailUtil.formatMoney(null));
        Assert.isTrue(REMS_EmailUtil.formatMoney(1234.5).endsWith('1,234.50'));
        Messaging.SingleEmailMessage m = REMS_EmailUtil.newMessage();
        Assert.isNotNull(m);
        // Second call hits the cache path.
        Assert.areEqual(REMS_EmailUtil.getOrgWideEmailAddressId(), REMS_EmailUtil.getOrgWideEmailAddressId());
    }
}