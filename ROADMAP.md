# XMotion Roadmap — north star: swervebot autonomous waypoints

- Status: Active (reviewed when a gap closes, not on a calendar)
- Operating rule: the family's charters-and-gates principle applied at system level — **the robot application is the consumer of the family.** Work queues behind a gap this milestone exposes; nothing system-level is built without one.
- Portfolio: ~70% milestone path · ~20% debt-and-lessons (the standing remediation lists) · ~10% exploration, no justification required.
- The four-question test for any proposed task: which milestone gap does it close? who is the named consumer? what measured claim proves it done? is it the smallest step that retires the largest unknown?

## The milestone (measured, falsifiable)

**Swervebot drives autonomous waypoint laps**: xmDriver actuation (DDSM drive + steering servos) + IMU/odometry MEKF state estimation + waypoint mission layer + tracking controller, composed over xmMessaging (in-process), black-box telemetry recording throughout, live diagnostics attached — **sustained 30 minutes**, with the observability chain proving control-loop tails on hardware are unaffected by full-rate observation.

The application repo is [swervebot_controller](https://github.com/rxdu/swervebot_controller) — a standalone application *on top of* the family (ADR 0005: applications compose; it is deliberately NOT an umbrella component and never gets pinned here).

## Phase 0 — platform + application skeleton (the two decisions everything waits on)

- [ ] **Compute platform decision (blocking, hardware)**: the current PocketBeagle is 32-bit ARM (Cortex-A8); `xmbase/concurrency`'s seqlock primitives require lock-free 64-bit atomics (`static_assert`ed) and family CI covers x86_64 + aarch64 only. Options: move to an aarch64 SBC (Pi 4/5, Radxa, Jetson — recommended; zero family work), or fund an armv7 port (mutex-fallback primitives + a new CI leg — real cost, one consumer). Decide before any bring-up work.
- [ ] **Swervebot rework — skeleton**: new composition-based application per the family pattern (`docs/` integration-patterns: construction from config, capability-typed actuator groups, app-owned loops); consumes family releases via find_package/debs (or submodules pinned at tags — app's choice, not the umbrella's). Old `external/libxmotion` retired. Port `sbot.yaml` config + FSM/control-mode structure. Gate for phase exit: **teleop parity on the bench** — joystick → SwerveDriveKinematics → DDSM/steering, using xmDriver only.

## Phase 1 — hardware-in-the-loop teleop (retire the biggest unknown first)

- [ ] Driver bring-up on the robot: DDSM_210 (exists, consolidated + checksum fixes), RC/sbus receiver (exists), joystick HID (exists); **WaveShare steering-servo driver — likely gap, audit against xmDriver's device set** (owner: xmDriver).
- [ ] Safety envelope before autonomy: failsafe stop path, command clamps, FSM guard states, RC override — validated on stands before wheels touch ground (owner: app + xmDriver HAL capabilities).
- [ ] Telemetry instrumented from day one: app binds the SDK, black-box recording on, `xm_logging`/spans in the control loop (owner: app; everything needed already shipped).
- Measured exit: teleop drive session recorded end-to-end; control-loop period tails published from the MCAP.

## Phase 2 — state estimation on the robot

- [ ] Swerve wheel-odometry model (kinematics exists; odometry integration + covariance is the gap — owner: xmNavigation estimation).
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
- [ ] Family: arm64 deb builds if the platform decision lands on aarch64 deploy-by-deb

## Deferred by the gate (not blocked — ungated)

- **P1 iceoryx2**: same-host IPC is served by the shm backend; revisit when a measured need (or the dependency-acquisition decision) arrives.
- **P2 Zenoh + M12 + threat model**: no second host in the milestone.
- **EventHub build**: waits for its first consumer (possibly Phase 2/3 multi-threaded processing — the design is ready, `xmBase docs/event_hub.md`).
- Depth-N `MessageBuffer` beyond what Phase 4's scope widget demands; `MpscQueue`; `FixedPool`; `TripleBuffer` — all per the taxonomy's reserved rows.
