# ADR 0004 — Telemetry layering: API / SDK / exporter split

- Status: Accepted (revised 2026-07-05: implementation specifics moved out of the public record; the decision and its rationale are unchanged)
- Date: 2026-07-03
- Scope: the XMotion telemetry stack — where the instrumentation API, the runtime machinery, and the backend exporters live, and how they bind
- Related: [ADR 0003](0003-naming-and-branding.md) (reserves **xmTelemetry**, `xmotion::telemetry`); [docs/design/telemetry-library-design.md](../design/telemetry-library-design.md) (the design this ADR governs)

## Context

An earlier draft placed the full telemetry spine — capture buffers, worker thread, routing, metric state — in **xmBase**, with xmTelemetry holding only heavy sinks. Design review found three structural problems:

1. **Dishonest optionality.** With the spine in the foundation, "xmTelemetry is optional" holds only for the exporters; every build pays for a worker thread and telemetry state. This contradicts OpenTelemetry's proven API/SDK/exporter layering, which the preceding evaluation recommended adopting.
2. **Crash consistency.** The flight recorder's defining requirement is to *keep the rare event*. An in-process buffer that dies with the process loses exactly the moment that motivates the recorder; crash consistency has to be a first-class property of the capture design, not an afterthought.
3. **Unowned seams.** How the API binds to the machinery, how high-rate streams are kept from starving diagnostics, and who owns init/shutdown ordering were all unspecified.

## Decision

Mirror OpenTelemetry's three-tier layering, with robotics-specific choices at each seam.

### 1. Three tiers, two homes

| Tier | Home | Contents | Deps | Linked |
|------|------|----------|------|--------|
| **API** | **xmBase** (`xmbase/telemetry`, ns `xmotion::telemetry`) | the 4 verbs + health, pre-registered handles, `TraceId`/`SpanId`/`Context` + inject/extract, monotonic clock, compile-out floor | std only; **no state, no threads** | always |
| **SDK** | **xmTelemetry** | the runtime machinery: RT-safe capture, crash-consistent flight recording, recording plane, lifecycle | optional | optional |
| **Exporters / tools** | **xmTelemetry** | recording and export formats, recovery/triage tooling | opt-in | opt-in |

Dependency rule: components (xmDriver, xmNavigation, …) instrument against the **API only**; only the application links the SDK and chooses exporters. `xmBase` never depends on `xmTelemetry`; neither depends on ROS.

### 2. Default binding without the SDK

A binary linking only xmBase gets honest console logging through a built-in, dependency-free binding; `metric`/`span`/`signal` are safe no-ops. Rationale: a pure no-op default (OTel-faithful) would silently swallow errors — unacceptable on a robot; lib-only builds are never silent about faults, and pay nothing else.

### 3. Binding seam: install-once handle table

The SDK binds to the API via a function/handle table installed **once**, before RT begins, guarded by an ABI version. Handles are resolved at *registration* time; no weak symbols (ODR/platform fragility), no per-call provider lookup (not RT-safe). Slot memory is process-lifetime by contract, so a handle held across shutdown stays safe to use. Shutdown drains, flushes, and unbinds before static destruction; both are the application's responsibility. The seam (`binding.hpp`) is public: any backend can implement it.

### 4. Capture guarantees (SDK contract)

The SDK's capture design guarantees: producers never block; high-rate signal streams can never evict or starve diagnostics; drops are bounded, counted, and themselves observable; and the flight recorder is crash-consistent — the recording survives process death and is recoverable on an unmodified machine. How these guarantees are met is SDK-internal.

### 5. Metric aggregation lives in the SDK

Metric state is SDK-owned and updated wait-free from the hot path; export sampling never intrudes into RT code. The API defines only the handle types. (Aggregating in xmBase would drag SDK responsibility into the foundation and is rejected.)

### 6. Logging unifies into the surface

`xmbase/logging` dissolves into this stack rather than living beside it: `XLOG_*` become facades over `event()`; third-party logging backends leave the foundation entirely (replaced by the dependency-free console binding). One spine, one clock, one correlation identity — a log line and a control-loop span line up on the same timeline by construction.

## Alternatives considered

- **Spine in xmBase** (draft v1) — rejected: foundation carries threads/state; optionality dishonest.
- **API also in xmTelemetry** — rejected: every instrumented component would depend on xmTelemetry, recreating the problem the API split solves.
- **A third-party tracing framework as the mandatory spine** — rejected as *mandatory* (platform and operational constraints); such backends remain possible behind the seam.
- **Pure no-op API without SDK** — rejected: silently swallows errors in lib-only builds.
- **A host telemetry daemon** — deferred, not rejected: per-process capture plus host-level collection covers current needs; revisit if per-process export duplication becomes a measured cost.

## Consequences

- xmBase gets *lighter*: a header-light API plus a small dependency-free console binding; third-party logging dependencies leave the foundation.
- xmDriver and xmNavigation instrument against the API alone; their existing observability data (`FreshnessMonitor::Age()`, `DeviceHealth`, `Status`) flows through `metric()`/`health()` with no new dependency.
- CI verifies the layering: an API-only link test (no SDK) and a symbol/size check that disabled instrumentation compiles out.
