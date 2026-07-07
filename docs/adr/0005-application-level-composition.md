# ADR 0005 — Application-level composition: algorithm components carry no hardware dependencies

- Status: Accepted
- Date: 2026-07-05
- Scope: the component dependency graph — which components may depend on which, and where hardware meets algorithms
- Related: [ADR 0001](0001-component-architecture.md) (the component split); [ADR 0004](0004-telemetry-layering.md) (the same philosophy applied to the telemetry stack)

## Context

xmNavigation — the family's motion-algorithms centerpiece — depended on xmDriver through a small hardware-composition layer: actuator groups (fan-out of motor commands) and robot assemblies (kinematics wired to actuators), plus a ROS application wrapper. The dependency was structurally thin (a handful of files) but architecturally heavy: it dragged the full hardware dependency set (serial/CAN/Modbus/input stacks) into every consumer of the planning and estimation libraries, coupled the algorithm release cycle to the driver release cycle, and left no principled home for "the robot" — each assembly hard-wired one composition into a library.

Meanwhile the planning core (~48k LOC), the estimators, the control laws, and the kinematics were already hardware-free. The dependency existed to serve glue, not algorithms.

## Decision

**Algorithm components depend on xmBase only. Hardware components depend on xmBase only. Only applications combine them — and the family maintains library components, not applications.**

1. **xmNavigation is algorithm-centric**: planning, estimation, control laws (PID, models, FSM), kinematics, mapping, and common utilities. Its dependency set is xmBase plus mathematical libraries. This is enforced, not aspirational: its CI asserts the absence of any hardware component from its build.
2. **Hardware composition lives with the hardware**: generic device compositions (e.g. actuator groups — fan-out of capability-typed motor references) belong to xmDriver, next to the HAL they compose.
3. **Robot assemblies are application code**: wiring kinematics (navigation) to actuator groups (driver), constructing devices from configuration, binding a telemetry backend, bridging to middleware (ROS) — all of it belongs to the application that owns the robot. The family repositories do not maintain applications; an umbrella `apps/` tree was considered and rejected because it would simply relocate the coupling into the umbrella.
4. **The family ships the pattern, not the glue**: the composition and middleware-bridge patterns are preserved as reviewed reference documentation (compile-checked snippets in the component docs), so an application author starts from a known-good shape without the family maintaining runnable app code.

This mirrors ADR 0004 one level up: there, components instrument against a stateless API and applications choose the machinery; here, components implement algorithms or hardware against the shared foundation, and applications choose the combination.

### Dependency classes (clarification, 2026-07)

The rule above constrains the **deployment closure** — what a robot links at runtime. Its rationale (consumers paying for stacks they don't use; behavior-critical layers entangling release cycles) applies to runtime dependencies only. Two classes are therefore distinguished:

1. **Runtime dependencies**: the deployment closure of an algorithm or hardware component is **xmBase plus mathematical libraries, nothing else**. Unchanged, strict, CI-enforced.
2. **Development-support dependencies**: components *may* depend on family components whose purpose is supporting development — visualization, simulation tooling, test infrastructure — provided the dependency is **always optional (build-gated) and provably absent from the deployment closure**. These support components exist so that domain components can see themselves during development; forbidding the dependency would invert their purpose.

**xmViewer** (quickviz) is the first registered development-support component: xmNavigation consumes its rendering primitives in the visualization-gated modules and demos. The division of labor is deliberate: the *drawers of a component's types live with that component* (they evolve with the algorithms); the support component stays domain-agnostic (canvases, windows, GUI primitives). Deployment builds are verified render-free the same way they are verified hardware-free.

## Alternatives considered

- **Keep the composition layer in xmNavigation** (status quo) — rejected: hardware dependencies in the algorithms component, coupled release cycles, and consumers paying for stacks they never use.
- **An `apps/` tree in the umbrella** — rejected: the umbrella superbuild would itself become the hardware+algorithms dependent, recreating the coupling one level up.
- **A dedicated applications component repo** — deferred, not rejected: if reference applications multiply, they can get a home then; today it would be a repo maintaining glue.
- **Navigation-owned abstract actuator interfaces (dependency inversion)** — rejected as unnecessary: the composition layer was small enough to relocate outright, and the HAL's capability mixins already are the right abstraction.

## Consequences

- xmNavigation's bundled xmDriver snapshot (and its nested foundation copy) is deleted with no replacement; its bundled foundation re-pins to the released xmBase. ADR 0002's Phase-2 decoupling closes.
- Actuator groups move to xmDriver and are rewritten natively against the capability-mixin HAL (typed units, `Status`/`Result` error semantics, per-repo instrumentation conventions).
- The robot assemblies and the ROS estimation wrapper are removed; their patterns move to documentation. Existing behavior relied upon by applications must be reconstructed application-side from the documented pattern.
- Assembly CI proves compile-level integration of the components; behavioral composition correctness is owned by applications by design.
- Component builds get lighter and more parallel: navigation consumers no longer install hardware libraries; driver consumers no longer see algorithm code.
