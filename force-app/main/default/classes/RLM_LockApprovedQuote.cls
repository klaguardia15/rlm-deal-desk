/**
 * Platform-locks a quote after Smart Approval sets Status to Approved.
 * Replaces the Word-file leakage path: the approved PC cannot be quietly restacked.
 */
public with sharing class RLM_LockApprovedQuote {

    public class LockInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
    }

    @InvocableMethod(label='Lock Approved Quote'
        description='Calls Approval.lock on the quote so an approved PC cannot be edited.')
    public static void lockQuotes(List<LockInput> inputs) {
        if (inputs == null) {
            return;
        }
        List<Id> toLock = new List<Id>();
        for (LockInput input : inputs) {
            if (input == null || String.isBlank(input.quoteId)) {
                continue;
            }
            try {
                Id quoteId = Id.valueOf(input.quoteId);
                if (String.valueOf(quoteId).startsWith('0Q0')) {
                    toLock.add(quoteId);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.FINE, 'Skip lock, invalid Id');
            }
        }
        if (!toLock.isEmpty()) {
            Approval.lock(toLock, false);
        }
    }
}
