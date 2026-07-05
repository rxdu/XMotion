# components/

Software components of the XMotion family, vendored as git submodules pinned to exact commits. Each also lives as a standalone repository and builds on its own.

Component names follow [ADR 0003](../docs/adr/0003-naming-and-branding.md): submodule paths use each component's function word, matching its `xm<Word>` repo name and `xmotion::<word>` namespace; the Greek letters are retained as logos only.

| Path | Submodule repo | Component |
|------|----------------|-----------|
| `base/`       | `rxdu/xmBase`       | xmBase (Σ) — foundation |
| `telemetry/`  | `rxdu/xmTelemetry`  | xmTelemetry — observability SDK + tools |
| `driver/`     | `rxdu/xmDriver`     | xmDriver (μ) — host hardware drivers |
| `navigation/` | `rxdu/xmNavigation` | xmNavigation (∇) — motion algorithms |
| `viewer/`     | `rxdu/quickviz`     | xmViewer (γ) — visualization |

Historical note: the paths carried the Greek codenames (`sigma/`, `mu/`, `nabla/`, `gamma/`) during the repo transition (see `../docs/adr/0002-repo-transition-plan.md`); they were renamed to the function words once every repo rename landed.
