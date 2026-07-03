# Lessons

Cross-cutting lessons for the XMotion polyrepo + umbrella. One entry per recurring mistake; keep concrete.

### `git submodule update` resets manual submodule checkouts
- **Pattern:** In a coordinated multi-repo change I pointed a bundled/umbrella submodule at an *unmerged* feature commit with `git -C <sub> checkout <sha>`, then ran `git submodule update --init --recursive` at the parent to fetch nested deps. `git submodule update` reset the submodule back to the **recorded** pin (the old commit), silently undoing the checkout — so the next commit/build used the wrong submodule. Hit twice in one session: once validating the umbrella assembly, once bumping xmMu's bundled xmSigma (which committed a wrong pin and needed an `--amend` + force-push).
- **Correction:** Never run `git submodule update` at the parent after manually checking out a submodule to a non-pinned commit. To initialize that submodule's *own* nested deps, run the update from **inside** it (`git -C <sub> submodule update --init --recursive`); to init sibling submodules, pass their explicit paths (excluding the manually-set one). Always verify the pin right before committing: `git ls-tree HEAD <sub>` (staged SHA) and `git -C <sub> rev-parse HEAD` must match the intended commit. A bump commit that stages fewer paths than expected (e.g. source edits but no submodule) is the tell.
- **Context:** git submodules; coordinated polyrepo + umbrella refactors where downstream repos pin unmerged upstream commits.

### Merge (don't squash) when a downstream repo pins an upstream commit
- **Pattern:** Squash-merging a component PR replaces its branch commits with a new squashed SHA on the target branch; any other repo that pinned one of the original commits (a bundled submodule) is left pointing at a commit no longer on any branch.
- **Correction:** Use real merge commits for coordinated component PRs, and merge in dependency order (Σ → μ → ∇ → umbrella) so each downstream pin resolves against an already-landed upstream. Re-pin the umbrella to the merged HEADs afterward.
- **Context:** polyrepo + umbrella; submodule SHA pins.

### DEV_MODE ≠ BUILD_TESTING in superbuilds
- **Pattern:** `XMOTION_DEV_MODE=ON` forces tests in *every* bundled component, so several bundled deps each `add_subdirectory(googletest)` and clash on the `gtest` target; it also exercises the bundled-spdlog export path. Regular CI uses `BUILD_TESTING=ON` (bundled siblings added as test-less modules) + system spdlog, so neither fires.
- **Correction:** Guard bundled `add_subdirectory(googletest)` with `if(NOT TARGET gtest)`. Keep `install(EXPORT)` consistent with the link: if a bundled lib (spdlog) is linked, it must travel in the same export set. Don't assume a green CI exercised the DEV_MODE superbuild path.
- **Context:** CMake superbuilds; bundled googletest/spdlog.
