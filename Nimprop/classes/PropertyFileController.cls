/**
 * @description Supports the propertyCreateForm LWC (REMS-PM-002/003). The LWC creates the Property
 *              via Lightning Data Service, then uploads each selected file through attachFile.
 *              If any upload fails, the LWC calls rollbackProperty so no image-less property survives.
 */
public with sharing class PropertyFileController {

    /**
     * @description Creates a Salesforce File linked to the record.
     * @return ContentDocumentId of the new file
     */
    @AuraEnabled
    public static Id attachFile(Id recordId, String fileName, String base64Data) {
        try {
            if (recordId == null || String.isBlank(fileName) || String.isBlank(base64Data)) {
                throw new REMSException('recordId, fileName and base64Data are required.');
            }
            if (!Schema.sObjectType.ContentVersion.isCreateable()) {
                throw new REMSException('You do not have permission to upload files.');
            }
            ContentVersion cv = new ContentVersion(
                Title = fileName,
                PathOnClient = fileName,
                VersionData = EncodingUtil.base64Decode(base64Data),
                FirstPublishLocationId = recordId
            );
            insert cv;
            return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes a property that was just created but whose image upload failed.
     *              Only properties created by the current user in this session are eligible.
     */
    @AuraEnabled
    public static void rollbackProperty(Id propertyId) {
        try {
            if (!Schema.sObjectType.Property__c.isDeletable()) {
                throw new REMSException('You do not have permission to delete properties.');
            }
            List<Property__c> props = [
                SELECT Id FROM Property__c
                WHERE Id = :propertyId AND CreatedById = :UserInfo.getUserId()
                WITH USER_MODE
                LIMIT 1
            ];
            if (!props.isEmpty()) {
                delete props;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Number of files linked to a record. Used to verify REMS-PM-003 post-save.
     */
    @AuraEnabled(cacheable=true)
    public static Integer getFileCount(Id recordId) {
        return [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :recordId];
    }
}