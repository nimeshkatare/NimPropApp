/**
 * @description Shared email helpers. Uses the first verified Organization-Wide Email Address when
 *              one exists (BRD §8), otherwise falls back to the running user's address.
 */
public with sharing class REMS_EmailUtil {

    private static Id cachedOrgWideAddressId;
    private static Boolean orgWideLookedUp = false;

    /**
     * @description Returns a pre-configured SingleEmailMessage.
     */
    public static Messaging.SingleEmailMessage newMessage() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        Id owea = getOrgWideEmailAddressId();
        if (owea != null) {
            mail.setOrgWideEmailAddressId(owea);
        }
        mail.setSaveAsActivity(false);
        mail.setUseSignature(false);
        return mail;
    }

    public static Id getOrgWideEmailAddressId() {
        if (!orgWideLookedUp) {
            orgWideLookedUp = true;
            List<OrgWideEmailAddress> addresses = [
                SELECT Id FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true ORDER BY CreatedDate ASC LIMIT 1
            ];
            cachedOrgWideAddressId = addresses.isEmpty() ? null : addresses[0].Id;
        }
        return cachedOrgWideAddressId;
    }

    /**
     * @description Formats a Date for email bodies (e.g. 15 Dec 2026).
     */
    public static String formatDate(Date d) {
        if (d == null) {
            return '';
        }
        return DateTime.newInstance(d.year(), d.month(), d.day()).format('d MMM yyyy');
    }

    /**
     * @description Formats a currency amount with the org's default currency code.
     */
    public static String formatMoney(Decimal amount) {
        if (amount == null) {
            return '';
        }
        // Decimal.format() drops trailing zeros, so group the whole part and append the 2-digit fraction ourselves.
        Decimal scaled = amount.setScale(2, RoundingMode.HALF_UP);
        String whole = Decimal.valueOf(scaled.longValue()).format();
        String fraction = String.valueOf(scaled.abs()).substringAfterLast('.');
        return UserInfo.getDefaultCurrency() + ' ' + whole + '.' + fraction;
    }
}