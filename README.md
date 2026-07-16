# SmartCart for iOS

SmartCart turns a recipe into a ready-to-shop Walmart grocery list with product links and an estimated total.

## What works in this prototype

- Import a recipe from pasted text, a sample, a camera capture, or a photo-library image.
- Run on-device Vision text recognition on recipe images.
- Import public recipe pages that expose standard schema.org Recipe metadata.
- Review and edit detected ingredient names, quantities, units, confidence, and inclusion.
- Scale recipe quantities for a new serving count.
- Mark pantry items as available, running low, needed, always ask, or excluded.
- Choose one Walmart location or plan multiple Walmart stops.
- Preselect pickup or delivery preferences and a preferred pickup window.
- Match ingredients to a realistic local demo product catalog with alternatives.
- Review package quantities, estimated prices, variable-weight disclosures, and totals.
- Share or save a shopping list.
- Open Walmart product searches in a guided open / mark added / next flow.
- Link out to supported delivery-app websites for final handoff.

## Integration boundary

The prototype does not store retailer credentials, process payment, claim live inventory, silently modify a Walmart cart, or book a pickup reservation. Product data and prices are local demo data. Walmart or a delivery partner performs final availability checks, substitutions, fees, payment, and checkout.

## Run

Open `Grocrygetter.xcodeproj`, select the `Gather` scheme, choose an iOS 17 or newer simulator, and run. The installed app name is **SmartCart**.
