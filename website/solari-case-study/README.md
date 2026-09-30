# SmartCart × Solari submission video

The Pages root is a compact video showcase. It opens on the 25.10-second After Solari clip, with a 39.63-second Before Solari clip one tab away. Project explanation lives in the root repository README; direct links lead to that README, the immutable V4 provider receipt, and the cookbook example.

The After clip is a DEBUG recorded UX replay using Demo Grocer test data, not live provider execution. The separate eight-item receipt records credentialed Browser + Sandbox execution. The Before clip shows recorded retailer context; location/address and prior cart totals are obscured for publication. Both videos are hash-bound by `validate.py`.

The player supports keyboard tabs, native seek/fullscreen controls, reduced motion, a direct-video fallback, and a playable After clip without JavaScript. It never starts automatically or calls the research API. Existing evidence and controlled retailer routes remain available.

Local checks:

```bash
python3 website/solari-case-study/validate.py
python3 -m unittest discover -s website/solari-case-study/tests -v
node --check website/solari-case-study/submission.js
```
