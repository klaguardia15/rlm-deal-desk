/**
 * Flags Create Order when quote net or discount drifted from the approved PC snapshot.
 */
public with sharing class RLM_CheckApprovedDrift {

    public class DriftInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
    }

    public class DriftOutput {
        @InvocableVariable(label='Needs Another Approval')
        public Boolean needsAnotherApproval;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
    }

    @InvocableMethod(label='Check Approved PC Drift'
        description='Compares current quote net/discount to the approved snapshot.')
    public static List<DriftOutput> check(List<DriftInput> inputs) {
        List<DriftOutput> results = new List<DriftOutput>();
        if (inputs == null) {
            return results;
        }
        for (DriftInput input : inputs) {
            results.add(checkOne(input));
        }
        return results;
    }

    @AuraEnabled
    public static DriftOutput checkQuote(String quoteId) {
        DriftInput input = new DriftInput();
        input.quoteId = quoteId;
        List<DriftOutput> results = check(new List<DriftInput>{ input });
        return results.isEmpty() ? null : results[0];
    }

    private static DriftOutput checkOne(DriftInput input) {
        DriftOutput out = new DriftOutput();
        out.isSuccess = false;
        out.needsAnotherApproval = false;
        if (input == null || String.isBlank(input.quoteId)) {
            out.message = 'Quote Id is required.';
            return out;
        }
        Id quoteId;
        try {
            quoteId = Id.valueOf(input.quoteId);
        } catch (Exception e) {
            out.message = 'Invalid quote Id.';
            return out;
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Quote.fields.getMap();
        if (!fields.containsKey('rlm_approved_grand_total__c')) {
            out.isSuccess = true;
            out.message = 'No approved snapshot fields on this org.';
            return out;
        }
        Quote q = [
            SELECT Id, Name, Status, GrandTotal, Discount, RLM_Discount_Percent__c,
                   RLM_Approved_Grand_Total__c, RLM_Approved_Discount_Pct__c
            FROM Quote
            WHERE Id = :quoteId
            WITH USER_MODE
            LIMIT 1
        ];
        if (q.RLM_Approved_Grand_Total__c == null) {
            out.isSuccess = true;
            out.message = 'No approved snapshot yet. Approve the PC before Create Order.';
            return out;
        }
        Decimal currentNet = q.GrandTotal == null ? 0 : q.GrandTotal;
        Decimal approvedNet = q.RLM_Approved_Grand_Total__c;
        Decimal currentDisc = q.RLM_Discount_Percent__c;
        if (currentDisc == null && q.Discount != null) {
            currentDisc = q.Discount >= 1 ? q.Discount : q.Discount * 100;
        }
        Boolean netDrift = approvedNet != null && currentNet.setScale(2) != approvedNet.setScale(2);
        Boolean discDrift = q.RLM_Approved_Discount_Pct__c != null && currentDisc != null
            && currentDisc.setScale(2) != q.RLM_Approved_Discount_Pct__c.setScale(2);
        out.isSuccess = true;
        if (netDrift || discDrift) {
            out.needsAnotherApproval = true;
            out.message = 'Prices or margins drifted from the approved PC. Needs another approval before Create Order.';
        } else {
            out.message = 'Current numbers match the approved PC.';
        }
        return out;
    }
}
