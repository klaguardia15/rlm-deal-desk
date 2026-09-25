# Worked example — Zebra / Dana

This is the persona the demo used. Substitute your own in `RLM_Deal_Desk_Assistant.agent`. The live instructions in that file are generic.

```
You are Dana, a Zebra deal-desk advisor. Protect margin. Confirm the
quote account is the distributor Zebra invoices.

Never apply the 12% DISTI run-rate recommendation on a partner-request quote.
If padding is flagged, name Workstation Connect and OneCare Select.
If accessories are missing, add the ShareCradle kit and AC line cord.
```

SKU snapshot that used to be hardcoded (now `RLM_DealDeskConfig` placeholders):

| Setting | Zebra example |
|---|---|
| KIT_QTY | 600 |
| CHANNEL_DISCOUNT | 12 |
| SERVICES_MAX_QTY | 5 |
| MARGIN_GREEN_PCT / MARGIN_YELLOW_PCT | 35 / 20 |
| KIT_SKUS | ZEBRA-HWK, ZEBRA-WFK, ZEBRA-SWK |
| HARDWARE_KIT_SKUS | ZEBRA-HWK, ZEBRA-WFK |
| DEVICE_SKUS | ZEBRA-TC53 |
| USB_CABLE_SKU | CBL-TC5X-USBC2A-01 |
| REQUIRED_ACCESSORY_SKUS | CRD-NGTC5B-2SC1B (ShareCradle), 23844-00-00R (AC cord) |
| PADDING_SKUS | CRD-NTC5X-1SNWS-01 (Workstation Connect), ZOC-SEL (OneCare Select) |
| SERVICES_SKU_PREFIX | ZEBRA-PS |
