# ADR 0006 — xmMessaging: the application-level communication layer

- Status: **Proposed** (draft for review; supersedes nothing)
- Date: 2026-07-05
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

- **Intra-host default: iceoryx2** — zero-copy shared memory, daemonless, aligned with the family's RT discipline. *(Open: evaluation against the 2023 iceoryx-classic prototype's findings.)*
- **Inter-host: zenoh or DDS** — selection deferred to an evaluation spike; the API must not leak backend types either way.
- **ROS 2 is a bridge, not a backend** (the ADR 0004 stance): a ROS application maps topics at its boundary; the family's components and messaging layer remain ROS-free.

### 4. Method

Scenario-driven, like the telemetry stack: the acceptance scenarios (wish-code first) define the API before the implementation exists — e.g. a planner process feeding a control process through the envelope contract at rate, with a mid-run subscriber join, a slow-consumer policy test, and a crash-of-one-process recovery expectation. The scenario suite is the executable specification; implementation phases follow it.

## Alternatives considered

- **Adopt ROS 2 as the family middleware** — rejected: couples every application to a heavy, non-RT-friendly (intra-host) stack, contradicts the family's ROS-free component rule; ROS interop remains an application-boundary bridge.
- **Messaging API in xmBase (telemetry-style seam)** — rejected: no universal component call-site exists; a foundation seam would invite components to publish, eroding ADR 0005.
- **Per-application hand-rolled IPC** (status quo) — rejected as the default: repeated glue, no shared QoS vocabulary, and telemetry context carriage left to per-app discipline.
- **A single hardwired backend (no seam)** — rejected: the 2023→2026 landscape shift (iceoryx → iceoryx2, DDS ↔ zenoh) is exactly why the seam pays.

## Consequences (if accepted)

- ADR 0003's component registry gains **xmMessaging** (`xmotion::messaging`); a repository is created when the scenario suite starts.
- xmNavigation's `common/ipc` remnants and the `ros2_idl` placeholder migrate out during or after the current refactor waves.
- The composition-pattern documentation (refactor W2) gains a multi-process variant once the API exists; until then it documents in-process composition and references this ADR.
- Sequencing: work begins **after the xmNavigation refactor completes (W5)** — this ADR exists now so the refactor's documentation and boundaries are drawn with it in view.

## Open questions

1. iceoryx2 maturity for the C++ surface vs. classic iceoryx (what did the 2023 prototype conclude?).
2. Inter-host backend: zenoh vs. DDS evaluation criteria and spike scope.
3. Service/RPC semantics: how much beyond pub/sub does v1 need?
4. Discovery and configuration: static wiring files vs. runtime discovery — where does the family stand?
5. Whether the high-rate signal plane of the telemetry SDK and the messaging zero-copy plane should share buffer machinery eventually, or stay deliberately separate.
