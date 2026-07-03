# components/

Software components of the XMotion family, vendored as git submodules pinned to exact commits. Each also lives as a standalone repository and builds on its own.

Component names follow [ADR 0003](../docs/adr/0003-naming-and-branding.md); the Greek letters are retained as logos only. Submodule repos keep their current names until each is renamed (a gradual, redirect-safe migration — see ADR 0003).

| Path | Submodule repo | Component |
|------|----------------|-----------|
| `sigma/` | `rxdu/xmBase` | xmBase (Σ) — foundation |
| `mu/`    | `rxdu/xmmu`    | xmDriver (μ) — host hardware drivers |
| `nabla/` | `rxdu/xmnabla` | xmNavigation (∇) — motion algorithms |
| `gamma/` | `rxdu/quickviz`| xmViewer (γ) — visualization |

Submodules are added during the repo transition (see `../docs/adr/0002-repo-transition-plan.md`); until then this directory is an intentional placeholder.
