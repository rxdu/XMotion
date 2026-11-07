# ADR 0008 — xmGymnasium: the training plane — where the family trains and measures policies

- Status: **Proposed** (name and charter decided with the owner on 2026-11-07; the open questions at the end need answers before the repository is created)
- Date: 2026-11-07
- Scope: where the family trains, measures and iterates learned policies; the component's name, class, charter and boundaries; its boundary with xmSimulator; what moves there, and when the on-robot half lifts into the family
- Related: [ADR 0003](0003-naming-and-branding.md) (naming derivation); [ADR 0005](0005-application-level-composition.md) (dependency classes); [ADR 0007](0007-module-placement.md) (charters and gates); [ROADMAP](../../ROADMAP.md) (the four-question test); xmAppLeggedController [ADR-0011](https://github.com/rxdu/xmAppLeggedController/blob/main/docs/adr/0011-learned-policy-artifact-and-inference.md) (private — the learned-policy contract this plane produces for)

## Context

What exists, verified on 2026-11-07 by reading the repositories:

- The legged application's ADR-0011 (accepted 2026-10-04) runs trained policies behind its controller seam: a policy artifact under a contract the application owns, allocation-free in-process MLP inference, and conformance vectors as the acceptance test. Its Phase L has the runtime half built through L3. The producer half P1–P3 is done; **P4, a converged Go2 flat-terrain policy, is open**.
- The producer code — contract export, conformance exporter, the Go2 velocity task — lives in the owner's fork of a vendor's upstream (`unitree_rl_mjlab`, mjlab 1.2.0 + rsl_rl 5.0.1, on MuJoCo Warp). ADR-0011 records why planning cannot live there: the fork's `main` mirrors someone else's project. Producer planning therefore sits in the private application's `TODO.md`. That is a workaround, not a home.
- The application's extraction ledger lists the MLP evaluator as a family candidate with home *"undecided — no family library hosts learned components yet"*, gated on a second consumer.
- xmSimulator is one CPU MuJoCo world stepped from C++ by the application, with sensors and actuator-dynamics models, host-x86 only. Applications use it to run their real autonomy software against a plant. The legged application's MuJoCo backend is built on it, and its L6 run (a trained policy walking inside the real controller) is an xmSimulator run.
- xmNavigation holds the pieces of a hardware-free second consumer: a deterministic simulation loop whose agent callback is any `f(state, tick) → control`, benchmark models, MPPI with CUDA rollout backends as a possible expert, and a validation tier with integration and nightly campaign labels.
- **Nothing in the family trains a policy, and nothing measures one.** mjlab trains and plays, in a fork. Everywhere else the family's differentiator is the measured, regression-gated claim ([observability budget](../design/observability-budget.md)); learned components have none.

The request that opened this ADR: a setup to *train, measure, evaluate and iterate* AI policies for robots.

## Decision

### 1. A new component: xmGymnasium

**xmGymnasium is the family's training plane.** It trains policies and measures them in their training environments, and it exports the artifacts the family's applications run.

Class: **development-support** (ADR 0005, class 2). Python, GPU, host x86 only. It is never in a deployment closure and no family C++ target links it. Its outputs are **artifacts** under a contract and **run records** — the producer/consumer vocabulary of ADR-0011. *Policy* means what ADR-0011 means by it: the learned artifact and the controller that runs it.

### 2. The two simulations

The family has two simulation components. They differ in job and in engine, and neither replaces the other.

| | xmSimulator | xmGymnasium |
|---|---|---|
| Job | **Verification of the autonomy software**: the application's real C++ stack runs against a plant, with or without a policy inside | **Training and training-side measurement of policies** |
| Engine | one CPU MuJoCo world, stepped from C++ by the application | thousands of GPU-batched environments, driven from Python (mjlab on MuJoCo Warp) |
| Who steps it | the application | the training framework |
| Deploys | never (host x86) | never (host x86) |

What crosses the boundary is the **policy artifact** and its **conformance vectors**, both under the consumer's contract (§5). The two sides load *different* models on purpose: ADR-0011 D7 keeps the application's MJCF apart from the training MJCF so that a policy surviving the gap is evidence, not construction. The gap between the two simulations — engine and model — is the family's first sim-to-sim transfer, and the consumer's L6 run on xmSimulator is where it is measured.

Scoring the deployed software is therefore verification and belongs to the application on xmSimulator, not to xmGymnasium.

### 3. Name derivation (ADR 0003)

- **Name:** `xmGymnasium`. "Gymnasium" is a venue noun, not a function noun, so it enters under ADR 0003's clause that an **established domain term wins** — the clause that admitted Driver and Viewer — and here the clause applies with full weight: in reinforcement learning the gym is, by definition, where agents train, a meaning fixed by OpenAI Gym and carried by its successor, Farama Gymnasium. The owner's reason for the choice: it best describes what the component does. The word is the full one; `xmGym` would be an abbreviation.
- **Namespace:** `xmotion.gymnasium` is the mechanical derivation. Python import, distribution and command-line name: `xmgym` — the registered short form, the analogue of ADR 0003's include-prefix registry (`xmnav`, `xmmsg`). Repository name, namespace and docs keep the full word.
- **Logo:** "Gymnasium" on a free Greek glyph, chosen with the icon. Σ τ μ ∇ γ π κ ζ Ψ are taken by components and Ξ by the family mark.
- **The one cost, accepted:** "Gymnasium" is also the name of a specific library and its environment interface. A reader may expect its `make` call to work on this component's tasks. **xmGymnasium is the family's gym in the generic sense and does not implement that interface unless a consumer asks for it** — the stance the family takes with ROS (a bridge, not a backend). There is no collision inside the component's own code: the training framework declares no dependency on the `gymnasium` package, and neither it nor the fork imports it (verified 2026-11-07 on the local mjlab checkout). Family docs refer to the library as *Farama Gymnasium* or the `gymnasium` package, never as "Gymnasium" alone.
- **Vocabulary reservation:** in this family *gym* and *gymnasium* mean this component. The words occur in the family today only in the legged application's research notes, naming the external frameworks Isaac Gym and legged_gym (grep across xmBase, xmMessaging, xmNavigation, xmTelemetry, the umbrella docs and the legged application, 2026-11-07). The residual ambiguity — in German, Dutch and Scandinavian usage a Gymnasium is a secondary school for people — is judged smaller than the one that rejected Learning (below): the family already uses *learning* for the owner's own path; it does not use *gymnasium* for anything.

### 4. Charter

Following ADR 0007, the charter says what belongs here eventually; the gates below say when it is built.

**Belongs:**

- **Training pipelines** — today RL through mjlab + rsl_rl; foreseen: behaviour cloning or DAgger with xmNavigation's MPPI as the expert. Tasks, randomization and curricula per platform.
- **Training-side measurement** — held-out scenario suites run in the training environment: a scenario's initial conditions, commands, perturbations and termination; its metrics (tracking error, fall rate, episode length, command-range coverage); its pass/fail thresholds. The same scenario-suite-as-executable-spec pattern the telemetry S-, messaging M- and shield S-suites use.
- **Run records and comparison** — per run the provenance the engineering preferences require: seed, resolved config, data version, commit; runs comparable across time and across checkpoints; regression gates on metrics, the way bench gates work on latency.
- **Export** — the policy artifact and conformance vectors under the consumer's contract (§5).

**Never:**

- Verification of the autonomy software. That is the application's job on xmSimulator (§2).
- A runtime inference engine, or anything that ships on a robot (§5).
- Robot descriptions and robot configuration. They stay with the application that owns the robot (ADR 0005); xmGymnasium carries its own training MJCF and references the application's as the deliberately different one.
- Ownership of the policy contract while a single consumer exists (§5).
- The physics. The training engine is the framework's; xmGymnasium configures, trains and scores.

### 5. The on-robot half and the contract

ADR-0011 D1 stands: **the consumer owns the contract while it is the only consumer.** The MLP evaluator and the contract loader stay in the legged application.

**Lift trigger:** a second consumer. The first candidate is xmNavigation's simulation loop running an exported artifact as its agent. When the trigger fires, the contract specification, the loader and the evaluator move to xmNavigation under `control/`, beside PID and MPPI — a learned controller is a control law, and the units and frames it needs are navigation's vocabulary. The legged ADR-0011 D1 is then superseded on its side. xmGymnasium conforms to the contract as a producer wherever the contract lives.

*Rejected:* a component of its own for the runtime half. A header-only Eigen evaluator and a YAML loader do not earn a repository, a release cycle and a Debian package.

### 6. Scope of v1 and the done condition

**v1 is RL policies for the legged consumer.**

**Done condition, measured and falsifiable:** from a clean checkout, one command reproduces P4 — a converged Go2 flat-terrain policy — and writes its run record; the exported artifact passes the legged application's L4 conformance test and walks in its L6 run on xmSimulator.

**Second milestone, hardware-free:** MPPI as expert → cloned policy → the policy running as the agent in xmNavigation's simulation loop, scored against the expert. This is the second consumer of §5.

### 7. The four-question test (ROADMAP operating rule)

- **Which gap does it close?** ADR-0011 P4 is open; the ledger records no family home for learned components; no learned component has a measured claim.
- **Who is the named consumer?** xmAppLeggedController, Phase L (L4, L6).
- **What measured claim proves it done?** §6.
- **Is it the smallest step that retires the largest unknown?** The unknown is whether a policy trained on one engine and model survives the consumer's different engine and model (§2). P4 plus L6 retire it with no hardware.
- **Lane:** not on the swervebot milestone path. It runs in the portfolio's parallel share and queues behind nothing on the swervebot roadmap.

## Alternatives considered

**Names** — each checked against ADR 0003 and against words the family already uses:

- **xmArena** — the name first chosen in this discussion, when the charter was evaluation-centred: established through Isaac Lab-Arena and LMArena for *policy evaluation*. Rejected once the charter became training: an arena is where trained contestants compete, and a reader primed by Isaac Lab-Arena would expect an evaluation framework and find a training one.
- **xmTrainer** — the rule-pure name for a training plane in the Driver/Viewer agent-noun form, established through the Trainer classes of ML tooling. Not chosen; recorded as the fallback.
- **xmTraining** — the literal function noun, but "XMotion training" reads as a course for people before it reads as model training. Rejected.
- **xmLearning** — the domain noun, and the closest contender on ADR 0003 grounds. Rejected because the word already means the *owner's* learning in this family: the legged application describes itself as a learn-by-doing path and its roadmap as a learning process, and every repository carries a `LESSONS.md`. "Robot learning" and "my learning" would share one word.
- **xmEvaluation** — the literal noun for the measuring half only; excludes training. Rejected.
- **xmDojo** — the strongest training metaphor without an established domain use; its case rests on one vendor's product name. **xmPlayground** — established through MuJoCo Playground, but names an environment suite and reads as a sandbox. **xmLaboratory** — established through Isaac Lab and mjlab, but heavy in every path. **xmFoundry** — established for model building, but reads as fabrication beside xmBoard. **xmGym, xmLab** — abbreviations. All rejected.
- **Collisions, rejected outright:** Bench and Benchmark (`bench/`, the bench harness, xmAppBotBench); Validation (navigation's validation tier and ladder); Replay (deterministic replay); Scenario and Harness (the method every suite uses); Critic (MPPI cost terms); Oracle (cross-implementation checks); Lesson (`LESSONS.md`); Incubator (ADR 0007); Teacher (the privileged policy inside distillation); Policy (learned artifact, recovery policy, QoS); Agent (the simulation loop's callback, an RL agent, an LLM agent); Cortex (ARM); Ring (ring buffers); Drill (PCB drill files); Plant (the control-theory plant); Stable (stability); Ground (ground truth); Factory (the motor factory seam).

**Structure:**

- **Keep the producers in the fork** — rejected for ADR-0011's reasons: a vendor's upstream, and no home for planning.
- **Train inside xmSimulator** — rejected: one CPU world stepped from C++ is the wrong engine for training, and giving xmSimulator a GPU Python stack would break the clean C++ surface its consumers link.
- **An `xmApp`** — rejected: applications are per-robot-type compositions; this is cross-robot infrastructure.
- **Two components, training and evaluation** — deferred: one consumer, walking skeleton first. Recorded as the obvious split if one ever happens.
- **One repository spanning the C++ runtime and the Python training stack** — rejected: a deployable library stays cheap to link and ships as one release and one Debian package; a GPU Python stack cannot share that release unit.
- **Adopt Isaac Lab-Arena for the measuring half** — rejected: it extends Isaac Lab, so it scores in Isaac Sim, while the family trains in MuJoCo and verifies on xmSimulator; it would add a second physics stack solely to score, and it is pre-alpha.

## Consequences

- A new repository, `rxdu/xmGymnasium`, import and command-line name `xmgym`, on the Python engineering preferences (typed config, Makefile verbs, pinned tooling, run records). The Python floor is set by mjlab's requirement — to verify.
- The producer code moves out of the fork: the P1 artifact export, the P2 conformance exporter and the P3 randomized Go2 task configuration, registered with mjlab through its `mjlab.tasks` entry-point group (open question 4). The fork returns to tracking upstream.
- The legged application's `TODO.md` Phase L *Producer side* section points at xmGymnasium's `TODO.md` once the repository exists; ADR-0011's planning-location amendment is revisited together with open question 1.
- Umbrella: a README component row, an icon and glyph, a row in ADR 0003's component-set table and in its short-form registry (`xmgym`), and a `TODO.md` *Next arc* entry (added with this ADR). The rest follows the repository.
- Vocabulary: *gym* and *gymnasium* reserved (§3). xmSimulator's README gains one sentence pointing at §2 for the boundary.
- **Not built by this ADR:** the agentic track (open question 7), the lift of the runtime half into xmNavigation (§5), a second producer repository, a Farama Gymnasium interface, and any shared scenario-definition format between the two simulations.

## Open questions

1. **Visibility.** Public like the library components, or private like xmTelemetry and the applications? ADR-0011's amendment moved producer planning to the private side; a public xmGymnasium reverses that for the producer half. Owner decision.
2. **Environment.** The engineering preferences require a project to state venv or conda. Torch ships CUDA wheels; the deciding fact is whether mjlab, MuJoCo Warp or EGL need conda-forge binaries. Check before creating the repository.
3. **Confirm §5:** xmNavigation `control/` as the eventual home of the evaluator and contract loader.
4. ~~**mjlab out-of-tree tasks.** Whether mjlab registers tasks from an external package is unverified.~~ — **resolved 2026-11-07**: mjlab auto-discovers external packages through the `mjlab.tasks` entry-point group (`mjlab/__init__.py`) and each package registers its tasks with `register_mjlab_task`; the fork already registers its tasks this way. Verified on the local mjlab checkout dated 2026-10-12. Residual: confirm the mechanism exists in the mjlab version the component pins (the fork pins 1.2.0).
5. **Umbrella pinning.** xmSimulator is pinned as a submodule although the superbuild is CMake-only; xmGymnasium has no CMake. Pin it for the known-good combination, or list it without a pin?
6. **The glyph.**
7. **The agentic track.** The original request included agentic workflows (task-level agents driven by language or vision-language models). Under §2 the work splits: fine-tuning or benchmarking an agent model is training and fits xmGymnasium; iterating a workflow against the robot's skills is verifying autonomy software and fits the application on xmSimulator. Both wait on a robot-side skill interface over xmMessaging, which nothing exposes today. Recommendation: decide when that interface exists, not before.
