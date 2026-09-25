@isTest
private class RLM_LockApprovedQuoteTest {

    @isTest
    static void locksApprovedQuote() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Lock Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Lock Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'Lock Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert q;

        RLM_LockApprovedQuote.LockInput input = new RLM_LockApprovedQuote.LockInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        RLM_LockApprovedQuote.lockQuotes(
            new List<RLM_LockApprovedQuote.LockInput>{ input }
        );
        Test.stopTest();
        System.assertEquals(true, Approval.isLocked(q.Id));
    }
}
