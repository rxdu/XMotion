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
  - [~] W0: rename branch lands (PR #37, red-by-design until W2)
  - [~] W1: extraction + decoupling (delete hardware layer + third_party/xmDriver; xmBase → v0.3.0; XLOG→XM; spdlog verdict) ∥ xmDriver adopts actuator groups
  - [ ] W2: composition/ROS patterns documented; driver-free gate green
  - [ ] W3: warning gate + advisory sanitizers + packaging (libxmotion-navigation)
  - [ ] W4: telemetry instrumentation (planning/estimation/dispatcher)
  - [ ] W5: umbrella re-pin; NAVIGATION=ON; full assembly returns
- [ ] Umbrella: re-pin xmNavigation; flip `XMOTION_WITH_NAVIGATION=ON` — full assembly returns
- [x] Rename component repos + umbrella submodule paths to function words; register xmTelemetry submodule (PR #12)

## Next arc (after the xmNavigation refactor)

- [ ] xmMessaging (ADR 0006, Proposed): scenario suite first (wish-code), then backend evaluation spike (iceoryx2 intra-host; zenoh vs DDS inter-host), then the repo
- [ ] evaluate: 2023 iceoryx prototype findings; adopt nav's common/ipc + ros2_idl remnants into the new component

## Deferred (revisit when the trigger condition arrives)

- [ ] xmTelemetry: live-export plane — when fleet deployment is real (offline exports already cover single-robot workflows)
- [ ] xmTelemetry: runtime-plugin instrumentation contract — if the family adopts plugin loading
