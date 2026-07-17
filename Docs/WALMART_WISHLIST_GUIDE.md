# Guided Walmart Wishlist workflow

SmartCart supports a user-driven Walmart Wishlist workflow. It does not link a
Walmart account and it does not call a Wishlist API.

## Ownership boundary

SmartCart can:

- Match recipe ingredients to seeded exact Walmart product URLs or clearly
  labeled search fallbacks.
- Open Walmart in `SFSafariViewController`.
- Guide the user through products one at a time.
- Record the user's answer after each Walmart page: saved to Wishlist, added to
  cart, unavailable, or skipped.
- Persist that self-reported progress across relaunches.
- Validate and save an optional shared Walmart Wishlist URL as a final
  destination.

Walmart owns:

- Account creation, sign-in, cookies, and session expiration.
- Wishlist creation, selection, item addition, contents, and quantities.
- Live product identity, price, availability, fulfillment eligibility, and
  variable-weight behavior.
- Store selection, pickup or delivery, substitutions, cart, payment, checkout,
  and order tracking.

SmartCart never asks for or stores Walmart credentials. It does not read
Walmart cookies, inject JavaScript, scrape account data, automate Walmart page
controls, or infer success from a page opening.

## Setup flow

1. Open **Walmart setup**.
2. Tap **Open Walmart Lists**.
3. Sign in directly with Walmart.
4. In Walmart, choose **My Items → Lists → Create a wishlist**.
5. Name it `SmartCart` or `SmartCart Groceries`.
6. In Walmart, choose **Share → Copy URL**.
7. Return to SmartCart and paste the shared URL.

The URL is optional. SmartCart validates that it is an HTTPS URL on
`walmart.com` with the official `/lists/shared/WL/…` path. It stores only:

- A local display name.
- The shared URL.
- Created and last-opened timestamps.

Saving a reference does not grant SmartCart access to view or change the list.

## Per-product flow

For each matched product, SmartCart shows the recipe requirement, selected
Walmart product, package count, and exact-product versus search-fallback status.

1. The user taps **Open at Walmart**.
2. SmartCart opens the public Walmart destination in in-app Safari.
3. The user selects Walmart's **Add to Wishlist** action and chooses a list.
4. On return, SmartCart asks what happened.
5. The selected self-reported result is persisted and the next unanswered item
   is shown.

At completion, SmartCart displays separate saved, cart, unavailable, and
skipped counts. **Open SmartCart Groceries** is available only when the user has
saved a valid shared Wishlist URL. The primary SmartCart action is **Finish
shopping at Walmart**, followed by **I'm back — update pantry**; Wishlist is an
implementation detail of the retailer-owned flow, not SmartCart's promise.

## Post-shopping pantry update

SmartCart asks one outcome question: bought all available items, bought most,
bought only a few, or did not shop. `Most` starts with eligible items selected
so the user taps only misses; `few` starts empty. Unavailable and skipped
products are never preselected, but remain available to select when they were
bought elsewhere or substituted. Confirmed purchases are committed as one
durable transaction and a repeated confirmation cannot add them twice.

Shopping sessions carry a deterministic fingerprint of item identity,
quantity, selected product, package metadata, store, and guide status. An exact
retry reuses the committed session; changing quantity or product selection with
the same item IDs creates a new session.

Substitutions can be selected from already matched alternatives or scanned by
barcode. The actual scanned amount is used for pantry stock. A replacement
becomes a future matching preference only when the user explicitly enables
**Prefer this product next time**.

## Local analytics

When on-device analytics is enabled, the workflow records:

- `walmart_setup_started`
- `walmart_wishlist_url_saved`
- `walmart_product_opened`
- `walmart_product_self_reported_saved`
- `walmart_guided_flow_completed`
- `walmart_wishlist_opened`

No shared URL, credential, cookie, address, email, or Walmart account identifier
is included in event properties.

## Human validation matrix

Before closed-beta promotion, test:

1. New Walmart account.
2. Existing signed-in account.
3. Walmart app installed.
4. Walmart app not installed.
5. Private Wishlist before sharing.
6. Valid shared Wishlist URL.
7. Invalid, non-Walmart, and non-HTTPS URLs.
8. Exact grocery product.
9. Search fallback.
10. Variable-weight product.
11. Product unavailable at the selected store.
12. Quantity greater than one.
13. Store changed during the flow.
14. Walmart session expires between items.
15. App terminated mid-flow and relaunched.
16. Saved Wishlist reference edited and removed.
17. Each of the four shopping outcomes.
18. Substitution with preference disabled and enabled.
19. App termination immediately before and after pantry confirmation.
20. Reopening an already committed session without a second stock increment.

The release gate is that the flow remains useful without implying that the
Wishlist or cart was populated automatically.
