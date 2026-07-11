<div align="center">

<img src="branding/icons/xmmotion.svg" width="104" alt="XMotion">

# XMotion

**Everything that moves a mobile robot** — board, firmware, drivers, messaging, and the algorithms that steer them.

<img src="branding/icons/xmbase.svg" width="48" alt="xmBase">&nbsp;
<img src="branding/icons/xmtelemetry.svg" width="48" alt="xmTelemetry">&nbsp;
<img src="branding/icons/xmdriver.svg" width="48" alt="xmDriver">&nbsp;
<img src="branding/icons/xmnavigation.svg" width="48" alt="xmNavigation">&nbsp;
<img src="branding/icons/xmmessaging.svg" width="48" alt="xmMessaging">&nbsp;
<img src="branding/icons/xmviewer.svg" width="48" alt="xmViewer">&nbsp;
<img src="branding/icons/xmfirmware.svg" width="48" alt="xmFirmware">&nbsp;
<img src="branding/icons/xmboard.svg" width="48" alt="xmBoard">

</div>

---

This repository is the **umbrella**: a thin CMake superbuild that assembles the components (pinned as git submodules under `components/`) and hosts family-level docs. Every component also stands alone — build, test, and `find_package` just the ones you need; the umbrella only fixes a known-good combination.

## Components

|   | Component | Role | Repo |
|---|-----------|------|------|
| **κ** | xmBoard | PCB / electronics (KiCAD) | [rxdu/xmBoard](https://github.com/rxdu/xmBoard) |
| **ζ** | xmFirmware | MCU firmware (Zephyr) | [rxdu/xmFirmware](https://github.com/rxdu/xmFirmware) |
| **Σ** | xmBase | foundation — logging · ipc · math · common types | [rxdu/xmBase](https://github.com/rxdu/xmBase) |
| **τ** | xmTelemetry | observability — logs · metrics · traces · black box | private<sup>1</sup> |
| **μ** | xmDriver | host hardware drivers — motor · CAN · serial · modbus · sbus · imu | [rxdu/xmDriver](https://github.com/rxdu/xmDriver) |
| **∇** | xmNavigation | motion algorithms — planning · control · estimation · mapping&nbsp;·&nbsp;*centerpiece* | [rxdu/xmNavigation](https://github.com/rxdu/xmNavigation) |
| **π** | xmMessaging | application communication — typed pub/sub · request/response · zero-copy transport | [rxdu/xmMessaging](https://github.com/rxdu/xmMessaging) |
| **γ** | xmViewer | visualization | [rxdu/quickviz](https://github.com/rxdu/quickviz) |

<sup>1</sup> *xmTelemetry — the production observability SDK and tooling — is privately maintained; available for production integrations.*

Component names follow [ADR 0003](docs/adr/0003-naming-and-branding.md); the Greek letters (κ ζ Σ τ μ ∇ γ π) are retained as logos only — every repo, submodule path, and icon file now carries its functional name. Everything builds on **xmBase**; dependencies point downward only. Two pairs span the boundary: **xmBase/xmDriver** on the host, **xmFirmware/xmBoard** on the embedded target — with **xmNavigation** the motion-algorithms core.

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

[Decision records](docs/adr/) · [Telemetry design](docs/design/telemetry-library-design.md) · [Brand & icons](branding/README.md) · [Tasks](TODO.md)

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Bundled third-party submodules retain their own licenses.
