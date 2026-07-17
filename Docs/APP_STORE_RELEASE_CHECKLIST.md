# App Store and public launch checklist

## Human-owned prerequisites

- [ ] Active Apple Developer Program membership and correct legal entity.
- [ ] App ID, signing certificates, profiles, App Store Connect record, and final bundle identifier.
- [ ] Legal review of Privacy Policy, Terms, Affiliate Disclosure, support/contact details, and retailer trademarks.
- [ ] Production support email and public HTTPS domain.
- [ ] Production backend, database, authentication, monitoring, deletion flow, and incident owner.
- [ ] Approved retailer/affiliate agreements and IDs for every enabled connector.
- [ ] App privacy questionnaire and required-reason API review completed from the shipped binary.
- [ ] Export-compliance, age-rating, category, content-rights, and accessibility declarations completed.

## TestFlight gate

- [ ] Clean checkout builds in Release with no warnings treated as errors.
- [ ] Unit/regression suite passes from clean Derived Data.
- [ ] Physical iPhone tests camera OCR and barcode scanning.
- [ ] iPad layout, Dynamic Type, VoiceOver, dark/high-contrast behavior, offline mode, and low-memory relaunch are checked.
- [ ] Upgrade from Beta 2 preserves or safely migrates local state.
- [ ] Corrupt state is quarantined without a crash.
- [ ] Every seeded price says demo/last-known/not live.
- [ ] Every exact product link and labeled search fallback is manually sampled.
- [ ] Unsupported cart, wishlist, delivery transfer, and pickup reservation are not presented as connected.
- [ ] Beta feedback instructions and known limitations are visible to testers.

## Store submission assets

- [ ] Final app name/subtitle/keywords/description approved.
- [ ] App icon and launch experience finalized.
- [ ] Required iPhone and iPad screenshots captured from the release candidate.
- [ ] Review notes explain recipe imports, demo catalog data, barcode testing, and any account requirements.
- [ ] Support URL, Marketing URL, and Privacy Policy URL are live.
- [ ] Version/build numbers and release notes match the uploaded archive.

## Go/no-go

Do not enable live commerce claims merely because an App Store build succeeds. Public launch requires closed-beta metrics, production security review, partner authorization, operational ownership, and a signed launch decision.
