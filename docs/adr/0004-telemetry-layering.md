# ADR 0004 — Telemetry layering: API / SDK / exporter split

- Status: Accepted
- Date: 2026-07-03
- Scope: the XMotion telemetry stack — where the instrumentation API, the runtime machinery, and the backend exporters live, and how they bind
- Related: [ADR 0003](0003-naming-and-branding.md) (reserves **xmTelemetry**, `xmotion::telemetry`); [docs/research/otel-robotics-telemetry.typ](../research/otel-robotics-telemetry.typ) (the evaluation this implements, esp. §9 "API-in-core / SDK-in-sidecar"); [docs/design/telemetry-library-design.md](../design/telemetry-library-design.md) (the design this ADR corrects and governs)

## Context

The telemetry design doc (2026-07-02 draft) placed the full spine — wait-free ring, drain thread, router, metric state — in **xmBase**, with xmTelemetry holding only heavy sinks. Design review found three structural problems:

1. **Dishonest optionality.** With the spine in the foundation, "xmTelemetry is optional" holds only for the exporters; every build pays for a drain thread and telemetry state. This contradicts the research report's own conclusion (report §9: the DDS/envelope constraint "reinforc[es] the API-in-core / SDK-in-sidecar split") and OpenTelemetry's proven API/SDK/exporter layering, which the report recommends adopting.
2. **Crash consistency.** The flight recorder's defining requirement is to *keep the rare event* (report §7). An in-process heap ring plus drain thread dies with the process — the crash that motivates the recorder is the moment its last N seconds are lost. The report's "Adopt: LTTng UST snapshot mode" pointed at exactly this property (mmap'd rings readable post-mortem); the design never confronted it.
3. **Unowned seams.** How the API binds to the machinery (per-call provider lookup is not RT-safe; weak symbols are ODR/platform-fragile), how signal floods are kept from evicting diagnostics, and who owns init/shutdown ordering were all unspecified.

Meanwhile xmBase already ships a proven, TSan-verified wait-free capture core (`MpscRtLogger`: bounded Vyukov MPSC ring, drop-newest + counted drops, single-consumer drain) — currently hard-wired to spdlog as a logging backend.

## Decision

Mirror OpenTelemetry's three-tier layering, with robotics-specific choices at each seam.

### 1. Three tiers, two homes

| Tier | Home | Contents | Deps | Linked |
|------|------|----------|------|--------|
| **API** | **xmBase** (`xmbase/telemetry`, ns `xmotion::telemetry`) | the 4 verbs + health, pre-registered handles, `TraceId`/`SpanId`/`Context` + inject/extract, monotonic clock, compile-out floor | std only; **no state, no threads** | always |
| **SDK** | **xmTelemetry** core | handle table, capture **channels**, per-QoS-class rings, drain thread, router, metric aggregation, `Null`/`Console` sinks, `Init()`/`Shutdown()` | std only, light | optional |
| **Exporters** | **xmTelemetry**, one CMake option each | `McapSink` + flight recorder + recovery tool, `OtelSink` → OTLP, LTTng channel, host collectors | heavy/external | opt-in each |

Dependency rule: components (xmDriver, xmNavigation, …) instrument against the **API only**; only the application links the SDK and chooses exporters. `xmBase` never depends on `xmTelemetry`; neither depends on ROS.

### 2. No-SDK default binding

A binary linking only xmBase gets: `event()` at **Warn and above → synchronous stderr**; `metric`/`scope`/`signal` → no-ops. Rationale: pure no-op (OTel-faithful) would silently swallow errors — a regression from today's always-on `XLOG` stderr behavior; unconditional stderr for all severities would spam. Lib-only builds are never silent about faults, and pay nothing else.

### 3. Binding seam: install-once handle table

The SDK binds to the API via a function/handle table installed **once** at `telemetry::Init()`, before RT begins. Handles (`Counter&`, `SignalChannel&`, interned name-ids) are resolved at *registration* time and point directly at SDK-allocated slots (or a shared no-op slot when unbound). No weak symbols (ODR/platform fragility), no per-call provider lookup (not RT-safe). `telemetry::Shutdown()` drains, flushes, and unbinds before static destruction; both are the application's responsibility.

### 4. Capture channels; the mmap black box

The SDK's ring sits behind a **channel** abstraction with three implementations: (a) **heap ring** — default, portable (the existing `MpscRtLogger` Vyukov ring, migrated); (b) **mmap black box** — the ring backed by a file-backed mmap on tmpfs with a versioned header (magic, schema hash, boot-id, monotonic→realtime offset). Identical wait-free code, but the buffer **survives process death**; a small `xmtelemetry-recover` CLI reads the mapping post-crash and emits the last N seconds as MCAP. This is LTTng's crash-recovery design (`lttng-crash`) without adopting its daemon; (c) **LTTng UST** — opt-in, for kernel-correlated tracing on deployments that run a session daemon. Note the tmpfs black box survives a process crash, not power loss; persistence across power events is the flight-recorder snapshot's job.

### 5. QoS class separation

Diagnostics (event/metric/span) and high-rate signals use **separate rings**, so a 1 kHz signal flood can never evict an Error event. Drop policy per class: drop-newest + counted drops (the counter is itself telemetry); producers never block.

### 6. Metric aggregation lives in the SDK

`Counter`/`Gauge`/`Histogram` state (atomics, fixed-boundary buckets) is SDK-allocated and updated via relaxed atomics — no ring push per increment; the drain samples aggregates periodically for export. The API defines only the handle types. (The earlier idea of aggregating in xmBase dragged SDK responsibility into the foundation and is rejected.)

### 7. Logging unifies into the surface

`xmbase/logging` dissolves into this stack rather than living beside it: `XLOG_*` / `XLOG_RT_*` become facades over `event()` (call sites unchanged); the `MpscRtLogger` ring code migrates to the SDK as the heap channel; spdlog demotes from foundation backbone to an implementation detail of the SDK's `ConsoleSink`. One spine, one clock, one correlation identity — a log line and a control-loop span line up on the same timeline by construction.

## Alternatives considered

- **Spine in xmBase** (design doc v1) — rejected: foundation carries threads/state; optionality dishonest; contradicts report §9.
- **API also in xmTelemetry** — rejected: every instrumented component would depend on xmTelemetry, recreating the problem the API split solves.
- **LTTng UST as the mandatory spine** — rejected as *mandatory* (Linux-only, sessiond ops burden, CTF→Foxglove workflow friction); retained as an opt-in channel.
- **Pure no-op API without SDK** — rejected: silently swallows errors in lib-only builds; stderr-for-Warn+ chosen instead.
- **A host telemetry daemon (shm protocol + agent)** — deferred, not rejected: the black box + per-process drain + one host OTel Collector covers current needs without inventing a daemon protocol; revisit if per-process export duplication becomes a real cost.

## Consequences

- xmBase gets *lighter*: eventually no compiled logging backbone, just a header-light API + a trivial stderr binding; the spdlog dependency leaves the foundation.
- xmDriver and xmNavigation instrument against the API alone; their existing observability data (`FreshnessMonitor::Age()`, `DeviceHealth`, `Status`) flows through `metric()`/`health()` with no new dependency.
- The design doc is rewritten to this layering (same document, revised); its phased plan re-cuts so P0 = API + SDK skeleton (migrating the proven ring), and the black box lands as its own phase.
- The ring choice open-question closes: adopt our own proven Vyukov ring; no third-party ring dependency.
- CI must eventually verify the layering: an API-only link test (no SDK) and a symbol/size check that disabled instrumentation compiles out.
