# XMotion TODO

The task tracker for the family. Cross-repo sequencing lives here; each component tracks its own internal work in its repo's `TODO.md`. Status: `[ ]` open · `[~]` in progress · `[x]` done.

## Rename / migration lockstep (ADR 0003 — foundation-up)

- [x] xmBase: merge PR [#18](https://github.com/rxdu/xmBase/pull/18) (telemetry docs package + examples + ABI v3)
- [x] xmBase: cut v0.3.0 (telemetry API baseline — released 2026-07-05)
- [x] xmDriver: migrate `XLOG_*` → `XM_*` telemetry API + adopt driver signals through the API (PRs #29 + #30)
- [~] Umbrella: re-pin xmBase + xmDriver + telemetry; `XMOTION_WITH_TELEMETRY=ON` (PR #16, awaiting merge)
- [x] xmBase: replace the interim spdlog binding with the permanent dependency-free console binding (shipped in v0.3.0 — spdlog left the foundation)
- [ ] xmNavigation: HAL migration + telemetry-instrumented refactor (includes ADR 0002 Phase-2 decoupling: drop bundled `third_party/xmMu`/`xmSigma` copies, depend on the renamed components)
- [ ] Umbrella: re-pin xmNavigation; flip `XMOTION_WITH_NAVIGATION=ON` — full assembly returns
- [x] Rename component repos + umbrella submodule paths to function words; register xmTelemetry submodule (PR #12)

## Deferred (revisit when the trigger condition arrives)

- [ ] xmTelemetry: live-export plane — when fleet deployment is real (offline exports already cover single-robot workflows)
- [ ] xmTelemetry: runtime-plugin instrumentation contract — if the family adopts plugin loading
