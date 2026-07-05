# Design: XMotion Telemetry Library (**xmTelemetry**)

- Status: Draft (rev. 2 — re-layered per ADR 0004)
- Date: 2026-07-03 (rev. 1: 2026-07-02)
- Owners: XMotion Engineering
- Rationale / evidence: [docs/research/otel-robotics-telemetry.typ](../research/otel-robotics-telemetry.typ) (the evaluation and strategy this document implements)
- Governing decisions: [ADR 0004](../adr/0004-telemetry-layering.md) (API/SDK/exporter layering — **supersedes rev. 1's spine-in-xmBase placement**); [ADR 0003](../adr/0003-naming-and-branding.md) (component is **xmTelemetry**, namespace `xmotion::telemetry`; the API lives in **xmBase**)
- Related: family ADRs `docs/adr/0001-component-architecture.md`

---

## 1. Purpose

This document specifies a single, thin, **ROS-free** instrumentation stack that every layer of the robot software — from a 1 kHz control loop through planning to decision-making — uses identically to emit logs, metrics, causal spans, high-rate signals, and health. Heavy, battle-tested engines (LTTng, MCAP, OpenTelemetry) are adopted behind it as pluggable, off-by-default exporters. It is the concrete realization of the research report's strategy (report §10): *own a thin spine, adopt the engines; coherence from one spine, lightness from pluggable compile-time-selected sinks.*

This is not a new telemetry engine. It is the **axle** that binds adopted engines coherently to the XMotion components. We build only the API, the capture machinery, and the routing; everything else is adopted.

## 2. Goals and non-goals

### Goals

- One instrumentation **API** (≈4 verbs) usable identically in RT and non-RT code.
- **ROS-free**: links into non-ROS control code and ROS 2 nodes alike.
- **Real-time safe** hot path: allocation-free, lock-free, bounded, and compile-out-able.
- **Honestly optional machinery**: the foundation carries only a stateless API; *all* runtime machinery (threads, buffers, aggregation) lives in the optional xmTelemetry component — the OpenTelemetry API/SDK relationship, applied here (ADR 0004).
- **Crash-consistent recording**: the last N seconds before a crash — the flight recorder's defining moment — must survive the process (report §7 "keep the rare event").
- **Coherent**: one monotonic time base and one correlation identity across all layers, so a control glitch, a planning stall, and a decision flip line up on one timeline.
- **Backend-flexible**: exporters (MCAP, OTLP/OpenTelemetry, LTTng) selected at compile/link time without touching call sites.

### Non-goals

- Not a safety monitor. The safety plane (watchdog / e-stop / deadline enforcement) is independent and out of scope (report §3, §4); telemetry never shares fate with the failsafe.
- Not a metrics/trace *engine* — we do not reimplement OTLP encoding, exporters, or backend protocols.
- Not a fleet backend — Grafana/Tempo/Foxglove/OTel Collector are external.
- Not a ROS package — any ROS glue lives in an optional application-side bridge (report §10.5).

## 3. Scope: three tiers, two homes (ADR 0004)

| Tier | Home | Contents | Dependency weight | Linked |
|------|------|----------|-------------------|--------|
| **API** | **xmBase** module `xmbase/telemetry` | the 4 verbs + health, handles, ids/context + inject/extract, monotonic clock, compile-out floor | std only; **no state, no threads** | always |
| **SDK** | **xmTelemetry** core | handle table, capture channels (ring), per-QoS-class buffers, drain thread, router, metric aggregation, Null/Console sinks, lifecycle | std only, light | optional |
| **Exporters** | **xmTelemetry**, one CMake option each | McapSink + flight recorder + `xmtelemetry-recover`, OtelSink → OTLP, LTTng channel, host collectors | heavy / external | opt-in each |
| **ROS bridge** | application layer (xmBot-\*) | ROS time mapping, header-id ingress, rosbag2/ros2_tracing glue | ROS 2 | app choice |

Why the API lives in xmBase: every component depends on the foundation, so the API must live there to be callable everywhere — and it must therefore be stateless and dependency-free. Why *everything else* lives in xmTelemetry: so "optional" is literally true — a lean/embedded or RT-partition build that links only xmBase pays for **nothing** (no thread, no buffer, no dependency), exactly as an OTel API-only library pays nothing until an application installs the SDK.

**Dependency rule (must hold):** components (xmDriver, xmNavigation, …) instrument against the **API only**. Only the application links the xmTelemetry SDK and selects exporters. `xmBase` never depends on `xmTelemetry`; neither ever depends on ROS.

## 4. Architecture

Three planes (report §4), with this stack owning the observability and recording data paths and staying out of the safety plane:

```
   xmDriver / xmNavigation / app code          control loop (µs, RT subset)
        │                                            │
        ▼                                            ▼
  ┌───────────── TIER 1: API (xmotion::telemetry, in xmBase) ─────────────────┐
  │  event()  metric()  scope()  signal()   [+ health() convention]           │
  │  handles · TraceId/Context · Now() · inject/extract · compile-out floor   │
  │  unbound default: event ≥ Warn → stderr; everything else → no-op          │
  └───────┬───────────────────────────────────────────────────────────────────┘
          │ bound ONCE at telemetry::Init() — install-time handle table;
          │ handles resolve at registration, never per call
  ┌───────▼──────── TIER 2: SDK (xmTelemetry core, optional) ─────────────────┐
  │  CHANNELS (wait-free ring):  heap │ mmap BLACK BOX (tmpfs) │ LTTng UST    │
  │  per-QoS-class rings (diagnostics ≠ signals) · drop-newest + counted      │
  │  metric aggregation (atomics, drain-sampled) · drain thread · ROUTER      │
  │  NullSink / ConsoleSink · Init()/Shutdown() lifecycle                     │
  └───────┬──────────────────────────────────────────┬────────────────────────┘
          │ diagnostics (event/metric/span)          │ raw signals
  ┌───────▼──────────┐  ┌────────────────┐  ┌────────▼─────────┐  TIER 3: exporters
  │ OtelSink → OTLP  │  │ LTTng channel  │  │ McapSink         │  (xmTelemetry,
  │ → Collector      │  │ (kernel corr.) │  │ flight recorder  │   one option each)
  │   (per-host)     │  └────────────────┘  │ + recover tool   │
  └──────────────────┘                      └──────────────────┘
```

Dependency directions: `app → xmTelemetry → xmBase`; `app → ROS`; **never** `xmBase → xmTelemetry`, **never** `xmBase/xmTelemetry → ROS`. The RT hot path calls only the API; with the SDK bound, a call is an atomic update or a wait-free ring push — never a sink, a lock, or an allocation.

## 5. The API (public surface sketch)

Illustrative C++17, namespace `xmotion::telemetry`. Signatures are indicative, not final.

### 5.1 Spine — time and identity

```cpp
namespace xmotion::telemetry {

using Clock     = std::chrono::steady_clock;   // monotonic; the one time base
using Timestamp = Clock::time_point;
Timestamp Now() noexcept;                       // cheap monotonic read

// W3C-shaped ids; the library owns the format, not the carrier (report §10.5)
struct TraceId { std::uint64_t hi, lo; };
struct SpanId  { std::uint64_t value; };
struct Context { TraceId trace; SpanId span; };

Context CurrentContext() noexcept;              // thread-local
void    SetCurrentContext(Context) noexcept;    // set by the message carrier at ingress
// envelope helpers: serialize/parse Context for message headers (any IPC)
std::array<std::uint8_t, 24> Inject(Context) noexcept;
Context Extract(const std::uint8_t* bytes, std::size_t len) noexcept;

// Process/robot identity (OTel "resource"), set once at startup
void SetResource(std::string_view key, std::string_view value);
}
```

### 5.2 The four verbs

```cpp
namespace xmotion::telemetry {

// ---- 1. EVENT — discrete structured record ----------------------------------
enum class Severity { kTrace, kDebug, kInfo, kWarn, kError };
// RT-safe: message string is compile-time-extracted; only args are copied,
// formatting is deferred to the drain (NanoLog/Quill pattern).
#define XM_EVENT(sev, fmt, ...)   /* alloc-free record push (stderr if unbound, sev>=Warn) */

// ---- 2. METRIC — pre-registered handles, atomic RT-safe updates -------------
// Handle types are API; their backing slots are SDK-allocated at registration
// (or a shared no-op slot when no SDK is bound). Aggregation state lives in the
// SDK and is sampled by the drain — no ring traffic per increment (ADR 0004 §6).
class Counter   { public: void Add(double v = 1.0) noexcept; };
class Gauge     { public: void Set(double v) noexcept; };
class Histogram { public: void Record(double v) noexcept; };
Counter&   GetCounter  (std::string_view name);   // register once, hold the handle
Gauge&     GetGauge    (std::string_view name);
Histogram& GetHistogram(std::string_view name);

// ---- 3. SCOPE — causal timing span, RAII, links to CurrentContext -----------
class Scope {
 public:
  explicit Scope(std::string_view name) noexcept;  // begin (record push)
  ~Scope();                                         // end (records duration)
};
#define XM_SCOPE(name) ::xmotion::telemetry::Scope XM_UNIQUE(name)

// ---- 4. SIGNAL — high-rate typed sample → recording plane -------------------
template <typename T>  // T: trivially copyable; schema registered at GetChannel
class SignalChannel { public: void Publish(const T& sample, Timestamp t = Now()) noexcept; };
template <typename T> SignalChannel<T>& GetChannel(std::string_view name);

// ---- HEALTH — convention over metric+event, NOT a 5th primitive -------------
enum class HealthState { kOk, kDegraded, kFault, kDisconnected };
void ReportHealth(std::string_view subsystem, HealthState s,
                  std::string_view detail = {}) noexcept;
}
```

### 5.3 Binding and lifecycle (SDK side, called by the application)

```cpp
namespace xmotion::telemetry {
struct SdkConfig {
  ChannelKind channel = ChannelKind::kHeap;   // kHeap | kBlackBox | kLttng
  std::string blackbox_path;                  // e.g. /dev/shm/xmtelemetry-<proc>.ring
  std::size_t diagnostics_ring_capacity = 8192;
  std::size_t signal_ring_capacity      = 65536;
  // ... sink registration, export cadence, metric sample period
};
void Init(SdkConfig);   // installs the handle table; BEFORE RT begins
void Shutdown();        // drain + flush + unbind; BEFORE static destruction
}
```

Binding is an **install-once handle table**: handles resolve to SDK-allocated slots at registration time, so the hot path has zero per-call indirection beyond a pointer fixed at init. No weak symbols, no per-call provider lookup (ADR 0004 §3). Registration after `Init()` but before RT is the contract; late registration is allowed but may allocate (non-RT only).

### 5.4 RT-safe subset vs full surface; no-SDK behavior

The *same* API serves both contexts; cost differs by *how* you call it:

- **RT hot path (control loop):** pre-register handles at init; on the hot path call only `counter.Add()`, `gauge.Set()`, `channel.Publish()`, `XM_EVENT` (deferred format), and `XM_SCOPE`. All `noexcept`, allocation-free: atomic updates or wait-free ring pushes.
- **Non-RT (planning/decision/app):** may additionally use lookup-by-name forms, richer attributes, formatted events.
- **No SDK bound (xmBase-only build):** `event()` at Warn+ writes synchronously to stderr — a lib-only build never silently swallows a fault (today's `XLOG` behavior preserved); `metric`/`scope`/`signal` are no-ops. The compile-time floor (`XM_TELEMETRY_LEVEL`) additionally strips below-floor call sites entirely.

## 6. The capture machinery (SDK; the differentiating design work)

The hot path never formats, serializes, allocates, blocks, or calls a sink. It writes a fixed-size POD **record** into a wait-free ring **channel**; a non-RT **drain** thread pops records and hands them to the router.

- **Record**: a small POD (`{ kind, timestamp, context, name-id, payload-union }`). Strings are pre-interned to ids at registration; no string copies on the hot path.
- **Ring**: the proven bounded Vyukov MPSC ring already in the family (xmBase's `MpscRtLogger`: wait-free producers, no heap, no syscall, TSan-verified in CI), **migrated into the SDK** and generalized from spdlog records to telemetry records. *This closes rev. 1's open question — we adopt our own proven ring, no third-party ring dependency.*
- **QoS class separation**: diagnostics (event/metric snapshots/spans) and high-rate signals use **separate rings**, so a 1 kHz signal flood can never evict an Error event (ADR 0004 §5).
- **Drop policy** (explicit, per class): on ring-full, **drop-newest + increment a dropped-count metric**; the producer never blocks. The drop counter is itself telemetry, so overload is observable.
- **Channels** (the ring's backing store, selected at `Init`):
  - **heap** — default, portable;
  - **mmap black box** — the same ring backed by a file-backed mmap on tmpfs with a versioned header (magic, schema hash, boot-id, monotonic→realtime offset captured at init). The buffer **survives process death**: after a crash, the `xmtelemetry-recover` CLI reads the mapping and emits the last N seconds as MCAP. This is LTTng's crash-recovery design (`lttng-crash`) without adopting its daemon (ADR 0004 §4). Survives a process crash, not power loss — persistence across power events is the flight-recorder snapshot's job;
  - **LTTng UST** — opt-in, for kernel-correlated tracing where a session daemon is acceptable.
- **Metrics bypass the ring**: `Add`/`Set`/`Record` are relaxed atomic updates on SDK-owned aggregation state (counters, gauges, fixed-boundary histogram buckets); the drain *samples* aggregates periodically into snapshot records for export. One atomic per metric beats a record per increment on both cost and memory bounds.
- **Time**: every record is stamped with monotonic `Now()` at push; hardware capture timestamps (where a device provides them) travel in the payload.

## 7. Router, sinks, and exporters

A `Sink` is the drain-side interface; the router dispatches by record class. Null/Console sinks ship in the SDK core (zero-config debug output); heavy exporters live behind per-sink CMake options.

```cpp
namespace xmotion::telemetry {
class Sink {
 public:
  virtual ~Sink() = default;
  virtual void Consume(const Record& r) = 0;  // called on the drain thread only
  virtual void Flush() {}
};
void RegisterSink(std::unique_ptr<Sink>);       // via SdkConfig / before RT begins
}
```

- **Routing**: *aggregatable diagnostics* (`event`/`metric`/`health`, `scope` spans) → the OTel sink; *raw high-rate signals* (`signal`) → the MCAP sink. The router — not the call site — enforces this, so a 1 kHz raw stream never enters the metrics pipeline (report §6.2).
- **Exporters** (each behind a CMake option):
  - `OtelSink` — maps records to OpenTelemetry metrics/logs/spans, exports via OTLP to a **per-host OTel Collector** (one exporter per robot, not per process — the Collector is the multi-process aggregation point and the store-and-forward buffer for intermittent connectivity).
  - `McapSink` — writes `signal` records + a rolling **flight recorder** buffer to MCAP; snapshot-to-disk on a trigger (fault/e-stop/anomaly). Neutral encoding so files open in Foxglove and the ROS ecosystem.
  - LTTng — surfaced as a *channel* (§6), not a drain-side sink, so its own wait-free capture is not double-buffered behind ours.
- **Compile-time selection**: disabled instrumentation compiles to nothing; a build links only the sink libraries it enables. Default application build = SDK + Null/Console sink, no external deps; library-only build = API, nothing else.

## 8. ROS-free / interoperability (per report §10.5)

The stack depends on none of rclcpp/rmw/DDS/rosbag2/ros2_tracing/ament. Interop is achieved at three seams, all outside the library:

- **Time**: core uses monotonic `Clock`; an app maps to ROS time (incl. sim `/clock`) at the boundary. The black-box header records the monotonic→realtime offset once for offline alignment.
- **Correlation id carrier**: the library owns the id type; a ROS node reads/writes it in a message header field via `Inject`/`Extract`, a non-ROS component in its DDS/shm envelope. `SetCurrentContext()` is the ingress hook.
- **Recording**: MCAP is a format, not rosbag2; a ROS-free producer yields ROS-/Foxglove-readable artifacts. Because LTTng can underlie both this stack and ros2_tracing, a ROS app can correlate both in one LTTng session.

## 9. Build, dependencies, and module layout

```
components/base/                (xmBase — always built; API ONLY, stateless)
  include/xmbase/telemetry/
    telemetry.hpp   # the 4 verbs — the ONE header component code includes
    time.hpp        # Clock, Timestamp, Now
    context.hpp     # TraceId/SpanId/Context, current-context, Inject/Extract
    health.hpp      # HealthState, ReportHealth
    handles.hpp     # Counter/Gauge/Histogram/SignalChannel handle types
    binding.hpp     # the install-once handle-table seam (filled by the SDK)
  src/telemetry/    # tiny: stderr default binding for unbound event()
  # NOTE: xmbase/logging/ dissolves into this API — XLOG_*/XLOG_RT_* become
  # facades over event(); the MpscRtLogger ring migrates to the SDK; spdlog
  # leaves the foundation (ADR 0004 §7).

components/telemetry/           (xmTelemetry — optional; SDK core + exporters)
  sdk/            # handle table, channels (heap | blackbox | lttng), rings,
                  # drain, router, metric aggregation, Null/Console sinks,
                  # Init/Shutdown
  blackbox/       # mmap channel format + xmtelemetry-recover CLI  (in core)
  otel_sink/      # -> OpenTelemetry SDK / OTLP     (option XMTELEMETRY_WITH_OTEL)
  mcap_sink/      # -> MCAP writer + flight recorder (option XMTELEMETRY_WITH_MCAP)
  lttng_channel/  # -> LTTng UST                     (option XMTELEMETRY_WITH_LTTNG)
  collectors/     # host CPU/PSI/GPU/thermal -> metrics (option XMTELEMETRY_WITH_HOST)
  test/

<app repos>/                    (ROS glue lives here, optional)
  ros_bridge/     # ROS time, header-id ingress, rosbag2/ros2_tracing export
```

Dependencies: the xmBase API adds **zero** external deps (std only) and no compiled machinery beyond the stderr fallback. The xmTelemetry SDK core is std-only. Exporters each pull their engine only when enabled. The default umbrella build stays light.

## 10. Implementation status

The design above is implemented and production-tested: the API tier lives in xmBase (`include/xmbase/telemetry/`, XLOG unified onto `event()`), and xmTelemetry carries the SDK (heap + mmap black-box channels on the migrated Vyukov ring), the recording plane (MCAP with rotation/retention/fault tolerance and trigger snapshots), and the insight tools (`xmtelemetry-tail`/`-recover`/`-diff`/`-report`, Perfetto and OTLP-JSON exports). The executable acceptance spec is the scenario suite in [xmTelemetry `docs/scenarios.md`](https://github.com/rxdu/xmTelemetry/blob/main/docs/scenarios.md) (S1–S12 live; S13 deferred). Remaining work — component adoption, re-pins, the deferred live-OTLP plane — is tracked in the umbrella [`TODO.md`](../../TODO.md), not here; each component's internal tasks live in its own `TODO.md`.

## 11. Testing and verification

- **Unit tests** per module (API semantics, binding/no-op behavior, router, health, sinks with fakes).
- **RT-safety**: ASan + UBSan over the suite; TSan over the drain/producer paths; a benchmark test that fails if the hot path allocates or exceeds a latency bound.
- **Overflow/drop**: fill each ring class under a stalled drain; assert bounded memory, counted drops, no producer block, and that a signal flood drops **zero** diagnostics records.
- **Crash consistency**: `SIGKILL` a producer mid-stream; `xmtelemetry-recover` must yield the expected tail; corrupted/partial header must fail safely.
- **Layering**: an API-only link test (no SDK — must link, run, and stderr-report a Warn); a symbol/size check that a build with instrumentation compiled out contains none of it.
- **Round-trip**: event/metric/span/signal → sink → decodable output (MCAP opens in Foxglove; OTLP arrives at a test Collector).

## 12. Risks and open questions

- **Signal channels and typed payloads**: `SignalChannel<T>` still lacks a POD-schema registration story (name + field layout) — MCAP currently records signal payloads as size + base64, not self-describing. Decide an encoding when a consumer needs field-level decoding.
- **Attribute cardinality**: enforce a discipline (bounded attribute keys) so the OTel path stays healthy (report §6.2) — becomes load-bearing with the deferred live-OTLP plane (S13).
- **Host daemon**: a per-host telemetry agent (shm protocol) was considered and deferred (ADR 0004); revisit if per-process export duplication becomes a measured cost.
- ~~Ring choice~~ — **closed** (ADR 0004): adopted the family's proven Vyukov ring from `MpscRtLogger`.
- ~~Black-box format stability~~ — **closed**: the genesis header is ABI-gated (`kBindingAbiVersion`); the recover tool and live followers reject mismatched layouts.
- ~~ConsoleSink backend~~ — **closed**: the SDK console sink is a dependency-free formatter; spdlog remains only in xmBase's interim binding, retired with the component migrations (see `TODO.md`).

## 13. Summary

We build a small **axle** in three tiers that mirror OpenTelemetry's layering (ADR 0004): a stateless, ROS-free, RT-safe **API** in xmBase that every component can call unconditionally; an optional **SDK** in xmTelemetry holding all machinery — the proven wait-free ring (migrated from xmBase's RT logger) behind a channel abstraction whose mmap **black box** makes the flight recorder crash-consistent; and per-option **exporters** (MCAP, OTLP→Collector, LTTng) that adopt the heavy engines. Logging is not a separate system: `XLOG_*` becomes the `event()` verb of the same spine, so every log line, metric, span, and signal shares one clock and one correlation identity. Components instrument against the API alone; applications choose the machinery.
