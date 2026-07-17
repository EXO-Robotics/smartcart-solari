# Instacart handoff integration

SmartCart owns recipe import, ingredient correction, serving changes, pantry
decisions, supported preference mapping, quantity normalization, final manifest
review, saved local state, and handoff feedback. Instacart owns live product and
store selection, prices, availability, substitutions, sign-in, fulfillment,
payment, checkout, and order tracking.

## Runtime configuration

The iOS app calls the SmartCart backend. It never receives an Instacart API key.

- `SMARTCART_COMMERCE_BACKEND_URL`: reachable SmartCart backend base URL for the
  app. The recipe backend URL is used as a fallback before localhost.
- `INSTACART_API_KEY`: server-side Instacart Developer Platform key.
- `INSTACART_API_BASE_URL`: defaults to the Instacart development host; use the
  production host only after production approval.
- `INSTACART_DEMO_HANDOFF_URL`: explicit local-development destination for
  deterministic UI testing without claiming a live provider call.

Physical iPhones cannot reach the Mac through `localhost`. Use a reachable LAN
address with appropriate development transport configuration, or deploy the
backend to HTTPS.

## Safety contract

`POST /api/handoffs/instacart` accepts an authenticated manifest identifier,
postal code, preferred-retailer hint, and fulfillment preference. The backend:

1. Revalidates manifest ownership and content.
2. Removes pantry-excluded and unselected optional items.
3. Rejects unresolved alternatives and unconfirmed quantities.
4. Converts common recipe units to Instacart-supported measurements.
5. Sends only supported health filters.
6. Sends a UPC only when exact identity is explicitly reliable.
7. Creates a shopping-list page and caches its URL by a SHA-256 fingerprint.
8. Returns a URL for `SFSafariViewController` without inferring checkout.

Instacart currently documents `line_item_measurements` as the supported shopping
list measurement field; the older direct `quantity` and `unit` fields are
deprecated. Re-check the official API changelog before production promotion.

## Human activation gate

- Obtain development access and store the key outside Git.
- Verify nearby retailer keys for each supported postal code.
- Exercise timeout, 400, 401/403, 429, malformed response, and expired-link paths.
- Validate the in-app Safari flow on a physical iPhone with Instacart signed in
  and signed out.
- Confirm Instacart branding, CTA, attribution, and pre-launch review rules.
- Confirm the return survey remains explicitly self-reported.
