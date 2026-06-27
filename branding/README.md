# xMotion brand — component icons

A cohesive icon set for the xMotion family. Each icon shares one visual language and differs only by **accent color**, **hero symbol**, and a small **function motif** — so they read as a set at a glance while each stays identifiable.

## Design system

- **Badge** — a dark rounded-square (`#161B26`, `rx=30` on a 128×128 grid) with a thin accent-colored rim. Common shape = family cohesion.
- **Hero symbol** — the component's Greek math symbol, centered, in the accent color (serif, for a mathematical feel). `xmNabla` is drawn as a bold outline triangle (∇) and given a brighter rim, marking it the centerpiece.
- **Motif** — a subtle accent-colored mark along the lower band encoding the module's job (see table). Consistent placement across all six.

## The set

<table>
  <tr>
    <td align="center"><img src="icons/xmsigma.svg" width="84" alt="xmSigma"></td>
    <td align="center"><img src="icons/xmmu.svg" width="84" alt="xmMu"></td>
    <td align="center"><img src="icons/xmnabla.svg" width="84" alt="xmNabla"></td>
    <td align="center"><img src="icons/xmgamma.svg" width="84" alt="xmGamma"></td>
    <td align="center"><img src="icons/xmzeta.svg" width="84" alt="xmZeta"></td>
    <td align="center"><img src="icons/xmkappa.svg" width="84" alt="xmKappa"></td>
  </tr>
  <tr>
    <td align="center"><b>xmSigma</b><br>Σ</td>
    <td align="center"><b>xmMu</b><br>μ</td>
    <td align="center"><b>xmNabla</b><br>∇</td>
    <td align="center"><b>xmGamma</b><br>γ</td>
    <td align="center"><b>xmZeta</b><br>ζ</td>
    <td align="center"><b>xmKappa</b><br>κ</td>
  </tr>
</table>

| Icon | Accent | Motif | Reads as |
|------|--------|-------|----------|
| **xmSigma** | `#5E6AD2` indigo | stacked layers | the foundation everything builds on |
| **xmMu** | `#F2A23A` amber | motor rotor | host hardware drivers |
| **xmNabla** | `#10B6C6` teal | gradient-descent arrow | motion algorithms (centerpiece) |
| **xmGamma** | `#C158DC` violet | gamma-correction curve | visualization |
| **xmZeta** | `#46B358` green | damped oscillation (ζ = damping ratio) | firmware / real-time loops |
| **xmKappa** | `#E5604D` coral | PCB trace + via (κ = curvature) | PCB / electronics |

## Usage notes

- Files are plain SVG at 128×128; scale freely. For favicons/app icons, export to PNG at 16/32/48/256.
- **Production hardening:** the hero glyphs use a system serif via `<text>`. For pixel-identical rendering everywhere (and to drop the font dependency), convert text to outlines — e.g. Inkscape *Path → Object to Path*, or `inkscape --export-text-to-path`. `xmNabla` is already pure geometry.
- Keep the dark badge; the accent color is the only thing that should change per component. A light-background variant can be added later if needed.
