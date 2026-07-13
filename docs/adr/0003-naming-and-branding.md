# ADR 0003 — Component Naming & Branding Convention

- **Status:** Accepted
- **Date:** 2026-07-03
- **Deciders:** Ruixiang Du
- **Supersedes:** the component-naming scheme in ADR 0001 §1 (the component *architecture* and dependency model in ADR 0001 otherwise stands).

## Context

ADR 0001 named the components with Greek letters — xmSigma (Σ), xmMu (μ), xmNabla (∇), xmGamma (γ), xmKappa (κ), xmZeta (ζ). In practice this scheme fails on several axes:

- **No mnemonic.** The symbol→function mapping is arbitrary (μ→drivers, ζ→firmware), so there is nothing to remember the components *by*; even the maintainer confuses which is which.
- **Collides with domain math.** μ, τ, ∇, γ, Σ, ω, θ all denote quantities in robotics/control (torque, angular velocity, joint angle, …). A component named after a scalar used in equations is a permanent ambiguity.
- **Not typeable or greppable.** The raw glyphs are already transliterated to `xmSigma`/`xmMu` in code — the scheme does not survive a keyboard.
- **The code already disagrees with it.** Foundation targets are `xmotion-core`, `xmotion::interface`, `xmotion::logging`, `xmotion::hal` — functional names. The Greek layer is a brand skin fighting a functional substrate.
- **No rule for growth.** Adding a telemetry component exposed the absence of any naming rule, producing ad-hoc, inconsistent proposals.

This ADR replaces the Greek scheme with a single derivable convention, keeping the **XMotion** umbrella brand and the `xm` component prefix (both established and, for us, conflict-free).

## Decision

### 1. Umbrella brand

The family is **XMotion** — capital `X`, capital `M` — so the **XM** monogram reads as a unit and ties the brand to the `xm` component prefix. "Motion" indicates the domain (things that move).

Capitalization carries meaning:

- **XM / XMotion** (uppercase) — the human-facing *brand* and the logo/monogram.
- **xm** (lowercase) — the *code* prefix: namespaces, CMake targets, package names.

Same mark, two registers (brand for the eye, prefix for the keyboard).

**Do not abbreviate the family to bare "XM"** in prose or marketing. Standalone "XM" collides with SiriusXM (formerly XM Satellite Radio), the XM forex broker (xm.com), and Qualtrics "XM" (Experience Management). "XM" is a *monogram inside* the full wordmark only; the name is always **XMotion**.

### 2. Component naming rule

> **`xm` + a single, *singular*, *full* functional noun naming the domain the component governs.**

- **No abbreviations** (`xmNavigation`, not `xmNav`).
- **No plurals** (`xmDriver`, not `xmDrivers`) — the name is a *domain label*, not an inventory of contents; and most of the set are mass nouns with no plural anyway (firmware, telemetry).
- **Established domain terms win** over grammatical purity — `xmDriver` and `xmViewer` are `-er` agent-nouns, but they are the standard, unambiguous names for those layers.
- **The foundation is the sole positional name.** It has no single function word (it is a shared base of logging, IPC, math, and types), so it is named for its role: **xmBase**. This is a declared, one-time carve-out, not a pattern.
- **Greek letters are retired to logos/marks only** — never names.

### 3. Component set

| Greek (→ logo) | Component | Function | C++ namespace | Repo (current) |
|:---:|---|---|---|---|
| Σ | **xmBase** | foundation — logging · IPC · math · common types | `xmotion` (root) | xmSigma |
| μ | **xmDriver** | host hardware drivers — motor · CAN · serial · modbus · IMU · SBUS · HID | `xmotion::driver` | xmMu |
| ∇ | **xmNavigation** | planning · control · estimation · mapping | `xmotion::navigation` | xmNabla |
| γ | **xmViewer** | visualization | `xmotion::viewer` | quickviz |
| κ | **xmBoard** | PCB / electronics (KiCAD) | — (no code) | xmKappa |
| ζ | **xmFirmware** | MCU firmware (Zephyr) | `xm_…` (C prefix) | xmZeta |
| — | **xmTelemetry** | telemetry / observability (new) | `xmotion::telemetry` | (to build) |

Umbrella: **XMotion**.

Note on ∇: `xmNavigation` fits a mobile-base navigation stack. If its scope later proves broader than navigation (e.g. legged whole-body control, manipulation), it may split into `xmPlanning` / `xmControl` / `xmEstimation` under this same rule. That is a future decision, not a blocker.

### 4. Namespace rule

> **C++ namespace = `xmotion::` + the component's function word (lowercase, full, no abbreviation).**

The **foundation owns the root namespace**: xmBase's shared vocabulary lives unqualified at `xmotion::` (e.g. `xmotion::Vector3f`, `xmotion::LogLevel`), and every other component is a topic sub-namespace `xmotion::<name>`. This mirrors `std::` — the core vocabulary is at the root; areas branch off it (`std::chrono`, `std::filesystem`) — so the base owning the root is principled, the same declared carve-out as its positional name.

Non-C++ components: **xmBoard** (KiCAD) has no code namespace; **xmFirmware** (Zephyr is C) uses a C identifier prefix `xm_…`.

**Include prefix (header install directory).** The default is `xm` + function word, matching the component (`xmbase/`, `xmdriver/`). Because the include prefix is typed in every consumer file, a long function word may register a short form — the registry is authoritative, one short form per component, decided at component creation:

| Component | Include prefix |
|---|---|
| xmBase | `xmbase/` |
| xmDriver | `xmdriver/` |
| xmNavigation | `xmnav/` |
| xmMessaging (planned) | `xmmsg/` |

Everything else keeps the full word: repository names, umbrella pin paths, C++ namespaces, CMake packages/targets, and package names never abbreviate.

**Applications (the `xmApp` tier).** Applications built on the family are named `xmApp` + function word (`xmAppCamera`, `xmAppSwerveBase`). They compose *released* family components and are never pinned into the umbrella (ADR 0005). The function word names what the application is — preferring the robot *type* and tier over a robot *instance* (instances are named by configuration files, not repositories): `xmAppSwerveBase` drives any swerve base; `sbot.yaml` names the robot.

### 5. Derivation test

The scheme is consistent iff all three artifacts derive mechanically from one function word:

- name → `xm` + Word (e.g. `xmDriver`),
- namespace → `xmotion::word` (e.g. `xmotion::driver`),
- logo → Word placed on its Greek glyph.

If any of the three cannot be generated from the word, the naming is wrong. (`xmDriver` / `xmotion::driver` passes; the old `xmDriver` / `xmotion::hal` failed.)

## Migration

**Clean break — no compatibility shims.** Each repo's rename replaces the old identifiers outright: no target aliases (`xmotion::xmSigma`), no compat package configs (`find_package(xmSigma)`), no namespace forwarding (`namespace hal = driver`). A renamed component therefore breaks its dependents until they are migrated, so renames proceed **foundation-up, in lockstep**, and the umbrella Assembly CI is red during a transition *by design* — the same trade-off as the ADR-0001 / HAL clean-replace. There is no "partially migrated but green" state.

Per-repo rename checklist (everything → the new name):

- **CMake:** `project()`, the library target, the `xmotion::<name>` alias, the export set, the generated package config, and the Debian package name.
- **Headers:** the include prefix `include/xm<old>/` → `include/xm<new>/`, and every `#include "xm<old>/..."` across the repo.
- **Identifiers & assets:** `XM<OLD>_*` macros, logo files, user-facing runtime strings, and docs. Brand casing `xMotion` → `XMotion`.
- **Dependents (same wave):** `find_package(xm<old>)` → `find_package(xm<new>)`; `xmotion::xm<old>` → `xmotion::xm<new>`; `#include "xm<old>/..."` → `#include "xm<new>/..."`.

Sequence:

1. Rename the GitHub repo (old URLs redirect automatically).
2. Land the internal clean rename so the repo builds standalone.
3. Migrate the direct dependents to the new names.
4. Bump the umbrella submodule pointer(s) once the component **and** its dependents are consistent.

Human-facing brand/docs (READMEs, the component table, logos) may lead — they carry no build dependency. Historical ADRs keep the old names (records of past decisions): superseded, not rewritten.

Precedent: `xmSigma` → **xmBase** was renamed this way (foundation, done); `xmMu` → **xmDriver** and `xmNabla` → **xmNavigation** follow, then the umbrella repins.

## Consequences

- **Positive:** names are memorable, collision-free, and *derivable* (name, namespace, logo from one word); the XM/xm mark unifies brand and code; new components name themselves by the rule; the scheme survives a keyboard and a code search.
- **Cost:** a clean-break rename per repo (no compat shims), executed foundation-up; the umbrella Assembly CI is transiently red until each component and its dependents are migrated in the same wave.
- **Scope:** this ADR governs naming/branding only; the ADR 0001 component architecture, dependency direction, and polyrepo+umbrella packaging are unchanged.
