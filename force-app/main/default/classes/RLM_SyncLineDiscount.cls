/**
 * Copies header AppliedDiscount (Quote Adjustment) onto lines so TLE
 * approval flags fire. Quote.Discount is not writeable in this org.
 * The calc formula can only see line Discount — ListPrice/NetUnitPrice
 * cannot be used there because the field rolls up to Approval Level.
 */
public without sharing class RLM_SyncLineDiscount {

    public class SyncInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
    }

    @InvocableMethod(label='Sync Line Discount From Header'
        description='Writes Quote.AppliedDiscount onto quote lines so Manager/Director/VP flags appear.')
    public static void sync(List<SyncInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> quoteIds = new Set<Id>();
        for (SyncInput input : inputs) {
            if (input == null || String.isBlank(input.quoteId)) {
                continue;
            }
            try {
                Id quoteId = Id.valueOf(input.quoteId);
                if (String.valueOf(quoteId).startsWith('0Q0')) {
                    quoteIds.add(quoteId);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.FINE, 'Skip discount sync, invalid Id');
            }
        }
        if (quoteIds.isEmpty()) {
            return;
        }
        Map<Id, Quote> quotes = new Map<Id, Quote>([
            SELECT Id, AppliedDiscount FROM Quote WHERE Id IN :quoteIds
        ]);
        List<QuoteLineItem> lines = [
            SELECT Id, QuoteId, Discount FROM QuoteLineItem WHERE QuoteId IN :quoteIds
        ];
        List<QuoteLineItem> patches = new List<QuoteLineItem>();
        for (QuoteLineItem line : lines) {
            Quote q = quotes.get(line.QuoteId);
            if (q == null) {
                continue;
            }
            Decimal header = normalizePercent(q.AppliedDiscount);
            if (header == null) {
                continue;
            }
            Decimal current = line.Discount == null ? 0 : line.Discount;
            if (Math.abs(current - header) > 0.0001) {
                patches.add(new QuoteLineItem(Id = line.Id, Discount = header));
            }
        }
        if (!patches.isEmpty()) {
            update patches;
        }
    }

    @TestVisible
    static Decimal normalizePercent(Decimal value) {
        if (value == null) {
            return null;
        }
        Decimal header = value;
        if (header >= 1) {
            header = header / 100;
        }
        return header.setScale(4);
    }
}
