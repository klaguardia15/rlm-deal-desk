/**
 * Deal-desk inspect. Flags missing accessories, padding SKUs,
 * revision vs the prior price concession, and approved concession vs order.
 * SKU lists come from RLM_DealDeskConfig.
 * USER_MODE throughout. Persists Deal Health fields when they are deployed.
 */
public with sharing class RLM_AI_DealDeskInspectService {

    private static final Pattern PC_NUMBER = Pattern.compile('(\\d{7,})');

    public class InspectInput {
        @InvocableVariable(required=true label='Quote Id'
            description='18-character Salesforce Id of the Quote (starts with 0Q0).')
        public String quoteId;
    }

    public class InspectOutput {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        @InvocableVariable(label='Has Missing Accessories')
        public Boolean hasMissingAccessories;
        @InvocableVariable(label='Has Padding')
        public Boolean hasPadding;
        @InvocableVariable(label='Suggested Approval Level'
            description='0 none, 1 Manager, 2 Director, 3 VP.')
        public Integer suggestedApprovalLevel;
        @InvocableVariable(label='Findings Display')
        public String findingsDisplay;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Deal Health Status')
        public String dealHealthStatus;
        @InvocableVariable(label='Blended Margin Percent')
        public Decimal blendedMarginPercent;
        @InvocableVariable(label='PC Compare Summary')
        public String pcCompareSummary;
    }

    @InvocableMethod(
        label='Inspect Deal Desk Quote'
        description='Inspects a quote for accessories, padding, the distributor, revision deltas, and price concession vs order.'
    )
    public static List<InspectOutput> inspect(List<InspectInput> inputs) {
        List<InspectOutput> results = new List<InspectOutput>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (InspectInput input : inputs) {
            results.add(inspectOne(input));
        }
        return results;
    }

    @AuraEnabled
    public static InspectOutput inspectQuote(String quoteId) {
        InspectInput input = new InspectInput();
        input.quoteId = quoteId;
        List<InspectOutput> results = inspect(new List<InspectInput>{ input });
        return results.isEmpty() ? null : results[0];
    }

    private static InspectOutput inspectOne(InspectInput input) {
        InspectOutput out = new InspectOutput();
        out.isSuccess = false;
        out.hasMissingAccessories = false;
        out.hasPadding = false;
        out.suggestedApprovalLevel = 0;
        if (input == null || String.isBlank(input.quoteId)) {
            out.errorMessage = 'Quote Id is required.';
            return out;
        }
        Id quoteId;
        try {
            quoteId = Id.valueOf(input.quoteId);
        } catch (Exception e) {
            out.errorMessage = 'Invalid quote Id.';
            return out;
        }
        if (quoteId == null || !String.valueOf(quoteId).startsWith('0Q0')) {
            out.errorMessage = 'Quote Id must be a Quote record.';
            return out;
        }

        try {
            Quote quote = [
                SELECT Id, Name, Status, Discount, RLM_Discount_Percent__c,
                       Account.Name, PartnerAccount.Name, GrandTotal, OpportunityId,
                       Description
                FROM Quote
                WHERE Id = :quoteId
                WITH USER_MODE
                LIMIT 1
            ];
            if (Schema.SObjectType.Quote.fields.getMap().containsKey('rlm_pc_justification__c')) {
                quote = [
                    SELECT Id, Name, Status, Discount, RLM_Discount_Percent__c,
                           Account.Name, PartnerAccount.Name, GrandTotal, OpportunityId,
                           Description, RLM_PC_Justification__c, RLM_Partner_Request__c
                    FROM Quote
                    WHERE Id = :quoteId
                    WITH USER_MODE
                    LIMIT 1
                ];
            }

            List<QuoteLineItem> lines = [
                SELECT Id, Quantity, UnitPrice, ListPrice, Discount, TotalPrice,
                       NetUnitPrice, UnitCost, TotalCost, Margin, TotalMargin,
                       Product2.Name, Product2.StockKeepingUnit, Product2.ProductCode
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
                WITH USER_MODE
                ORDER BY LineNumber
            ];
            return buildFindings(quote, lines, out);
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    private static InspectOutput buildFindings(Quote quote, List<QuoteLineItem> lines, InspectOutput out) {
        Set<String> skus = new Set<String>();
        List<String> paddingNames = new List<String>();
        Decimal revenue = 0;
        Decimal cost = 0;
        Decimal listTotal = 0;
        Decimal netForDiscount = 0;
        Map<String, QuoteLineItem> bySku = new Map<String, QuoteLineItem>();
        for (QuoteLineItem line : lines) {
            String sku = line.Product2 != null ? line.Product2.StockKeepingUnit : null;
            String code = line.Product2 != null ? line.Product2.ProductCode : null;
            if (String.isNotBlank(sku)) {
                skus.add(sku);
                bySku.put(sku, line);
            }
            if (String.isNotBlank(code)) {
                skus.add(code);
            }
            if (RLM_DealDeskConfig.isPaddingSku(sku) || RLM_DealDeskConfig.isPaddingSku(code)) {
                paddingNames.add(line.Product2.Name);
            }
            if (line.TotalPrice != null) {
                revenue += line.TotalPrice;
            }
            Decimal netUnit = line.NetUnitPrice != null ? line.NetUnitPrice : line.UnitPrice;
            if (line.ListPrice != null && line.Quantity != null) {
                listTotal += line.ListPrice * line.Quantity;
            }
            if (netUnit != null && line.Quantity != null) {
                netForDiscount += netUnit * line.Quantity;
            }
            if (line.TotalCost != null) {
                cost += line.TotalCost;
            } else if (line.UnitCost != null && line.Quantity != null) {
                cost += line.UnitCost * line.Quantity;
            }
        }

        Boolean hasDevice = false;
        for (String sku : skus) {
            if (RLM_DealDeskConfig.isDeviceSku(sku)) {
                hasDevice = true;
                break;
            }
        }
        List<String> missing = new List<String>();
        if (hasDevice) {
            for (String reqSku : RLM_DealDeskConfig.REQUIRED_ACCESSORY_SKUS) {
                if (!skus.contains(reqSku)) {
                    missing.add(RLM_DealDeskConfig.REQUIRED_ACCESSORY_LABELS.get(reqSku));
                }
            }
        }
        out.hasMissingAccessories = !missing.isEmpty();
        out.hasPadding = !paddingNames.isEmpty();
        Boolean missingUsbc = hasDevice && !skus.contains(RLM_DealDeskConfig.USB_CABLE_SKU);

        Decimal discountPct = 0;
        if (listTotal > 0 && netForDiscount >= 0) {
            discountPct = ((listTotal - netForDiscount) / listTotal) * 100;
        } else if (quote.RLM_Discount_Percent__c != null) {
            Decimal header = quote.RLM_Discount_Percent__c;
            discountPct = header >= 1 ? header : header * 100;
        } else if (quote.Discount != null) {
            Decimal header = quote.Discount;
            discountPct = header >= 1 ? header : header * 100;
        }
        out.suggestedApprovalLevel = approvalLevel(discountPct);

        Decimal marginPct = 0;
        if (revenue > 0 && cost > 0) {
            marginPct = ((revenue - cost) / revenue) * 100;
        }
        out.blendedMarginPercent = marginPct.setScale(1);

        String distiName = quote.Account != null ? quote.Account.Name : null;
        Boolean missingDisti = String.isBlank(distiName);

        String orderCompare = compareToOrders(quote.Id, skus, lines);
        String pcCompare = compareToPriorQuote(quote, lines, bySku);
        out.pcCompareSummary = pcCompare;

        List<String> nextSteps = new List<String>();
        List<String> flagLines = new List<String>();
        if (out.hasMissingAccessories) {
            flagLines.add('Missing required charging: ' + String.join(missing, '; '));
            nextSteps.add('Add the required charging accessories so the seller does not absorb the cost.');
        }
        if (missingUsbc) {
            flagLines.add('USB-C cable omitted. Staging and first-line support typically include it; skipping it often means a follow-up parts order and a second freight charge.');
            nextSteps.add('Re-open Configure and add ' + RLM_DealDeskConfig.USB_CABLE_SKU + ', or leave it off if the distributor already stocks it.');
        }
        if (out.hasPadding) {
            flagLines.add('Margin padding: ' + String.join(paddingNames, '; '));
            nextSteps.add('Remove padding SKUs unless the distributor asked for them, then re-check margin.');
        }
        if (missingDisti) {
            flagLines.add('Distributor account is blank — this quote has no customer.');
            nextSteps.add('Set the quote account to the distributor on this deal.');
        }
        if (out.suggestedApprovalLevel >= 1 && quote.Status == 'Draft' && !isPartnerRequest(quote)) {
            nextSteps.add('Submit this as a Price Concession (Manager band). Put the bid / contract reason in the comments.');
        }
        if (isPartnerRequest(quote)) {
            nextSteps.add('Confirm, then apply the partner-requested concession from their message. Do not apply the ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% channel run-rate recommendation.');
        }
        if (String.isNotBlank(orderCompare) && orderCompare.startsWith('Order delta')) {
            flagLines.add(orderCompare);
            nextSteps.add('Reconcile the order to the approved price concession before it ships.');
        }
        if (String.isNotBlank(pcCompare) && pcCompare.contains('Modified')) {
            flagLines.add(pcCompare);
        }
        if (nextSteps.isEmpty()) {
            nextSteps.add('Catalog, distributor, and accessories look consistent. Proceed to approval or order.');
        }

        String status = 'Healthy';
        if (out.hasMissingAccessories || missingDisti) {
            status = 'Risk';
        } else if (missingUsbc || out.hasPadding || out.suggestedApprovalLevel >= 1
            || (String.isNotBlank(orderCompare) && orderCompare.startsWith('Order delta'))) {
            status = 'Review';
        }
        out.dealHealthStatus = status;

        List<String> spoken = new List<String>();
        spoken.add(quote.Name + ' is ' + quote.Status + '.');
        if (String.isNotBlank(distiName)) {
            spoken.add('The customer is distributor ' + distiName + '.');
        } else {
            spoken.add('Distributor account is not on this quote.');
        }
        if (isPartnerRequest(quote)) {
            spoken.add('This is a partner Price Concession request, not the ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '% channel run-rate recommendation.');
            String partnerMsg = partnerMessageSnippet(quote);
            if (String.isNotBlank(partnerMsg)) {
                spoken.add('Their message: ' + partnerMsg);
            }
        }
        spoken.add('Realized discount is ' + String.valueOf(discountPct.setScale(1))
            + '% (approval level ' + levelName(out.suggestedApprovalLevel) + ').');
        if (revenue > 0 && cost > 0) {
            spoken.add('Blended margin is ' + String.valueOf(marginPct.setScale(1)) + '%.');
        }
        if (out.hasMissingAccessories) {
            spoken.add('Required charging is missing: ' + String.join(missing, '; ')
                + '. The seller absorbs that cost today if the partner forgets it.');
        } else if (hasDevice) {
            spoken.add('Required charging accessories are on the quote.');
        }
        if (missingUsbc) {
            spoken.add('USB-C cable is off the kit. Staging usually includes it; omitting it often means a follow-up parts order.');
        }
        if (out.hasPadding) {
            spoken.add(String.join(paddingNames, ' and ')
                + ' look like margin padding. They lift blended margin without changing the discount the ladder sees.');
        }
        if (String.isNotBlank(pcCompare)) {
            spoken.add(pcCompare);
        }
        if (String.isNotBlank(orderCompare)) {
            spoken.add(orderCompare);
        }
        spoken.add('Recommended: ' + String.join(nextSteps, ' '));
        out.findingsDisplay = String.join(spoken, ' ');
        out.isSuccess = true;

        persistDealHealth(quote.Id, status, marginPct, flagLines, nextSteps, pcCompare);
        return out;
    }

    private static Boolean isPartnerRequest(Quote quote) {
        try {
            if (Schema.SObjectType.Quote.fields.getMap().containsKey('rlm_partner_request__c')) {
                Object raw = quote.get('RLM_Partner_Request__c');
                if (raw == true) {
                    return true;
                }
            }
        } catch (SObjectException e) {
            System.debug(LoggingLevel.FINE, e.getMessage());
        }
        return String.isNotBlank(partnerMessageSnippet(quote));
    }

    private static String partnerMessageSnippet(Quote quote) {
        try {
            if (!Schema.SObjectType.Quote.fields.getMap().containsKey('rlm_pc_justification__c')) {
                return '';
            }
            Object raw = quote.get('RLM_PC_Justification__c');
            if (raw == null) {
                return '';
            }
            String compact = String.valueOf(raw).replace('\n', ' ').trim();
            if (compact.length() > 180) {
                return compact.substring(0, 177) + '…';
            }
            return compact;
        } catch (SObjectException e) {
            return '';
        }
    }

    @TestVisible
    private static String compareToPriorQuote(
        Quote quote,
        List<QuoteLineItem> lines,
        Map<String, QuoteLineItem> bySku
    ) {
        String justification = '';
        if (Schema.SObjectType.Quote.fields.getMap().containsKey('rlm_pc_justification__c')) {
            Object raw = quote.get('RLM_PC_Justification__c');
            justification = raw == null ? '' : String.valueOf(raw);
        }
        if (String.isBlank(justification)) {
            justification = quote.Description == null ? '' : quote.Description;
        }
        String justRef = justificationRef(justification, quote.Name);

        Quote prior = findPriorQuote(quote);
        if (prior == null) {
            if (String.isNotBlank(justRef)) {
                return 'Justification Ref ' + justRef
                    + ' does not match a previous revision on this opportunity.';
            }
            return null;
        }
        List<QuoteLineItem> priorLines = [
            SELECT Quantity, UnitPrice, Discount, NetUnitPrice, TotalPrice,
                   Product2.StockKeepingUnit, Product2.Name
            FROM QuoteLineItem
            WHERE QuoteId = :prior.Id
            WITH USER_MODE
        ];
        Map<String, QuoteLineItem> priorBySku = new Map<String, QuoteLineItem>();
        for (QuoteLineItem line : priorLines) {
            String sku = line.Product2 != null ? line.Product2.StockKeepingUnit : null;
            if (String.isNotBlank(sku)) {
                priorBySku.put(sku, line);
            }
        }
        Integer added = 0;
        Integer modified = 0;
        Integer unchanged = 0;
        List<String> deltaBits = new List<String>();
        Set<String> allSkus = new Set<String>();
        allSkus.addAll(bySku.keySet());
        allSkus.addAll(priorBySku.keySet());
        for (String sku : allSkus) {
            QuoteLineItem cur = bySku.get(sku);
            QuoteLineItem old = priorBySku.get(sku);
            if (cur == null) {
                modified++;
                deltaBits.add(sku + ' removed');
                continue;
            }
            if (old == null) {
                added++;
                deltaBits.add(sku + ' added');
                continue;
            }
            Decimal curQty = cur.Quantity == null ? 0 : cur.Quantity;
            Decimal oldQty = old.Quantity == null ? 0 : old.Quantity;
            Decimal curDisc = cur.Discount == null ? 0 : cur.Discount;
            Decimal oldDisc = old.Discount == null ? 0 : old.Discount;
            Decimal curPrice = cur.UnitPrice == null ? 0 : cur.UnitPrice;
            Decimal oldPrice = old.UnitPrice == null ? 0 : old.UnitPrice;
            if (curQty != oldQty || curDisc != oldDisc || curPrice != oldPrice) {
                modified++;
                deltaBits.add(sku + ' qty/discount/price changed');
            } else {
                unchanged++;
            }
        }
        String priorKind = 'previous revision ' + prior.Name;
        if (String.isNotBlank(justRef) && !prior.Name.contains(justRef)) {
            priorKind = 'Justification Ref ' + justRef + ' (not the previous revision)';
        }
        return 'AI Analysis vs ' + priorKind + ': '
            + String.valueOf(modified) + ' Modified, +'
            + String.valueOf(added) + ' Added, '
            + String.valueOf(unchanged) + ' Unchanged'
            + (deltaBits.isEmpty() ? '.' : '. Deltas: ' + String.join(deltaBits, '; ') + '.');
    }

    private static Quote findPriorQuote(Quote quote) {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Quote.fields.getMap();
        if (fields.containsKey('rlm_prior_pc__c')) {
            Quote self = [
                SELECT RLM_Prior_PC__c FROM Quote WHERE Id = :quote.Id WITH USER_MODE LIMIT 1
            ];
            if (self.RLM_Prior_PC__c != null) {
                List<Quote> linked = [
                    SELECT Id, Name, Status, GrandTotal
                    FROM Quote
                    WHERE Id = :self.RLM_Prior_PC__c
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!linked.isEmpty()) {
                    return linked[0];
                }
            }
        }
        if (quote.OpportunityId == null) {
            return null;
        }
        List<Quote> siblings = [
            SELECT Id, Name, Status, GrandTotal, CreatedDate
            FROM Quote
            WHERE OpportunityId = :quote.OpportunityId AND Id != :quote.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        return siblings.isEmpty() ? null : siblings[0];
    }

    private static String justificationRef(String text, String currentName) {
        if (String.isBlank(text)) {
            return null;
        }
        Matcher m = PC_NUMBER.matcher(text);
        while (m.find()) {
            String num = m.group(1);
            if (currentName != null && currentName.contains(num)) {
                continue;
            }
            return num;
        }
        return null;
    }

    private static String compareToOrders(Id quoteId, Set<String> quoteSkus, List<QuoteLineItem> lines) {
        List<Order> orders;
        try {
            orders = [
                SELECT Id, OrderNumber, Status, Account.Name
                FROM Order
                WHERE QuoteId = :quoteId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];
        } catch (Exception e) {
            return null;
        }
        if (orders == null || orders.isEmpty()) {
            return null;
        }
        Order latest = orders[0];
        List<OrderItem> items = [
            SELECT Quantity, Product2.Name, Product2.StockKeepingUnit
            FROM OrderItem
            WHERE OrderId = :latest.Id
            WITH USER_MODE
        ];
        Set<String> orderSkus = new Set<String>();
        Map<String, Decimal> orderQty = new Map<String, Decimal>();
        for (OrderItem item : items) {
            String sku = item.Product2 != null ? item.Product2.StockKeepingUnit : null;
            if (String.isBlank(sku)) {
                continue;
            }
            orderSkus.add(sku);
            Decimal qty = orderQty.containsKey(sku) ? orderQty.get(sku) : 0;
            orderQty.put(sku, qty + (item.Quantity == null ? 0 : item.Quantity));
        }
        Map<String, Decimal> quoteQty = new Map<String, Decimal>();
        for (QuoteLineItem line : lines) {
            String sku = line.Product2 != null ? line.Product2.StockKeepingUnit : null;
            if (String.isBlank(sku)) {
                continue;
            }
            Decimal qty = quoteQty.containsKey(sku) ? quoteQty.get(sku) : 0;
            quoteQty.put(sku, qty + (line.Quantity == null ? 0 : line.Quantity));
        }
        List<String> deltas = new List<String>();
        Set<String> allSkus = new Set<String>();
        allSkus.addAll(quoteSkus);
        allSkus.addAll(orderSkus);
        for (String sku : allSkus) {
            Decimal qQty = quoteQty.containsKey(sku) ? quoteQty.get(sku) : 0;
            Decimal oQty = orderQty.containsKey(sku) ? orderQty.get(sku) : 0;
            if (qQty != oQty) {
                deltas.add(sku + ' quote ' + String.valueOf(qQty) + ' vs order ' + String.valueOf(oQty));
            }
        }
        String who = latest.Account != null ? latest.Account.Name : 'the order account';
        if (deltas.isEmpty()) {
            return 'Order ' + latest.OrderNumber + ' matches the approved PC and is for ' + who + '.';
        }
        return 'Order delta vs PC (' + latest.OrderNumber + ' for ' + who + '): '
            + String.join(deltas, '; ') + '.';
    }

    private static void persistDealHealth(
        Id quoteId,
        String status,
        Decimal marginPct,
        List<String> flagLines,
        List<String> nextSteps,
        String pcCompare
    ) {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Quote.fields.getMap();
        if (!fields.containsKey('rlm_deal_health_status__c')) {
            return;
        }
        Quote patch = new Quote(Id = quoteId);
        patch.put('RLM_Deal_Health_Status__c', status);
        if (fields.containsKey('rlm_blended_margin__c')) {
            patch.put('RLM_Blended_Margin__c', marginPct);
        }
        if (fields.containsKey('rlm_deal_health_flags__c')) {
            patch.put('RLM_Deal_Health_Flags__c', flagLines.isEmpty() ? 'None' : String.join(flagLines, '\n'));
        }
        if (fields.containsKey('rlm_deal_health_next_steps__c')) {
            patch.put('RLM_Deal_Health_Next_Steps__c', String.join(nextSteps, '\n'));
        }
        if (fields.containsKey('rlm_deal_health_last_run__c')) {
            patch.put('RLM_Deal_Health_Last_Run__c', System.now());
        }
        if (fields.containsKey('rlm_pc_compare_summary__c') && String.isNotBlank(pcCompare)) {
            patch.put('RLM_PC_Compare_Summary__c', pcCompare);
        }
        try {
            update as user patch;
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'Deal Health persist skipped: ' + e.getMessage());
        }
    }

    private static String levelName(Integer level) {
        if (level == null || level <= 0) {
            return 'none';
        }
        if (level == 1) {
            return 'Manager';
        }
        if (level == 2) {
            return 'Director';
        }
        return 'VP';
    }

    @TestVisible
    private static Integer approvalLevel(Decimal discountPct) {
        if (discountPct == null || discountPct < 15) {
            return 0;
        }
        if (discountPct < 25) {
            return 1;
        }
        if (discountPct < 35) {
            return 2;
        }
        return 3;
    }
}
