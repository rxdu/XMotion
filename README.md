<div align="center">

<img src="branding/icons/xmkappa.svg" width="60" alt="xmKappa">
<img src="branding/icons/xmzeta.svg" width="60" alt="xmZeta">&nbsp;
<img src="branding/icons/xmsigma.svg" width="60" alt="xmSigma">&nbsp;
<img src="branding/icons/xmmu.svg" width="60" alt="xmMu">&nbsp;
<img src="branding/icons/xmnabla.svg" width="60" alt="xmNabla">&nbsp;
<img src="branding/icons/xmgamma.svg" width="60" alt="xmGamma">&nbsp;

# xMotion

**Everything that moves a mobile robot** — board, firmware, drivers, and the algorithms that steer them.

</div>

---

This repository is the **umbrella**: a thin CMake superbuild that assembles the components (pinned as git submodules under `components/`) and hosts family-level docs. Every component also stands alone — build, test, and `find_package` just the ones you need; the umbrella only fixes a known-good combination.

## Components

|   | Component | Role | Repo |
|---|-----------|------|------|
| **κ** | xmKappa | PCB / electronics (KiCAD) | [rxdu/xmKappa](https://github.com/rxdu/xmKappa) |
| **ζ** | xmZeta | MCU firmware (Zephyr) | [rxdu/xmZeta](https://github.com/rxdu/xmZeta) |
| **Σ** | xmSigma | foundation — logging · ipc · math · common types | [rxdu/xmSigma](https://github.com/rxdu/xmSigma) |
| **μ** | xmMu | host hardware drivers — motor · CAN · serial · modbus · sbus · imu | [rxdu/xmMu](https://github.com/rxdu/xmMu) |
| **∇** | xmNabla | motion algorithms — planning · control · estimation · mapping&nbsp;·&nbsp;*centerpiece* | [rxdu/xmNabla](https://github.com/rxdu/xmNabla) |
| **γ** | xmGamma | visualization | [rxdu/quickviz](https://github.com/rxdu/quickviz) |

Everything builds on **xmSigma**; dependencies point downward only. Two pairs span the boundary: **Σ/μ** on the host, **ζ/κ** on the embedded target — with **∇** the motion-algorithms core.

## Applications

Per-robot controllers — thin consumers of the stack, each in its own repo: [xmBot-Swerve](https://github.com/rxdu/xmbot-swerve) · [xmBot-Tracked](https://github.com/rxdu/xmbot-tracked) · [xmBot-Legged](https://github.com/rxdu/xmbot-legged).

## Build

```bash
git clone --recurse-submodules https://github.com/rxdu/xmotion.git
cd xmotion
cmake --preset default && cmake --build build
```

Each submodule is pinned to an exact commit, so `clone → configure → build` always reproduces a known-good set. Toggle components with `-DXMOTION_WITH_<NAME>=ON/OFF`.

## Documentation

[Architecture & naming](docs/adr/0001-component-architecture.md) · [Transition plan](docs/adr/0002-repo-transition-plan.md) · [Brand & icons](branding/README.md)

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Bundled third-party submodules retain their own licenses.
