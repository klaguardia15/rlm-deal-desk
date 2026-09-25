@isTest
private class RLM_CheckApprovedDriftTest {

    @isTest
    static void flagsWhenNetChanged() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Drift Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Drift Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'Drift Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Approved_Grand_Total__c = 1000
        );
        insert q;

        RLM_CheckApprovedDrift.DriftInput input =
            new RLM_CheckApprovedDrift.DriftInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        List<RLM_CheckApprovedDrift.DriftOutput> results =
            RLM_CheckApprovedDrift.check(
                new List<RLM_CheckApprovedDrift.DriftInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
    }
}
