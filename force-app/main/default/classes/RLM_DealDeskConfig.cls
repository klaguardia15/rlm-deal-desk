/**
 * Catalog and margin settings for deal analysis and the Deal Desk Assistant.
 * The adapt-deal-desk skill edits this class, then the agent instructions.
 * Margin Health formula thresholds in RLM_Margin_Flag__c must match
 * MARGIN_GREEN_PCT and MARGIN_YELLOW_PCT.
 */
public with sharing class RLM_DealDeskConfig {
    public static final Decimal KIT_QTY = 100;
    public static final Decimal CHANNEL_DISCOUNT = 10;
    public static final Decimal SERVICES_MAX_QTY = 5;
    public static final Decimal MARGIN_GREEN_PCT = 35;
    public static final Decimal MARGIN_YELLOW_PCT = 20;

    public static final Set<String> KIT_SKUS = new Set<String>{ 'KIT-PARENT' };
    public static final Set<String> HARDWARE_KIT_SKUS = new Set<String>{ 'KIT-PARENT' };
    public static final Set<String> DEVICE_SKUS = new Set<String>{ 'DEVICE' };
    public static final Set<String> HARDWARE_CHILD_SKUS = new Set<String>{
        'DEVICE', 'ACCESSORY-CHARGE', 'ACCESSORY-CORD', 'CABLE'
    };
    public static final String SERVICES_SKU_PREFIX = 'PS-';
    public static final String USB_CABLE_SKU = 'CABLE';
    public static final Set<String> REQUIRED_ACCESSORY_SKUS = new Set<String>{
        'ACCESSORY-CHARGE',
        'ACCESSORY-CORD'
    };
    public static final Set<String> PADDING_SKUS = new Set<String>{ 'PADDING-1' };
    public static final Map<String, String> REQUIRED_ACCESSORY_LABELS = new Map<String, String>{
        'ACCESSORY-CHARGE' => 'Required charging accessory',
        'ACCESSORY-CORD' => 'Required power cord'
    };

    public static Boolean isKitSku(String sku) {
        return matchesAny(sku, KIT_SKUS);
    }

    public static Boolean isHardwareKitSku(String sku) {
        return matchesAny(sku, HARDWARE_KIT_SKUS);
    }

    public static Boolean isDeviceSku(String sku) {
        return matchesAny(sku, DEVICE_SKUS);
    }

    public static Boolean isHardwareChildSku(String sku) {
        return matchesAny(sku, HARDWARE_CHILD_SKUS);
    }

    public static Boolean isServicesSku(String sku) {
        return String.isNotBlank(sku)
            && String.isNotBlank(SERVICES_SKU_PREFIX)
            && sku.startsWith(SERVICES_SKU_PREFIX);
    }

    public static Boolean isPaddingSku(String sku) {
        return matchesAny(sku, PADDING_SKUS);
    }

    public static Boolean matchesAny(String sku, Set<String> keys) {
        if (String.isBlank(sku) || keys == null || keys.isEmpty()) {
            return false;
        }
        if (keys.contains(sku)) {
            return true;
        }
        for (String key : keys) {
            if (String.isNotBlank(key) && sku.startsWith(key)) {
                return true;
            }
        }
        return false;
    }
}
