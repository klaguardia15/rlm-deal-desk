# Deal desk quote compare

On-quote deal analysis (prompts, apply, quote compare, margin flags) and the Deal Desk Assistant agent. Drop this onto a Revenue Cloud org, then point the SKUs at your catalog.

The partner portal that sends price-concession requests into this desk is a separate repo: [rlm-partner-portal](https://github.com/klaguardia15/rlm-partner-portal).

## Deploy mechanism (for an AI agent following a deploy prompt)

- **SFDX source deploy** — `sf project deploy start --source-dir force-app`. There is **no** CumulusCI project and **no** `cumulusci.yml`; do not look for one.
- **No data is loaded or deleted** by this repo. The only post-deploy script (`patch_quote_pages.py`) retrieves, patches, and redeploys **Lightning record pages** (FlexiPages) — org *config*, not records — so it is safe to run once the org is confirmed, but tell me before it modifies pages.
- This repo is **private**. If `git clone https://github.com/klaguardia15/rlm-deal-desk.git` returns 404, that is a GitHub **auth** problem (run `gh auth login` or use SSH), not a missing repo — do not substitute another repo.

## What you get

Two surfaces share the same engines:

- **Deal analysis** on the Quote (compare and margin) and on the Opportunity (prompts and compare). Component `rlmDealAnalysis`. Panel `rlmDealHealth` re-runs inspect.
- **Deal Desk Assistant** (`RLM_Deal_Desk_Assistant`) inspects the quote and can apply the partner-requested header concession.

SKU lists, kit quantity, channel discount, and margin bands live in one class: `force-app/main/default/classes/RLM_DealDeskConfig.cls`. The defaults are obvious placeholders (`KIT-PARENT`, `DEVICE`, quantity 100, channel discount 10%). A Zebra catalog example is in `examples/zebra/agent-instructions.md`.

## Prerequisites — the metadata deploy FAILS without these

This package does not build the org. It references components that must **already exist** in the target org, or `sf project deploy start` errors out before anything lands:

- **Revenue Cloud quoting** with the **cost & margin** fields the permission sets grant:
  `QuoteLineItem.UnitCost`, `TotalCost`, `Margin`, `TotalMargin`.
- **Partner pricing fields** the permission sets grant: `QuoteLineItem.PartnerUnitPrice`,
  `QuoteLineItem.PartnerDiscountPercent`, `Quote.PartnerAccountId`. These come from RLM
  partner/PRM pricing — if the org doesn't have them, remove those `fieldPermissions` or enable the feature first.
- **Agentforce (employee agents) + Einstein** enabled — required for the `RLM_Deal_Desk_Assistant`
  agent bundle (`aiAuthoringBundles/`) and for the `agentAccesses` entry in `RLM_DealDeskAgent`.
- **Quote / Opportunity Lightning record pages** to patch in post-deploy: `RLM_Quote_Record_Page`,
  and `RLM_MFG_Quote_Record_Page` / `RLM_Opportunity_Record_Page` when those exist.

Everything else the package needs — the `RLM_*` Apex classes, the five flows, the quick action,
the custom Quote/QuoteLineItem `RLM_*__c` fields, and the three permission sets — ships **in this repo**
and deploys together.

> The Apex runs in `with sharing` / `USER_MODE` (and `RLM_SyncLineDiscount` is `without sharing` by
> design for the discount rollup), so field-level security is enforced at runtime. The permission sets
> below are what make the UI and agent actually work for a user — assigning them is not optional.

## Deploy

**Dry-run first** (validate without saving — this is where missing prerequisites surface):

```bash
sf project deploy start --source-dir force-app --dry-run --target-org <sf-alias> --wait 30
```

Then deploy and assign the persona permission sets:

```bash
sf project deploy start --source-dir force-app --target-org <sf-alias> --wait 30
sf org assign permset --name RLM_Deal_Desk    --target-org <sf-alias>
sf org assign permset --name RLM_DealDeskAgent --target-org <sf-alias>
python scripts/patch_quote_pages.py --target-org <sf-alias>
```

`<sf-alias>` is an `sf` CLI alias or username, not a CumulusCI org name.

## Post-deploy checklist

1. **Assign permission sets.** Three personas ship:
   - `RLM_Deal_Desk` — full cost/margin/PC visibility (deal desk).
   - `RLM_DealDeskAgent` — grants access to the `RLM_Deal_Desk_Assistant` agent + its services.
   - `RLM_Seller` — quote and discount only; cost and true margin hidden. Assign to sellers:
     `sf org assign permset --name RLM_Seller --target-org <sf-alias>`.
2. **Patch the Quote/Opportunity pages** — `python scripts/patch_quote_pages.py --target-org <sf-alias>`.
   It retrieves the live FlexiPages, injects the Deal analysis components, and redeploys them. Pass
   `--no-deploy` to inspect the change first. *(Modifies org config — confirm before running.)*
3. **Publish the agent — cannot be automated here.** If the metadata deploy leaves
   `RLM_Deal_Desk_Assistant` inactive, open **Agentforce Builder** and publish it. The permission set
   grants access but does not activate the agent.
4. **Point it at your catalog — manual.** Edit `RLM_DealDeskConfig.cls` (SKUs, kit quantity, channel
   discount, margin bands) and the agent instructions, then redeploy. See *Repeat it for another catalog*.

## Safety

Nothing in this repo loads or deletes records. The one mutating post-deploy action is the page patch,
which changes **Lightning record pages** (config). Confirm before running it. Do not deploy Network
metadata (`*.network-meta.xml`) — none is included, and the scripts strip it.

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
