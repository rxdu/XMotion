# ADR 0002 — Repo Transition Plan (split, extract & wire)

- **Status:** Accepted — Phase 1 executed (repos split/renamed with history, umbrella wired, submodules pinned; paths later renamed to function words per ADR 0003). Phase-2 decoupling is folded into the xmNavigation migration, tracked in [`TODO.md`](../../TODO.md).
- **Date:** 2026-06-27
- **Deciders:** Ruixiang Du
- **Depends on:** [ADR 0001](0001-component-architecture.md)

## Purpose & scope

Stand up the polyrepo + umbrella structure of ADR 0001 from today's repos, **preserving git history per component**, and wire the umbrella — *without* yet decoupling the source (removing extracted code from `xmNabla`, rewiring includes/deps). That decoupling and the `find_package` switch are **Phase 2**.

- **Phase 1 (this plan):** create/rename the component repos (with history), set up the `xmotion` umbrella, add submodule pins. Every existing repo still builds exactly as before; the new repos exist but are not yet load-bearing.
- **Phase 2 (later):** in `xmNabla`, delete the now-extracted `common/` and `driver/` and depend on `xmSigma`/`xmMu`; unify build idioms; fix `project(xmotion)`; switch apps to `find_package`. Out of scope here.

## Decisions (resolved)

- **D0 — Topology:** **polyrepo + umbrella** (ADR 0001 §3). ✔
- **D1 — Rename vs new:** **rename** existing repos where a 1:1 mapping exists (preserves history + GitHub redirects); **extract** where one repo becomes several. ✔
- **D2 — Keep `libgraph` & `quickviz` identities:** **keep.** They remain standalone upstreams; `xmNabla` consumes `libgraph` as a submodule, `xmGamma` is sourced from `quickviz`. ✔
- **D3 — Legged:** rename `legged_controller → xmbot-legged`; `legged_locomotion` (ROS2) stays out of scope. ✔ *(confirmed 2026-06-27)*
- **D4 — Local dirs:** rename local working dirs to match. ✔ *(cosmetic)*

## Repo mapping

| Current | → Target repo | Action | History |
|---|---|---|---|
| `rxdu/libxmotion` | `rxdu/xmnabla` | **rename** (keeps the bulk: planning/control/estimation/mapping) | full history travels with xmNabla |
| `rxdu/libxmotion` `src/common` | `rxdu/xmsigma` | **extract** (`git filter-repo`) into a new repo | its slice of history |
| `rxdu/libxmotion` `src/driver` | `rxdu/xmmu` | **extract** (`git filter-repo`) into a new repo | its slice of history |
| `rxdu/libzdriver` | `rxdu/xmzeta` | **rename** | full |
| `rxdu/libkpcb` | `rxdu/xmkappa` | **rename** | full |
| `rxdu/swervebot_controller` | `rxdu/xmbot-swerve` | **rename** | full |
| `rxdu/trackedbot_controller` | `rxdu/xmbot-tracked` | **rename** | full |
| `rxdu/legged_controller` | `rxdu/xmbot-legged` | **rename** | full |
| `rxdu/quickviz`, `rxdu/libgraph` | *(unchanged)* | keep | — |
| `rxdu/xmotion` | `rxdu/xmotion` | **umbrella** (new; scaffolded) | new |

Repo names are lowercase; display/target/namespace names keep their cased forms.

## Execution sequence

> **Gate:** the `gh repo rename`, `git filter-repo`, and `git push` steps below are outward-facing and history-rewriting. **None are run until this ADR is signed off.** Extraction is always done on a **fresh clone**, never on a working checkout, and never force-pushes an existing repo.

**Step 0 — Umbrella scaffold (done)**
`rxdu/xmotion` initialized with superbuild `CMakeLists.txt`, `CMakePresets.json`, `cmake/`, `components/` placeholder, README, LICENSE, and these ADRs. No submodules yet.

**Step 1 — Rename the independent leaves**
```
gh repo rename xmzeta  --repo rxdu/libzdriver
gh repo rename xmkappa --repo rxdu/libkpcb
```
Update each local `origin` remote; optionally rename local dirs.

**Step 2 — Rename the apps**
```
gh repo rename xmbot-swerve  --repo rxdu/swervebot_controller
gh repo rename xmbot-tracked --repo rxdu/trackedbot_controller
gh repo rename xmbot-legged  --repo rxdu/legged_controller
```

**Step 3 — Rename the core to xmNabla**
```
gh repo rename xmnabla --repo rxdu/libxmotion
```
`xmNabla` now holds the entire old tree (still including `common/` and `driver/`) — it builds unchanged. Decoupling is Phase 2.

**Step 4 — Extract xmSigma and xmMu (history-preserving)**
For each, on a **fresh clone** (requires `git-filter-repo`):
```
# xmSigma  ← src/common
git clone git@github.com:rxdu/xmnabla.git /tmp/extract-sigma
cd /tmp/extract-sigma
git filter-repo --path src/common/ --path-rename src/common/:
gh repo create rxdu/xmsigma --private --source=. --remote=origin
git push -u origin --all && git push origin --tags

# xmMu  ← src/driver   (repeat on a fresh clone)
git filter-repo --path src/driver/ --path-rename src/driver/:
```
Result: `xmSigma` and `xmMu` are standalone repos carrying only their files and the commits that touched them. The originals in `xmNabla` are untouched in Phase 1.

**Step 5 — Wire the umbrella**
```
cd <xmotion-umbrella>
git submodule add git@github.com:rxdu/xmsigma.git  components/sigma
git submodule add git@github.com:rxdu/xmmu.git     components/mu
git submodule add git@github.com:rxdu/xmnabla.git  components/nabla
git submodule add git@github.com:rxdu/quickviz.git components/gamma
git commit -m "chore: pin component submodules"
```
Each submodule is pinned at its current commit. The superbuild's `xmotion_add_component` picks them up automatically.

**Step 5b — Relicense to Apache-2.0**
As each component repo is stood up, replace its BSD-3-Clause `LICENSE` with Apache-2.0 and add a `NOTICE` (per ADR 0001 §4.7). First-party code only — bundled third-party submodules keep their own licenses. The umbrella is already Apache-2.0.

**Step 6 — Validate (no decoupling yet)**
- Each renamed/extracted repo: fresh clone + its existing build → green.
- Umbrella: `cmake --preset default` configures and builds the assembled set (with `XMOTION_WITH_*` toggles). Note: until Phase 2, `xmNabla` still contains its own copy of common/driver, so the assembled build may have duplicate symbols if all are enabled — validate components **individually** in Phase 1; full-assembly correctness is a Phase-2 milestone after decoupling.

## Rollback

- Renames: `gh repo rename` back; redirects keep old URLs alive.
- Extractions: the new `xmsigma`/`xmmu` repos are *additive* — delete them to undo; `xmNabla` (the source) is never rewritten in Phase 1, so nothing is lost.
- Umbrella submodules: `git rm` the submodule and revert the pin commit.

## Risks & notes

- **`git filter-repo` rewrites history** on the clone it runs in — always a throwaway clone; never the canonical repo, never force-pushed back.
- **Transient duplication:** between Step 4 and Phase 2, `common`/`driver` exist both in their new repos and inside `xmNabla`. Intended and harmless as long as full-assembly builds aren't relied on until Phase 2.
- **Redirects free the old name:** after rename, the old repo name becomes claimable; rely on the redirect for the short window or place a placeholder.
- **Phase discipline:** no source decoupling, `find_package` switch, or `project()` fixes in Phase 1 — those are Phase 2, so any Phase-1 breakage is unambiguously a rename/extract issue.

## Follow-up

On sign-off, this becomes the Phase-1 checklist. Phase 2 (ADR 0001 decoupling + `find_package` + app rewiring) begins only after Phase 1 validates green per component.
