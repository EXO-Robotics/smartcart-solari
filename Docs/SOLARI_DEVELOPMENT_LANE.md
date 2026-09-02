# Solari local-device development lane

This lane exists only so an Xcode-installed SmartCart Solari build can exercise the real App Attest → Solari Browser → Solari Sandbox path before TestFlight. It is not a fixture bypass and it does not weaken the distribution endpoint.

## Exact separation

| Caller | Xcode scheme | Backend base | Apple validation category | Redis namespace |
|---|---|---|---:|---|
| Local Apple Development build | `SmartCart-SolariDevelopment` | `https://smartcart-solari-beta.vercel.app/dev` | 3 only | `smartcart:solari:dev` |
| TestFlight build | `SmartCart-SolariBeta` | `https://smartcart-solari-beta.vercel.app` | 2 only | `smartcart:solari:beta` |

Both lanes require the same exact App Attest team ID, bundle ID, and `CFBundleVersion` allowlist. Both use Apple's production App Attest environment, one-use challenges, signed exact-body-and-route assertions, monotonic counters, quotas, concurrency leases, cancellation, and the server runtime switch. A `/dev/v1/solari/research` assertion is cryptographically invalid at `/v1/solari/research` and vice versa. The development lane reuses server-held Solari and Redis credentials; it does not copy them or place any credential in Swift.

The development routes are default-off behind `SOLARI_DEVELOPMENT_LANE_ENABLED=false`. When disabled they return 404. When enabled, `/dev/v1/solari/research` rejects every payload except the signed App Attest envelope. It cannot invoke the older operator-bearer route.

## Local iPhone run

1. Connect the explicitly trusted development iPhone.
2. In Xcode select the shared `SmartCart-SolariDevelopment` scheme.
3. Confirm the installed app is bundle `com.blakestudio.smartcart.solari-beta`, build `4`.
4. Open a normal eligible SmartCart trip and tap **Research current options**.
5. If a prior 401/403 occurred, tap retry once. SmartCart intentionally clears only the rejected public App Attest key reference and generates a new attestation on the explicit retry.
6. Confirm the result identifies owned Demo Grocer evidence, observation timestamps, package counts, basket comparison, and the unchanged user-controlled handoff.

Do not call the lane qualified until the physical device completes attestation, assertion, Browser, Sandbox, response validation, and UI rendering. A challenge 201 or an unsigned build is not that proof.

## Distribution safety check

The `SmartCart-SolariDevelopment` scheme deliberately archives with `Release-SolariBeta`, not `Development-SolariBeta`. A TestFlight archive therefore points at the distribution base URL and remains category-2-only even if a developer accidentally archives from the development scheme.
