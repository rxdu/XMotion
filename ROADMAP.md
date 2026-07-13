# XMotion Roadmap — north star: swervebot autonomous waypoints

- Status: Active (reviewed when a gap closes, not on a calendar)
- Operating rule: the family's charters-and-gates principle applied at system level — **the robot application is the consumer of the family.** Work queues behind a gap this milestone exposes; nothing system-level is built without one.
- Portfolio: ~70% milestone path · ~20% debt-and-lessons (the standing remediation lists) · ~10% exploration, no justification required.
- The four-question test for any proposed task: which milestone gap does it close? who is the named consumer? what measured claim proves it done? is it the smallest step that retires the largest unknown?

## The milestone (measured, falsifiable)

**Swervebot drives autonomous waypoint laps**, on a two-computer architecture with **CAN as the boundary**:

- **Base tier ("firmware role")** — the existing PocketBeagle running the reworked [xmAppSwerveBase](https://github.com/rxdu/xmAppSwerveBase): motor/servo control, swerve kinematics, RC failsafe, exposing a high-level command/state interface **over CAN bus**. To the upper layer, the base is a CAN device — like any commercial chassis.
- **Autonomy tier** — an aarch64/x86 computer running the composition: swerve-base CAN driver (xmDriver) + IMU/odometry MEKF + waypoint mission + tracking controller over xmMessaging (in-process), black-box telemetry, live diagnostics — **sustained 30 minutes**, with the observability chain proving control-loop tails are unaffected by full-rate observation.

Both applications compose the family (ADR 0005) and are deliberately NOT umbrella components — never pinned here.

**armv7 support is scoped to the driver tier only** (owner decision): the base runs xmDriver + xmBase core on 32-bit ARM; the seqlock/messaging/nav stack is not required there. (Correction of an earlier claim: Cortex-A8 is ARMv7-A, which has `ldrexd`/`strexd` — 64-bit lock-free atomics likely exist; the accurate status is *unverified*, and the narrow scoping keeps the verification burden proportional.)

## Phase 0 — the CAN contract + two skeletons

- [ ] **Base CAN protocol spec (the new wire vocabulary)**: command set (body twist in, mode/enable, e-stop), state set (odometry twist/pose delta, module states, faults, battery), heartbeat + **command-timeout failsafe defined ON the base** (loss of CAN = safe stop, non-negotiable), versioned like the family's wire contracts. Lives in the swervebot repo (it owns the interface); the upper-layer driver consumes it.
- [ ] **Swervebot rework — base firmware skeleton**: composition-based app per the family pattern, scoped to the base role (config from `sbot.yaml`, FSM/control modes, RC override, kinematics → DDSM/steering, CAN server). Consumes xmDriver + xmBase core via the app's own pinning. Old `external/libxmotion` retired. Exit gate: **teleop parity on the bench through the new stack**.
- [ ] **armv7 driver-tier build proof**: cross-compile (or on-target build) of xmDriver + xmBase core for armhf; a cross-compile CI check if it proves cheap (GitHub has no armhf runners — build-only). Owner: xmDriver/xmBase.
- [ ] **Upper-compute choice**: which aarch64/x86 machine rides the robot (and whether Phase 1–2 can run it tethered/desk-side first). Owner: you.

## Phase 0.5 — the upper layer sees the base

- [ ] **swerve_base CAN device driver in xmDriver** (upper side): speaks the Phase-0 protocol via socketcan (exists), exposes the base as capability-typed HAL (twist-commandable, odometry-reporting, health) like any other device. This replaces the earlier "steering-servo driver" gap — steering stays base-internal behind CAN.
- Measured exit: upper computer commands laps of the *bench-mounted* base over CAN; command→wheel latency and heartbeat-failsafe behavior measured and recorded.

## Phase 1 — hardware-in-the-loop teleop (retire the biggest unknown first)

- [ ] Base bring-up on the robot: DDSM_210 (exists), WaveShare steering servos (**likely xmDriver gap — audit the device set**; base-side), RC/sbus (exists) — all on the PocketBeagle build.
- [ ] Safety envelope before autonomy, layered: base-level (CAN-timeout failsafe, command clamps, RC override — validated on stands) and upper-level (FSM guards). 
- [ ] Telemetry: the autonomy tier binds the SDK with black-box recording from day one; the base stays lean (console/log tier initially — whether the base ever records MCAP is a later, gated question).
- Measured exit: teleop through the FULL chain (joystick on upper computer → CAN → base → wheels) recorded end-to-end; control-loop period tails published from the MCAP.

## Phase 2 — state estimation on the robot

- [ ] Swerve wheel-odometry: decide the split — base computes odom (reports over CAN, part of the protocol) vs raw module states up + upper-side model. Then the model/covariance work lands where decided (owner: protocol decision first).
- [ ] IMU on robot: imu_hipnuc driver exists; hardware IMU bench exists (`bench/imu_attitude`) — run the attitude bench on the actual unit (owner: umbrella bench).
- [ ] MEKF fusion (IMU + odom) on-target; **validation ladder L0–L5 executed against recorded robot data** (the ladder was proposed for exactly this; owner: xmNavigation).
- [ ] Localization honesty check: odom+IMU dead-reckoning drifts — decide whether waypoint laps need an absolute reference (UWB/LiDAR/camera) or whether drift-bounded laps satisfy the milestone. **Scoping decision, owner: you.**
- Measured exit: pose estimate vs ground-truth tape-measure course; NEES consistency from the ladder.

## Phase 3 — waypoint autonomy (the composition payoff)

- [ ] Waypoint mission layer: sequencing, arrival tolerance, loop — small; lives app-side unless a second app demands it (charters/gates).
- [ ] Tracking controller: pure-pursuit-class follower first (MPPI exists for later; smallest step wins), consuming the MEKF pose (owner: xmNavigation control or app-side initially).
- [ ] **Compose over xmMessaging in-process** — estimator → planner → controller as the M1/M13 coupling on a real robot: the transport's first production consumer; lineage (`origin_age`) gating actuation on stale-information (owner: app wiring; messaging is ready).
- [ ] Sim-first: the headless SimLoop + swerve model validates the mission/controller before hardware (exists in nav).
- Measured exit: autonomous laps in sim, then on robot; waypoint arrival errors published.

## Phase 4 — tuning, soak, and the observability claim

- [ ] Live tuning loop: start with what ships today (`xmmsg` CLI + MCAP → Foxglove converters); pull **quickviz `bridges/xmotion` (topic-bound scope + tuner)** into scope here if offline iteration proves too slow — this is also the gated first consumer for quickviz I3 counters and depth-N `MessageBuffer` snapshots.
- [ ] 30-minute soak: continuous laps, black box on, `/dev/shm` and RSS flat, deadline-miss counters zero or explained.
- [ ] **The headline measured claim**: control-loop tails with full observability attached vs detached — the M10-A4 shape, end-to-end, on hardware. This closes the observability-budget arc ([docs/design/observability-budget.md](docs/design/observability-budget.md)).

## Debt lane (~20%, standing)

- [ ] quickviz: I3 overflow counters · I7 bench CI gate · I5 hardware-GL observer A/B (one command on a desktop session) · `thread_safe_queue` move-fix audit · `namespace xmotion` residue cleanup
- [ ] xmMessaging: bench `reference.json` pinning (needs a designated stable runner) · ASan CI job (ran manually at W2)
- [ ] xmBase: clang-format pass on W1 files where formatter exists
- [ ] Family: arm64 deb builds for the autonomy tier; armhf cross-compile check for the driver tier

## Deferred by the gate (not blocked — ungated)

- **P1 iceoryx2**: same-host IPC is served by the shm backend; revisit when a measured need (or the dependency-acquisition decision) arrives.
- **P2 Zenoh + M12 + threat model**: no second host in the milestone.
- **EventHub build**: waits for its first consumer (possibly Phase 2/3 multi-threaded processing — the design is ready, `xmBase docs/event_hub.md`).
- Depth-N `MessageBuffer` beyond what Phase 4's scope widget demands; `MpscQueue`; `FixedPool`; `TripleBuffer` — all per the taxonomy's reserved rows.
