# XMotion TODO

The task tracker for the family. Cross-repo sequencing lives here; each component tracks its own internal work in its repo's `TODO.md`. Status: `[ ]` open · `[~]` in progress · `[x]` done.

## Rename / migration lockstep (ADR 0003 — foundation-up)

- [ ] xmBase: merge PR [#18](https://github.com/rxdu/xmBase/pull/18) (telemetry docs package + examples + ABI v3)
- [ ] xmBase: cut v0.3.0 (telemetry API baseline; gated on #18 and explicit go)
- [ ] xmDriver: migrate `XLOG_*` → `XM_*` telemetry API (one-touch, clean break); adopt driver signals (FreshnessMonitor age, tx-queue depth, fault counters, DeviceHealth) through the API
- [ ] Umbrella: re-pin xmBase + xmDriver after the migration; flip `XMOTION_WITH_TELEMETRY=ON` in the assembly
- [ ] xmBase: retire the interim spdlog binding + private `src/logging` backend (SDK console sink has reached parity)
- [ ] xmNavigation: HAL migration + telemetry-instrumented refactor (includes ADR 0002 Phase-2 decoupling: drop bundled `third_party/xmMu`/`xmSigma` copies, depend on the renamed components)
- [ ] Umbrella: re-pin xmNavigation; flip `XMOTION_WITH_NAVIGATION=ON` — full assembly returns
- [x] Rename component repos + umbrella submodule paths to function words; register xmTelemetry submodule (PR #12)

## Deferred (revisit when the trigger condition arrives)

- [ ] xmTelemetry: S13 exporter isolation + live OTLP fan-out — when fleet deployment is real (offline OTLP-JSON export already covers single-robot workflows)
- [ ] xmTelemetry: `dlopen` plugin instrumentation contract — if the family adopts runtime plugin loading
