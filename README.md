# Deal desk quote compare

On-quote deal analysis (prompts, apply, quote compare, margin flags) and the Deal Desk Assistant agent. Drop this onto a Revenue Cloud org, then point the SKUs at your catalog.

The partner portal that sends price-concession requests into this desk is a separate repo: [rlm-partner-portal](https://github.com/klaguardia15/rlm-partner-portal).

## What you get

Two surfaces share the same engines:

- **Deal analysis** on the Quote (compare and margin) and on the Opportunity (prompts and compare). Component `rlmDealAnalysis`. Panel `rlmDealHealth` re-runs inspect.
- **Deal Desk Assistant** (`RLM_Deal_Desk_Assistant`) inspects the quote and can apply the partner-requested header concession.

SKU lists, kit quantity, channel discount, and margin bands live in one class: `force-app/main/default/classes/RLM_DealDeskConfig.cls`. The defaults are obvious placeholders (`KIT-PARENT`, `DEVICE`, quantity 100, channel discount 10%). A Zebra catalog example is in `examples/zebra/agent-instructions.md`.

## Prerequisites

An org that already has Revenue Cloud quoting and Agentforce. This package does not build that org.

- Quote and Opportunity Lightning pages you can patch (`RLM_Quote_Record_Page`, and `RLM_MFG_Quote_Record_Page` / `RLM_Opportunity_Record_Page` when those exist)
- Agentforce employee agents enabled
- Standard quote margin fields (`QuoteLineItem.Margin`, `UnitCost`) for the deal-desk permission set

## Deploy

```bash
sf project deploy start --source-dir force-app --target-org <sf-alias> --wait 30
sf org assign permset --name RLM_Deal_Desk --target-org <sf-alias>
sf org assign permset --name RLM_DealDeskAgent --target-org <sf-alias>
python scripts/patch_quote_pages.py --target-org <sf-alias>
```

`<sf-alias>` is an `sf` CLI alias or username, not a CumulusCI org name.

Publish the agent in Agentforce Builder if the metadata deploy leaves it inactive. Assign `RLM_Seller` to sellers who should see margin health without cost fields.

## Repeat it for another catalog

Open this repo in Cursor and ask to adapt the deal desk. The procedure is `.cursor/skills/adapt-deal-desk/SKILL.md`.

Edit `RLM_DealDeskConfig.cls` and the agent instructions, keep the margin formula in `RLM_Margin_Flag__c` on the same thresholds, deploy, and run the page patch.

## Share this repo

The GitHub repo is private. Invite people from the repo page, or:

```bash
gh repo add-collaborator klaguardia15/rlm-deal-desk <github-username>
```

## License

Apache-2.0. See `LICENSE.txt`. Copyright Salesforce, Inc.
