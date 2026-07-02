# Design: xMotion Telemetry Library (working name **xmTau · τ**)

- Status: Draft
- Date: 2026-07-02
- Owners: xMotion Engineering
- Rationale / evidence: [docs/research/otel-robotics-telemetry.typ](../research/otel-robotics-telemetry.typ) (the evaluation and strategy this document implements)
- Related: family ADRs `docs/adr/0001-component-architecture.md`

---

## 1. Purpose

This document specifies a single, thin, **ROS-free** instrumentation library that every layer of the robot software — from a 1 kHz control loop through planning to decision-making — uses identically to emit logs, metrics, causal spans, high-rate signals, and health. Heavy, battle-tested engines (LTTng, NanoLog/Quill, MCAP, OpenTelemetry) are adopted behind it as pluggable, off-by-default sinks. It is the concrete realization of the research report's strategy (report §10): *own a thin spine, adopt the engines; coherence from one spine, lightness from pluggable compile-time-selected sinks.*

This is not a new telemetry engine. It is the **axle** that binds adopted engines coherently to the xMotion HAL. We build only the surface, the spine, the capture boundary, and the routing; everything else is adopted.

## 2. Goals and non-goals

### Goals

- One instrumentation **surface** (≈4 verbs) usable identically in RT and non-RT code.
- **ROS-free** core: links into non-ROS control code and ROS 2 nodes alike.
- **Real-time safe** hot path: allocation-free, lock-free, bounded, and compile-out-able.
- **Lightweight core**: header-light, no heavy dependency in the foundation; heavy sinks isolated and optional.
- **Coherent**: one monotonic time base and one correlation identity across all layers, so a control glitch, a planning stall, and a decision flip line up on one timeline.
- **Backend-flexible**: sinks (MCAP, OTLP/OpenTelemetry, LTTng) selected at compile/link time without touching call sites.

### Non-goals

- Not a safety monitor. The safety plane (watchdog / e-stop / deadline enforcement) is independent and is out of scope (report §3, §4).
- Not a metrics/trace *engine* — we do not reimplement OTLP encoding, histogram aggregation, lockless buffering, or exporters.
- Not a fleet backend — Grafana/Tempo/Foxglove/OTel Collector are external.
- Not a ROS package — any ROS glue lives in an optional application-side bridge (report §10.5).

## 3. Scope: what we are building, where it lives

The library splits across two homes, following the family's downward-only dependency rule.

| Piece | Home | Dependency weight | Always built? |
|-------|------|-------------------|---------------|
| **Surface + spine + capture boundary** (the *axle*) | **Σ (xmSigma)** module `xmsigma/telemetry` | Header-light, `std` only | Yes |
| **Sinks + collectors** (the adopted *engines*) | **New component xmTau (τ)** | LTTng / MCAP / OpenTelemetry | No — optional, per-sink CMake option |
| **ROS bridge** (time/id/rosbag2/ros2_tracing glue) | **Application layer** (xmBot-\*) | ROS 2 | No — app choice |

Why Σ for the surface: every component depends on Σ, so the surface must live there to be callable everywhere, and it must therefore be dependency-light. Why a separate τ for sinks: the heavy engines must be isolatable and optional so a lean/embedded build (or the RT partition) never pays for them.

> Naming note: `xmTau (τ)` is a proposal consistent with the family's Greek-letter components (κ ζ Σ μ ∇ γ). The namespace for the surface is proposed as `xmotion::tm`. Both are open to change; nothing in this design depends on the names.

## 4. Architecture

Three planes (report §4), with this library owning the observability and recording data paths and staying out of the safety plane:

```
  app / ROS2 node        control loop (µs)      planning / decision
        │                      │                       │
        ▼                      ▼ (RT subset)            ▼
  ┌───────────────────────── SURFACE (xmotion::tm, in Σ) ─────────────────────┐
  │   event()   metric()   scope()   signal()      [+ health() convention]    │
  └───────────────┬───────────────────────────────────────────────┬──────────┘
                  │ POD record (no format, no alloc)               │
        ┌─────────▼─────────┐  wait-free ring (Σ)         handles (atomic)
        │   CAPTURE BOUNDARY │  ── drop policy, bounded ──┐
        └─────────┬─────────┘                            │
                  │ non-RT drain thread (Σ)              │
        ┌─────────▼──────────────── ROUTER (Σ) ──────────┴────────┐
        │  diagnostics → OTel sink        raw signal → MCAP sink   │
        └──────┬───────────────────────────────┬──────────────────┘
               ▼                                ▼
        ┌────────────┐  ┌────────────┐   ┌────────────┐   (sinks in τ, optional)
        │  OtelSink  │  │ LttngSink  │   │  McapSink  │
        │ →OTLP/Coll.│  │ (optional) │   │ →flight rec│
        └────────────┘  └────────────┘   └────────────┘
```

Dependency directions (must hold): `app → τ → Σ`; `app → ROS`; **never** `Σ → τ`, **never** `Σ/τ → ROS`. The RT hot path calls only the surface (in Σ) and never touches a sink.

## 5. The surface (public API sketch)

Illustrative C++17, namespace `xmotion::tm`. Signatures are indicative, not final.

### 5.1 Spine — time and identity

```cpp
namespace xmotion::tm {

using Clock     = std::chrono::steady_clock;   // monotonic; the one time base
using Timestamp = Clock::time_point;
Timestamp Now() noexcept;                       // cheap monotonic read

// W3C-shaped ids; the library owns the format, not the carrier (report §10.5)
struct TraceId { std::uint64_t hi, lo; };
struct SpanId  { std::uint64_t value; };
struct Context { TraceId trace; SpanId span; };

Context CurrentContext() noexcept;              // thread-local
void    SetCurrentContext(Context) noexcept;    // set by the message carrier at ingress

// Process/robot identity (OTel "resource"), set once at startup
void SetResource(std::string_view key, std::string_view value);
}
```

### 5.2 The four verbs

```cpp
namespace xmotion::tm {

// ---- 1. EVENT — discrete structured record ----------------------------------
enum class Severity { kTrace, kDebug, kInfo, kWarn, kError };
// RT-safe: message string is compile-time-extracted; only args are copied,
// formatting is deferred to the drain (NanoLog/Quill pattern).
#define XM_EVENT(sev, fmt, ...)   /* expands to an alloc-free record push */

// ---- 2. METRIC — pre-registered handles, atomic RT-safe updates -------------
class Counter   { public: void Add(double v = 1.0) noexcept; };
class Gauge     { public: void Set(double v) noexcept; };
class Histogram { public: void Record(double v) noexcept; };
Counter&   GetCounter  (std::string_view name);   // register once, hold the handle
Gauge&     GetGauge    (std::string_view name);
Histogram& GetHistogram(std::string_view name);

// ---- 3. SCOPE — causal timing span, RAII, links to CurrentContext -----------
class Scope {
 public:
  explicit Scope(std::string_view name) noexcept;  // begin
  ~Scope();                                         // end (records duration)
};
#define XM_SCOPE(name) ::xmotion::tm::Scope XM_UNIQUE(name)

// ---- 4. SIGNAL — high-rate typed sample → recording plane -------------------
template <typename T>
class SignalChannel { public: void Publish(const T& sample, Timestamp t = Now()) noexcept; };
template <typename T> SignalChannel<T>& GetChannel(std::string_view name);

// ---- HEALTH — convention over metric+event, NOT a 5th primitive -------------
enum class HealthState { kOk, kDegraded, kFault, kDisconnected };
void ReportHealth(std::string_view subsystem, HealthState s,
                  std::string_view detail = {}) noexcept;
}
```

### 5.3 RT-safe subset vs full surface

The *same* API serves both contexts; cost differs by *how* you call it, not by a different API:

- **RT hot path (control loop):** pre-register handles at init (`GetCounter`, `GetChannel`); on the hot path call only `counter.Add()`, `gauge.Set()`, `channel.Publish()`, `XM_EVENT` (deferred format), and `XM_SCOPE`. All are `noexcept`, allocation-free, and push a POD record into the wait-free ring.
- **Non-RT (planning/decision/app):** may additionally use string/lookup-by-name forms, richer attributes, and formatted events.

This is what "integrate everywhere" means concretely: one small vocabulary, two cost profiles.

## 6. The capture boundary (the differentiating design work)

The hot path never formats, serializes, allocates, blocks, or calls a sink. It writes a fixed-size POD **record** into a wait-free ring; a non-RT **drain** thread pops records and hands them to the router. This is the one place real design rigor is warranted (report §RT-line discussion).

- **Record**: a small POD (`{ kind, timestamp, context, name-id, payload-union }`). Strings are pre-interned to ids at registration; no string copies on the hot path.
- **Ring**: wait-free, bounded, single-producer-per-thread (SPSC) preferred, drained by one consumer. Start by evaluating an adopted lock-free ring (e.g. `rigtorp/SPSCQueue`, `folly::ProducerConsumerQueue`) before writing our own; adopt if it fits. For the flight recorder we may instead front the whole thing with **LTTng UST** (which *is* a wait-free ring + snapshot mode) — see §9.
- **Drop policy** (explicit, configurable): on ring-full, **drop-newest + increment a dropped-count metric**; the producer must never block. The drop counter is itself telemetry, so overload is observable.
- **Backpressure**: bounded by construction; the drain falling behind (e.g. during the incident) degrades to counted drops, never to a stalled control loop.
- **Time**: every record is stamped with monotonic `Now()` at push; hardware capture timestamps (where a device provides them) travel in the payload.

## 7. Sinks and routing

A `Sink` is the drain-side interface; sinks live in τ and are registered at startup. The router (in Σ) dispatches by record class.

```cpp
namespace xmotion::tm {
class Sink {
 public:
  virtual ~Sink() = default;
  virtual void Consume(const Record& r) = 0;  // called on the drain thread only
  virtual void Flush() {}
};
void RegisterSink(std::unique_ptr<Sink>);       // at startup, before RT begins
}
```

- **Routing**: *aggregatable diagnostics* (`event`/`metric`/`health`, and `scope` spans) → the OTel sink; *raw high-rate signals* (`signal`) → the MCAP sink. The router — not the call site — enforces this, so a 1 kHz raw stream never enters the metrics pipeline (report §6.2).
- **Sinks (in τ, each behind a CMake option):**
  - `OtelSink` — maps records to OpenTelemetry metrics/logs/spans, exports via OTLP (to a local OTel Collector sidecar).
  - `McapSink` — writes `signal` records + a rolling **flight recorder** buffer to MCAP; snapshot-to-disk on a trigger (fault/e-stop/anomaly). Neutral encoding so files open in Foxglove and the ROS ecosystem.
  - `LttngSink` (optional) — forwards to LTTng UST tracepoints for kernel-correlated, RT-grade tracing.
  - `NullSink` / `ConsoleSink` — built into Σ for zero-config and debug.
- **Compile-time selection**: disabled instrumentation compiles to nothing; a build links only the sink libraries it enables. Default build (Σ only) = surface + Null/Console sink, no external deps.

## 8. ROS-free / interoperability (per report §10.5)

The library depends on none of rclcpp/rmw/DDS/rosbag2/ros2_tracing/ament. Interop is achieved at three seams, all outside the library:

- **Time**: core uses monotonic `Clock`; an app maps to ROS time (incl. sim `/clock`) at the boundary.
- **Correlation id carrier**: the library owns the id type; a ROS node reads/writes it in a message header field, a non-ROS component in its DDS/shm envelope. `SetCurrentContext()` is the ingress hook.
- **Recording**: MCAP is a format, not rosbag2; a ROS-free producer yields ROS-/Foxglove-readable artifacts. Because LTTng underlies both this library and ros2_tracing, a ROS app can correlate both in one LTTng session.

## 9. Build, dependencies, and module layout

```
components/sigma/               (Σ — always built, light)
  include/xmsigma/telemetry/
    telemetry.hpp   # the 4 verbs — the ONE header app code includes
    time.hpp        # Clock, Timestamp, Now
    context.hpp     # TraceId/SpanId/Context, current-context hooks
    health.hpp      # HealthState, ReportHealth
    record.hpp      # POD Record type crossing the boundary
    ring.hpp        # wait-free ring (adopted impl or thin wrapper)
    sink.hpp        # Sink interface, RegisterSink, Router, drain
  src/telemetry/    # drain thread, router, NullSink/ConsoleSink
  test/telemetry/   # unit + RT-safety (ASan/TSan) + micro-benchmarks

components/tau/                 (τ — new component, optional sinks/collectors)
  otel_sink/    # -> OpenTelemetry SDK / OTLP     (option XMTAU_WITH_OTEL)
  mcap_sink/    # -> MCAP writer + flight recorder (option XMTAU_WITH_MCAP)
  lttng_sink/   # -> LTTng UST                     (option XMTAU_WITH_LTTNG)
  collectors/   # host CPU/PSI/GPU/thermal -> metrics
  test/

<app repos>/                    (ROS glue lives here, optional)
  ros_bridge/   # ROS time, header-id ingress, rosbag2/ros2_tracing export
```

Dependencies: Σ telemetry adds **zero** external deps (std only). τ sinks each pull their engine only when enabled. CMake options gate every heavy dependency; the default umbrella build stays light.

## 10. Phased implementation plan

Each phase is independently useful, buildable, and testable. Ship in order.

- **P0 — Surface + spine + boundary (Σ), Null/Console sink.** The 4 verbs, `Now`, context, health, the POD record, the ring + drain + router, and a Console/Null sink. Zero external deps. Outcome: code can be instrumented everywhere; output is console/no-op. *This is the MVP and the highest-leverage step.*
- **P1 — Wait-free ring hardening + benchmarks.** Adopt/validate the ring; ASan/TSan clean; a benchmark asserting the hot path is allocation-free and bounded (hooked allocator + p99 latency). Drop-policy tests.
- **P2 — McapSink + flight recorder (τ).** `signal` → MCAP; rolling buffer + snapshot-on-trigger. Verify files open in Foxglove.
- **P3 — OtelSink + Collector (τ).** diagnostics → OTLP → local OTel Collector → Grafana. Host-metrics semantic conventions.
- **P4 — Host collectors (τ).** PSI, per-core CPU, memory, thermal, GPU (NVML/tegrastats) → metrics.
- **P5 — LttngSink (optional) + app-side ROS bridge.** RT-grade tracing; ROS correlation.
- **Cross-cutting — μ adoption.** Migrate μ drivers to emit their existing signals (`FreshnessMonitor` age, tx-queue depth, fault counters, `DeviceHealth`) through the surface. Low effort, high value — μ already produces the data.

## 11. Testing and verification

- **Unit tests** per module (surface semantics, router, health, sinks with fakes).
- **RT-safety**: ASan + UBSan over the suite (the family already runs these in CI); TSan over the drain/producer paths; a benchmark test that fails if the hot path allocates or exceeds a latency bound.
- **Overflow/drop**: fill the ring under a stalled drain, assert bounded memory + counted drops + no producer block.
- **Round-trip**: event/metric/span/signal → sink → decodable output (MCAP opens in Foxglove; OTLP arrives at a test Collector).
- **No-op-when-off**: a build with all sinks disabled produces a binary with the instrumentation compiled out (verify symbol/size).

## 12. Risks and open questions

- **Ring choice**: adopt an existing SPSC/MPSC ring vs. front everything with LTTng UST from the start. *Decision deferred to P1; the surface hides it.*
- **MCAP encoding schema**: neutral (protobuf/flatbuffers/custom) for ROS-free interop vs. optional ros2msg channels via the app bridge.
- **Naming**: `xmTau`/`xmotion::tm` are proposals.
- **Attribute cardinality**: enforce a discipline (bounded attribute keys) so the OTel path stays healthy (report §6.2).
- **Σ/τ boundary precision**: the drain lives in Σ but dispatches to τ-provided sinks; confirm the registration lifetime (sinks registered before RT begins, unregistered after RT ends).

## 13. Summary

We build a small **axle**: a ROS-free, RT-safe, OTel-shaped instrumentation surface plus a spine and a wait-free capture boundary in Σ, with adopted engines (MCAP, OpenTelemetry, LTTng) as optional compile-time-selected sinks in a new τ component. Call sites are uniform across control, planning, and decision; the heavy machinery is isolated and optional; ROS is an application-layer consumer, never a dependency. Start at P0 (surface + spine + Null sink, zero deps) and add sinks incrementally.
