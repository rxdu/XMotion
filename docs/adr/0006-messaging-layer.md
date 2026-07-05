# ADR 0006 — xmMessaging: the application-level communication layer

- Status: **Proposed** (draft for review; supersedes nothing)
- Date: 2026-07-05 (revised same day with the candidate-evaluation research pass)
- Scope: how components of a running robot system exchange data across threads, processes, and hosts — the glue tier that ADR 0005 assigns to applications
- Related: [ADR 0003](0003-naming-and-branding.md) (naming derivation); [ADR 0004](0004-telemetry-layering.md) (the seam pattern this reuses); [ADR 0005](0005-application-level-composition.md) (the layering rule this completes)

## Context

ADR 0005 made composition an application concern: algorithm components (xmNavigation) and hardware components (xmDriver) depend on xmBase only, and applications combine them. That answers *who* composes but not *how* a composed system actually runs: a real robot is multiple processes — perception, planning, control, drivers — exchanging typed data at high rates under latency and reliability constraints. Today each application would hand-roll this glue.

The need is not new to this codebase: iceoryx integration was prototyped in 2023 (xNavigation history #15/#16), a `ros2_idl` placeholder submodule exists for message definitions, and xmBase already carries a serialization module and — critically — a middleware-agnostic correlation-identity carriage (`Inject`/`Extract`, a fixed-size byte envelope) that was explicitly designed to ride "in any envelope."

## Decision (proposed)

Introduce **xmMessaging** (`xmotion::messaging`, per the ADR 0003 derivation: full function word) — a library component providing typed, low-latency communication for composing components into systems.

### 1. Position in the dependency graph

xmMessaging depends on xmBase. **Algorithm and hardware components never link it** — they keep producing/consuming plain xmBase types. Only applications link xmMessaging, using it to move those types between the components they compose. This preserves ADR 0005 exactly: the family maintains the *library*; applications own the wiring.

A deliberate contrast with ADR 0004: the telemetry API lives in xmBase because *every component* instruments unconditionally. Messaging has no such universal call-site — no component publishes on its own — so there is no messaging API in xmBase and no binding seam in the foundation. The API lives in xmMessaging itself.

### 2. What it owns

- **Typed publish/subscribe and request/response** over a backend seam (the ADR 0004 pattern: thin portable API, heavy engines behind it, one CMake option per backend).
- **The envelope contract**: every message carries the telemetry context bytes as a standard header field. Cross-process traces (the "planning stall and the motor fault on one timeline" story) become a property of the transport rather than per-application discipline.
- **A robotics QoS vocabulary stated explicitly**: deadline, reliability (best-effort vs reliable), history (latest-only vs queue-N), and zero-copy loans for high-rate fixed-size payloads.
- **Self-instrumentation** through the telemetry API: queue depths, drops, and hop latency are ordinary metrics — the communication layer is observable like everything else.
- **The message-definition home**: the family's wire vocabulary (IDL mappings where a backend needs them) and the adopted remnants of prior IPC work (`ros2_idl`, nav's `common/ipc`).

### 3. Backend strategy

Based on the candidate evaluation below:

- **Intra-host default: iceoryx2** — daemonless true zero-copy shared memory (publisher loans, subscriber reads in place), sub-microsecond latencies flat across payload sizes, no central broker process to fail, first-class C++ binding. Its pre-1.0 API churn (1.0 planned late 2026) is exactly what the backend seam exists to absorb: pin a version, adopt upgrades on our schedule.
- **Inter-host: Zenoh** — brokerless peer-to-peer with optional routers, single-digit-µs same-host / robust-under-load network behavior in independent automotive testing, and the momentum of `rmw_zenoh` shipping in ROS 2 releases (useful for the bridge story, not a coupling). DDS remains addable behind the seam if an integration ever contractually requires it; it is not the default because its QoS richness comes with tuning-heavy, discovery-fragile operations.
- **ROS 2 is a bridge, not a backend** (the ADR 0004 stance): a ROS application maps topics at its boundary; the family's components and messaging layer remain ROS-free.

### 4. Method

Scenario-driven, like the telemetry stack: the acceptance scenarios (wish-code first) define the API before the implementation exists — e.g. a planner process feeding a control process through the envelope contract at rate, with a mid-run subscriber join, a slow-consumer policy test, and a crash-of-one-process recovery expectation. The scenario suite is the executable specification; implementation phases follow it.

## Candidates & evaluation (research pass, 2026-07)

Seven candidates were evaluated against the family's criteria — low latency, high throughput, predictability (allocation/daemon/RT story), lightweight-ness, and ease of use from C++17 — plus typed-message support, license, and robotics adoption. Sources: project documentation and benchmarks, independent third-party measurements where they exist, and issue-tracker evidence for operational behavior.

| | iceoryx2 | Zenoh | CycloneDDS / FastDDS | eCAL | iceoryx (classic) | Aeron | dora-rs |
|---|---|---|---|---|---|---|---|
| Kind | zero-copy IPC library | pub/sub protocol + library | DDS middleware | pub/sub middleware | zero-copy IPC | reliable-stream transport | dataflow framework |
| Intra-host latency | <1 µs, flat across payload sizes | ~7 µs same-host | ~10–30 µs, payload-dependent | low (1-copy default, SHM opt) | <1 µs | ~0.25 µs RTT *with spin config* | 104–347 µs p50; <4 KiB msgs take a TCP path |
| Zero-copy | true (loan/read-in-place) | SHM API unstable | via iceoryx plugin (Cyclone) | optional iceoryx path | true | publish-side only; assembly copies >MTU | receive-side; 4 KiB threshold |
| Daemon | **none** | none (opt. router) | none | none (opt. services) | RouDi required | **required**; clients die with it | daemon + coordinator |
| Predictability | wait-free, no alloc on hot path | good under load (indep. tests) | QoS-rich but tuning-heavy | good, less RT rigor | proven | needs 3+ spinning cores; default config: ms-class tails at low rates | no published tail/jitter data |
| C++17 ease | first-class binding | good C/C++ API | mature APIs | very good + best tooling | mature | C wrapper, Java-first docs, SBE needs JVM at build | cxx-bridge; Cargo mandatory; experimental |
| Typed messages | yours via seam | yours via seam | IDL toolchain | protobuf native | yours | SBE (build-time JVM) | implicit Arrow conventions |
| Robotics adoption | growing fast (ROS 2 ecosystem) | rmw_zenoh in ROS 2 binaries | ROS 2 defaults | automotive/robotics | wide but **EOL 2026** | **none found** | demos only |
| License | Apache-2.0 OR MIT | Apache-2.0/EPL | EPL / Apache-2.0 | Apache-2.0 | Apache-2.0 | Apache-2.0 | Apache-2.0 |
| Main risk | pre-1.0 churn until ~late 2026 | SHM API instability | ops complexity | weaker RT story | end of life | ops weight, no ecosystem fit | 1.0 rewrite in flight, bus factor 2 |

Findings that shaped the decision:

- **iceoryx2** is the only candidate that is simultaneously daemonless, truly zero-copy, allocation-free on the hot path, and flat in latency across payload sizes — the profile of the family's own RT discipline. Classic iceoryx (the 2023 prototype's target) reaches EOL in 2026 and requires the RouDi daemon; the successor removes that architecture's main operational weakness.
- **Zenoh** was the strongest networked candidate: independent automotive testing showed it robust at loads where FastDDS lost messages, and the ROS 2 ecosystem is converging on it (`rmw_zenoh` ships in current distributions), which strengthens the bridge story without coupling us.
- **DDS (CycloneDDS/FastDDS)** offers the richest QoS vocabulary but at fleet scale is what teams migrate *away from* (discovery storms, per-transport tuning). It stays available behind the seam rather than being the default.
- **eCAL** is the pragmatic "works today with the best recorder/monitor tooling" option; it lost to iceoryx2 on RT rigor (1-copy default) — but its tooling sets the bar for what our telemetry/insight plane should offer around the messaging layer.
- **Aeron** (evaluated on request) delivers its famous numbers only with finance-grade operations: a mandatory media-driver daemon whose death requires restarting every client, ~3 dedicated spinning cores for low-latency config, millisecond-class worst-case latencies *at robot-typical low message rates* under default config, a 16 MB message ceiling, bytes-only API (SBE codegen needs a JVM at build time), and zero robotics-ecosystem presence. Verdict: not a candidate; a benchmark reference. Two of its ideas are worth stealing: explicit back-pressure return codes on `publish` (no silent drops), and monitoring counters exposed via shared memory so any process can scrape transport health.
- **dora-rs** (evaluated on request) is a dataflow *framework*, not a message bus: components must become daemon-spawned processes wired by YAML graphs, with lifecycle owned by the runtime. That inverts control in exactly the way ADR 0005 rejects — applications would stop composing libraries and become graph fragments. Its performance case also inverts for us: it wins only at multi-MB payloads (its own benchmarks show ROS 2 C++ beating it at 4 KB–40 KB, and messages under 4 KiB bypass shared memory entirely), while control-loop traffic is small and rate-critical. Pre-1.0 with a breaking Rust-first 1.0 rework in flight and a two-person bus factor. Verdict: not a fit as substrate or composition layer — but a useful validation: its data plane is literally Zenoh + shared memory, i.e. the same ingredients this ADR adopts as libraries, minus the framework.

## Alternatives considered

- **Adopt ROS 2 as the family middleware** — rejected: couples every application to a heavy, non-RT-friendly (intra-host) stack, contradicts the family's ROS-free component rule; ROS interop remains an application-boundary bridge.
- **Messaging API in xmBase (telemetry-style seam)** — rejected: no universal component call-site exists; a foundation seam would invite components to publish, eroding ADR 0005.
- **Per-application hand-rolled IPC** (status quo) — rejected as the default: repeated glue, no shared QoS vocabulary, and telemetry context carriage left to per-app discipline.
- **A single hardwired backend (no seam)** — rejected: the 2023→2026 landscape shift (iceoryx → iceoryx2, DDS ↔ zenoh) is exactly why the seam pays.
- **Adopt a dataflow framework (dora-rs) as the composition layer** — rejected: inverts control over component lifecycle and composition (see evaluation), contradicting ADR 0005.
- **Aeron as the transport** — rejected for the family's profile (see evaluation); retained as a benchmark reference and a source of API ideas (explicit back-pressure results, shared-memory health counters).

## Consequences (if accepted)

- ADR 0003's component registry gains **xmMessaging** (`xmotion::messaging`); a repository is created when the scenario suite starts.
- xmNavigation's `common/ipc` remnants and the `ros2_idl` placeholder migrate out during or after the current refactor waves.
- The composition-pattern documentation (refactor W2) gains a multi-process variant once the API exists; until then it documents in-process composition and references this ADR.
- Sequencing: work begins **after the xmNavigation refactor completes (W5)** — this ADR exists now so the refactor's documentation and boundaries are drawn with it in view.

## Open questions

1. iceoryx2 version policy: which release to pin first, and the cadence for absorbing pre-1.0 breaking changes behind the seam (1.0 expected ~late 2026).
2. Zenoh scope at v1: inter-host only, or also the intra-host fallback where iceoryx2 is unavailable? Its shared-memory API is still unstable — treat as network transport only for now?
3. Service/RPC semantics: how much beyond pub/sub does v1 need? (iceoryx2 has request/response since 0.6; Zenoh has queryables.)
4. Discovery and configuration: static wiring files vs. runtime discovery — where does the family stand?
5. Whether the high-rate signal plane of the telemetry SDK and the messaging zero-copy plane should share buffer machinery eventually, or stay deliberately separate.
6. Back-pressure surface (the Aeron lesson): should `publish` return an explicit would-block/loan-exhausted status everywhere, with drops observable as metrics by default?
