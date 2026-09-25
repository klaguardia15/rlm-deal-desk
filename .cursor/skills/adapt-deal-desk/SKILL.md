# Adapt Deal Desk

Point quote compare, margin bands, and the Deal Desk Assistant at another catalog.

## Quick Rules

1. Change catalog numbers and SKUs only in `force-app/main/default/classes/RLM_DealDeskConfig.cls`.
2. Change the agent voice only in `force-app/main/default/aiAuthoringBundles/RLM_Deal_Desk_Assistant/RLM_Deal_Desk_Assistant.agent`.
3. If you change `MARGIN_GREEN_PCT` or `MARGIN_YELLOW_PCT`, update the same thresholds in `QuoteLineItem.RLM_Margin_Flag__c`.
4. Deploy the package, assign `RLM_Deal_Desk`, then run `scripts/patch_quote_pages.py` against the target org.

## DO NOT

- Do not scatter SKUs, kit quantity, channel discount, or margin bands through `RLM_DealDeskService` or `RLM_AI_DealDeskInspectService`. Those classes read `RLM_DealDeskConfig`.
- Do not treat `examples/zebra/agent-instructions.md` as the live prompt. It is a labeled example.
- Do not deploy Network metadata.

## Entry Conditions

Use this skill when someone wants to reuse deal analysis (quote compare and margin flags) or the Deal Desk Assistant on a different catalog.

| Task | Use this skill? |
|---|---|
| Swap SKUs, kit quantity, channel discount, or margin bands | Yes |
| Rename the agent persona | Yes. Edit the agent file, not the Apex. |
| Rebrand Partner Central | No. That is the `rlm-partner-portal` repo. |

## What to edit

`RLM_DealDeskConfig` fields:

| Field | Meaning |
|---|---|
| `KIT_QTY` | Quantity written on the kit parent and its children |
| `CHANNEL_DISCOUNT` | Header percent recommended for run-rate quotes |
| `SERVICES_MAX_QTY` | Cap for SKUs that start with `SERVICES_SKU_PREFIX` |
| `MARGIN_GREEN_PCT` / `MARGIN_YELLOW_PCT` | Healthy vs watch vs low. Green is `>=` green. Yellow is `>=` yellow and below green. |
| `KIT_SKUS` / `HARDWARE_KIT_SKUS` | Parent kits. A SKU matches when it equals the key or starts with it. |
| `DEVICE_SKUS` | Devices that require `USB_CABLE_SKU` and `REQUIRED_ACCESSORY_SKUS` |
| `PADDING_SKUS` | Lines called out as margin padding |
| `REQUIRED_ACCESSORY_LABELS` | Words the inspect speaks for each required SKU |

Prefix matching is exact-or-starts-with. A key of `DEVICE` also matches `DEVICE-100`.

The Zebra catalog that this package was extracted from is listed in `examples/zebra/agent-instructions.md`. Copy those values into the config class only when you are deliberately rebuilding that demo.

## Examples

Worked example — set a 100-unit kit and a 10% channel discount (the defaults), then place the components on the live quote page:

```bash
sf project deploy start --source-dir force-app --target-org <sf-alias> --wait 30
python scripts/patch_quote_pages.py --target-org <sf-alias>
```

The patch script retrieves `RLM_Quote_Record_Page`, `RLM_MFG_Quote_Record_Page`, and `RLM_Opportunity_Record_Page` when those pages exist, injects `c:rlmDealAnalysis` and `c:rlmDealHealth`, and deploys the pages. A missing page is skipped. If none are retrieved, rename the list in the script to the pages in that org.

## Validation Checks

1. `RLM_DealDeskService` and `RLM_AI_DealDeskInspectService` contain no SKU literals. Search the `force-app` classes for a quoted SKU you just added; it should appear only in `RLM_DealDeskConfig.cls`.
2. The agent file's `target` for apply is `flow://RLM_Apply_Partner_Concession`.
3. After deploy, Deal analysis on the quote shows compare, and the agent action Inspect Deal Desk Quote runs.
4. Margin Health colors match the two percents in the config class and in `RLM_Margin_Flag__c`.
