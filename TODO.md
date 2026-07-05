# XMotion TODO

The task tracker for the family. Cross-repo sequencing lives here; each component tracks its own internal work in its repo's `TODO.md`. Status: `[ ]` open · `[~]` in progress · `[x]` done.

## Rename / migration lockstep (ADR 0003 — foundation-up)

- [x] xmBase: merge PR [#18](https://github.com/rxdu/xmBase/pull/18) (telemetry docs package + examples + ABI v3)
- [x] xmBase: cut v0.3.0 (telemetry API baseline — released 2026-07-05)
- [x] xmDriver: migrate `XLOG_*` → `XM_*` telemetry API + adopt driver signals through the API (PRs #29 + #30)
- [x] Umbrella: re-pin xmBase + xmDriver + telemetry; `XMOTION_WITH_TELEMETRY=ON` (PR #16; assembly proof lives in the SDK repo CI)
- [x] xmTelemetry: v0.1.0 released (private assets; requires xmBase >= 0.3.0)
- [ ] xmDriver: packaging fix — bundled xmBase install rules leak into the deb (needs EXCLUDE_FROM_ALL like xmTelemetry)
- [x] xmBase: replace the interim spdlog binding with the permanent dependency-free console binding (shipped in v0.3.0 — spdlog left the foundation)
- [~] xmNavigation: algorithm-centric refactor (ADR 0005) — plan approved, baseline v0.1.0 cut
  - [x] W0+W1: rename + extraction/decoupling merged as one wave (nav #38; hardware layer gone; xmBase → v0.3.0; XLOG→XM) ∥ xmDriver adopts actuator groups (driver #31 — still open)
  - [x] W2: composition/ROS patterns documented; driver-free gate enforced in CI (nav #39)
  - [x] W3: warning gate (~60 findings fixed incl. a latent OOB read) + sanitizers (now gating) + libxmotion-navigation packaging, GSL removed for std::random (nav #41, #45)
  - [x] W3.5 reorganization: navigation-stack areas (estimation/mapping/decision/planning/control), dormant modules revived for new development, xmnavigation/ include namespace, quickviz → third_party, visualization extracted (viz-independent ABI), event+math promoted to xmBase #25 (nav #42, #43, #44)
  - [ ] W4: telemetry instrumentation (planning/estimation/decision + revived modules)
  - [ ] W5: umbrella re-pin (needs xmBase v0.4.0 cut); NAVIGATION=ON; full assembly returns
- [ ] Umbrella: re-pin xmNavigation; flip `XMOTION_WITH_NAVIGATION=ON` — full assembly returns
- [x] Rename component repos + umbrella submodule paths to function words; register xmTelemetry submodule (PR #12)

## Next arc (after the xmNavigation refactor)

- [ ] xmMessaging (ADR 0006, Proposed): scenario suite first (wish-code), then backend evaluation spike (iceoryx2 intra-host; zenoh vs DDS inter-host), then the repo
- [ ] evaluate: 2023 iceoryx prototype findings (nav's common/ipc + ros2_idl remnants already removed in W3; ADR 0006 candidate evaluation in PR #19)
- [ ] xmNavigation: grow common/ into the inter-area stack vocabulary (state → map → decision → plan → control contracts), scenario-driven; controller_interface gets its first real consumers
- [ ] xmNavigation: traffic_map / road-network revival — unblocks the prediction module and the excluded ghost apps/tests

## Deferred (revisit when the trigger condition arrives)

- [ ] xmTelemetry: live-export plane — when fleet deployment is real (offline exports already cover single-robot workflows)
- [ ] xmTelemetry: runtime-plugin instrumentation contract — if the family adopts plugin loading
