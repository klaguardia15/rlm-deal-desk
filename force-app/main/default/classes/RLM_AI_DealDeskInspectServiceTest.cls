@isTest
private class RLM_AI_DealDeskInspectServiceTest {

    @isTest
    static void flagsMissingAccessoriesAndPadding() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Inspect Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Inspect Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 tc53 = new Product2(
            Name = 'TC53 Mobile Computer',
            StockKeepingUnit = 'DEVICE-INSP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            ProductCode = 'DEVICE',
            IsActive = true
        );
        Product2 pad = new Product2(
            Name = 'Workstation Connect Cradle',
            StockKeepingUnit = 'PADDING-1-INSP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            ProductCode = 'PADDING-1',
            IsActive = true
        );
        insert new List<Product2>{ tc53, pad };
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = tc53.Id, UnitPrice = 1895, IsActive = true),
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = pad.Id, UnitPrice = 495, IsActive = true)
        };
        Quote q = new Quote(
            Name = 'Inspect Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert q;
        PricebookEntry tc53Pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :tc53.Id LIMIT 1];
        PricebookEntry padPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :pad.Id LIMIT 1];
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = tc53Pbe.Id, Quantity = 1, UnitPrice = 1895, Product2Id = tc53.Id),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = padPbe.Id, Quantity = 1, UnitPrice = 495, Product2Id = pad.Id)
        };

        RLM_AI_DealDeskInspectService.InspectInput input =
            new RLM_AI_DealDeskInspectService.InspectInput();
        input.quoteId = String.valueOf(q.Id);

        Test.startTest();
        List<RLM_AI_DealDeskInspectService.InspectOutput> results =
            RLM_AI_DealDeskInspectService.inspect(
                new List<RLM_AI_DealDeskInspectService.InspectInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess, 'Inspect should succeed: ' + results[0].errorMessage);
        System.assertEquals(true, results[0].hasMissingAccessories);
        System.assertEquals(true, results[0].hasPadding);
        System.assert(results[0].findingsDisplay.contains('ShareCradle')
            || results[0].findingsDisplay.contains('charging'));
        System.assert(results[0].findingsDisplay.contains('Workstation Connect'));
        System.assertEquals(false, results[0].findingsDisplay.contains('<br'));
        System.assertEquals('Risk', results[0].dealHealthStatus);
        System.assert(results[0].findingsDisplay.contains('DISTI')
            || results[0].findingsDisplay.contains('Inspect Account'));
    }

    @isTest
    static void rejectsBlankId() {
        RLM_AI_DealDeskInspectService.InspectInput input =
            new RLM_AI_DealDeskInspectService.InspectInput();
        List<RLM_AI_DealDeskInspectService.InspectOutput> results =
            RLM_AI_DealDeskInspectService.inspect(
                new List<RLM_AI_DealDeskInspectService.InspectInput>{ input }
            );
        System.assertEquals(false, results[0].isSuccess);
    }

    @isTest
    static void approvalBandsMatchCalcField() {
        System.assertEquals(0, RLM_AI_DealDeskInspectService.approvalLevel(10));
        System.assertEquals(1, RLM_AI_DealDeskInspectService.approvalLevel(22));
        System.assertEquals(2, RLM_AI_DealDeskInspectService.approvalLevel(30));
        System.assertEquals(3, RLM_AI_DealDeskInspectService.approvalLevel(40));
    }

    @isTest
    static void partnerRequestQuotesMessageNotDistiHistory() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Channel Inspect Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Partner Inspect Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'Partner Inspect Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Partner_Request__c = true,
            RLM_PC_Justification__c =
                'Need 18% off this Warehouse Frontline Kit for a 10-device refresh.'
        );
        insert q;
        Product2 kit = new Product2(
            Name = 'Warehouse Frontline Kit',
            StockKeepingUnit = 'KIT-PARENT-INSP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert kit;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = kit.Id, UnitPrice = 0, IsActive = true
        );
        PricebookEntry kitPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :kit.Id LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = kitPbe.Id, Quantity = 10, UnitPrice = 0, Product2Id = kit.Id
        );
        RLM_AI_DealDeskInspectService.InspectInput input =
            new RLM_AI_DealDeskInspectService.InspectInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        List<RLM_AI_DealDeskInspectService.InspectOutput> results =
            RLM_AI_DealDeskInspectService.inspect(
                new List<RLM_AI_DealDeskInspectService.InspectInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(true, results.isEmpty() == false, 'inspect should return a row');
        System.assertEquals(true, results[0].isSuccess, 'inspect: ' + results[0].errorMessage);
        System.assert(results[0].findingsDisplay.contains('partner'), results[0].findingsDisplay);
        System.assert(results[0].findingsDisplay.contains('18%'), results[0].findingsDisplay);
        System.assert(results[0].findingsDisplay.contains('channel run-rate'), results[0].findingsDisplay);
    }
}
