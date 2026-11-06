@IsTest
private class PropertyFileControllerTest {

    @IsTest
    static void attachFileLinksFileToProperty() {
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));

        Test.startTest();
        Id docId = PropertyFileController.attachFile(p.Id, 'front.jpg', base64);
        Test.stopTest();

        Assert.isNotNull(docId);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :p.Id AND ContentDocumentId = :docId]);
        Assert.areEqual(1, PropertyFileController.getFileCount(p.Id));
    }

    @IsTest
    static void attachFileRejectsMissingArguments() {
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        try {
            PropertyFileController.attachFile(p.Id, '', 'abc');
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void rollbackDeletesOwnProperty() {
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];

        Test.startTest();
        PropertyFileController.rollbackProperty(p.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Property__c WHERE Id = :p.Id]);
    }

    @IsTest
    static void rollbackIsNoOpForUnknownId() {
        Property__c p = REMS_TestDataFactory.createProperties(1, true, true)[0];
        Id fakeId = p.Id;
        delete p;
        PropertyFileController.rollbackProperty(fakeId);
        Assert.areEqual(0, [SELECT COUNT() FROM Property__c]);
    }
}