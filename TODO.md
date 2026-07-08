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
- [x] xmNavigation: algorithm-centric refactor (ADR 0005) — v0.1.0 baseline → v0.2.0 released
  - [x] W0+W1: rename + extraction/decoupling merged as one wave (nav #38; hardware layer gone; xmBase → v0.3.0; XLOG→XM) ∥ xmDriver adopts actuator groups (driver #31 — still open)
  - [x] W2: composition/ROS patterns documented; driver-free gate enforced in CI (nav #39)
  - [x] W3: warning gate (~60 findings fixed incl. a latent OOB read) + sanitizers (now gating) + libxmotion-navigation packaging, GSL removed for std::random (nav #41, #45)
  - [x] W3.5 reorganization: navigation-stack areas (estimation/mapping/decision/planning/control), dormant modules revived for new development, xmnavigation/ include namespace, quickviz → third_party, visualization extracted (viz-independent ABI), event+math promoted to xmBase #25 (nav #42, #43, #44)
  - [x] W4: telemetry instrumentation across all areas (nav #59)
  - [x] W5: xmBase v0.4.0 released; umbrella re-pin + full assembly green (#22); **xmNavigation v0.2.0 released** — the algorithm-centric migration arc is COMPLETE
- [x] Umbrella: re-pin xmNavigation; `XMOTION_WITH_NAVIGATION=ON` — full assembly green (#22)
- [x] Viz v2 COMPLETE (nav #61): quickviz migration (cvdraw → image/) + interactive MPPI tuner (cairo alpha-fan world view, live ESS/cost plots, pause/step + λ/σ sliders); still open: quickviz #30 merge (merge-commit, NOT squash — nav pins 318daf4 from that branch), scene/ 3D for SRB + OccupancyGrid renderable
- [x] MPPI M4a–c COMPLETE (nav #62/#63): rollout-backend seam + threaded CPU backend; CUDA backends (wheeled + SRB programs over shared raw-span cores, float32) + on-device Philox sampling — wheeled end-to-end 0.14 ms @K=2048 / 9.4 ms @K=131072 on GTX 1660 Ti; remaining M4d: device spline-knot sampling for SRB, Jetson Orin deployment/profiling, robot trial
- [x] control folder pass (nav #64/#65/#66): fsm → vendored ctfsm v0.2.0 submodule; safety shield (envelope + ctfsm fallback ladder + CBF-QP barrier, scenario-driven S1–S6); model zoo consolidated into control/models (BicycleAccelModel + dep-free RK4, boost::odeint out of control/); follow-ups: PID production pass, boost removal from state_lattice + reachability internals, S5 quadruped GRF cone shield
- [x] Rename component repos + umbrella submodule paths to function words; register xmTelemetry submodule (PR #12)

## Next arc (after the xmNavigation refactor)

- [ ] xmMessaging (ADR 0006, Proposed): scenario suite first (wish-code), then backend evaluation spike (iceoryx2 intra-host; zenoh vs DDS inter-host), then the repo
- [ ] evaluate: 2023 iceoryx prototype findings (nav's common/ipc + ros2_idl remnants already removed in W3; ADR 0006 candidate evaluation in PR #19)
- [ ] xmNavigation: grow common/ into the inter-area stack vocabulary (state → map → decision → plan → control contracts), scenario-driven; controller_interface gets its first real consumers
- [ ] xmNavigation: traffic_map / road-network revival — unblocks the prediction module and the excluded ghost apps/tests

## Deferred (revisit when the trigger condition arrives)

- [ ] xmTelemetry: live-export plane — when fleet deployment is real (offline exports already cover single-robot workflows)
- [ ] xmTelemetry: runtime-plugin instrumentation contract — if the family adopts plugin loading
