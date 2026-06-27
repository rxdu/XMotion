# components/

Software components of the xMotion family, vendored as git submodules pinned to exact commits. Each also lives as a standalone repository and builds on its own.

| Path | Submodule repo | Component |
|------|----------------|-----------|
| `sigma/` | `rxdu/xmsigma` | xmSigma (Σ) — foundation |
| `mu/`    | `rxdu/xmmu`    | xmMu (μ) — drivers |
| `nabla/` | `rxdu/xmnabla` | xmNabla (∇) — motion algorithms |
| `gamma/` | `rxdu/quickviz`| xmGamma (γ) — visualization |

Submodules are added during the repo transition (see `../docs/adr/0002-repo-transition-plan.md`); until then this directory is an intentional placeholder.
