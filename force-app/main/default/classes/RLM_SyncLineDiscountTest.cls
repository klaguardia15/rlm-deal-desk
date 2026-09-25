@isTest
private class RLM_SyncLineDiscountTest {

    @isTest
    static void normalizesHeaderPercent() {
        Decimal fromFraction = RLM_SyncLineDiscount.normalizePercent(0.22);
        Decimal fromWhole = RLM_SyncLineDiscount.normalizePercent(22);
        System.assert(fromFraction != null && Math.abs(fromFraction - 0.22) < 0.0001);
        System.assert(fromWhole != null && Math.abs(fromWhole - 0.22) < 0.0001);
        System.assertEquals(null, RLM_SyncLineDiscount.normalizePercent(null));
    }

    @isTest
    static void copiesAppliedDiscountToLines() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Discount Sync Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Discount Sync Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 prod = new Product2(
            Name = 'TC53',
            StockKeepingUnit = 'DEVICE-DS-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert prod;
        insert new PricebookEntry(Pricebook2Id = pbId, Product2Id = prod.Id, UnitPrice = 1895, IsActive = true);
        Quote q = new Quote(
            Name = 'Discount Sync Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            AppliedDiscount = 0.22
        );
        insert q;
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1895, Product2Id = prod.Id
        );

        RLM_SyncLineDiscount.SyncInput input = new RLM_SyncLineDiscount.SyncInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        RLM_SyncLineDiscount.sync(new List<RLM_SyncLineDiscount.SyncInput>{ input });
        Test.stopTest();

        QuoteLineItem line = [SELECT Discount FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1];
        System.assert(Math.abs(line.Discount - 0.22) < 0.0001, 'Expected 22% on the line');
    }
}
