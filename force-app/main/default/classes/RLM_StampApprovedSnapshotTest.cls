@isTest
private class RLM_StampApprovedSnapshotTest {

    @isTest
    static void stampsGrandTotal() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Snapshot Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Snapshot Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'Snapshot Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert q;

        RLM_StampApprovedSnapshot.StampInput input =
            new RLM_StampApprovedSnapshot.StampInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        RLM_StampApprovedSnapshot.stamp(
            new List<RLM_StampApprovedSnapshot.StampInput>{ input }
        );
        Test.stopTest();

        Quote stored = [
            SELECT RLM_Approved_Grand_Total__c FROM Quote WHERE Id = :q.Id
        ];
        System.assertNotEquals(null, stored.RLM_Approved_Grand_Total__c);
    }
}
