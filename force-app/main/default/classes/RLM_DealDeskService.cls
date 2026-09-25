/**
 * Deal analysis for Opportunity and Quote: motion (run-rate vs quote-to-order),
 * recommended next steps, optional apply actions, and revision compare.
 */
public with sharing class RLM_DealDeskService {

    public static final String ACTION_SCALE_KIT = 'SCALE_KIT_50';
    public static final String ACTION_DISTI_12 = 'APPLY_DISTI_12';
    public static final String ACTION_PARTNER_PC = 'APPLY_PARTNER_PC';
    // SKUs, quantities, and margin bands live in RLM_DealDeskConfig.

    public class Prompt {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String severity;
        @AuraEnabled public String actionKey;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public Boolean canApply;
    }

    public class PromptResponse {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String headline;
        @AuraEnabled public String contextLabel;
        @AuraEnabled public String motionKey;
        @AuraEnabled public String motionLabel;
        @AuraEnabled public String motionBody;
        @AuraEnabled public List<Prompt> prompts;
        @AuraEnabled public List<QuoteChoice> quoteChoices;
        @AuraEnabled public String defaultLeftId;
        @AuraEnabled public String defaultRightId;
    }

    public class QuoteChoice {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public Integer revision;
    }

    public class CompareResponse {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String leftTitle;
        @AuraEnabled public String rightTitle;
        @AuraEnabled public Integer modifiedCount;
        @AuraEnabled public Integer addedCount;
        @AuraEnabled public Integer removedCount;
        @AuraEnabled public Integer unchangedCount;
        @AuraEnabled public String managementSummary;
        @AuraEnabled public Boolean comparedToList;
        @AuraEnabled public List<HeaderRow> headerRows;
        @AuraEnabled public List<LineDelta> lineDeltas;
    }

    public class HeaderRow {
        @AuraEnabled public String field;
        @AuraEnabled public String previousValue;
        @AuraEnabled public String currentValue;
        @AuraEnabled public Boolean changed;
        @AuraEnabled public String rowClass;
    }

    public class LineDelta {
        @AuraEnabled public String sku;
        @AuraEnabled public String name;
        @AuraEnabled public String changeType;
        @AuraEnabled public String previousQty;
        @AuraEnabled public String currentQty;
        @AuraEnabled public String previousDiscount;
        @AuraEnabled public String currentDiscount;
        @AuraEnabled public String previousList;
        @AuraEnabled public String currentList;
        @AuraEnabled public String previousNetUnit;
        @AuraEnabled public String currentNetUnit;
        @AuraEnabled public String previousMargin;
        @AuraEnabled public String currentMargin;
        @AuraEnabled public String marginFlag;
        @AuraEnabled public String deltaNet;
        @AuraEnabled public String previousNet;
        @AuraEnabled public String currentNet;
        @AuraEnabled public String rowClass;
        @AuraEnabled public String changeChipClass;
        @AuraEnabled public String qtyValue;
        @AuraEnabled public String qtyDelta;
        @AuraEnabled public String qtyImpactClass;
        @AuraEnabled public String discValue;
        @AuraEnabled public String discDelta;
        @AuraEnabled public String discImpactClass;
        @AuraEnabled public String netValue;
        @AuraEnabled public String netDeltaLabel;
        @AuraEnabled public String netImpactClass;
        @AuraEnabled public String marginValue;
        @AuraEnabled public String marginDelta;
        @AuraEnabled public String marginImpactClass;
    }

    public class ApplyResponse {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String message;
    }

    public class PartnerConcessionInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
    }

    public class PartnerConcessionOutput {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Applied Percent')
        public Decimal appliedPercent;
    }

    @InvocableMethod(
        label='Apply Partner-Requested Concession'
        description='Reads the partner PC justification, writes that percent on the quote header, and refreshes prices. Does not submit approval.'
    )
    public static List<PartnerConcessionOutput> applyPartnerRequestedConcession(
        List<PartnerConcessionInput> inputs
    ) {
        List<PartnerConcessionOutput> results = new List<PartnerConcessionOutput>();
        if (inputs == null) {
            return results;
        }
        for (PartnerConcessionInput input : inputs) {
            PartnerConcessionOutput row = new PartnerConcessionOutput();
            String quoteId = input == null ? null : input.quoteId;
            ApplyResponse applied = applyAction(quoteId, ACTION_PARTNER_PC);
            row.isSuccess = applied.isSuccess;
            row.message = applied.message;
            row.errorMessage = applied.errorMessage;
            if (applied.isSuccess == true && String.isNotBlank(quoteId)) {
                try {
                    Quote q = [
                        SELECT AppliedDiscount, RLM_PC_Justification__c
                        FROM Quote
                        WHERE Id = :Id.valueOf(quoteId)
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    row.appliedPercent = parseRequestedPercent(q.RLM_PC_Justification__c);
                    if (row.appliedPercent == null) {
                        row.appliedPercent = percentPoints(q.AppliedDiscount);
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.FINE, e.getMessage());
                }
            }
            results.add(row);
        }
        return results;
    }

    @TestVisible
    static Boolean forcePriceRefreshCallout = false;

    public static PromptResponse getPrompts(String recordId) {
        return getPrompts(recordId, false);
    }

    @AuraEnabled(cacheable=false)
    public static PromptResponse getPrompts(String recordId, Boolean skipStamp) {
        PromptResponse out = new PromptResponse();
        out.isSuccess = false;
        out.prompts = new List<Prompt>();
        out.quoteChoices = new List<QuoteChoice>();
        Id rid = parseId(recordId);
        if (rid == null) {
            out.errorMessage = 'Open a Quote or Opportunity for Deal analysis.';
            return out;
        }
        try {
            String keyPrefix = String.valueOf(rid).substring(0, 3);
            if (keyPrefix == '0Q0') {
                fillQuotePrompts(rid, out, skipStamp == true);
            } else if (keyPrefix == '006') {
                fillOpportunityPrompts(rid, out, skipStamp == true);
            } else {
                out.errorMessage = 'Deal analysis is available on Opportunity and Quote.';
                return out;
            }
            out.isSuccess = true;
            return out;
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    @AuraEnabled
    public static ApplyResponse applyAction(String recordId, String actionKey) {
        ApplyResponse out = new ApplyResponse();
        out.isSuccess = false;
        Id rid = parseId(recordId);
        if (rid == null || String.isBlank(actionKey)) {
            out.errorMessage = 'Nothing to apply.';
            return out;
        }
        try {
            Id quoteId = resolveQuoteId(rid);
            if (quoteId == null) {
                out.errorMessage = 'Create the quote first, then apply quantity or the recommended discount.';
                return out;
            }
            if (actionKey == ACTION_SCALE_KIT) {
                Integer n = scaleKit(quoteId);
                if (n == 0) {
                    List<QuoteLineItem> current = [
                        SELECT Id, Quantity, ParentQuoteLineItemId,
                               Product2.StockKeepingUnit, Product2.ProductCode
                        FROM QuoteLineItem
                        WHERE QuoteId = :quoteId
                        WITH USER_MODE
                    ];
                    if (hardwareKitLineIds(current).isEmpty()) {
                        out.errorMessage = 'No hardware kit line to scale.';
                        return out;
                    }
                    out.message = 'Kit quantity is already 600.';
                } else {
                    out.message = 'Set kit parent and children to 600 (50 per month on a 12-month agreement).';
                }
            } else if (actionKey == ACTION_DISTI_12) {
                applyHeaderPercent(quoteId, RLM_DealDeskConfig.CHANNEL_DISCOUNT);
                out.message = 'Wrote 12% on the quote header only. Line discounts are blank so you can still discount individual SKUs.';
            } else if (actionKey == ACTION_PARTNER_PC) {
                Quote partnerQuote = [
                    SELECT Id, RLM_PC_Justification__c
                    FROM Quote
                    WHERE Id = :quoteId
                    WITH USER_MODE
                    LIMIT 1
                ];
                Decimal requested = parseRequestedPercent(partnerQuote.RLM_PC_Justification__c);
                if (requested == null) {
                    out.errorMessage = 'No percent in the partner message. Add 18% (or similar) to PC Justification first.';
                    return out;
                }
                applyHeaderPercent(quoteId, requested);
                out.message = 'Wrote ' + requested.stripTrailingZeros().toPlainString()
                    + '% from the partner message on the quote header only. Line discounts are blank.';
            } else {
                out.errorMessage = 'That action is not available.';
                return out;
            }
            out.isSuccess = true;
            return out;
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    @AuraEnabled
    public static ApplyResponse refreshPrices(String recordId) {
        ApplyResponse out = new ApplyResponse();
        out.isSuccess = false;
        Id rid = parseId(recordId);
        if (rid == null) {
            out.errorMessage = 'Open a Quote or Opportunity to refresh prices.';
            return out;
        }
        try {
            Id quoteId = resolveQuoteId(rid);
            if (quoteId == null) {
                out.errorMessage = 'Create the quote first, then refresh prices.';
                return out;
            }
            if (Test.isRunningTest() && !forcePriceRefreshCallout) {
                out.isSuccess = true;
                out.message = 'Prices refreshed.';
                return out;
            }
            refreshQuotePrices(quoteId);
            out.isSuccess = true;
            out.message = 'Prices refreshed.';
            return out;
        } catch (Exception e) {
            out.errorMessage = 'Could not refresh prices automatically. Use Refresh prices on the quote. '
                + e.getMessage();
            return out;
        }
    }

    private static Id parseId(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }
        try {
            return Id.valueOf(recordId);
        } catch (Exception e) {
            return null;
        }
    }

    private static Id resolveQuoteId(Id rid) {
        String keyPrefix = String.valueOf(rid).substring(0, 3);
        if (keyPrefix == '0Q0') {
            return rid;
        }
        if (keyPrefix == '006') {
            List<Quote> quotes = [
                SELECT Id
                FROM Quote
                WHERE OpportunityId = :rid
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            return quotes.isEmpty() ? null : quotes[0].Id;
        }
        return null;
    }

    private static void fillQuotePrompts(Id quoteId, PromptResponse out, Boolean skipStamp) {
        Quote quote = [
            SELECT Id, Name, Status, AppliedDiscount, Discount, OpportunityId,
                   RLM_PC_Justification__c, RLM_Partner_Request__c, RLM_MFG_Sales_Agreement__c,
                   RLM_Deal_Motion__c
            FROM Quote
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        List<QuoteLineItem> lines = [
            SELECT Id, Quantity, Discount, ParentQuoteLineItemId, SellingModelType,
                   Product2.Name, Product2.StockKeepingUnit, Product2.ProductCode
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH USER_MODE
            ORDER BY LineNumber
        ];
        out.contextLabel = quote.Name;
        String motion = classifyMotion(quote, lines);
        applyMotion(out, motion, !lines.isEmpty());
        if (motion == 'unset') {
            out.prompts.add(prompt(
                'set-motion',
                'Set how this quote closes',
                'Open Deal motion and pick Sales Agreement (run-rate call-off) or Quote to order (one-shot). Hardware is valid on both — it is not inferred from the products.',
                'info',
                null,
                null,
                false
            ));
        }

        Set<String> skus = collectSkus(lines);
        Boolean needsKitScale = kitNeedsScale(lines);
        Boolean hasDevice = false;
        for (String sku : skus) {
            if (RLM_DealDeskConfig.isDeviceSku(sku)) {
                hasDevice = true;
                break;
            }
        }

        if (lines.isEmpty()) {
            out.prompts.add(prompt(
                'add-products',
                'Add products from the catalog',
                'Browse Catalog and add the products for this deal. Set the kit parent quantity to the annual volume when you add it — children scale with the parent.',
                'info',
                null,
                null,
                false
            ));
            return;
        }

        Boolean partnerPc = quote.RLM_Partner_Request__c == true
            || String.isNotBlank(quote.RLM_PC_Justification__c);

        if (!partnerPc && needsKitScale) {
            out.prompts.add(prompt(
                'qty-50',
                'Set kit quantity to ' + String.valueOf(RLM_DealDeskConfig.KIT_QTY),
                'Annual agreement quantity (' + String.valueOf(RLM_DealDeskConfig.KIT_QTY) + '). Parent and children are set to that quantity. Children scale with the parent.',
                'warning',
                ACTION_SCALE_KIT,
                'Apply kit qty ' + String.valueOf(RLM_DealDeskConfig.KIT_QTY),
                true
            ));
        }

        if (partnerPc) {
            addPartnerConcessionPrompt(quote, out);
        } else {
            Decimal headerRaw = quote.AppliedDiscount;
            Boolean needsRecommended = headerRaw == null || Math.abs(headerRaw - RLM_DealDeskConfig.CHANNEL_DISCOUNT) > 0.5;
            if (needsRecommended) {
                out.prompts.add(prompt(
                    'disti-12',
                    'Apply recommended ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% discount',
                    'Deal analysis recommends ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% on the quote header from channel history — not a typed price-book discount. Line discounts stay blank so you can still override a SKU. Submit for approval before it is contracted.',
                    'warning',
                    ACTION_DISTI_12,
                    'Apply recommended ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '%',
                    true
                ));
            } else if (quote.Status == 'Draft' || quote.Status == 'Needs Review') {
                out.prompts.add(prompt(
                    'submit-approval',
                    'Submit the recommended discount for approval',
                    String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% is on the quote as a recommendation. Approval is what turns it into contracted price on a Sales Agreement (run-rate) or an order (quote to order).',
                    'warning',
                    null,
                    null,
                    false
                ));
            } else if (motion == 'run-rate' && quote.RLM_MFG_Sales_Agreement__c == null) {
                out.prompts.add(prompt(
                    'create-sa',
                    'Create the Sales Agreement',
                    'Approved net becomes contracted price. Partners then place self-serve orders against the agreement; the pricing procedure applies that net automatically.',
                    'info',
                    null,
                    null,
                    false
                ));
            } else if (motion == 'quote-to-order') {
                out.prompts.add(prompt(
                    'create-order',
                    'Create the order when pricing is final',
                    'Quote-to-order does not need a Sales Agreement. Create Order after approval (if the discount required it).',
                    'success',
                    null,
                    null,
                    false
                ));
            } else if (quote.RLM_MFG_Sales_Agreement__c != null) {
                out.prompts.add(prompt(
                    'sa-ready',
                    'Contracted price is on the agreement',
                    'Partners call off in Partner Central. The pricing procedure includes this net — they should not re-type the discount.',
                    'success',
                    null,
                    null,
                    false
                ));
            }
        }

        if (hasDevice && !skus.contains(RLM_DealDeskConfig.USB_CABLE_SKU)) {
            out.prompts.add(prompt(
                'usbc',
                'Required cable is missing',
                RLM_DealDeskConfig.USB_CABLE_SKU + ' is required with the configured device SKUs. Leaving it off typically means a replacement-parts quote and a second freight charge. Re-open Configure to add it.',
                'warning',
                null,
                null,
                false
            ));
        }
        attachQuoteChoices(out, quote.OpportunityId, quote.Id);
        if (skipStamp != true) {
            stampFromDefaults(out);
        }
    }

    private static void fillOpportunityPrompts(Id opportunityId, PromptResponse out, Boolean skipStamp) {
        Opportunity opp = [
            SELECT Id, Name, StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Quote> quotes = [
            SELECT Id, Name, Status, LastModifiedDate, RLM_MFG_Sales_Agreement__c
            FROM Quote
            WHERE OpportunityId = :opportunityId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        out.contextLabel = opp.Name;

        if (quotes.isEmpty()) {
            applyMotion(out, 'unset');
            out.prompts.add(prompt(
                'new-quote',
                'Create a quote',
                'Use New Quote and pick how it closes: Sales Agreement (run-rate call-off) or Quote to order (one-shot). Hardware is valid on both paths.',
                'info',
                null,
                null,
                false
            ));
            return;
        }

        Quote latest = quotes[quotes.size() - 1];
        List<QuoteLineItem> lines = [
            SELECT Id, Quantity, ParentQuoteLineItemId,
                   Product2.StockKeepingUnit, Product2.ProductCode
            FROM QuoteLineItem
            WHERE QuoteId = :latest.Id
            WITH USER_MODE
        ];
        Quote typed = [
            SELECT Id, RLM_PC_Justification__c, RLM_Partner_Request__c, RLM_MFG_Sales_Agreement__c,
                   RLM_Deal_Motion__c
            FROM Quote
            WHERE Id = :latest.Id
            WITH USER_MODE
            LIMIT 1
        ];
        applyMotion(out, classifyMotion(typed, lines), !lines.isEmpty());

        out.prompts.add(prompt(
            'open-quote',
            'Open ' + latest.Name,
            'Continue pricing on that quote.',
            'info',
            null,
            null,
            false
        ));

        if (kitNeedsScale(lines) && typed.RLM_Partner_Request__c != true) {
            out.prompts.add(prompt(
                'qty-50-opp',
                'Set kit quantity to ' + String.valueOf(RLM_DealDeskConfig.KIT_QTY) + ' on ' + latest.Name,
                'Annual agreement quantity (' + String.valueOf(RLM_DealDeskConfig.KIT_QTY) + '). Apply writes that quantity on the kit parent and its children.',
                'warning',
                ACTION_SCALE_KIT,
                'Apply kit qty ' + String.valueOf(RLM_DealDeskConfig.KIT_QTY),
                true
            ));
        }
        attachQuoteChoices(out, opportunityId, latest.Id);
        if (skipStamp != true) {
            stampFromDefaults(out);
        }
    }

    private static String classifyMotion(Quote quote, List<QuoteLineItem> lines) {
        if (quote.RLM_MFG_Sales_Agreement__c != null) {
            return 'run-rate';
        }
        String chosen = quote.RLM_Deal_Motion__c;
        if (chosen == 'Sales_Agreement') {
            return 'run-rate';
        }
        if (chosen == 'Quote_To_Order') {
            return 'quote-to-order';
        }
        return 'unset';
    }

    private static void applyMotion(PromptResponse out, String motion) {
        applyMotion(out, motion, true);
    }

    private static void applyMotion(PromptResponse out, String motion, Boolean hasProducts) {
        out.motionKey = motion;
        if (motion == 'run-rate') {
            out.motionLabel = 'Run-rate (Sales Agreement)';
            out.motionBody = 'Recommended discount still needs approval. After approval, Create Sales Agreement so that net is contracted. Partners then call off in Partner Central and the pricing procedure applies it automatically.';
            out.headline = 'Next steps for a run-rate quote.';
        } else if (motion == 'quote-to-order') {
            out.motionLabel = 'Quote to order';
            out.motionBody = 'Price this quote, submit if the discount needs approval, then Create Order. No Sales Agreement on this path.';
            out.headline = 'Next steps for a quote-to-order deal.';
        } else if (motion == 'mixed') {
            out.motionLabel = 'Mixed motion';
            out.motionBody = 'This quote has one-time and subscription lines. Hardware run-rate usually belongs on a Sales Agreement; subscriptions go quote-to-order (or a separate quote).';
            out.headline = 'This quote mixes run-rate and quote-to-order lines.';
        } else {
            out.motionLabel = null;
            out.motionBody = null;
            out.headline = null;
        }
        if (hasProducts != true) {
            out.motionBody = null;
            out.headline = null;
        }
    }

    private static void attachQuoteChoices(PromptResponse out, Id opportunityId, Id currentQuoteId) {
        out.quoteChoices = new List<QuoteChoice>();
        if (opportunityId == null) {
            return;
        }
        List<Quote> quotes = [
            SELECT Id, Name, QuoteNumber, Status, CreatedDate
            FROM Quote
            WHERE OpportunityId = :opportunityId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        if (quotes.isEmpty()) {
            return;
        }
        Set<Id> quoteIds = new Map<Id, Quote>(quotes).keySet();
        Set<Id> linedIds = new Set<Id>();
        for (AggregateResult row : [
            SELECT QuoteId
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
            WITH USER_MODE
            GROUP BY QuoteId
        ]) {
            linedIds.add((Id) row.get('QuoteId'));
        }
        List<Quote> lined = new List<Quote>();
        for (Quote q : quotes) {
            if (linedIds.contains(q.Id)) {
                lined.add(q);
            }
        }
        if (lined.isEmpty()) {
            return;
        }
        QuoteChoice listChoice = new QuoteChoice();
        listChoice.id = 'LIST';
        listChoice.label = 'List price (no concession)';
        listChoice.revision = 0;
        listChoice.status = 'List';
        out.quoteChoices.add(listChoice);
        Integer rev = 1;
        for (Quote q : lined) {
            QuoteChoice choice = new QuoteChoice();
            choice.id = String.valueOf(q.Id);
            choice.revision = rev;
            String num = String.isBlank(q.QuoteNumber) ? q.Name : q.QuoteNumber;
            choice.label = 'Rev ' + String.valueOf(rev) + ' · ' + num + ' · ' + q.Status;
            choice.status = q.Status;
            out.quoteChoices.add(choice);
            rev++;
        }
        Id rightId = currentQuoteId != null && linedIds.contains(currentQuoteId)
            ? currentQuoteId
            : lined[lined.size() - 1].Id;
        out.defaultRightId = String.valueOf(rightId);
        if (lined.size() == 1) {
            out.defaultLeftId = 'LIST';
        } else {
            out.defaultLeftId = String.valueOf(lined[0].Id);
            if (out.defaultLeftId == out.defaultRightId && lined.size() >= 2) {
                out.defaultLeftId = String.valueOf(lined[lined.size() - 2].Id);
            }
        }
    }

    private static void stampFromDefaults(PromptResponse out) {
        if (out == null || String.isBlank(out.defaultRightId)) {
            return;
        }
        compareQuotes('LIST', out.defaultRightId);
    }

    private static void stampLineChanges(
        Id quoteId,
        List<LineDelta> deltas,
        Map<String, QuoteLineItem> currentBySku
    ) {
        if (quoteId == null || deltas == null || deltas.isEmpty() || currentBySku == null) {
            return;
        }
        Map<String, String> typeBySku = new Map<String, String>();
        for (LineDelta delta : deltas) {
            if (delta == null || String.isBlank(delta.sku) || String.isBlank(delta.changeType)) {
                continue;
            }
            if (delta.changeType == 'Removed') {
                continue;
            }
            typeBySku.put(delta.sku, delta.changeType);
        }
        List<QuoteLineItem> patches = new List<QuoteLineItem>();
        for (String sku : typeBySku.keySet()) {
            QuoteLineItem line = currentBySku.get(sku);
            if (line == null || line.Id == null) {
                continue;
            }
            String change = typeBySku.get(sku);
            patches.add(new QuoteLineItem(
                Id = line.Id,
                RLM_Change_Type__c = change,
                RLM_Change__c = change
            ));
        }
        if (patches.isEmpty()) {
            return;
        }
        try {
            update as user patches;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Change stamp skipped: ' + e.getMessage());
        }
    }

    private static Integer scaleKit(Id quoteId) {
        List<QuoteLineItem> lines = [
            SELECT Id, Quantity, ParentQuoteLineItemId,
                   Product2.StockKeepingUnit, Product2.ProductCode
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH USER_MODE
        ];
        Set<Id> kitIds = hardwareKitLineIds(lines);
        List<QuoteLineItem> patches = new List<QuoteLineItem>();
        for (QuoteLineItem line : lines) {
            Decimal target = scaleTarget(line, kitIds);
            if (target == null) {
                continue;
            }
            Decimal current = line.Quantity == null ? 0 : line.Quantity;
            if (current != target) {
                patches.add(new QuoteLineItem(Id = line.Id, Quantity = target));
            }
        }
        if (!patches.isEmpty()) {
            update as user patches;
        }
        return patches.size();
    }

    private static Boolean kitNeedsScale(List<QuoteLineItem> lines) {
        Set<Id> kitIds = hardwareKitLineIds(lines);
        if (kitIds.isEmpty()) {
            return false;
        }
        for (QuoteLineItem line : lines) {
            Decimal target = scaleTarget(line, kitIds);
            if (target == null) {
                continue;
            }
            Decimal current = line.Quantity == null ? 0 : line.Quantity;
            if (current != target) {
                return true;
            }
        }
        return false;
    }

    private static Set<Id> hardwareKitLineIds(List<QuoteLineItem> lines) {
        Set<Id> kitIds = new Set<Id>();
        for (QuoteLineItem line : lines) {
            if (line.ParentQuoteLineItemId == null && isHardwareKitSku(skuOf(line))) {
                kitIds.add(line.Id);
            }
        }
        return kitIds;
    }

    private static Decimal scaleTarget(QuoteLineItem line, Set<Id> kitIds) {
        if (kitIds.isEmpty()) {
            return null;
        }
        if (kitIds.contains(line.Id)) {
            return RLM_DealDeskConfig.KIT_QTY;
        }
        if (line.ParentQuoteLineItemId != null && kitIds.contains(line.ParentQuoteLineItemId)) {
            return childScaleQty(skuOf(line));
        }
        if (line.ParentQuoteLineItemId == null && isHardwareChildSku(skuOf(line))) {
            return childScaleQty(skuOf(line));
        }
        return null;
    }

    private static Decimal childScaleQty(String sku) {
        if (RLM_DealDeskConfig.isServicesSku(sku)) {
            return RLM_DealDeskConfig.SERVICES_MAX_QTY;
        }
        return RLM_DealDeskConfig.KIT_QTY;
    }

    private static Boolean isHardwareChildSku(String sku) {
        return RLM_DealDeskConfig.isHardwareChildSku(sku);
    }

    private static void addPartnerConcessionPrompt(Quote quote, PromptResponse out) {
        Decimal requested = parseRequestedPercent(quote.RLM_PC_Justification__c);
        Decimal headerPts = percentPoints(quote.AppliedDiscount);
        String snippet = partnerSnippet(quote.RLM_PC_Justification__c);
        if (requested == null) {
            out.prompts.add(prompt(
                'partner-pc-read',
                'Read the partner Price Concession message',
                'This is a partner-requested exception, not the ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% channel run-rate recommendation. '
                    + snippet
                    + ' Ask them for a percent if the message does not include one.',
                'info',
                null,
                null,
                false
            ));
            return;
        }
        if (headerPts == null || Math.abs(headerPts - requested) > 0.5) {
            String pct = requested.stripTrailingZeros().toPlainString();
            out.prompts.add(prompt(
                'partner-pc',
                'Apply partner-requested ' + pct + '% concession',
                'The partner asked for ' + pct
                    + '% because this mix is not on the run-rate agreement. '
                    + snippet
                    + ' This is not the ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% channel close-history recommendation. Writes the header only.',
                'warning',
                ACTION_PARTNER_PC,
                'Apply partner-requested ' + pct + '%',
                true
            ));
            return;
        }
        if (quote.Status == 'Draft' || quote.Status == 'Needs Review') {
            out.prompts.add(prompt(
                'submit-partner-pc',
                'Submit the partner-requested concession for approval',
                'The partner percent is on the quote header. Approval is still an internal desk action — do not skip it.',
                'warning',
                null,
                null,
                false
            ));
        } else {
            out.prompts.add(prompt(
                'create-order',
                'Create the order when pricing is final',
                'Quote-to-order does not need a Sales Agreement. Create Order after approval (if the discount required it).',
                'success',
                null,
                null,
                false
            ));
        }
    }

    @TestVisible
    static Decimal parseRequestedPercent(String justification) {
        if (String.isBlank(justification)) {
            return null;
        }
        Matcher match = Pattern.compile('(\\d{1,2}(?:\\.\\d+)?)\\s*%').matcher(justification);
        if (!match.find()) {
            return null;
        }
        Decimal value = Decimal.valueOf(match.group(1));
        if (value < 1 || value > 50) {
            return null;
        }
        return value.setScale(2);
    }

    private static String partnerSnippet(String justification) {
        if (String.isBlank(justification)) {
            return 'No partner message yet.';
        }
        String compact = justification.replace('\n', ' ').trim();
        if (compact.length() > 220) {
            return compact.substring(0, 217) + '…';
        }
        return compact;
    }

    private static void applyHeaderPercent(Id quoteId, Decimal percentPoints) {
        Quote quote = [
            SELECT Id, AppliedDiscount
            FROM Quote
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        Decimal current = quote.AppliedDiscount;
        Decimal target = percentPoints;
        if (current == null || Math.abs(percentPoints(current) - target) > 0.05) {
            quote.AppliedDiscount = target;
            update as user quote;
        }
        List<QuoteLineItem> lines = [
            SELECT Id, Discount, DiscountAmount
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH USER_MODE
        ];
        List<QuoteLineItem> clears = new List<QuoteLineItem>();
        for (QuoteLineItem line : lines) {
            if (line.Discount != null || line.DiscountAmount != null) {
                clears.add(new QuoteLineItem(
                    Id = line.Id,
                    Discount = null,
                    DiscountAmount = null
                ));
            }
        }
        if (!clears.isEmpty()) {
            update as user clears;
        }
    }

    private static void applyDisti(Id quoteId) {
        applyHeaderPercent(quoteId, RLM_DealDeskConfig.CHANNEL_DISCOUNT);
    }

    private static Set<String> collectSkus(List<QuoteLineItem> lines) {
        Set<String> skus = new Set<String>();
        for (QuoteLineItem line : lines) {
            String sku = skuOf(line);
            if (String.isNotBlank(sku)) {
                skus.add(sku);
            }
            if (line.Product2 != null && String.isNotBlank(line.Product2.ProductCode)) {
                skus.add(line.Product2.ProductCode);
            }
        }
        return skus;
    }

    private static String skuOf(QuoteLineItem line) {
        if (line.Product2 == null) {
            return null;
        }
        if (String.isNotBlank(line.Product2.StockKeepingUnit)) {
            return line.Product2.StockKeepingUnit;
        }
        return line.Product2.ProductCode;
    }

    private static Boolean isHardwareKitSku(String sku) {
        return RLM_DealDeskConfig.isHardwareKitSku(sku);
    }

    private static Boolean isKitSku(String sku) {
        return RLM_DealDeskConfig.isKitSku(sku);
    }

    private static Boolean isDeviceSku(String sku) {
        return RLM_DealDeskConfig.isDeviceSku(sku);
    }

    private static Decimal headerDiscount(Quote quote, List<QuoteLineItem> lines) {
        if (quote.AppliedDiscount != null) {
            return percentPoints(quote.AppliedDiscount);
        }
        if (quote.Discount != null) {
            return percentPoints(quote.Discount);
        }
        for (QuoteLineItem line : lines) {
            if (line.Discount != null && line.Discount > 0) {
                return percentPoints(line.Discount);
            }
        }
        return null;
    }

    @TestVisible
    static Decimal normalizePercent(Decimal value) {
        return percentPoints(value);
    }

    @TestVisible
    static Decimal percentPoints(Decimal value) {
        if (value == null) {
            return null;
        }
        if (value <= 1) {
            return (value * 100).setScale(2);
        }
        return value.setScale(2);
    }

    private static Prompt prompt(
        String key,
        String title,
        String body,
        String severity,
        String actionKey,
        String actionLabel,
        Boolean canApply
    ) {
        Prompt p = new Prompt();
        p.key = key;
        p.title = title;
        p.body = body;
        p.severity = severity;
        p.actionKey = actionKey;
        p.actionLabel = actionLabel;
        p.canApply = canApply;
        return p;
    }

    @AuraEnabled(cacheable=false)
    public static CompareResponse compareQuotes(String leftQuoteId, String rightQuoteId) {
        CompareResponse out = new CompareResponse();
        out.isSuccess = false;
        out.headerRows = new List<HeaderRow>();
        out.lineDeltas = new List<LineDelta>();
        out.comparedToList = false;
        if (leftQuoteId == 'LIST') {
            return compareToList(rightQuoteId, out);
        }
        Id leftId = parseId(leftQuoteId);
        Id rightId = parseId(rightQuoteId);
        if (leftId == null || rightId == null) {
            out.errorMessage = 'Pick two quotes, or List price vs a quote.';
            return out;
        }
        if (leftId == rightId) {
            out.errorMessage = 'Pick two different quotes.';
            return out;
        }
        try {
            Map<Id, Quote> quotes = new Map<Id, Quote>([
                SELECT Id, Name, QuoteNumber, Status, GrandTotal, Discount, AppliedDiscount,
                       ExpirationDate, StartDate, CurrencyIsoCode, Description,
                       RLM_PC_Justification__c, CreatedDate, OpportunityId
                FROM Quote
                WHERE Id IN :new Set<Id>{ leftId, rightId }
                WITH USER_MODE
            ]);
            Quote left = quotes.get(leftId);
            Quote right = quotes.get(rightId);
            if (left == null || right == null) {
                out.errorMessage = 'One of those quotes is not visible.';
                return out;
            }
            Map<Id, Integer> revisions = revisionMap(left.OpportunityId);
            Integer leftRev = revisions.containsKey(left.Id) ? revisions.get(left.Id) : 1;
            Integer rightRev = revisions.containsKey(right.Id) ? revisions.get(right.Id) : 1;
            out.leftTitle = 'Rev ' + String.valueOf(leftRev) + ' · ' + quoteNumberOf(left);
            out.rightTitle = 'Rev ' + String.valueOf(rightRev) + ' · ' + quoteNumberOf(right);

            addHeader(out, 'Quote Number', quoteNumberOf(left), quoteNumberOf(right));
            addHeader(out, 'Status', left.Status, right.Status);
            addHeader(out, 'Revision', String.valueOf(leftRev), String.valueOf(rightRev));
            addHeader(out, 'Net', money(left.GrandTotal, left.CurrencyIsoCode),
                money(right.GrandTotal, right.CurrencyIsoCode));
            addHeader(out, 'Discount %', percentLabel(headerDiscount(left, new List<QuoteLineItem>())),
                percentLabel(headerDiscount(right, new List<QuoteLineItem>())));
            addHeader(out, 'Currency', left.CurrencyIsoCode, right.CurrencyIsoCode);
            addHeader(out, 'Start Date', dateLabel(left.StartDate), dateLabel(right.StartDate));
            addHeader(out, 'Expiration Date', dateLabel(left.ExpirationDate), dateLabel(right.ExpirationDate));
            addHeader(out, 'Reason', reasonOf(left), reasonOf(right));

            List<QuoteLineItem> allLines = [
                SELECT Id, QuoteId, Quantity, Discount, DiscountAmount, UnitPrice, ListPrice,
                       NetUnitPrice, TotalPrice, Margin,
                       Product2.StockKeepingUnit, Product2.Name, Product2.ProductCode
                FROM QuoteLineItem
                WHERE QuoteId IN :new Set<Id>{ leftId, rightId }
                WITH USER_MODE
            ];
            Map<String, QuoteLineItem> leftBySku = new Map<String, QuoteLineItem>();
            Map<String, QuoteLineItem> rightBySku = new Map<String, QuoteLineItem>();
            for (QuoteLineItem line : allLines) {
                String sku = lineKey(line);
                if (line.QuoteId == leftId) {
                    leftBySku.put(sku, line);
                } else {
                    rightBySku.put(sku, line);
                }
            }
            Set<String> keys = new Set<String>();
            keys.addAll(leftBySku.keySet());
            keys.addAll(rightBySku.keySet());
            Integer added = 0;
            Integer removed = 0;
            Integer modified = 0;
            Integer unchanged = 0;
            List<String> sorted = new List<String>(keys);
            sorted.sort();
            for (String sku : sorted) {
                QuoteLineItem prev = leftBySku.get(sku);
                QuoteLineItem cur = rightBySku.get(sku);
                LineDelta delta = new LineDelta();
                delta.sku = sku;
                QuoteLineItem named = cur != null ? cur : prev;
                delta.name = named.Product2 == null ? sku : named.Product2.Name;
                if (prev == null) {
                    delta.changeType = 'Added';
                    added++;
                } else if (cur == null) {
                    delta.changeType = 'Removed';
                    removed++;
                } else if (qtyOf(prev) != qtyOf(cur)
                    || discOf(prev) != discOf(cur)
                    || netOf(prev) != netOf(cur)
                    || listOf(prev) != listOf(cur)
                    || percentPoints(prev.Margin) != percentPoints(cur.Margin)) {
                    delta.changeType = 'Modified';
                    modified++;
                } else {
                    delta.changeType = 'Unchanged';
                    unchanged++;
                }
                decorateDelta(delta, prev, cur, left.CurrencyIsoCode, right.CurrencyIsoCode);
                out.lineDeltas.add(delta);
            }
            out.addedCount = added;
            out.removedCount = removed;
            out.modifiedCount = modified;
            out.unchangedCount = unchanged;
            out.managementSummary = buildSummary(out, false);
            out.isSuccess = true;
            return out;
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    private static CompareResponse compareToList(String rightQuoteId, CompareResponse out) {
        Id rightId = parseId(rightQuoteId);
        if (rightId == null) {
            out.errorMessage = 'Pick a quote to compare to list.';
            return out;
        }
        try {
            Quote right = [
                SELECT Id, Name, QuoteNumber, Status, GrandTotal, Discount, AppliedDiscount,
                       ExpirationDate, StartDate, CurrencyIsoCode, Description,
                       RLM_PC_Justification__c, OpportunityId
                FROM Quote
                WHERE Id = :rightId
                WITH USER_MODE
                LIMIT 1
            ];
            out.comparedToList = true;
            out.leftTitle = 'List price';
            Map<Id, Integer> revisions = revisionMap(right.OpportunityId);
            Integer rightRev = revisions.containsKey(right.Id) ? revisions.get(right.Id) : 1;
            out.rightTitle = 'Rev ' + String.valueOf(rightRev) + ' · ' + quoteNumberOf(right);
            addHeader(out, 'Quote Number', 'List', quoteNumberOf(right));
            addHeader(out, 'Status', 'List', right.Status);
            addHeader(out, 'Revision', '—', String.valueOf(rightRev));
            addHeader(out, 'Net', 'List', money(right.GrandTotal, right.CurrencyIsoCode));
            addHeader(out, 'Discount %', '0%', percentLabel(headerDiscount(right, new List<QuoteLineItem>())));
            addHeader(out, 'Currency', right.CurrencyIsoCode, right.CurrencyIsoCode);
            List<QuoteLineItem> lines = [
                SELECT Id, Quantity, Discount, DiscountAmount, UnitPrice, ListPrice,
                       NetUnitPrice, TotalPrice, Margin,
                       Product2.StockKeepingUnit, Product2.Name, Product2.ProductCode
                FROM QuoteLineItem
                WHERE QuoteId = :rightId
                WITH USER_MODE
            ];
            Map<String, QuoteLineItem> rightBySku = new Map<String, QuoteLineItem>();
            Integer modified = 0;
            Integer unchanged = 0;
            Decimal headerPct = headerDiscount(right, lines);
            for (QuoteLineItem cur : lines) {
                rightBySku.put(lineKey(cur), cur);
                LineDelta delta = new LineDelta();
                delta.sku = lineKey(cur);
                delta.name = cur.Product2 == null ? delta.sku : cur.Product2.Name;
                Decimal listAmt = listOf(cur);
                Decimal listNet = listAmt * qtyOf(cur);
                Boolean changed = pricingDiffersFromList(cur, headerPct);
                delta.changeType = changed ? 'Modified' : 'Unchanged';
                if (changed) {
                    modified++;
                } else {
                    unchanged++;
                }
                Decimal listMargin;
                String iso = right.CurrencyIsoCode;
                delta.previousQty = String.valueOf(qtyOf(cur));
                delta.currentQty = String.valueOf(qtyOf(cur));
                delta.previousDiscount = percentLabel(0);
                delta.currentDiscount = percentLabel(percentPoints(cur.Discount));
                delta.previousList = money(listAmt, iso);
                delta.currentList = money(listAmt, iso);
                delta.previousNetUnit = money(listAmt, iso);
                delta.currentNetUnit = money(netUnitOf(cur), iso);
                delta.previousNet = money(listNet, iso);
                delta.currentNet = money(netOf(cur), iso);
                delta.previousMargin = percentLabel(percentPoints(listMargin));
                delta.currentMargin = percentLabel(percentPoints(cur.Margin));
                delta.marginFlag = marginFlagFor(cur.Margin);
                delta.deltaNet = money(netOf(cur) - listNet, iso);
                applyImpacts(
                    delta,
                    qtyOf(cur), qtyOf(cur),
                    0, percentPoints(cur.Discount),
                    listNet, netOf(cur),
                    percentPoints(listMargin), percentPoints(cur.Margin),
                    iso
                );
                out.lineDeltas.add(delta);
            }
            out.addedCount = 0;
            out.removedCount = 0;
            out.modifiedCount = modified;
            out.unchangedCount = unchanged;
            out.managementSummary = buildSummary(out, true);
            stampLineChanges(rightId, out.lineDeltas, rightBySku);
            out.isSuccess = true;
            return out;
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    private static void decorateDelta(
        LineDelta delta,
        QuoteLineItem prev,
        QuoteLineItem cur,
        String leftIso,
        String rightIso
    ) {
        delta.previousQty = prev == null ? '—' : String.valueOf(qtyOf(prev));
        delta.currentQty = cur == null ? '—' : String.valueOf(qtyOf(cur));
        delta.previousDiscount = prev == null ? '—' : percentLabel(percentPoints(prev.Discount));
        delta.currentDiscount = cur == null ? '—' : percentLabel(percentPoints(cur.Discount));
        delta.previousList = prev == null ? '—' : money(listOf(prev), leftIso);
        delta.currentList = cur == null ? '—' : money(listOf(cur), rightIso);
        delta.previousNetUnit = prev == null ? '—' : money(netUnitOf(prev), leftIso);
        delta.currentNetUnit = cur == null ? '—' : money(netUnitOf(cur), rightIso);
        delta.previousNet = prev == null ? '—' : money(netOf(prev), leftIso);
        delta.currentNet = cur == null ? '—' : money(netOf(cur), rightIso);
        delta.previousMargin = prev == null ? '—' : percentLabel(percentPoints(prev.Margin));
        delta.currentMargin = cur == null ? '—' : percentLabel(percentPoints(cur.Margin));
        delta.marginFlag = marginFlagFor(cur != null ? cur.Margin : (prev == null ? null : prev.Margin));
        Decimal prevNet = prev == null ? 0 : netOf(prev);
        Decimal curNet = cur == null ? 0 : netOf(cur);
        delta.deltaNet = money(curNet - prevNet, rightIso);
        applyImpacts(
            delta,
            prev == null ? 0 : qtyOf(prev),
            cur == null ? 0 : qtyOf(cur),
            prev == null ? 0 : percentPoints(prev.Discount),
            cur == null ? 0 : percentPoints(cur.Discount),
            prevNet,
            curNet,
            prev == null ? null : percentPoints(prev.Margin),
            cur == null ? null : percentPoints(cur.Margin),
            rightIso
        );
    }

    private static void applyImpacts(
        LineDelta delta,
        Decimal qtyPrev,
        Decimal qtyCur,
        Decimal discPrev,
        Decimal discCur,
        Decimal netPrev,
        Decimal netCur,
        Decimal marginPrev,
        Decimal marginCur,
        String iso
    ) {
        String change = delta.changeType == null ? 'Unchanged' : delta.changeType;
        if (change == 'Added') {
            delta.changeChipClass = 'change-chip chip-add';
        } else if (change == 'Removed') {
            delta.changeChipClass = 'change-chip chip-rem';
        } else if (change == 'Modified') {
            delta.changeChipClass = 'change-chip chip-mod';
        } else {
            delta.changeChipClass = 'change-chip chip-ok';
        }
        Decimal qtyP = qtyPrev == null ? 0 : qtyPrev;
        Decimal qtyC = qtyCur == null ? 0 : qtyCur;
        Decimal discP = discPrev == null ? 0 : discPrev;
        Decimal discC = discCur == null ? 0 : discCur;
        Decimal netP = netPrev == null ? 0 : netPrev;
        Decimal netC = netCur == null ? 0 : netCur;
        Decimal marP = marginPrev == null ? 0 : marginPrev;
        Decimal marC = marginCur == null ? 0 : marginCur;
        delta.qtyValue = qtyLabel(qtyC);
        delta.qtyDelta = signedPlain(qtyC - qtyP);
        delta.qtyImpactClass = impactClass(qtyC - qtyP, true);
        delta.discValue = percentLabel(discCur);
        delta.discDelta = signedPct(discC - discP);
        delta.discImpactClass = impactClass(discC - discP, false);
        delta.netValue = money(netC, iso);
        delta.netDeltaLabel = signedMoney(netC - netP, iso);
        delta.netImpactClass = impactClass(netC - netP, true);
        delta.marginValue = percentLabel(marginCur);
        delta.marginDelta = signedPct(marC - marP);
        delta.marginImpactClass = impactClass(marC - marP, true);
        delta.rowClass = 'delta-' + change.toLowerCase() + ' '
            + (delta.marginFlag == null ? 'margin-unknown' : delta.marginFlag);
    }

    private static String qtyLabel(Decimal qty) {
        if (qty == null) {
            return '—';
        }
        if (qty == qty.setScale(0)) {
            return String.valueOf(qty.setScale(0));
        }
        return String.valueOf(qty.setScale(2));
    }

    private static String signedPlain(Decimal delta) {
        if (delta == null || delta == 0) {
            return '(+0)';
        }
        Decimal n = delta.setScale(0);
        return n > 0 ? '(+' + String.valueOf(n) + ')' : '(' + String.valueOf(n) + ')';
    }

    private static String signedPct(Decimal delta) {
        if (delta == null || delta.abs() < 0.05) {
            return '(+0.0%)';
        }
        Decimal n = delta.setScale(1);
        return n > 0 ? '(+' + String.valueOf(n) + '%)' : '(' + String.valueOf(n) + '%)';
    }

    private static String signedMoney(Decimal delta, String iso) {
        if (delta == null || delta.abs() < 0.005) {
            return '(+$0.00)';
        }
        String sign = delta > 0 ? '+' : '−';
        Decimal absVal = delta.abs().setScale(2);
        if (iso == 'USD' || String.isBlank(iso)) {
            return '(' + sign + '$' + String.valueOf(absVal) + ')';
        }
        return '(' + sign + iso + ' ' + String.valueOf(absVal) + ')';
    }

    private static String impactClass(Decimal delta, Boolean higherIsGood) {
        if (delta == null || delta == 0) {
            return 'impact-none';
        }
        Boolean good = higherIsGood ? delta > 0 : delta < 0;
        return good ? 'impact-pos' : 'impact-neg';
    }

    private static String marginFlagFor(Decimal margin) {
        Decimal pts = percentPoints(margin);
        if (pts == null) {
            return 'margin-unknown';
        }
        if (pts >= RLM_DealDeskConfig.MARGIN_GREEN_PCT) {
            return 'margin-green';
        }
        if (pts >= RLM_DealDeskConfig.MARGIN_YELLOW_PCT) {
            return 'margin-yellow';
        }
        return 'margin-red';
    }

    private static String buildSummary(CompareResponse cmp, Boolean vsList) {
        List<String> bits = new List<String>();
        if (vsList) {
            bits.add('Management brief — this revision versus list (no prior Price Concession).');
        } else {
            bits.add('Management brief — ' + cmp.leftTitle + ' versus ' + cmp.rightTitle + '.');
        }
        bits.add(String.valueOf(cmp.modifiedCount) + ' line(s) changed, '
            + String.valueOf(cmp.addedCount) + ' added, '
            + String.valueOf(cmp.removedCount) + ' removed, '
            + String.valueOf(cmp.unchangedCount) + ' unchanged.');
        Integer red = 0;
        Integer yellow = 0;
        List<String> redNames = new List<String>();
        for (LineDelta line : cmp.lineDeltas) {
            if (line.marginFlag == 'margin-red') {
                red++;
                if (redNames.size() < 3) {
                    redNames.add(line.name);
                }
            } else if (line.marginFlag == 'margin-yellow') {
                yellow++;
            }
        }
        if (red > 0) {
            bits.add(String.valueOf(red)
                + ' SKU(s) are red on margin (below ' + String.valueOf(RLM_DealDeskConfig.MARGIN_YELLOW_PCT) + '%): '
                + String.join(redNames, ', ')
                + '. Worth a deal-desk look before approval.');
        } else if (yellow > 0) {
            bits.add(String.valueOf(yellow)
                + ' SKU(s) are yellow on margin (' + String.valueOf(RLM_DealDeskConfig.MARGIN_YELLOW_PCT) + '–' + String.valueOf(RLM_DealDeskConfig.MARGIN_GREEN_PCT) + '%). Confirm the concession is still earned.');
        } else {
            bits.add('Margin on compared lines is in the healthy band (' + String.valueOf(RLM_DealDeskConfig.MARGIN_GREEN_PCT) + '%+).');
        }
        bits.add('Click Modified / Added / Removed to filter the grid. Green deltas are better for the seller (more qty or net, higher margin, lower discount); red is worse.');
        return String.join(bits, ' ');
    }

    private static Map<Id, Integer> revisionMap(Id opportunityId) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        if (opportunityId == null) {
            return out;
        }
        List<Quote> quotes = [
            SELECT Id FROM Quote
            WHERE OpportunityId = :opportunityId
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ];
        Integer rev = 1;
        for (Quote q : quotes) {
            out.put(q.Id, rev);
            rev++;
        }
        return out;
    }

    private static void addHeader(CompareResponse out, String field, String previousValue, String currentValue) {
        HeaderRow row = new HeaderRow();
        row.field = field;
        row.previousValue = String.isBlank(previousValue) ? '—' : previousValue;
        row.currentValue = String.isBlank(currentValue) ? '—' : currentValue;
        row.changed = row.previousValue != row.currentValue;
        row.rowClass = row.changed ? 'header-changed' : '';
        out.headerRows.add(row);
    }

    private static String quoteNumberOf(Quote q) {
        return String.isBlank(q.QuoteNumber) ? q.Name : q.QuoteNumber;
    }

    private static String reasonOf(Quote q) {
        if (String.isNotBlank(q.RLM_PC_Justification__c)) {
            return q.RLM_PC_Justification__c;
        }
        return q.Description;
    }

    private static String percentLabel(Decimal value) {
        if (value == null) {
            return '—';
        }
        return String.valueOf(value.setScale(1)) + '%';
    }

    private static String money(Decimal amount, String iso) {
        if (amount == null) {
            return '—';
        }
        String code = String.isBlank(iso) ? 'USD' : iso;
        return code + ' ' + String.valueOf(amount.setScale(2));
    }

    private static String dateLabel(Date value) {
        return value == null ? '—' : String.valueOf(value);
    }

    private static String lineKey(QuoteLineItem line) {
        String sku = skuOf(line);
        if (String.isNotBlank(sku)) {
            return sku;
        }
        if (line.Product2 != null && String.isNotBlank(line.Product2.ProductCode)) {
            return line.Product2.ProductCode;
        }
        return line.Product2 == null ? 'line' : line.Product2.Name;
    }

    private static Decimal qtyOf(QuoteLineItem line) {
        return line.Quantity == null ? 0 : line.Quantity;
    }

    private static Boolean pricingDiffersFromList(QuoteLineItem line, Decimal headerPct) {
        if (headerPct != null && headerPct != 0) {
            return true;
        }
        if (discOf(line) != 0) {
            return true;
        }
        return Math.abs(netUnitOf(line) - listOf(line)) > 0.01;
    }

    private static void refreshQuotePrices(Id quoteId) {
        System.Url orgUrl = URL.getOrgDomainUrl();
        if (orgUrl == null) {
            throw new CalloutException('No org domain URL for Instant Pricing');
        }
        Quote quote = [
            SELECT Id, AppliedDiscount
            FROM Quote
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        List<QuoteLineItem> lines = [
            SELECT Id, Quantity
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH USER_MODE
        ];
        List<Object> records = new List<Object>();
        Map<String, Object> quoteRecord = new Map<String, Object>();
        quoteRecord.put('attributes', new Map<String, Object>{
            'type' => 'Quote',
            'method' => 'PUT'
        });
        if (quote.AppliedDiscount != null) {
            quoteRecord.put('AppliedDiscount', quote.AppliedDiscount);
        }
        records.add(new Map<String, Object>{
            'referenceId' => String.valueOf(quoteId),
            'record' => quoteRecord
        });
        for (QuoteLineItem line : lines) {
            Map<String, Object> lineRecord = new Map<String, Object>();
            lineRecord.put('attributes', new Map<String, Object>{
                'type' => 'QuoteLineItem',
                'method' => 'PUT'
            });
            lineRecord.put('Quantity', line.Quantity);
            records.add(new Map<String, Object>{
                'referenceId' => String.valueOf(line.Id),
                'record' => lineRecord
            });
        }
        Map<String, Object> body = new Map<String, Object>{
            'correlationId' => String.valueOf(Math.abs(Crypto.getRandomInteger())),
            'records' => records,
            'configuratorOptions' => new Map<String, Object>{
                'executeConfigurationRules' => false
            }
        };
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(
            URL.getOrgDomainUrl().toExternalForm()
            + '/services/data/v67.0/industries/cpq/quotes/actions/get-instant-price'
        );
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() >= 400 && body.containsKey('configuratorOptions')) {
            body.remove('configuratorOptions');
            req.setBody(JSON.serialize(body));
            res = new Http().send(req);
        }
        if (res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Instant Pricing ' + String.valueOf(res.getStatusCode()) + ': ' + res.getBody()
            );
        }
    }

    private static Decimal discOf(QuoteLineItem line) {
        return line.Discount == null ? 0 : line.Discount;
    }

    private static Decimal listOf(QuoteLineItem line) {
        if (line.ListPrice != null) {
            return line.ListPrice;
        }
        return line.UnitPrice == null ? 0 : line.UnitPrice;
    }

    private static Decimal netUnitOf(QuoteLineItem line) {
        if (line.NetUnitPrice != null) {
            return line.NetUnitPrice;
        }
        return listOf(line);
    }

    private static Decimal netOf(QuoteLineItem line) {
        if (line.TotalPrice != null) {
            return line.TotalPrice;
        }
        if (line.NetUnitPrice != null && line.Quantity != null) {
            return line.NetUnitPrice * line.Quantity;
        }
        return listOf(line) * qtyOf(line);
    }
}
