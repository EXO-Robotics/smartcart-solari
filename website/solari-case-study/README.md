# SmartCart × Solari case study

This dependency-free static site is the public presentation layer for the SmartCart × Solari submission.

It intentionally separates three kinds of evidence:

- the root case study explains the product transformation and replaceable-frontend architecture;
- `assets/smartcart-before-solari.mp4` is the hash-bound 39.63-second original SmartCart retailer-handoff recording;
- `assets/smartcart-after-solari.mp4` is the hash-bound 25.10-second, eight-item DEBUG recorded replay of the Solari-enhanced native UX;
- neither case-study video is provider-execution proof or a current retailer price/availability claim;
- `website/solari-demo/` remains the explicit replay and controlled retailer surface;
- `evidence/live/smartcart-solari-v4-qualification-33546912947.json` remains the immutable provider-execution receipt.

Run the local checks from the repository root:

```bash
python3 website/solari-case-study/validate.py
python3 -m unittest discover -s website/solari-case-study/tests -v
node --check website/solari-case-study/script.js
```

The GitHub Pages workflow publishes the contents of this directory at the repository Pages root without altering the existing replay routes.
