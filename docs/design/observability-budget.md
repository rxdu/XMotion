# The observability budget — one chain, three measured stages

- Status: Active (stage contracts live in their components; this page is the map)
- Date: 2026-07-11
- Intent: **high-performance, low-overhead telemetry and data visualization for best-in-class robot observability** — the robot must not be able to tell it is being watched. Reference bar: HEBI's hebi-charts (MHz-rate ingestion, published nanosecond overhead, render fully decoupled from data).

## The chain

Observability in the family is one composed system with a per-stage overhead budget. Every stage's claim is **measured in-tree, published with hardware context, and regression-gated** — never asserted. The stage contracts are owned by their components; this page only binds them together and states the end-to-end claim.

| Stage | Component | Contract (executable spec) | Hot-path claim (measured, dev-box class¹) |
|---|---|---|---|
| 1. Instrument | xmBase / xmTelemetry | telemetry scenario suite (S1 RT gate: alloc-free, wait-free, zero page faults, one clock read per record) | ~100 ns-class per record, p99-gated in CI |
| 2. Move | xmMessaging | scenarios M1–M14 + M9 benchmark gates ([docs/scenarios.md](https://github.com/rxdu/xmMessaging/blob/main/docs/scenarios.md)) | publish 64 B p50 ~100–140 ns; 1 kHz hop p99 ~420 ns; explicit statuses, counted drops |
| 3. Visualize | quickviz (xmViewer) | ingestion contract I1–I7 ([docs/ingestion_contract.md](https://github.com/rxdu/quickviz/blob/main/docs/ingestion_contract.md)) | ring write p50 ~22 ns; ingest cost invariant across headless / 60 fps / stalled render |

¹ Reference numbers are per-machine artifacts embedded with hardware context in each component's benchmark reports; the numbers here indicate the class, not a promise for your hardware — run each component's one-command bench to get yours.

## The composed claim

**Full-rate observation, zero perturbation**: a robot instrumented at every tier, streaming over the transport, with live visualization attached, exhibits loop-timing tails statistically indistinguishable from the same robot running unobserved.

The acceptance shape for this claim at every boundary is the *observer-invisibility A/B* (first stated as xmMessaging M10-A4): attach the most aggressive observer the plane supports, measure the observed process's tails, compare against baseline. It holds today at stage 2 (introspection observer at ~125 k snapshots/s: indistinguishable) and is pending a hardware-GL rerun at stage 3 (software rasterization confounds the A/B by competing for cores — a measurement artifact, not a coupling).

## Shared doctrine across the stages

- **Loss is counted, never silent** — telemetry drop counters, messaging drop/refusal/overwrite counters, and (remediation in flight) viz overflow counters. A number that can quietly lose samples is not an observability number.
- **The observed side never blocks on the observer** — telemetry's wait-free hot path, messaging's latest-only overwrite and never-blocking publish, viz's producer-never-blocks ingestion (proven against a deliberately stalled render thread).
- **One clock** — stamps and records across all three stages derive from the xmBase monotonic clock; timelines interleave by construction.
- **Render/drain planes are decoupled by design** — a hidden render or drain thread is legitimate *inside* the observer plane; it is forbidden in the transport and instrumentation hot paths.

## Current status and gaps

Stage 1 and 2 gates run in CI. Stage 3 (quickviz PR #31): I1/I4/I6 conform with ≥2× margin; open remediation, in order — overflow counters (I3, the silent-loss gap), CI regression gate (I7), heap-payload slot pre-sizing (I2), hardware-GL observer A/B (I5).
