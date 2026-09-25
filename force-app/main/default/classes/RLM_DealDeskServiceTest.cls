@isTest
private class RLM_DealDeskServiceTest {

    @isTest
    static void rejectsBlankId() {
        RLM_DealDeskService.PromptResponse out = RLM_DealDeskService.getPrompts(null);
        System.assertEquals(false, out.isSuccess);
        System.assert(out.errorMessage != null);
    }

    @isTest
    static void promptsAndAppliesOnQuote() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Copilot DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Copilot Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 kit = new Product2(
            Name = 'TC53 Hardware Kit',
            StockKeepingUnit = 'KIT-PARENT-T' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        Product2 tc53 = new Product2(
            Name = 'TC53 Mobile Computer',
            StockKeepingUnit = 'DEVICE-T' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert new List<Product2>{ kit, tc53 };
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = kit.Id, UnitPrice = 0, IsActive = true),
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = tc53.Id, UnitPrice = 1895, IsActive = true)
        };
        Quote q = new Quote(
            Name = 'Copilot Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Deal_Motion__c = 'Sales_Agreement'
        );
        insert q;
        PricebookEntry kitPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :kit.Id LIMIT 1];
        PricebookEntry tc53Pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :tc53.Id LIMIT 1];
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = kitPbe.Id, Quantity = 1, UnitPrice = 0, Product2Id = kit.Id),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = tc53Pbe.Id, Quantity = 1, UnitPrice = 1895, Product2Id = tc53.Id)
        };

        Test.startTest();
        RLM_DealDeskService.PromptResponse prompts =
            RLM_DealDeskService.getPrompts(String.valueOf(q.Id));
        System.assertEquals(true, prompts.isSuccess, 'getPrompts: ' + prompts.errorMessage);
        System.assert(prompts.prompts.size() >= 2, 'Expected quantity and discount prompts');
        System.assertEquals('Run-rate (Sales Agreement)', prompts.motionLabel);
        Boolean sawRecommended = false;
        for (RLM_DealDeskService.Prompt p : prompts.prompts) {
            if (p.key == 'disti-12') {
                sawRecommended = true;
                System.assert(p.body.contains('recommendation') || p.body.contains('recommends'), p.body);
                System.assert(p.body.contains('approval'), p.body);
                System.assert(p.body.contains(String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '%'), p.body);
                System.assert(p.body.contains('channel'), p.body);
            }
            System.assertEquals(false, p.title.contains('TC53 Hardware Kit'));
        }
        System.assertEquals(true, sawRecommended);

        RLM_DealDeskService.ApplyResponse qty =
            RLM_DealDeskService.applyAction(
                String.valueOf(q.Id),
                RLM_DealDeskService.ACTION_SCALE_KIT
            );
        System.assertEquals(true, qty.isSuccess, 'scale: ' + qty.errorMessage);

        RLM_DealDeskService.ApplyResponse disti =
            RLM_DealDeskService.applyAction(
                String.valueOf(q.Id),
                RLM_DealDeskService.ACTION_DISTI_12
            );
        Test.stopTest();

        System.assertEquals(true, disti.isSuccess, 'disti: ' + disti.errorMessage);
        QuoteLineItem kitLine = [
            SELECT Quantity FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :kit.Id
            LIMIT 1
        ];
        QuoteLineItem tc53Line = [
            SELECT Quantity FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :tc53.Id
            LIMIT 1
        ];
        System.assertEquals(RLM_DealDeskConfig.KIT_QTY, kitLine.Quantity, 'Parent kit quantity should match config');
        System.assertEquals(RLM_DealDeskConfig.KIT_QTY, tc53Line.Quantity, 'Apply writes the config quantity on kit children');
        Quote refreshed = [SELECT AppliedDiscount FROM Quote WHERE Id = :q.Id];
        System.assert(
            Math.abs(RLM_DealDeskService.normalizePercent(refreshed.AppliedDiscount) - RLM_DealDeskConfig.CHANNEL_DISCOUNT) < 0.01,
            'AppliedDiscount is percent points (12), not a fraction: ' + refreshed.AppliedDiscount
        );
        RLM_DealDeskService.PromptResponse skipped =
            RLM_DealDeskService.getPrompts(String.valueOf(q.Id), true);
        System.assertEquals(true, skipped.isSuccess, 'skipStamp: ' + skipped.errorMessage);
        QuoteLineItem kitDisc = [
            SELECT Discount, DiscountAmount FROM QuoteLineItem
            WHERE QuoteId = :q.Id AND Product2Id = :kit.Id
            LIMIT 1
        ];
        System.assertEquals(null, kitDisc.Discount, 'Line discount stays blank so header is the only 12%');
        System.assertEquals(null, kitDisc.DiscountAmount);
    }

    @isTest
    static void opportunityWithNoQuote() {
        Account acct = new Account(Name = 'Copilot Opp Account');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Empty Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        RLM_DealDeskService.PromptResponse out =
            RLM_DealDeskService.getPrompts(String.valueOf(opp.Id));
        System.assertEquals(true, out.isSuccess, 'getPrompts: ' + out.errorMessage);
        System.assertEquals(1, out.prompts.size());
        System.assertEquals('new-quote', out.prompts[0].key);
        System.assertEquals(null, out.motionLabel);
        System.assertEquals(true, out.quoteChoices == null || out.quoteChoices.isEmpty());
        System.assert(out.prompts[0].body.contains('Sales Agreement'), out.prompts[0].body);
        System.assert(out.prompts[0].body.contains('Quote to order'), out.prompts[0].body);
    }

    @isTest
    static void emptyQuoteHidesMotionNextSteps() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Empty Quote DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Empty Quote Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'No products yet',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Deal_Motion__c = 'Sales_Agreement'
        );
        insert q;

        Test.startTest();
        RLM_DealDeskService.PromptResponse out =
            RLM_DealDeskService.getPrompts(String.valueOf(q.Id));
        Test.stopTest();

        System.assertEquals(true, out.isSuccess, 'getPrompts: ' + out.errorMessage);
        System.assertEquals('Run-rate (Sales Agreement)', out.motionLabel);
        System.assertEquals(null, out.motionBody);
        System.assertEquals(null, out.headline);
        System.assertEquals('add-products', out.prompts[0].key);
        System.assertEquals(false, out.prompts[0].body.contains('quantity 1'), out.prompts[0].body);
        System.assertEquals(true, out.quoteChoices == null || out.quoteChoices.isEmpty());
        System.assertEquals(null, out.defaultLeftId);

        RLM_DealDeskService.PromptResponse oppOut =
            RLM_DealDeskService.getPrompts(String.valueOf(opp.Id));
        System.assertEquals(true, oppOut.isSuccess, 'opp getPrompts: ' + oppOut.errorMessage);
        System.assertEquals(true, oppOut.quoteChoices == null || oppOut.quoteChoices.isEmpty());
    }

    @isTest
    static void comparesTwoQuotes() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Compare DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Compare Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 device = new Product2(
            Name = 'Scanner',
            StockKeepingUnit = 'CMP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert device;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = device.Id, UnitPrice = 1895, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :device.Id LIMIT 1];
        Quote rev1 = new Quote(
            Name = 'PC Rev 1',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert rev1;
        insert new QuoteLineItem(
            QuoteId = rev1.Id, PricebookEntryId = pbe.Id, Quantity = 10, UnitPrice = 1895, Product2Id = device.Id
        );
        Quote rev2 = new Quote(
            Name = 'PC Rev 2',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert rev2;
        insert new QuoteLineItem(
            QuoteId = rev2.Id, PricebookEntryId = pbe.Id, Quantity = 50, UnitPrice = 1895, Product2Id = device.Id
        );

        Test.startTest();
        RLM_DealDeskService.CompareResponse cmp =
            RLM_DealDeskService.compareQuotes(String.valueOf(rev1.Id), String.valueOf(rev2.Id));
        Test.stopTest();

        System.assertEquals(true, cmp.isSuccess, 'compare: ' + cmp.errorMessage);
        System.assert(cmp.modifiedCount >= 1, 'Quantity change should count as modified');
        System.assert(cmp.headerRows.size() >= 5);
        Boolean sawNet = false;
        for (RLM_DealDeskService.HeaderRow row : cmp.headerRows) {
            if (row.field == 'Revision') {
                System.assertEquals('1', row.previousValue);
                System.assertEquals('2', row.currentValue);
            }
            if (row.field == 'Net') {
                sawNet = true;
            }
        }
        System.assertEquals(true, sawNet);
        System.assert(String.isNotBlank(cmp.managementSummary));
        System.assertEquals(false, cmp.comparedToList);
        Boolean sawQtyDelta = false;
        for (RLM_DealDeskService.LineDelta line : cmp.lineDeltas) {
            if (line.changeType == 'Modified') {
                sawQtyDelta = true;
                System.assertEquals('impact-pos', line.qtyImpactClass, line.qtyDelta);
                System.assert(line.qtyDelta.contains('+'), line.qtyDelta);
                System.assertNotEquals(null, line.netDeltaLabel);
                System.assertEquals('change-chip chip-mod', line.changeChipClass);
            }
        }
        System.assertEquals(true, sawQtyDelta);
        QuoteLineItem stamped = [
            SELECT RLM_Change_Type__c, RLM_Change__c FROM QuoteLineItem WHERE QuoteId = :rev2.Id LIMIT 1
        ];
        System.assertEquals(null, stamped.RLM_Change__c,
            'Quote-vs-quote compare must not stamp TLE Change; TLE is list-price only');
        System.assertEquals(null, stamped.RLM_Change_Type__c);
    }

    @isTest
    static void listCompareIgnoresQuantityOnly() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Qty DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Qty Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 device = new Product2(
            Name = 'Scanner',
            StockKeepingUnit = 'QTY-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert device;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = device.Id, UnitPrice = 1895, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :device.Id LIMIT 1];
        Quote q = new Quote(
            Name = 'Qty only',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft'
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 600, UnitPrice = 1895, Product2Id = device.Id
        );

        Test.startTest();
        RLM_DealDeskService.CompareResponse cmp =
            RLM_DealDeskService.compareQuotes('LIST', String.valueOf(q.Id));
        Test.stopTest();

        System.assertEquals(true, cmp.isSuccess, 'list compare: ' + cmp.errorMessage);
        System.assertEquals(1, cmp.lineDeltas.size());
        System.assertEquals('Unchanged', cmp.lineDeltas[0].changeType,
            'Quantity vs list is not a pricing change');
        QuoteLineItem stamped = [
            SELECT RLM_Change__c FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1
        ];
        System.assertEquals('Unchanged', stamped.RLM_Change__c);
    }

    @isTest
    static void stampsChangeVsListWhenTwoQuotesExist() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Two DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Two Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 device = new Product2(
            Name = 'Scanner',
            StockKeepingUnit = 'TWO-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert device;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = device.Id, UnitPrice = 1895, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :device.Id LIMIT 1];
        Quote rev1 = new Quote(
            Name = 'PC Rev 1', OpportunityId = opp.Id, Pricebook2Id = pbId, Status = 'Draft'
        );
        insert rev1;
        insert new QuoteLineItem(
            QuoteId = rev1.Id, PricebookEntryId = pbe.Id, Quantity = 10, UnitPrice = 1895, Product2Id = device.Id
        );
        Quote rev2 = new Quote(
            Name = 'PC Rev 2', OpportunityId = opp.Id, Pricebook2Id = pbId, Status = 'Draft'
        );
        insert rev2;
        insert new QuoteLineItem(
            QuoteId = rev2.Id, PricebookEntryId = pbe.Id, Quantity = 50, UnitPrice = 1895, Product2Id = device.Id
        );

        Test.startTest();
        RLM_DealDeskService.PromptResponse prompts =
            RLM_DealDeskService.getPrompts(String.valueOf(rev2.Id));
        Test.stopTest();

        System.assertEquals(true, prompts.isSuccess, 'getPrompts: ' + prompts.errorMessage);
        System.assertNotEquals('LIST', prompts.defaultLeftId);
        QuoteLineItem stamped = [
            SELECT RLM_Change__c FROM QuoteLineItem WHERE QuoteId = :rev2.Id LIMIT 1
        ];
        System.assertEquals('Unchanged', stamped.RLM_Change__c,
            'TLE Change is vs list even when compare defaults to the prior revision');
    }

    @isTest
    static void refreshPricesRejectsBlankId() {
        RLM_DealDeskService.ApplyResponse priced = RLM_DealDeskService.refreshPrices(null);
        System.assertEquals(false, priced.isSuccess);
        System.assert(priced.errorMessage != null);
    }

    @isTest
    static void comparesQuoteToList() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'List DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'List Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 device = new Product2(
            Name = 'Scanner',
            StockKeepingUnit = 'LST-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert device;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = device.Id, UnitPrice = 1895, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :device.Id LIMIT 1];
        Quote q = new Quote(
            Name = 'First PC',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            AppliedDiscount = 12
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 50, UnitPrice = 1895, Product2Id = device.Id
        );

        Test.startTest();
        RLM_DealDeskService.PromptResponse prompts =
            RLM_DealDeskService.getPrompts(String.valueOf(opp.Id));
        RLM_DealDeskService.CompareResponse cmp =
            RLM_DealDeskService.compareQuotes('LIST', String.valueOf(q.Id));
        Test.stopTest();

        System.assertEquals(true, prompts.isSuccess, 'getPrompts: ' + prompts.errorMessage);
        System.assertEquals(true, prompts.quoteChoices.size() >= 2);
        System.assertEquals('LIST', prompts.quoteChoices[0].id);
        System.assertEquals('LIST', prompts.defaultLeftId);
        System.assertEquals(true, cmp.isSuccess, 'list compare: ' + cmp.errorMessage);
        System.assertEquals(true, cmp.comparedToList);
        System.assertEquals('List price', cmp.leftTitle);
        System.assert(String.isNotBlank(cmp.managementSummary));
        System.assert(cmp.lineDeltas.size() >= 1);
        System.assertNotEquals(null, cmp.lineDeltas[0].marginFlag);
        System.assertNotEquals(null, cmp.lineDeltas[0].netDeltaLabel);
        QuoteLineItem stamped = [
            SELECT RLM_Change_Type__c, RLM_Change__c FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1
        ];
        System.assertEquals(cmp.lineDeltas[0].changeType, stamped.RLM_Change__c);
        System.assertEquals(cmp.lineDeltas[0].changeType, stamped.RLM_Change_Type__c);
        System.assertEquals('Modified', stamped.RLM_Change__c,
            'Header 12% vs list is a pricing change even before line net updates');
    }

    @isTest
    static void hardwareCanBeQuoteToOrder() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Q2O DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Q2O Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 device = new Product2(
            Name = 'Handheld',
            StockKeepingUnit = 'Q2O-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert device;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = device.Id, UnitPrice = 1895, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :device.Id LIMIT 1];
        Quote q = new Quote(
            Name = 'One-shot HW',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Deal_Motion__c = 'Quote_To_Order'
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 10, UnitPrice = 1895, Product2Id = device.Id
        );

        Test.startTest();
        RLM_DealDeskService.PromptResponse out =
            RLM_DealDeskService.getPrompts(String.valueOf(q.Id));
        Test.stopTest();
        System.assertEquals(true, out.isSuccess, 'getPrompts: ' + out.errorMessage);
        System.assertEquals('Quote to order', out.motionLabel);
    }

    @isTest
    static void partnerRequestShowsMessagePercentNotDisti12() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Northstar Partner PC');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Partner PC Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Product2 kit = new Product2(
            Name = 'Warehouse Frontline Kit',
            StockKeepingUnit = 'KIT-PARENT-T' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert kit;
        insert new PricebookEntry(
            Pricebook2Id = pbId, Product2Id = kit.Id, UnitPrice = 0, IsActive = true
        );
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :kit.Id LIMIT 1];
        Quote q = new Quote(
            Name = 'Northstar portal WFK live',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Deal_Motion__c = 'Quote_To_Order',
            RLM_Partner_Request__c = true,
            RLM_PC_Justification__c =
                'Need 18% off this Warehouse Frontline Kit for a 10-device refresh. '
                + 'Combined hardware + Workcloud + OneCare is not on our TC53 run-rate agreement, '
                + 'and Honeywell is quoting the software stack 20% under list.'
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 10, UnitPrice = 0, Product2Id = kit.Id
        );

        Test.startTest();
        System.assertEquals(18, RLM_DealDeskService.parseRequestedPercent(q.RLM_PC_Justification__c).intValue());
        RLM_DealDeskService.PromptResponse prompts =
            RLM_DealDeskService.getPrompts(String.valueOf(q.Id), true);
        Boolean sawPartner = false;
        Boolean sawDisti = false;
        for (RLM_DealDeskService.Prompt p : prompts.prompts) {
            if (p.key == 'partner-pc') {
                sawPartner = true;
                System.assert(p.body.contains('18'), p.body);
                System.assert(p.body.contains('not the ' + String.valueOf(RLM_DealDeskConfig.CHANNEL_DISCOUNT) + '%'), p.body);
                System.assertEquals(RLM_DealDeskService.ACTION_PARTNER_PC, p.actionKey);
            }
            if (p.key == 'disti-12') {
                sawDisti = true;
            }
        }
        System.assertEquals(true, sawPartner, 'Expected partner concession prompt');
        System.assertEquals(false, sawDisti, 'Must not show DISTI 12% on a partner request');

        RLM_DealDeskService.ApplyResponse applied =
            RLM_DealDeskService.applyAction(
                String.valueOf(q.Id),
                RLM_DealDeskService.ACTION_PARTNER_PC
            );
        Test.stopTest();

        System.assertEquals(true, applied.isSuccess, 'apply: ' + applied.errorMessage);
        Quote refreshed = [SELECT AppliedDiscount FROM Quote WHERE Id = :q.Id];
        System.assert(
            Math.abs(RLM_DealDeskService.normalizePercent(refreshed.AppliedDiscount) - 18) < 0.01,
            'Header should be 18 from the partner message: ' + refreshed.AppliedDiscount
        );
    }

    @isTest
    static void invocableAppliesPartnerPercent() {
        Id pbId = Test.getStandardPricebookId();
        Account acct = new Account(Name = 'Invocable DISTI');
        insert acct;
        Opportunity opp = new Opportunity(
            Name = 'Invocable Opp',
            AccountId = acct.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pbId
        );
        insert opp;
        Quote q = new Quote(
            Name = 'Invocable PC',
            OpportunityId = opp.Id,
            Pricebook2Id = pbId,
            Status = 'Draft',
            RLM_Partner_Request__c = true,
            RLM_PC_Justification__c = 'Need 18% off this Warehouse Frontline Kit.'
        );
        insert q;
        RLM_DealDeskService.PartnerConcessionInput input =
            new RLM_DealDeskService.PartnerConcessionInput();
        input.quoteId = String.valueOf(q.Id);
        Test.startTest();
        List<RLM_DealDeskService.PartnerConcessionOutput> rows =
            RLM_DealDeskService.applyPartnerRequestedConcession(
                new List<RLM_DealDeskService.PartnerConcessionInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals(true, rows[0].isSuccess, 'invocable: ' + rows[0].errorMessage);
        System.assertEquals(18, rows[0].appliedPercent.intValue());
    }
}
