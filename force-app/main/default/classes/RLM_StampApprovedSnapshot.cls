/**
 * Stamps approved net and discount when Status becomes Approved.
 * Replaces click-lock as the required beat; lock Apex remains for speak-to.
 */
public with sharing class RLM_StampApprovedSnapshot {

    public class StampInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
    }

    @InvocableMethod(label='Stamp Approved PC Snapshot'
        description='Writes approved grand total and discount so Create Order can flag drift.')
    public static void stamp(List<StampInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> quoteIds = new Set<Id>();
        for (StampInput input : inputs) {
            if (input == null || String.isBlank(input.quoteId)) {
                continue;
            }
            try {
                Id quoteId = Id.valueOf(input.quoteId);
                if (String.valueOf(quoteId).startsWith('0Q0')) {
                    quoteIds.add(quoteId);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.FINE, 'Skip approved snapshot, invalid Id');
            }
        }
        if (quoteIds.isEmpty()) {
            return;
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Quote.fields.getMap();
        if (!fields.containsKey('rlm_approved_grand_total__c')) {
            return;
        }
        List<Quote> quotes = [
            SELECT Id, GrandTotal, Discount, RLM_Discount_Percent__c
            FROM Quote
            WHERE Id IN :quoteIds
            WITH USER_MODE
        ];
        List<Quote> patches = new List<Quote>();
        for (Quote q : quotes) {
            Quote patch = new Quote(Id = q.Id);
            patch.put('RLM_Approved_Grand_Total__c', q.GrandTotal);
            Decimal discountPct = q.RLM_Discount_Percent__c;
            if (discountPct == null && q.Discount != null) {
                discountPct = q.Discount >= 1 ? q.Discount : q.Discount * 100;
            }
            if (fields.containsKey('rlm_approved_discount_pct__c') && discountPct != null) {
                patch.put('RLM_Approved_Discount_Pct__c', discountPct);
            }
            patches.add(patch);
        }
        if (!patches.isEmpty()) {
            update as user patches;
        }
    }
}
