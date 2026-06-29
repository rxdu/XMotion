# ADR 0001 — xMotion Component Architecture & Product-Family Naming

- **Status:** Accepted
- **Date:** 2026-06-27
- **Deciders:** Ruixiang Du
- **Supersedes:** —
- **Note:** §3 (packaging) was revised from a single-monorepo decision to a
  **polyrepo + umbrella** decision on 2026-06-27; see the revision note in §3.

## Context

Years of robotics work are spread across several repositories: `libxmotion` (the multi-year C++ core), `quickviz` (visualization), `libgraph` (graph algorithms), `libzdriver` (Zephyr firmware), `libkpcb` (KiCAD PCB designs), and a set of per-robot controllers (`swervebot_controller`, `trackedbot_controller`, `legged_controller`, `legged_locomotion`). The platform/app code that used to live inside `libxmotion` has already been split out into separate controller repos.

The goal is to consolidate this into a cohesive, production-grade product family that is reusable across robots, while keeping each component lightweight and easy to integrate with minimal dependencies.

Today's structure has several inconsistencies that work against that goal:

- **Fat core.** `libxmotion` bundles unrelated dependency footprints (serial/CAN drivers, Eigen-heavy planning, an OpenGL/imgui visualization stack) into one library, so any consumer pays for all of it.
- **Source-vendoring consumption.** Each app embeds the entire `libxmotion` source as an `external/libxmotion` submodule and `add_subdirectory`s it, recompiling the whole core per app.
- **Name collision.** `trackedbot_controller/CMakeLists.txt` declares `project(xmotion)` — the same project name as the core it pulls in, risking target/namespace clashes.
- **Forked abstractions.** The core ships `fsm_template.hpp`, but `legged_controller` adopted `ctfsm`; the supposedly shared FSM is not actually shared.
- **Divergent build idioms.** `legged_controller` uses a modern style (CMakePresets, top-level guards, weighted submodules); `libxmotion` and the bot controllers use older plain CMake; `legged_locomotion` is ROS2/ament. Nothing is shared.

## Decision

### 1. Component model

The stack is a set of components with a strict, downward-only dependency direction. Each component is maintained in its **own repository**; the `xmotion` umbrella repo reassembles the software components via a superbuild. Firmware and hardware are sibling repos that share the brand but not the toolchain.

```
                          xMotion (umbrella superbuild repo)

  ┌──────────────────────── SOFTWARE (per-component repos) ───────────────────┐
  │   xmMu (host HAL)        xmNabla (motion)     xmGamma (viz, optional)       │
  │            └────────────────────┼────────────────────┘                     │
  │                            xmSigma (runtime foundation, always)            │
  └────────────────────────────────────────────────────────────────────────────┘
        ▲ wire (CAN/serial/DDS)                      ▲ depends-on
   xmZeta (firmware, Zephyr — separate repo)    xmKappa (PCB, KiCAD — separate repo)

                 APPLICATIONS:  xmBot-Swerve · xmBot-Tracked · xmBot-Legged · …
                 thin consumers — superbuild or find_package(xmSigma/xmMu/…)
```

| # | Name | Symbol | Role | Contains (from today's code) | Heavy deps | Repo |
|---|------|--------|------|------------------------------|------------|------|
| 0 | **xmSigma** | Σ | runtime foundation (always built) | logging + the shared geometry/primitive type vocabulary (`xmotion/types/`); a single `xmotion::xmSigma` target | Eigen, spdlog | `rxdu/xmsigma` |
| 3 | **xmMu** | μ | host-side hardware abstraction | `driver/` — motor (vesc/waveshare/akelc), async_port (CAN/serial), modbus, sbus, imu, hid; **+ the driver HAL contracts** (`xmotion::hal`, `xmmu/hal/`) | asio, libmodbus, libevdev, socketcan | `rxdu/xmmu` |
| 4 | **xmNabla** | ∇ | motion algorithms — math-driven planning, control, estimation | `planning/` (graph, geometry, decomp, sampling, state_lattice, decision), `control/` (fsm, pid, model), `estimation/`, `mapping/`; **+ motion/control types** (`xmnabla/`); **depends on μ's HAL** | Eigen, GSL, quadprog, CGAL, tbb | `rxdu/xmnabla` |
| – | **xmGamma** | γ | visualization | `quickviz/` | GLFW, OpenGL, imgui, cairo, glm | `rxdu/quickviz` |
| 2 | **xmZeta** | ζ | MCU firmware | `libzdriver` (Zephyr/west) | Zephyr SDK | `rxdu/xmzeta` |
| 1 | **xmKappa** | κ | PCB / electronics | `libkpcb` (KiCAD) | — | `rxdu/xmkappa` |
| 5 | **xmBot-\*** | — | per-robot applications | swervebot / trackedbot / legged controllers | xMotion | `rxdu/xmbot-*` |

### 2. Naming

The product family uses an `xm-` prefix (the shared "surname", connoting *extreme/solid* and unambiguously xMotion's). The umbrella name **xMotion** is deliberately concrete and motion-domain, grounding the abstract symbol components. Each module's given name is a **mathematical symbol**, chosen to be *triple-coded*:

1. **Theme** — a math symbol, signalling the rigorous, algorithm-driven character of the stack (in the tradition of Eigen, Ceres, Sophus, manif).
2. **Tech-initial mnemonic** — the symbol's first letter hooks the module's underlying technology or concept.
3. **Domain meaning** — the symbol's standard mathematical meaning matches what the module does.

| Name | Symbol | Letter hook | Symbol's domain meaning |
|------|--------|-------------|-------------------------|
| **xmSigma** | Σ | **S**ubstrate / **S**um | Σ = covariance matrix (estimation) |
| **xmMu** | μ | **M**otor | μ = friction coefficient (traction/contact) |
| **xmNabla** | ∇ | the math itself (gradients/fields) | ∇ = gradient (planning / optimal control) |
| **xmGamma** | γ | **G**raphics / OpenGL | γ = gamma correction (rendering/display) |
| **xmZeta** | ζ | **Z**ephyr | ζ = damping ratio (real-time control loops) |
| **xmKappa** | κ | **K**iCAD | κ = curvature (geometry / layout) |

`xmNabla` is the centerpiece: the only *operator* (∇) among letter-symbols. Because the symbol names are abstract, the standard is: **never ship a name without its one-line descriptor** (e.g. `xmNabla — motion & control algorithms`) in READMEs, CMake comments, and consumer docs.

Names were collision-checked (GitHub / package indexes / products); every exact `xm<symbol>` string is unclaimed, bare-word echoes are cross-domain. `xmPilot` (→ Sony XM-Pilot) and `xmDelta` (→ delta robots) were rejected during selection in favor of `xmNabla` and `xmMu`.

### 3. Packaging & consumption — **polyrepo + umbrella**

> **Revision (2026-06-27).** This section originally specified a single `xMotion` monorepo with the components as build-time-option folders. It was revised to **polyrepo + umbrella** because the components differ materially by dependency footprint *and* lifecycle (xmZeta/Zephyr and xmKappa/KiCAD are different toolchains entirely; xmSigma, xmMu, xmNabla, xmGamma are four different dependency worlds). Maintaining each as its own repo enforces the boundaries physically and lets each be reused and evolve independently. The accepted cost is coordinating cross-cutting changes across repos.

- **Each component is its own repository** with its own modern CMake build, tests, and install/export rules, and is independently `find_package`-able. A consumer depends on only the components it needs (`find_package(xmSigma)` + `find_package(xmNabla)`), pulling only those dependency footprints.
- **The `xmotion` umbrella is a thin superbuild.** It vendors the software components as **git submodules under `components/`, pinned to exact commits**, and its top-level CMake configures the pinned set together. `clone --recurse-submodules → configure → build` yields the whole stack from a known-good combination.
- **Pin by commit (submodule SHA), not independent semver.** At this scale (a single maintainer consuming the stack across a handful of robots), SHA pins avoid a version matrix while still giving reproducible, deliberate updates. Independent semantic versioning can be layered on later if external consumers need it.
- **Firmware (`xmZeta`) and PCB (`xmKappa`) stay outside the superbuild** — different toolchains (Zephyr/west, KiCAD), referenced from docs.
- **Mental model:** N small single-concern repos, reassembled on demand by one umbrella; not one fat repo.

Accepted tradeoff: a change to a shared `xmSigma` API requires bumping its pin in each dependent repo (vs. one commit in a monorepo). This is tolerable because foundational APIs churn rarely, and the umbrella's superbuild keeps "build everything together" a single command.

### 4. Standards

1. **Dependencies point downward only** — `xmSigma ← xmMu`, `xmSigma ← xmNabla`, `xmSigma ← xmGamma`; apps depend on any. No upward or sideways edges. Each repo's CI builds it standalone, proving the boundary; the umbrella CI builds the assembled set.

   > **Revision (2026-06-30) — Σ scope tightened; one intentional downward edge `μ ← ∇`.** The original rule placed all driver/control interfaces and common types in Σ and forbade *any* sideways edge. In practice that put things in Σ that belong to a single upper layer (driver interfaces only the drivers implement; trajectory/control types only ∇ uses) — Σ should hold *only what is universal*, since every component depends on it. Σ was therefore narrowed to **logging + the shared `xmotion/types/` vocabulary**, as one `xmotion::xmSigma` target. The 12 driver interfaces moved to **xmMu** as its header-only HAL (`xmotion::hal`, `xmmu/hal/`); `trajectory`/`ControllerInterface` moved to **xmNabla** (`xmnabla/…`, `xmotion::xmnabla_common`). Because ∇'s control commands hardware *through* the motor HAL **and** implements it via actuator-group adapters (a bilateral contract with no natural owner among the siblings), this introduces the one deliberate edge **`xmMu ← xmNabla`**: ∇ links μ's header-only HAL. The model is now a strict layering **Σ ← μ ← ∇** (μ and ∇ are no longer pure siblings); γ remains a Σ-only sibling. Landed as a coordinated 4-PR change, gated on the umbrella Assembly CI.
2. **Heavy/optional deps behind `*_WITH_*` flags, off by default** — each component's base build stays minimal; the umbrella exposes `XMOTION_WITH_MU/_NABLA/_GAMMA`.
3. **One build idiom everywhere** — adopt the `legged_controller` style in every repo: `CMakePresets.json`, `PROJECT_IS_TOP_LEVEL` guards, `EXCLUDE_FROM_ALL` on vendored submodules, install/export rules with namespaced targets, semantic versioning per repo.
4. **One FSM** — converge on `ctfsm` (already proven in `legged_controller`); retire `fsm_template.hpp`.
5. **Naming is a standard** — `xm-` symbol names map 1:1 to repos, CMake targets (`xmotion::sigma/mu/nabla/gamma`), and namespaces (`xmotion::`); each always travels with a one-line function descriptor.
6. **Fix known issues on migration** — rename `trackedbot_controller`'s `project(xmotion)`; replace full-source `add_subdirectory` vendoring with `find_package`.
7. **Licensing** — the family is licensed **Apache-2.0** (permissive + explicit patent grant), replacing the prior BSD-3-Clause. Each repo carries `LICENSE` (Apache-2.0) + `NOTICE`; bundled third-party submodules keep their own licenses. To preserve the option of future commercialization / dual-licensing, **outside contributions require a CLA or DCO** so copyright ownership stays consolidated.

### 5. Target layout

```
rxdu/xmotion   = umbrella: superbuild CMake + submodule pins + family docs
  └─ components/
     ├─ sigma/   → submodule rxdu/xmsigma   (xmotion::sigma)
     ├─ mu/      → submodule rxdu/xmmu      (xmotion::mu)
     ├─ nabla/   → submodule rxdu/xmnabla   (xmotion::nabla)
     └─ gamma/   → submodule rxdu/quickviz  (xmotion::gamma)

rxdu/xmsigma · rxdu/xmmu · rxdu/xmnabla   each: standalone repo, CI, install rules
rxdu/quickviz                              (xmGamma source; keeps its own identity)
rxdu/xmzeta (Zephyr) · rxdu/xmkappa (KiCAD)   separate toolchains
rxdu/xmbot-swerve · …-tracked · …-legged      app consumers
```

`xmNabla` inherits `libxmotion`'s git history (it is the bulk of it); `xmSigma` and `xmMu` are extracted from `libxmotion` with their slice of history (see ADR 0002).

## Consequences

**Positive**

- Component boundaries enforced physically by repo separation; minimal-dependency consumption is the default.
- Each component independently reusable, versionable, and releasable (e.g. `xmNabla` can be consumed like Eigen/Ceres).
- The umbrella still gives a one-command build of the whole stack from a pinned, known-good set.
- A cohesive, distinctive math-symbol family signalling rigor end to end.

**Negative / costs**

- Cross-cutting changes span repos: a shared-API change in `xmSigma` means bumping its pin in each dependent (vs. one monorepo commit).
- More infrastructure: N repos × (CI, releases, README, versioning).
- The symbol names are not self-documenting — they require the descriptor rule and a legend.
- Converging on `ctfsm` requires porting existing `fsm_template.hpp` users.

**Follow-up actions**

- Execute the split-and-extract transition (ADR 0002) under sign-off.
- Address the High-severity core bugs found in review (dead DDS publisher, async self-join on comms loss, `ThreadSafeQueue` self-move, modbus double-free, unclamped VESC RPM) — they live in xmSigma/xmMu, which every app depends on. Capture recurring patterns in `docs/LESSONS.md`.

## Open questions

1. Robot/application naming: keep the `xmBot-*` lineage, or give robots standalone product names (a future "star line") that merely depend on xMotion?
2. CMake `COMPONENTS`/target names: keep abstract symbols (`xmotion::mu`, `xmotion::gamma`) for 1:1 mapping, or expose *functional* aliases (`drivers`, `viz`) for consumer readability while repo/target codenames stay symbolic?
3. Whether/when to layer independent semantic versioning over the SHA-pin scheme (only if external consumers need it).
