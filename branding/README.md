# XMotion brand — component icons

A cohesive icon set for the XMotion family. Each icon shares one visual language and differs by **accent color** and a **functional illustration of what the component does** — so they read as a set at a glance while each communicates its job, not just its name.

## Design system

- **Badge** — a dark rounded-square (`#161B26`, `rx=30` on a 128×128 grid) with a thin accent-colored rim. Common shape + shared line style = family cohesion.
- **Hero** — functional line-art of what the component *does* (an IMU, a flow field, a surface plot, a UART decode, a PCB…), drawn in the accent color with consistent stroke weight and rounded joins. `xmNavigation`, the centerpiece, keeps a brighter rim.
- **Avatar cut** — a companion set in `icons/avatar/`: the same badge and accent, with the component's Greek glyph (full-strength outline path) as the entire artwork. Heroes are the identity at README scale (84 px+); the avatar cut is for the 16–40 px world — GitHub avatars, favicons, tabs — where hero line-art turns to texture. The hero icons themselves carry no watermark (removed 2026-07-05); the glyphs live on in the names, the logos, and this avatar set.

## The set

<table>
  <tr>
    <td align="center"><img src="icons/xmbase.svg" width="84" alt="xmBase"></td>
    <td align="center"><img src="icons/xmtelemetry.svg" width="84" alt="xmTelemetry"></td>
    <td align="center"><img src="icons/xmdriver.svg" width="84" alt="xmDriver"></td>
    <td align="center"><img src="icons/xmnavigation.svg" width="84" alt="xmNavigation"></td>
    <td align="center"><img src="icons/xmviewer.svg" width="84" alt="xmViewer"></td>
    <td align="center"><img src="icons/xmfirmware.svg" width="84" alt="xmFirmware"></td>
    <td align="center"><img src="icons/xmboard.svg" width="84" alt="xmBoard"></td>
  </tr>
  <tr>
    <td align="center"><b>xmBase</b><br>Σ</td>
    <td align="center"><b>xmTelemetry</b><br>τ</td>
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
| **xmTelemetry** | `#E0487B` rose | τ | a flight-recorder ring, open at the write head, around a live pulse — observability |
| **xmDriver** | `#F2A23A` amber | μ | a 3-axis IMU frame with a gyro ring — host hardware drivers |
| **xmNavigation** | `#10B6C6` teal | ∇ | a flow field of vectors converging to a goal (forms the ∇) — motion algorithms (centerpiece) |
| **xmViewer** | `#C158DC` violet | γ | a 3D gamma-distribution surface plot — visualization |
| **xmFirmware** | `#46B358` green | ζ | a UART decode — logic-analyzer waveform + the decoded byte `0x5A` — firmware (Zephyr) |
| **xmBoard** | `#E5604D` coral | κ | a PCB fan-out — IC footprint, disciplined 45° traces and a via — electronics (KiCAD) |

## Usage notes

- Files are plain SVG at 128×128; scale freely. For favicons/app icons, export to PNG at 16/32/48/256.
- **Font-independent:** every element — including the Greek watermarks and `xmFirmware`'s `0x5A` byte — is baked to vector outlines (no `<text>`, no font dependency), so the files render pixel-identically everywhere. The shapes derive from DejaVu Serif/Mono Bold, positioned to match the original text exactly.
- Keep the dark badge; the accent color is the only thing that should change per component. A light-background variant can be added later if needed.
- Icon **filenames** carry the functional names (`xmbase.svg`, `xmdriver.svg`, …), matching the component names per [ADR 0003](../docs/adr/0003-naming-and-branding.md); the Greek letters live on *inside* the artwork as the logos themselves.
