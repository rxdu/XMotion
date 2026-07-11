# ADR 0007 — Module placement: what moves to xmBase, what stays with its component

- Status: **Proposed**
- Date: 2026-07-11
- Scope: where shared-looking modules live across the family — foundation promotion criteria, the UI-events/transport plane boundary, the concurrency-primitive consolidation, and quickviz's dual-mode position
- Related: [ADR 0001](0001-component-architecture.md) (component tiers), [ADR 0005](0005-application-level-composition.md) (dependency classes), [ADR 0006](0006-messaging-layer.md) (xmMessaging), [observability budget](../design/observability-budget.md)

## Context

Three pressures surfaced together during the xmMessaging build-out (2026-07-10/11) and the viz-plane ingestion contract work:

1. **Three generations of the same concurrency primitives coexist.** xmBase carries the Σ-era `container/` pair (`ring_buffer`, `thread_safe_queue`; consumed today by xmDriver's `async_port` and xmBase's own async event dispatcher). quickviz carries its own mutex-based `core/buffer/` set (now contract-benchmarked, I1–I7). xmMessaging carries the newest and by far best-verified set in `xmmsg/detail/` — a placement-parameterized seqlock `LatestSlot`, an SPSC `BoundedQueue`, and condvar/futex `Waiter` policies, proven under TSan, ASan, aarch64 CI, cross-process shared memory, and SIGKILL crash tests.
2. **The performance-testing toolkit is triplicated.** xmTelemetry's perf tier, xmMessaging's `bench/`, and quickviz's ingestion bench each hand-rolled the same percentile harness and allocation probe. The observability budget depends on cross-component numbers being comparable; three drifting methodologies is how they stop being comparable.
3. **A name-collision almost caused a wrong consolidation.** xmBase's `event/` and quickviz's `core/event/` share ancestry and names but are different designs: xmBase's is a 43-line name-keyed pub/sub with no external consumers; quickviz's is a 280-line GUI event system whose consumption semantics, handler priorities, and GUI-thread marshaling are the library's threading model (one render thread, N background threads, lossless inter-thread message passing — the machinery every GUI toolkit ships). Treating these as duplicates to merge would have forced one design to serve two jobs.

Separately, quickviz's position was settled in the same discussions: it remains one repo, no family fork (the fork trigger is recorded below), with a foreseen family integration — telemetry and messaging support for easy data logging/visualization from other components — arriving as an optional module rather than core coupling.

## Decision

### 1. Foundation promotion criteria

A module moves into xmBase only when **all four** hold:

1. **Two or more real consumers with the same contract.** Name-alikes do not count; the event-dispatcher pair is the cautionary example.
2. **Contract-stable and verified.** The module arrives with its tests and benchmarks; verification transfers with the code.
3. **No heavyweight dependencies.** The foundation earns its position by being cheap to link.
4. **Domain-neutral.** Robot semantics stay in components (ADR 0005 doctrine).

Everything else stays with its owning component until a second consumer *materializes* — never speculatively (anti-pattern 5).

### 2. The plane boundary (UI events vs transport)

**UI/command events** — lossless FIFO, handler consumption, priorities, GUI-thread marshaling — live in the viz library; they are quickviz's GUI programming model, a core capability, not incidental duplication. **Observability data** — drop-tolerant, topic-routed, QoS-governed — lives in the transport (xmMessaging). Neither layer hosts the other's plane. The only adapter between them is quickviz's gated `bridges/xmotion/` module: family data flows in via xmMessaging subscriptions into quickviz's buffers and charts; UI events never ride the transport; robot data never rides the GUI event system.

### 3. Target layout

| Component | Keeps | Gains | Sheds |
|---|---|---|---|
| **xmBase** | types, clock, telemetry API, serialization, math | `concurrency/` — `LatestSlot`, `BoundedQueue`, `Waiter`, `Placement` promoted from xmMessaging with their full verification suite; `testing/` — the allocation probe + percentile bench harness, unified from the three copies | Σ-era `container/ring_buffer` + `thread_safe_queue` (superseded by `concurrency/`); `event/` — retired **together with** `container/thread_safe_queue` (its only consumer is xmBase's own async dispatcher), unless the audit surfaces a named consumer, in which case the dispatcher repatriates to that component |
| **xmMessaging** | envelope/wire contract, schema hash, mail record, shm segment, backends, Domain wiring | — | `detail/{latest_slot, bounded_queue, waiter, placement}` become thin includes of `xmbase/concurrency/` |
| **quickviz** | everything: the GUI event system (core capability per §2), its contract-conformant buffers, zero family dependencies in core | `bridges/xmotion/` — dual-mode gated module (in-tree targets > installed packages > absent-and-skipped): topic-bound widgets, telemetry signal taps, GUI domain browser over the introspection reader, metric-schema dashboard, and recording *controls* driving xmTelemetry's recorder (never a second logger — one recording plane) | nothing structural |
| **xmTelemetry** | its RT-specialized rings (mlock'd, crash-safe — deliberately not general) | adopts `xmbase/testing/` | its private harness copy |
| **xmDriver** | — | — | `async_port` include swap to `xmbase/concurrency/` |

**Deliberately not promoted** (criterion 1 fails today — single consumer each): the schema hash (xmMessaging; revisit if serialization wants type identity), the introspection reader, telemetry's rings, quickviz's `DataStream`/`BufferRegistry`.

### 4. quickviz dual-mode identity

quickviz builds in two modes from one repo: **standalone** (no family packages present; `bridges/xmotion/` silently skipped; today's zero-dependency behavior) and **within the family** (umbrella in-tree targets or installed family packages activate the bridge; option `AUTO|ON|OFF`). "xmViewer" names the family-mode build; no fork. **Fork trigger, recorded**: fork only if a *measured* family requirement demands a core change that conflicts with quickviz's standalone public mission; nothing measured today comes close (ingestion contract I1–I7 conforms with ≥2× margin).

## Alternatives considered

- **Full unification including quickviz** (quickviz depends on xmBase for primitives) — rejected: drags Eigen and the telemetry surface into a deliberately dependency-free public library, violates its own core-depends-on-nothing rule, and buys no measured performance.
- **Promote quickviz's buffers as asked initially** — rejected: they are the least-verified of the three generations; xmMessaging would not adopt them, leaving two implementations anyway.
- **A family-specialized quickviz fork** — rejected: the family owns upstream, so a fork buys only API-breaking freedom at a permanent divergence tax; the dual-mode bridge delivers the integration additively.
- **quickviz UI events over xmMessaging** — rejected: layering inversion (viz core linking the robot transport) plus a semantic mismatch (lossless prioritized consumption vs drop-tolerant QoS fan-out); see §2.
- **Status quo** — rejected: three drifting primitive generations and a triplicated measurement methodology directly undermine the observability budget's comparability requirement.

## Consequences (migration waves, clean break, batched one-touch)

- **W1** — xmBase 0.5.0: add `concurrency/` + `testing/` (code, tests, and benchmarks move together); release notes mark `container/` and `event/` deprecated-for-removal.
- **W2** — xmMessaging: repin to xmBase 0.5.0, swap `detail/` duplicates for foundation includes; the full suite must stay green across plain/TSan/ASan and aarch64 CI — this is the proof the verification transferred.
- **W3** — xmDriver `async_port` include swap; xmBase drops `container/` and `event/` (or repatriates the dispatcher per the audit). W2+W3 batch into a single umbrella repin.
- **W4** (independent track) — quickviz: `thread_safe_queue` move-fix audit, I3 overflow counters, `namespace xmotion`/`XMOTION_` guard residue cleanup; `bridges/xmotion/` skeleton when the integration begins.

## Open questions

1. The `xmbase/event/` audit: confirm no unnamed consumer exists (it was promoted from navigation on 2026-07-06 yet nothing includes it — establish why before deleting).
2. Whether xmBase should split an Eigen-free core target — deferred until a consumer that needs it materializes (criterion 1).
3. `xmbase/testing/` packaging: header-only install vs a dev-only component in the deb — decide at W1.
