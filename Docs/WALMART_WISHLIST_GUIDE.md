# Walmart Shopping Trip and legacy Wishlist reference

The active Walmart experience is a user-driven Safari Shopping Trip. SmartCart matches products, opens public Walmart destinations, and keeps the trip position on device. It does not link a Walmart account, call a Wishlist API, automate Walmart controls, or detect a retailer or purchase result.

This file keeps its historical name because schema-v4 state can contain an optional shared-Wishlist reference. That legacy record remains decodable, but a shared URL and the old per-page return questionnaire are not required by the current Shopping Trip.

## Ownership boundary

SmartCart can:

- Match recipe ingredients to seeded exact Walmart product URLs or clearly labeled search fallbacks.
- Require an explicit decision only for a fallback or lower-confidence product choice.
- Open one product after another in an in-app Safari Shopping Trip.
- Record **Next Item** as `visited`, meaning only that the shopper chose to advance after a successful page load.
- Record explicit unavailable and skip actions, apply a user-selected safe replacement, and persist pause/resume position.
- Offer a separate, user-confirmed pantry update after the trip.

Walmart owns:

- Account creation, sign-in, cookies, and session expiration.
- Lists, favorites, cart contents, item quantities, and every action on the Walmart page.
- Live product identity, price, availability, fulfillment eligibility, and variable-weight behavior.
- Store selection, pickup or delivery, substitutions, payment, checkout, and order tracking.

SmartCart never asks for or stores Walmart credentials. It does not read Walmart cookies, inject JavaScript, scrape account data, inspect a list or cart, or infer success from opening or leaving a page.

## Before the trip

Recipe Ready shows the selected retailer, Walmart matching location, fulfillment preference, and shopping preferences together. A first-time setup confirmation may open Walmart so the shopper can sign in or prepare a retailer-owned list. SmartCart stores only the shopper’s confirmation; it cannot verify sign-in or list readiness.

Starting the trip prepares product matches immediately. Eligible high-confidence exact matches proceed without a separate review screen. Search fallbacks and lower-confidence selections stop in **Review product choices**, where the shopper can accept the choice, choose a safe alternative, search manually, or skip it.

## Continuous Safari Shopping Trip

1. SmartCart opens the current Walmart product or labeled search in Safari.
2. After the initial page load succeeds, **Next Item** becomes available.
3. **Next Item** records `visited` and opens the next waiting product in the same trip. It does not mean saved, added to cart, ordered, checked out, or purchased.
4. **More** offers unavailable, a safe SmartCart replacement when available, skip, reload, and the retailer disclaimer.
5. No mandatory “what happened?” questionnaire appears between retailer pages.

A `visited` item may be selected by default in the later pantry check-in, while unavailable and skipped items default to excluded. Those are editable starting points only; SmartCart still relies on the shopper to report what was actually bought.

## Pause, dismissal, and load failure

- **Pause** saves the trip without advancing the current waiting item and returns home.
- Safari’s native close control and an interactive sheet dismissal are ambiguous, so either one safely pauses at the same item.
- A failed initial load keeps the item waiting and disables **Next Item**. The shopper can retry, open the URL externally, skip the item explicitly, or pause.
- Relaunch resumes the durable trip at its first waiting item. A completed trip is frozen; editing it creates a new trip.

## Pantry update and reminder

Finishing the retailer pages does not prove that shopping or checkout occurred. SmartCart offers **I’m back — update pantry**, where the shopper chooses an overall outcome, edits included items, records substitutions, and confirms quantities. The update is atomic and idempotent, so repeating confirmation cannot add stock twice. A replacement becomes a future preference only after explicit opt-in.

If the pantry update is left unfinished, Home can ask whether the shopper got the items:

- **Yes** opens the pantry update for that completed trip.
- **Not Yet** leaves the reminder and trip pending without changing data.
- **Archive** suppresses only the repeated Home reminder. It does not record a purchase, change pantry stock or preferences, or delete the frozen trip; the suppression persists across relaunch.

## Preserved legacy Wishlist state

Schema-v4 and later files may contain a `WalmartWishlistReference` with a local display name, validated HTTPS `walmart.com/lists/shared/WL/…` URL, and created/last-opened timestamps. Saving that reference never granted SmartCart access to view or change the list. Schema migration preserves the record and its historical local analytics names, including `walmart_wishlist_url_saved`, `walmart_product_self_reported_saved`, `walmart_guided_flow_completed`, and `walmart_wishlist_opened`.

Legacy item outcomes such as saved-to-Wishlist and added-to-cart also remain decodable for historical trips. New normal-flow advancement uses `visited` instead. These internal compatibility values do not establish current Walmart state.

## Human validation matrix

Before closed-beta promotion, test:

1. First-time retailer setup and an already confirmed setup.
2. Walmart app installed and not installed.
3. Exact product and labeled search fallback.
4. Lower-confidence selection and each exception-review action.
5. Variable-weight product and quantity greater than one.
6. Successful load followed by **Next Item** and automatic opening of the next product.
7. **Pause**, native Safari close, and interactive dismissal, each resuming at the same waiting item.
8. Load failure with **Next Item** disabled, followed separately by retry, external open, skip, and pause.
9. Product unavailable, safe replacement, and explicit skip.
10. Store change, expired Walmart sign-in, app termination, and relaunch mid-trip.
11. Every post-trip pantry outcome, a substitution with preference disabled/enabled, and repeated confirmation without a second stock increment.
12. Home **Yes**, **Not Yet**, and **Archive**, including archive persistence and preserved trip history after relaunch.
13. Migration of a valid, invalid, edited, and removed legacy shared-Wishlist reference.
14. Dynamic Type and VoiceOver operation of exception choices, the Shopping Trip bar, More menu, failure actions, and reminder actions.

The release gate is that the flow remains useful without implying that SmartCart populated or inspected a Wishlist/cart, linked an account, observed live price or availability, detected a purchase, or knew anything about checkout.
