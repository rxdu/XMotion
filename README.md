# xMotion

**xMotion** is a family of components for mobile-robot motion: a reusable software stack plus its firmware and hardware companions. This repository is the **umbrella** — a thin superbuild that assembles the component repos and hosts the family-level documentation. Each component is maintained in its own repository (they differ by dependency footprint and toolchain) and can be built and consumed independently.

## The family

A concrete, motion-domain surname (**xMotion**) over abstract, mathematical component codenames — each a math symbol whose first letter hooks the underlying technology and whose meaning matches the module's job.

| Component | Symbol | Role | Repo |
|-----------|--------|------|------|
| **xmSigma** | Σ | runtime foundation — logging, event, ipc, math, containers | `rxdu/xmsigma` |
| **xmMu** | μ | host-side hardware drivers — motor / CAN / serial / modbus / sbus / imu | `rxdu/xmmu` |
| **xmNabla** | ∇ | motion algorithms — planning, control, estimation, mapping | `rxdu/xmnabla` |
| **xmGamma** | γ | visualization | `rxdu/quickviz` |
| **xmZeta** | ζ | MCU firmware (Zephyr) | `rxdu/xmzeta` |
| **xmKappa** | κ | PCB / electronics (KiCAD) | `rxdu/xmkappa` |
| **xmBot-\*** | — | per-robot applications | `rxdu/xmbot-swerve`, `…-tracked`, `…-legged` |

Dependencies point downward only: `xmSigma ← xmMu`, `xmSigma ← xmNabla`, `xmSigma ← xmGamma`; applications depend on any.

```
        xMotion  ──  the motion-robotics stack
        │
        ├─ xmSigma  (Σ)  foundation        substrate · covariance
        ├─ xmMu     (μ)  drivers           Motor · friction
        ├─ xmNabla  (∇)  motion algorithms gradient — the centerpiece
        ├─ xmGamma  (γ)  visualization     Graphics · gamma correction
        ├─ xmZeta   (ζ)  firmware (Zephyr) Zephyr · damping ratio
        └─ xmKappa  (κ)  PCB (KiCAD)       KiCAD · curvature
```

## How this umbrella works

The software components live under `components/` as **git submodules pinned to exact commits**. The umbrella's top-level CMake is a superbuild that configures the pinned set together, so `clone → configure → build` produces the whole stack from a known-good combination — without forcing independent semantic-version management across repos.

You do **not** have to use the umbrella. Each component repo builds, tests, installs, and is `find_package`-able on its own; depend on just the ones you need.

> **Status:** scaffolding. The component submodules are wired during the repo transition — see [docs/adr/0002-repo-transition-plan.md](docs/adr/0002-repo-transition-plan.md).

## Build (once components are wired)

```bash
git clone --recurse-submodules git@github.com:rxdu/xmotion.git
cd xmotion
cmake --preset default
cmake --build build
```

Select components with `-DXMOTION_WITH_<NAME>=ON/OFF` (see `CMakeLists.txt`).

## Documentation

- [ADR 0001 — Component Architecture & Naming](docs/adr/0001-component-architecture.md)
- [ADR 0002 — Repo Transition Plan](docs/adr/0002-repo-transition-plan.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Bundled third-party submodules retain their own licenses.
