# XMotion brand — component icons

A cohesive icon set for the XMotion family. Each icon shares one visual language and differs by **accent color** and a **functional illustration of what the component does** — so they read as a set at a glance while each communicates its job, not just its name.

## Design system

- **Badge** — a dark rounded-square (`#161B26`, `rx=30` on a 128×128 grid) with a thin accent-colored rim. Common shape + shared line style = family cohesion.
- **Hero** — functional line-art of what the component *does* (an IMU, a flow field, a surface plot, a UART decode, a PCB…), drawn in the accent color with consistent stroke weight and rounded joins. `xmNavigation`, the centerpiece, keeps a brighter rim.
- **Brand watermark** — the component's Greek symbol sits faintly behind the art (~10% opacity; `xmBoard`'s is enlarged and boosted so the κ reads through its busier routing), retaining the naming identity without competing with the function cue.

## The set

<table>
  <tr>
    <td align="center"><img src="icons/xmsigma.svg" width="84" alt="xmBase"></td>
    <td align="center"><img src="icons/xmmu.svg" width="84" alt="xmDriver"></td>
    <td align="center"><img src="icons/xmnabla.svg" width="84" alt="xmNavigation"></td>
    <td align="center"><img src="icons/xmgamma.svg" width="84" alt="xmViewer"></td>
    <td align="center"><img src="icons/xmzeta.svg" width="84" alt="xmFirmware"></td>
    <td align="center"><img src="icons/xmkappa.svg" width="84" alt="xmBoard"></td>
  </tr>
  <tr>
    <td align="center"><b>xmBase</b><br>Σ</td>
    <td align="center"><b>xmDriver</b><br>μ</td>
    <td align="center"><b>xmNavigation</b><br>∇</td>
    <td align="center"><b>xmViewer</b><br>γ</td>
    <td align="center"><b>xmFirmware</b><br>ζ</td>
    <td align="center"><b>xmBoard</b><br>κ</td>
  </tr>
</table>

| Icon | Accent | Symbol | Icon depicts |
|------|--------|--------|--------------|
| **xmBase** | `#5E6AD2` indigo | Σ | a hub of connected nodes — the runtime/event/IPC substrate everything plugs into |
| **xmDriver** | `#F2A23A` amber | μ | a 3-axis IMU frame with a gyro ring — host hardware drivers |
| **xmNavigation** | `#10B6C6` teal | ∇ | a flow field of vectors converging to a goal (forms the ∇) — motion algorithms (centerpiece) |
| **xmViewer** | `#C158DC` violet | γ | a 3D gamma-distribution surface plot — visualization |
| **xmFirmware** | `#46B358` green | ζ | a UART decode — logic-analyzer waveform + the decoded byte `0x5A` — firmware (Zephyr) |
| **xmBoard** | `#E5604D` coral | κ | a PCB fan-out — IC footprint, pins, traces and vias — electronics (KiCAD) |

## Usage notes

- Files are plain SVG at 128×128; scale freely. For favicons/app icons, export to PNG at 16/32/48/256.
- **Font-independent:** every element — including the Greek watermarks and `xmFirmware`'s `0x5A` byte — is baked to vector outlines (no `<text>`, no font dependency), so the files render pixel-identically everywhere. The shapes derive from DejaVu Serif/Mono Bold, positioned to match the original text exactly.
- Keep the dark badge; the accent color is the only thing that should change per component. A light-background variant can be added later if needed.
- Icon **filenames** keep their Greek-letter identity (`xmsigma.svg`, `xmmu.svg`, …) because, per [ADR 0003](../docs/adr/0003-naming-and-branding.md), the Greek letters *are* the logos; the component **names** are functional (xmBase, xmDriver, …). A file rename to match the functional names is an optional future cleanup.
