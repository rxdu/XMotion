#import "template/techreport.typ": techreport, appendix

#show: techreport.with(
  title: "Observability for Robots",
  subtitle: "An Evaluation of OpenTelemetry for Real-Time and Safety-Critical Robotic Systems",
  org: "xMotion Family",
  running-head: "Observability for Robots",
  report-number: "XM-TR-2026-01",
  version: "1.0",
  status: "Draft for review",
  authors: (
    (name: "xMotion Engineering", email: "engineering@xmotion", affiliation: "xMotion Family"),
  ),
  abstract: [
    Cloud-native observability has converged on OpenTelemetry (OTel) as a
    vendor-neutral standard for traces, metrics, and logs. Robotics teams,
    seeking better tools for post-incident reconstruction and issue
    localization, are tempted to adopt it wholesale. This report evaluates how
    much of OpenTelemetry actually transfers to a robotic system, from the joint
    perspective of a cloud-native and a hard-real-time/safety-critical engineer.
    We argue that the recurring confusion stems from treating "observability" as
    a single concern. We decompose a robot's telemetry needs into *three planes*
    --- a *safety plane*, a *recording plane*, and an *observability plane* ---
    and show that OpenTelemetry cleanly owns only the last. We provide a
    component-by-component evaluation, a quantitative analysis of the timescale,
    loss-tolerance, and causality mismatches between cloud and robotic workloads,
    and five case studies drawn from published measurements (Dapper, ros2_tracing/LTTng,
    PREEMPT_RT, ROS 2/DDS communications, and Pressure Stall Information). We
    conclude that OpenTelemetry is a strong *adopt* for the observability plane
    and its transport ($approx$40% of the problem), a *borrow-and-adapt* for
    dataflow tracing and health metrics ($approx$30%), and irrelevant-to-harmful
    for the real-time hot path and the safety monitor ($approx$30%). We enumerate
    the gaps a robotics stack must fill --- real-time-safe capture, a hardware
    time model, lossless anomaly recording, and dataflow-native causality. A
    prior-art survey then shows these gaps are met by mature, framework-agnostic
    building blocks (LTTng, NanoLog/Quill, MCAP, OpenTelemetry), so the design
    task is not to build an engine but to bind them coherently. We propose a
    lightweight strategy --- one thin, OTel-shaped instrumentation surface plus a
    common spine, with the engines as pluggable, compile-time-selected sinks ---
    and map it onto the xMotion component family.
  ],
  keywords: ("observability", "OpenTelemetry", "real-time systems", "robotics", "safety-critical", "telemetry", "flight recorder"),
  date: "July 2, 2026",
)

= Introduction

Robotic systems deployed in the field fail in ways that are hard to reproduce on
the bench: a control loop that misses a deadline once every few hours, a sensor
that goes stale for 40 ms during a thermal transient, a planner starved of CPU
while a log rotation flushes to a slow SD card. Diagnosing these requires
*observability* --- the ability to reconstruct what the system was doing, across
software and hardware, at the moment of failure. The cloud-native community has
invested a decade building exactly this capability and has standardized it around
OpenTelemetry (OTel), now one of the most active projects in the Cloud Native
Computing Foundation @otelspec.

It is therefore natural for a robotics team to ask: _should we adopt
OpenTelemetry?_ The answer that circulates informally --- "yes, it does
structured logs, metrics, and traces" --- is incomplete and, applied naively,
dangerous. OpenTelemetry was designed against a set of assumptions (millisecond
request latencies, abundant and droppable traffic, remote-procedure-call
causality, always-on connectivity) that hold in a data center and fail on a
robot. Conversely, a reflexive "no, robots are different" discards a genuine gift
from the cloud-native community: a mature, vendor-neutral transport and a rich
backend ecosystem that robotics has never had.

== Contributions

This report makes the disagreement precise. Specifically, we:

+ Decompose robot telemetry into a *three-plane model* (§4) that predicts which
  OpenTelemetry components fit and which do not.
+ Provide a *component-by-component evaluation* with an adopt/adapt/skip verdict
  and rationale for each of OpenTelemetry's parts (§5).
+ Quantify the *timescale, loss-tolerance, and causality mismatches* between
  cloud and robotic workloads using published rates and measurements (§6).
+ Ground the argument in *five case studies* from the literature (§7).
+ Enumerate the *gaps* a robotics stack must fill beyond OpenTelemetry (§8) and
  map a concrete architecture onto the xMotion component family (§9).

== Scope and non-goals

We consider host-side telemetry for a mobile robot: a multi-core Linux compute
node (possibly with a GPU), one or more real-time control loops, a set of
device drivers, and intermittent connectivity to a fleet backend. We treat the
microcontroller/firmware tier only where it bears on safety independence. We do
not evaluate specific commercial backends, and we do not benchmark the xMotion
stack itself --- our quantitative claims are drawn from published,
reproducible measurements and are used to establish *order-of-magnitude*
arguments, not point estimates (see §10, Threats to Validity).

= Background: What OpenTelemetry Is

"OpenTelemetry" names three separable things, and conflating them is the source
of most confusion.

/ Specifications: a data model for three *signals* --- *traces* (causally linked
  spans), *metrics* (counters, gauges, histograms with attributes), and *logs*
  (structured records) --- plus *semantic conventions* that fix attribute names
  (e.g. `system.cpu.utilization`, `system.memory.usage`) @otelhostmetrics, and a
  *context propagation* mechanism (W3C Trace Context @w3ctracecontext) for
  carrying trace identity across service boundaries.

/ Wire protocol: the OpenTelemetry Protocol (OTLP) @otlp, a push-based,
  Protobuf-over-gRPC-or-HTTP encoding, with a high-throughput Arrow variant.

/ Implementation: language SDKs split into a lightweight *API* (no-op unless an
  SDK is installed) and a heavier *SDK* (aggregation, batching, exporters); the
  vendor-neutral *Collector* (a standalone process with receivers, processors,
  and exporters); and the backend ecosystem (Prometheus-compatible stores,
  Tempo/Jaeger, Grafana).

Three architectural properties matter for our evaluation. First, the *API/SDK
split* means a library can instrument against a cheap API and let the
application choose the heavy SDK and exporter. Second, the *Collector* can run as
a sidecar that buffers and forwards, decoupling the workload from backend
availability. Third, the model is fundamentally *sampling-oriented*: it assumes
data volume so high that keeping all of it is neither necessary nor affordable
--- an assumption inherited directly from its intellectual ancestor, Google's
Dapper @sigelman2010dapper.

= Background: Real-Time and Safety-Critical Constraints

Robotic control operates under constraints that observability tooling must
respect rather than violate.

/ Determinism: a torque or current loop runs at 1--10 kHz, i.e. a 100 µs--1 ms
  period, with a jitter budget in the low microseconds. On mainline Linux,
  scheduling latency can spike into the milliseconds; PREEMPT_RT reduces
  worst-case latency to the tens of microseconds on tuned hardware
  @reghenzani2019preemptrt @osadl. Any instrumentation on this path must be
  lock-free, allocation-free, and bounded --- properties the OTel SDK does not
  provide.

/ Safety independence: functional-safety standards (ISO 26262 @iso26262,
  IEC 61508 @iec61508, DO-178C @do178c) require that a monitor detecting a
  hazardous condition be *independent* of the function it monitors, often on a
  separate execution partition (ARINC 653 @arinc653) or a separate processor with
  a hardware watchdog (AUTOSAR Watchdog Manager @autosarwdgm). A diagnostic
  pipeline that can itself fail, block, or consume unbounded resources cannot be
  load-bearing for safety.

/ Dataflow causality: a robot's "unit of work" is not a request but a *pipeline*
  --- sensor $arrow.r$ perception $arrow.r$ planning $arrow.r$ control --- often
  realized over shared memory or a publish/subscribe middleware such as DDS
  @ddsspec, pipelined and many-to-many, with no clean request boundary to anchor
  a trace.

/ Connectivity: robots are mobile and frequently disconnected. A pull-based,
  always-reachable monitoring model does not apply; telemetry must be captured
  locally and shipped opportunistically.

= An Analytical Framework: The Three-Plane Model

The central claim of this report is that "robot observability" is not one concern
but three, distinguished by their loss tolerance, latency budget, and consumer
(#ref(<tab:planes>)).

#figure(
  caption: [The three telemetry planes of a robotic system. OpenTelemetry is a
    native fit only for the observability plane.],
  table(
    columns: (auto, auto, auto, auto),
    align: (left, left, left, left),
    table.header([*Plane*], [*Loss tolerance*], [*Latency / rate*], [*Primary consumer*]),
    [Safety], [zero --- must never miss a hazard], [hard real-time (µs)], [the robot itself (failsafe)],
    [Recording], [zero around incidents --- lossless], [high-rate raw (10 Hz--10 kHz)], [engineer, post-incident],
    [Observability], [tolerant --- sampling/aggregation OK], [seconds, aggregated], [fleet operator, dashboards],
  )
) <tab:planes>

/ Safety plane: an independent health/watchdog channel that can trip a failsafe.
  It must be deterministic and verifiable and must not share the fate of what it
  monitors. *OpenTelemetry has no place here.*

/ Recording plane: a lossless, high-rate, on-robot capture of raw signals and
  events for incident reconstruction --- the software analogue of an aircraft
  flight recorder. Its defining requirement (keep everything around the rare
  event) is the *opposite* of sampling. *OpenTelemetry is the wrong tool; the
  robotics-native format is MCAP/rosbag2 @mcap.*

/ Observability plane: aggregated, non-real-time, fleet-wide health, metrics, and
  cross-component correlation. Loss-tolerant, dashboard-facing. *OpenTelemetry
  owns this plane.*

The model's predictive power is that every subsequent verdict follows from asking
"which plane?" A component that assumes loss tolerance is fine on the
observability plane and disqualifying on the safety plane; a format optimized for
aggregation is right for observability and destructive for recording.

= Component-by-Component Evaluation

#ref(<tab:scorecard>) gives the verdict for each OpenTelemetry component; the
rationale is developed below and quantified in §6--7.

#figure(
  caption: [Adopt / adapt / skip verdicts for OpenTelemetry components in a
    robotics context.],
  table(
    columns: (auto, auto, 1fr),
    align: (left, center, left),
    table.header([*Component*], [*Verdict*], [*Rationale*]),
    [OTLP wire protocol], [Adopt], [Vendor-neutral and *push*-based; better than pull scraping for mobile/intermittent robots @otlp.],
    [Collector (sidecar)], [Adopt], [On-robot store-and-forward, batching, routing; runs as a separate process (fault isolation).],
    [Metrics data model], [Adopt#super[\*]], [Ideal for *aggregated health/SLO*; \*not for high-rate raw signals (§6.2).],
    [Semantic conventions (`system.*`, `hw.*`)], [Adopt], [Free, portable dashboards for host/OS/accelerator telemetry @otelhostmetrics.],
    [Resource model], [Adopt], [Fleet identity (robot id, version) for cross-robot queries.],
    [Backend ecosystem], [Adopt], [Off-robot analysis; no reason to rebuild.],
    [Traces / spans], [Adapt], [Keep causal correlation; export sampled/anomaly-triggered, never per control cycle (§6, §7.1).],
    [Context propagation], [Adapt], [Keep trace-id correlation; change the carrier from HTTP headers to messages (§8).],
    [Logs signal], [Bridge], [Least mature OTel signal; forward existing structured logs rather than migrate the hot path.],
    [SDK on the hot path], [Skip], [Not lock-free/allocation-free/bounded (§3, §6.3).],
    [Head-based sampling], [Skip], [Inverts the robotics requirement to keep the rare event (§7.1).],
    [Pull scraping as transport], [Skip], [Assumes reachability; robots are mobile/air-gapped.],
    [RPC auto-instrumentation, service mesh], [Skip], [No on-robot analogue.],
  )
) <tab:scorecard>

= Quantitative Analysis of the Mismatch

== Timescale: four to six orders of magnitude

The single most important number is the ratio between how fast a robot's inner
loop runs and how slowly cloud observability samples. #ref(<tab:timescales>)
collects representative rates.

#figure(
  caption: [Representative operating rates. The robotic control path runs
    $10^4$--$10^6 times$ faster than the default OpenTelemetry metric export
    interval.],
  table(
    columns: (1fr, auto),
    align: (left, right),
    table.header([*Activity*], [*Period / interval*]),
    [Current/torque control loop], [0.1--1 ms (1--10 kHz)],
    [IMU sample], [1--10 ms (100--1000 Hz)],
    [LiDAR scan], [50--100 ms (10--20 Hz)],
    [Camera frame], [16--33 ms (30--60 Hz)],
    [Typical cloud request (Dapper domain @sigelman2010dapper)], [1--1000 ms],
    [Prometheus default scrape interval @prometheusnaming], [15 s],
    [OTel metric export interval (SDK default)], [60 s],
  )
) <tab:timescales>

A metrics pipeline sampling at $1/60$ Hz cannot observe a 1 kHz control loop; it
can only observe *aggregates* of it. This is not a tuning problem --- pushing the
scrape interval to 1 kHz would multiply cardinality by the time series count and
overwhelm any Prometheus-class store @prometheusnaming. The correct inference is
architectural: *aggregated health* and *high-rate raw signal* are different data
products with different pipelines (§6.2).

== Cardinality and aggregation destroy forensic value

OpenTelemetry metrics inherit Prometheus's cardinality discipline: each unique
combination of attribute values is a distinct time series, and best practice is
to keep cardinality bounded @prometheusnaming. Robotics telemetry is natively
high-cardinality (per-joint, per-sensor, per-cycle) and high-rate. Forcing it
through the metrics model requires aggregation (histograms, rates), which is
*lossy by construction*: a p99 latency histogram cannot tell you *which* cycle
overran or *what the IMU read* at that instant --- precisely the facts needed for
reconstruction. Hence the recording plane must preserve raw, timestamped samples
(MCAP @mcap), and the metrics plane must carry only their aggregates.

== Overhead and determinism

Instrumentation cost separates the planes. A kernel-level tracepoint via LTTng
imposes overhead on the order of tens to a few hundred nanoseconds per event and
is explicitly engineered to be usable in production and real-time contexts
@desnoyers2006lttng; ros2_tracing builds on it and reports overhead low enough
for real-time ROS 2 systems, adding only a small percentage to message latency
@bedard2022ros2tracing. By contrast, an OpenTelemetry SDK span or measurement
allocates on the heap, takes locks in the processor/exporter path, and batches
for network export @otelspec --- an architecture appropriate for millisecond
requests but not for a microsecond jitter budget. The design conclusion is not
"OTel is slow" but "OTel belongs on the non-real-time side of a lock-free
boundary": the hot path writes to a wait-free ring; a non-real-time thread drains
it into the SDK.

= Case Studies

== Dapper: sampling is a feature of scale, not of correctness (cloud)

Google's Dapper, the origin of modern distributed tracing and a direct ancestor
of OpenTelemetry, sampled aggressively --- retaining a small fraction of traces
(on the order of $1/1000$ for high-volume services) --- and still delivered its
diagnostic value @sigelman2010dapper. This works because in a data center the
*population* of events is enormous and statistically homogeneous: a
representative sample characterizes the whole. On a robot the diagnostically
important events are *rare and non-representative* (the one overrun, the one
dropped frame). Sampling optimizes for the common case; robotics reconstruction
optimizes for the tail. This is the crispest statement of why the cloud
sampling model must be *inverted* on the robot: record everything locally,
*upload* a sample or a trigger.

== ros2_tracing / LTTng: real-time tracing is possible, but it is not OTel (robotics)

The ros2_tracing framework demonstrates that low-overhead, real-time-safe tracing
of a robotic middleware is achievable --- by using static instrumentation points
and a kernel-grade tracer (LTTng) rather than a general-purpose SDK
@bedard2022ros2tracing @desnoyers2006lttng. It is the existence proof for the
recommended architecture: the on-robot causal/latency signal is captured by an
RT-safe tracer, and OpenTelemetry, if used at all, consumes the *result*
off-line. It also shows that the robotics community already has purpose-built
tooling for the recording plane that OTel does not replace.

== PREEMPT_RT and OSADL latency plots: the hiccup budget is microseconds (real-time)

Surveys and continuous measurement of PREEMPT_RT show worst-case scheduling
latencies in the tens of microseconds on tuned hardware, versus millisecond-scale
spikes on unconfigured mainline kernels @reghenzani2019preemptrt @osadl. This
quantifies the determinism plane's budget and explains why instrumentation
overhead and, critically, *page faults* (a major fault can cost milliseconds)
must be engineered out of the control path (e.g. via `mlockall`, CPU isolation).
An observability agent that can induce a page fault or a lock on the RT thread is
not a diagnostic aid but a new fault source.

== ROS 2 / DDS communications: dataflow latency is real and jitter-sensitive (robotics)

Independent evaluations of ROS 2 over DDS report end-to-end message latencies
ranging from tens of microseconds to milliseconds depending on QoS, transport,
and payload, with jitter that matters for control @maruyama2016ros2
@gutierrez2018ros2realtime. Two implications follow. First, the causality a robot
engineer needs is *dataflow provenance* across these pub/sub hops, not an RPC
call tree --- so trace identity must ride in the message envelope, and DDS's own
QoS (`deadline`, `liveliness`) is a native liveness signal to harvest
@ddsspec. Second, systems like Autoware run this stack on embedded compute
@kato2018autoware, where the heavy OTLP/gRPC exporter's footprint is a real
constraint, reinforcing the API-in-core / SDK-in-sidecar split.

== Pressure Stall Information: the cloud-native community built the right hiccup detector (transferable)

Linux PSI, contributed from hyperscale operations, exposes per-resource stall
time for CPU, memory, and I/O --- a direct, low-overhead measure of "is something
being starved" @psi. It is a canonical example of a cloud-native artifact that
transfers *directly* to robotics: the same signal that detects a noisy-neighbour
container also detects a planner starved by a log flush. Together with eBPF-based
introspection @gregg2019bpf, PSI is exactly the kind of host-telemetry the
observability plane should collect and export via OTLP.

= Gap Analysis: What Robotics Must Add

OpenTelemetry supplies the observability plane; the following are the pieces a
robotics stack must build or borrow elsewhere for the whole to be valuable.

+ *Real-time-safe front-end.* A wait-free capture ring on the hot path, drained
  off-RT into the SDK. OTel has no hard-real-time story; this is legitimately the
  robot's to own.
+ *A hardware time model.* Monotonic clocks for intervals, *hardware capture
  timestamps* (sample time $eq.not$ ingestion time --- the distinction that
  governs sensor fusion), and PTP/gPTP cross-device synchronization. OTel
  attributes can *carry* these but do not define them.
+ *Lossless flight recorder.* An always-on bounded ring snapshotted pre/post
  trigger on any anomaly, fault, or e-stop --- the inverse of sampling, stored in
  MCAP @mcap, not the metrics pipeline.
+ *A high-rate signal store distinct from metrics* (§6.2).
+ *Dataflow-native context propagation.* Correlation identity attached to
  messages/frames across DDS/ROS/shared memory (§7.4), not HTTP headers.
+ *Robotics semantic conventions.* `robot.joint.*`, `sensor.*`, `battery.*`,
  `motor.*`, `safety.state`, `frame_id` --- with prior art in ROS 2 diagnostics
  @ros2diagnostics and a candidate for upstreaming to OTel's convention process.
+ *Health aggregation with hysteresis*, fusing per-device health and host
  resources into a roll-up tree (semantics from `diagnostic_aggregator`
  @ros2diagnostics), exported as OTel metrics.
+ *Boot/lifecycle and offline-first capture*, retained locally and shipped
  opportunistically via the Collector's persistent queue.
+ *Strict observability/safety separation* (§3): the safety monitor remains
  independent of OTel.

= Related Work: Existing Building Blocks

Before designing anything, we surveyed whether the real-time capture layer that
§8 identifies as differentiating already exists as adoptable software. It does,
and at high maturity (#ref(<tab:related>)). The wait-free ring with
flight-recorder snapshot --- which one might assume is bespoke --- is precisely
LTTng's documented design @desnoyers2006lttng and ROS 2's rosbag2 snapshot mode
@rosbag2snapshot; the deferred-format hot-path logging that the "capture raw,
decode off-line" pattern (§6.3) describes is shipped by NanoLog @nanolog and Quill
@quill at nanosecond scale.

#figure(
  caption: [Adoptable building blocks per layer. The real-time-capture primitives
    are mature and framework-agnostic; most turnkey robotics observability is
    coupled to ROS 2.],
  table(
    columns: (auto, auto, auto, auto),
    align: (left, left, center, center),
    table.header([*Layer*], [*Solution*], [*ROS-coupled?*], [*Verdict*]),
    [Wait-free ring + flight recorder], [LTTng UST, snapshot mode @desnoyers2006lttng], [No], [Adopt],
    [RT logging (deferred format)], [NanoLog @nanolog, Quill @quill], [No], [Adopt],
    [RT tracing for robotics], [ros2_tracing @bedard2022ros2tracing, ros2probe @ros2probe], [Yes], [Adopt if ROS],
    [Recording format], [MCAP @mcap], [No], [Adopt],
    [Snapshot-to-disk on trigger], [rosbag2 snapshot @rosbag2snapshot], [Yes], [Pattern to mirror],
    [Zero-copy RT transport], [Eclipse iceoryx @iceoryx], [No], [Adopt if needed],
    [Fleet export + backends], [OpenTelemetry @otelspec, Foxglove @foxglove, Sift @siftstack], [No], [Adopt],
    [OTel$arrow.l.r$ROS bridge], [ros-opentelemetry @rosopentelemetry], [Yes], [Reference],
  )
) <tab:related>

Two conclusions follow. First, the capture engine must be *adopted, not
reimplemented*: reproducing lockless multi-core buffering or nanosecond deferred
logging would re-derive published, battle-tested work. Second, a *framework*
split emerges: the turnkey robotics tools (ros2_tracing, rosbag2,
ros-opentelemetry) assume ROS 2, whereas the substrate primitives (LTTng,
NanoLog/Quill, MCAP, OpenTelemetry, iceoryx) are framework-agnostic and adoptable
by a non-ROS C++ family such as xMotion. The design task is therefore not to
build an engine but to *bind* these engines coherently to the xMotion HAL without
bloat --- the subject of §10.

= A Coherent, Lightweight Instrumentation Strategy

The objective is a single, thin instrumentation *surface* usable identically from
control, planning, and decision code, with the §9 engines plugged in behind it.
The organizing principle: *coherence comes from one spine; lightness comes from
pluggable, compile-time-selected, off-by-default sinks.* We design the spine and
adopt the engines.

== One surface, many sinks

Call sites bind to a minimal first-party surface --- roughly four verbs:
`event` (discrete structured record), `metric` (counter/gauge/histogram),
`scope` (causal timing span with a correlation id), and `signal` (high-rate typed
sample). Domain `health` is not a fifth primitive but a convention expressed over
`metric` and `event`. The surface must be *smaller than any single backend's API*
--- minimalism is the anti-bloat constraint --- yet *shaped to the OpenTelemetry
data model*, so each backend adapter is a near-zero-cost mapping rather than a fat
translation layer. Binding call sites to the surface (not to LTTng's or OTel's API
directly) is the same decoupling the family already applies to its logging vendor.

== What to own versus what to adopt

#figure(
  caption: [The division of labour. The owned "spine" is small and specific to the
    xMotion HAL; the adopted engines are the mature commodity substrate.],
  table(
    columns: (1fr, 1fr),
    align: (left, left),
    table.header([*Own and design (the spine)*], [*Adopt (the engines)*]),
    [The 4-verb instrumentation surface], [Wait-free ring / flight recorder: LTTng @desnoyers2006lttng],
    [Monotonic clock, run/session id, resource identity], [Deferred-format RT logging: NanoLog/Quill @nanolog @quill],
    [Correlation-id-in-message convention (not HTTP)], [Recording format: MCAP @mcap],
    [RT capture boundary contract (wait-free produce, drop policy)], [Export + backends: OpenTelemetry/OTLP @otlp],
    [Domain vocabulary: health / freshness / deadline-miss], [Time synchronization: PTP/gPTP],
    [Routing policy: primitive $arrow.r$ plane/sink], [Correlation-id encoding: W3C Trace Context @w3ctracecontext],
  )
) <tab:ownadopt>

== Three rules that keep it lightweight

+ *Thin, adapted, not bound.* Call sites use the four verbs; backends are adapted
  behind them. The surface stays OTel-shaped so adapters are trivial, but no call
  site ever includes a backend header.
+ *Compile-time selection and no-op-when-off.* A build links only the sinks it
  enables; disabled instrumentation compiles to nothing (NanoLog-style
  compile-time extraction). "Integrate everywhere" must not mean "everywhere
  pays."
+ *Header-light core, heavy sinks isolated.* The surface is a light header plus a
  small runtime in the foundation with no LTTng/OTel/MCAP dependency; sinks are
  separate optional targets. This is the OpenTelemetry API/SDK split applied to
  the family's own surface.

== Two data classes, one surface

The same four verbs carry two data classes with different fates: *aggregatable
diagnostics* (`event`/`metric`/`health`) routed to the observability plane
(OpenTelemetry), and *raw high-rate signals* (`signal`) routed to the recording
plane (MCAP/LTTng). The routing policy --- not the call site --- separates them,
so a 1 kHz raw stream never enters the metrics pipeline (§6.2). A discipline test
follows directly: if adding a backend requires touching call sites, the surface
has leaked; if instrumenting a new module pulls a heavy dependency, the core has
leaked. Either is a design defect, not a feature.

A strategic corollary: because the surface hides the sinks, the layer can be built
before the remaining engine choice (LTTng versus a lock-free ring on lean
targets) is made --- the call sites do not change when it is resolved later. The
design is deliberately decision-independent, which de-risks it.

== ROS-free core, ROS-bridgeable edge

The library is deliberately *ROS-free*: it depends on none of rclcpp/rmw/DDS,
rosbag2, ros2_tracing, or ament, so it links identically into non-ROS control code
and into ROS 2 nodes. This honours the family's downward-only dependency rule ---
ROS lives at the application layer as a *consumer*, not a dependency of the
foundation. ROS-free is not ROS-hostile: three seams keep the core ROS-free while
remaining fully interoperable with a ROS 2 application.

/ Time: the core stamps with a plain monotonic clock and hardware capture time;
  mapping to ROS time (including simulated `/clock` time) is done by the
  application at the boundary, not baked into the library --- no `rclcpp::Clock`
  dependency.
/ Correlation id: the core owns the id *type/format* (W3C-shaped) and the
  get/set-current-context helpers, but not the *carrier*. A non-ROS component
  places the id in its DDS/shared-memory envelope; a ROS 2 node places it in a
  message-header field. The library never includes a ROS message type.
/ Recording: MCAP is a serialization-agnostic *format*, not a ROS component
  (rosbag2 is the ROS wrapper around it). The core writes MCAP directly with a
  neutral encoding, yielding artifacts the ROS ecosystem and Foxglove can open ---
  a ROS-free producer with a ROS-compatible artifact.

Any genuinely ROS-specific glue --- injecting ROS time, reading the id from a
message header, exporting to a ROS diagnostics topic or a rosbag2/ros2_tracing
session --- lives in an *optional application-side bridge* that depends on ROS,
never in the library. Because LTTng is the tracing substrate beneath both this
library and ros2_tracing @bedard2022ros2tracing, a ROS application can even
correlate the two in a single LTTng session without the library knowing ROS
exists. This decision fixes the engine set: the library adopts only the
framework-agnostic engines (LTTng, NanoLog/Quill, MCAP, OpenTelemetry); the
ROS-coupled tools of #ref(<tab:related>) become optional application-side bridges,
not library dependencies.

= Recommended Architecture for the xMotion Family

The three-plane model maps onto the xMotion components (Σ foundation, μ drivers,
∇ algorithms, γ visualization, ζ firmware) as shown in #ref(<fig:arch>).

#figure(
  caption: [Three-plane telemetry architecture mapped onto the xMotion family.
    One monotonic time base and run/correlation id thread all planes.],
  ```
  ┌──────────── SAFETY PLANE (independent, ζ / hardware) ─────────────┐
  │  watchdog · e-stop · deadline monitor — NO OTel, no shared fate    │
  └───────────────────────────────────────────────────────────────────┘

  RT loop ─(wait-free ring: Σ rt_logger_mpsc)─► non-RT drain ─┬─► OBSERVABILITY
  (µs budget, no OTel calls on this path)                     │   OTel API (Σ)
                                                              │   → OTLP → Collector
  device Health()/freshness, host PSI/CPU/GPU/thermal ────────┤   → fleet TSDB/Grafana
                                                              │
  high-rate raw signals (IMU/control/lidar) ─────────────────►└─► RECORDING PLANE
                                                                  MCAP ring → snapshot
                                                                  on trigger (flight rec.)

     common monotonic time base + run/session/correlation id across all planes
  ```
) <fig:arch>

/ Σ (foundation): owns the *spine* of §10 --- the four-verb instrumentation
  surface, the monotonic time base, the run/correlation-id convention, the domain
  health vocabulary, and the RT capture boundary contract --- as a light header
  plus small runtime with *no* heavy telemetry dependency in core.
/ New telemetry component (optional, off by default): the adopted *engines* as
  sinks behind the surface --- LTTng/NanoLog for RT capture, MCAP for recording,
  the OpenTelemetry SDK + Collector for export --- plus the host/GPU/thermal
  collectors. Compile-time-selected; depends on Σ.
/ ∇ (algorithms): the reaction/policy layer --- fuse health, enforce budgets, arm
  the recorder, degrade or failsafe. The only layer permitted to act on telemetry.
/ γ (quickviz): live on-robot visualization; Foxglove/Grafana for offline and
  fleet analysis.
/ ζ (firmware) + application/umbrella: the independent safety backstop; the
  composition root that selects exporters, budgets, and retention; and the home of
  any optional ROS bridge (§10.5) --- ROS-specific glue lives here, never in the
  ROS-free library.

The guiding invariant restates the safety argument in dependency terms:
telemetry primitives point *down* into Σ, collectors are *optional peers*, and
only ∇ may *react*. A collector that could trip a failsafe directly would couple
observation to actuation --- exactly what independence forbids.

= Threats to Validity

Our quantitative claims are order-of-magnitude arguments built from published
measurements on *representative* platforms, not a controlled benchmark of the
xMotion stack; absolute overhead and latency figures are implementation- and
hardware-dependent (kernel configuration, DDS vendor, SoC). The specific
sampling ratio attributed to Dapper is illustrative of a policy, not a universal
constant. The three-plane model is a design heuristic; some concerns
(e.g. anomaly-triggered trace export) legitimately straddle the recording and
observability planes. These caveats do not affect the central, direction-level
conclusions, which rest on qualitative architectural properties (loss tolerance,
determinism, causality shape) rather than precise numbers.

= Conclusion

OpenTelemetry is neither a silver bullet nor an ill fit for robotics --- it is a
precise fit for one of three planes. For the *observability plane*, adopt it
directly: OTLP, the Collector, the metrics/resource model, host and hardware
semantic conventions, and the backend ecosystem are a mature capability robotics
should not rebuild. For *dataflow tracing* and *health metrics*, borrow the model
and adapt the mechanism. For the *real-time hot path* and the *safety monitor*,
keep OpenTelemetry out entirely; those belong to a wait-free capture lane and an
independent safety channel respectively, and the high-rate recording plane
belongs to MCAP. Quantitatively, OpenTelemetry is a strong adopt for roughly 40%
of the problem, a borrow-and-adapt for 30%, and irrelevant-to-harmful for the 30%
that is the control loop and the safety case. The cloud-native community's
durable gifts to robotics --- OTLP and the Collector for transport and buffering,
eBPF and PSI for low-overhead introspection, and the discipline of semantic
conventions --- are real; realizing them requires filling the robotics-specific
gaps of real-time-safe capture, a hardware time model, lossless anomaly
recording, and dataflow-native causality, unified by a single time base and
correlation identity across all three planes.

#pagebreak()

#show: appendix

= Host telemetry data sources (Linux)

#figure(
  caption: [Low-overhead kernel interfaces for observability-plane collection.],
  table(
    columns: (auto, 1fr),
    align: (left, left),
    table.header([*Signal*], [*Source*]),
    [Per-core CPU], [`/proc/stat`, `/proc/schedstat`],
    [Resource stall (hiccups)], [`/proc/pressure/{cpu,memory,io}` (PSI) @psi],
    [Memory], [`/proc/meminfo`, cgroup `memory.stat`],
    [Disk I/O + latency], [`/proc/diskstats`],
    [Network], [`/proc/net/dev`, socket drop counters],
    [Thermal], [`/sys/class/thermal`, `hwmon`],
    [GPU], [NVML (desktop), `tegrastats` (Jetson), ROCm-SMI (AMD)],
    [Scheduling latency / jitter], [`cyclictest`, direct loop-wakeup measurement @osadl],
    [Kernel/syscall/sched introspection], [eBPF (`bcc`, `bpftrace`) @gregg2019bpf],
  )
)

= Proposed `robot.*` semantic-convention seeds

Candidate attribute names, aligned in spirit with OpenTelemetry conventions and
seeded from ROS 2 diagnostics @ros2diagnostics: `robot.id`, `robot.frame_id`,
`robot.joint.name`, `robot.motor.current_a`, `robot.motor.temperature_c`,
`robot.sensor.staleness_ms`, `robot.battery.state_of_charge`, `robot.safety.state`,
`robot.mission.phase`.

#bibliography("otel-robotics-telemetry.bib", title: "References")
