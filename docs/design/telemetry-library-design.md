# Design: XMotion Telemetry (**xmTelemetry**)

- Status: Shipped (API tier in xmBase; SDK + tools in xmTelemetry)
- Governing decision: [ADR 0004 — telemetry layering](../adr/0004-telemetry-layering.md)
- User-facing documentation: the [xmBase telemetry docs](https://github.com/rxdu/xmBase/tree/main/docs/telemetry) (design · reference · guide · examples) — the API is the surface users interact with, and its docs live with it.

## 1. Purpose

One instrumentation surface for the whole XMotion family — logs, metrics, causal traces, high-rate signals, and health — usable identically from a 1 kHz control loop and a planning thread, with one clock and one correlation identity across threads and processes.

## 2. Goals and non-goals

### Goals

- **RT-safe hot path**: every hot-path operation is `noexcept`, allocation-free, and bounded; producers never block; faults are never silently swallowed.
- **Honest optionality**: components instrument unconditionally against a stateless API; what happens to the data is the application's choice.
- **One timeline**: the family `Clock`/`Timestamp` is the time base; `TraceId`/`SpanId` context propagates via `Inject`/`Extract` so a control glitch, a log line, and a planning stall align by construction.
- **Production forensics**: the stack is built so that the rare event — the crash, the once-a-day glitch — is the thing that gets kept and explained.

### Non-goals

- Not a ROS layer: nothing here depends on ROS; ROS glue is an app-side bridge.
- Not a dashboard product: exports feed existing viewers and toolchains rather than reinventing them.

## 3. The layering (ADR 0004)

The stack mirrors OpenTelemetry's API/SDK/exporter split, adapted for robotics:

| Tier | Home | What it is | Linked |
|------|------|------------|--------|
| **API** | **xmBase** `include/xmbase/telemetry/` | the 4 verbs (`event`/`metric`/`span`/`signal`) + health, context spine, pre-registered handles, the binding seam, and a dependency-free console binding | always |
| **SDK** | **xmTelemetry** (private) | the runtime machinery: RT-safe capture, crash-surviving flight recording, recording plane, insight tooling | optional |
| **Exporters / tools** | xmTelemetry | MCAP recordings for Foxglove/PlotJuggler, Perfetto and OTLP trace exports, post-mortem triage tooling, CI regression gates | opt-in |

Dependency rule: components (xmDriver, xmNavigation, …) instrument against the **API only**; only the application links the SDK. xmBase never depends on xmTelemetry.

**xmBase alone is a complete experience**: full-severity console logging through the built-in dependency-free binding, safe no-op handles for everything else, and a public, ABI-gated binding seam (`binding.hpp`) that any backend can implement. The API-tier design — the seam contract, the cost model, the RT-safe subset — is documented in [xmBase `docs/telemetry/design.md`](https://github.com/rxdu/xmBase/blob/main/docs/telemetry/design.md).

## 4. The xmTelemetry SDK

The SDK is a separate, privately maintained component for teams integrating XMotion into production systems. At the capability level, binding it turns the same instrumented call sites into:

- **A crash-surviving flight recorder** — the last seconds before a `SIGKILL` or panic are recoverable post-mortem, with metrics, spans, and the log tail intact, on an unmodified machine.
- **A recording plane** — MCAP recordings that open directly in Foxglove/PlotJuggler, with rotation, retention, storage-fault tolerance, and pre/post-trigger snapshot windows (EDR semantics).
- **Insight tooling** — live tailing of a running (or dead) process, one-command post-mortem triage reports that surface sporadic stalls and rare bugs with trace drill-downs, Perfetto/OTLP exports for interactive analysis, and machine-readable digests that gate CI on performance regressions.
- **RT discipline throughout** — wait-free capture, bounded memory, counted drops, verified under ASan/TSan/UBSan and enforced per-operation latency budgets.

Interested in production integration? Reach out via the repository owner.

## 5. Interoperability

- **Time**: the core uses the monotonic family clock; an app maps to ROS time (incl. sim `/clock`) at the boundary.
- **Correlation id carriage**: the library owns the id type; a ROS node reads/writes it in a message header field via `Inject`/`Extract`, a non-ROS component in its own envelope. `SetCurrentContext()` is the ingress hook.
- **Formats over pipelines**: recordings and exports are files in open formats (MCAP, Trace Event JSON, OTLP JSON) consumed by existing viewers — nothing on the robot grows a network dependency.

## 6. Summary

A stateless, ROS-free, RT-safe **API** in xmBase that every component calls unconditionally — with honest console logging built in — and an optional production **SDK** that turns the same call sites into a crash-consistent observability system. Components instrument against the API alone; applications choose the machinery.
