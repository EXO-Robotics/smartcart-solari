# SmartCart Milestone 8 website

This directory is a deploy-ready, dependency-free static website package for the
SmartCart private iOS beta. It is intentionally unpublished and contains no live
domain, analytics, remote assets, sign-up system, email address, form endpoint,
retailer API, or affiliate tracking.

## Package contents

- `index.html` — responsive landing page and product boundary
- `privacy.html` and `terms.html` — conspicuous pre-publication legal drafts
- `support.html`, `faq.html`, and `contact.html` — beta help and safe placeholders
- `about.html` and `affiliate-disclosure.html` — project and relationship context
- `developers/` — implementation and architecture documentation
- `media-kit/` — internal press language, brand specimens, and plain-text notes
- `styles.css` and `script.js` — shared local presentation and accessible navigation
- `validate.py` and `tests/` — standard-library validation and regression tests

## Local preview

From the repository root:

```sh
python3 -m http.server 8080 --directory website
```

Then open `http://localhost:8080/`. Stop the preview with `Control-C`.

Directly opening `website/index.html` also works, but the local server better
matches static hosting behavior.

## Validation

Run the package validator:

```sh
python3 website/validate.py
```

Run validator regression tests:

```sh
python3 -m unittest discover -s website/tests -v
```

The validator checks required pages and content markers, local links and fragment
targets, unique IDs and titles, basic document semantics, skip links, viewport
metadata, remote dependencies, accidental email addresses, form endpoints, and
required pre-publication placeholders.

If Node.js is available, the JavaScript can also be syntax-checked with:

```sh
node --check website/script.js
```

## Human pre-publication checklist

Do not deploy this package publicly until each item is owned, verified, and tested.

### Product and legal

1. Search for every `[REPLACE BEFORE PUBLISHING` marker and complete it with
   approved facts. Do not replace a placeholder with guessed information.
2. Have an authorized legal reviewer approve Privacy, Terms, age/region scope,
   beta participation, intellectual-property language, liability, and dispute terms.
3. Confirm the exact product version, distribution status, supported iOS versions,
   and all capability claims against the release candidate.
4. Audit retailer names, destinations, screenshots, trademarks, product data,
   affiliate relationships, and usage rights. Keep demo records labeled as demo.
5. Approve the owner or legal entity, spokesperson, biography, and press assets.

### Domain and deployment

1. Select and register the real domain; no domain is assumed in this package.
2. Choose a static host and document what it logs, retains, and shares.
3. Configure the verified domain, HTTPS, canonical redirects, a useful 404 page,
   cache rules, compression, security headers, and deployment rollback.
4. Update metadata only with the verified production URL. Add a social preview
   image only after its text, rights, and product truth are approved.
5. Deploy to a private preview first. Re-run validation against the exact artifact,
   test every route at mobile and desktop widths, and perform keyboard and
   screen-reader checks before production promotion.

### Email, support, and contact

1. Choose a monitored support/contact system and accountable human owner.
2. If using email, create the real mailbox on the verified domain and configure
   SPF, DKIM, and DMARC. Do not publish an unmonitored address.
3. If using a form service, document its data fields, subprocessors, retention,
   abuse controls, deletion flow, and accessibility; then update Privacy and Terms.
4. Replace or remove the contact-page demo form. Test delivery, acknowledgements,
   escalation, privacy requests, and accessibility reports end to end.

### Final verification

1. Run `python3 website/validate.py` and the unittest command above.
2. Search for `REPLACE BEFORE PUBLISHING`, `localhost`, and unsupported claims.
3. Confirm that no secret, personal contact detail, private beta link, or source-only
   test fixture entered the publish artifact.
4. Obtain explicit human approval for deployment. Publishing is intentionally not
   part of this Milestone 8 package.
