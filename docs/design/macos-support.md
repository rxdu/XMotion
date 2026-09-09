# xMotion on native macOS (arm64)

Every component except xmDriver builds and tests natively on macOS on Apple Silicon, with no compile flags and no header shims. Each portable component carries a `macos-14` CI lane, and the umbrella assembles the non-driver set there.

Verified on macOS 15 / arm64 with AppleClang, libc++ and Homebrew.

## Build

`eigen@3` and `opencv@4` are keg-only because Homebrew now defaults to Eigen 5 and OpenCV 5, and this project targets the 3.x and 4.x APIs. Those two prefixes are the only arguments that are not plain component toggles — they select between installed versions rather than working around anything.

```bash
brew install cmake pkg-config abseil re2 boost glfw cairo fontconfig \
             googletest glm pcl eigen@3 opencv@4
components/simulator/scripts/setup/fetch_mujoco.sh

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DXMOTION_WITH_DRIVER=OFF \
  -DXMOTION_WITH_TELEMETRY=ON -DXMOTION_WITH_NAVIGATION=ON \
  -DXMOTION_WITH_VIEWER=ON -DXMOTION_WITH_MESSAGING=ON \
  -DXMOTION_WITH_SIMULATOR=ON \
  -DXMSIM_MUJOCO_DIR="$PWD/components/simulator/third_party/mujoco" \
  -DCMAKE_PREFIX_PATH="$(brew --prefix eigen@3);$(brew --prefix opencv@4)"
cmake --build build -j"$(sysctl -n hw.ncpu)"
```

`XMSIM_MUJOCO_DIR` must be passed explicitly under the umbrella: its default resolves against `CMAKE_SOURCE_DIR`, which under `add_subdirectory` is the umbrella root rather than the simulator's own. That is pre-existing and not macOS-specific.

## Test results

Standalone runs with each component's own CI flags:

| Component | Tests | Notes |
|---|---|---|
| xmBase | 86 / 86 | with `XMOTION_WERROR=ON` |
| xmTelemetry | 72 / 72 | with `XMOTION_WERROR=ON` |
| xmNavigation | 118 / 118 | 204 / 204 with `XMOTION_DEV_MODE=ON` |
| xmViewer | 123 / 123 | GUI itself unexercised — see Known gaps |
| xmMessaging | 44 / 44 | with `XMMESSAGING_WERROR=ON` |
| xmSimulator | 16 / 16 | camera sensor unavailable — see below |
| xmDriver | — | not supported |

## Not supported, and why

**xmDriver.** It binds kernel interfaces with no macOS equivalent: `<linux/can.h>` (SocketCAN) in `async_can.hpp:26` and `detail/socketcan_frame.hpp:20`, `<linux/serial.h>` in `async_serial.cpp:13`, and libevdev over `/dev/input/event*` in `src/devices/input_hid/`. Supporting these means a driver port, not a build fix. Nothing else depends on xmDriver — the only references to it in other components' CMake are comments — so `-DXMOTION_WITH_DRIVER=OFF` costs the hardware layer and nothing else. It deliberately has no macOS CI lane.

**xmSimulator's camera sensor.** It needs EGL (`src/camera/camera.cpp:13`), which macOS does not provide. The existing `find_library` guard already degrades cleanly, reporting *"camera DISABLED — EGL not found (lidar still built)"*. Physics, dynamics, lidar and scan patterns are unaffected. A headless-GL port over CGL or Metal is possible but is a project rather than a fix.

**Five `AllocationTest` cases in xmNavigation.** They assert that hot paths allocate nothing, which needs glibc malloc interposition. macOS uses libSystem malloc, so the test detects the situation and skips with a stated reason rather than failing. Supporting it means writing a Darwin malloc-zone interposer.

## MPPI sampling is now reproducible across toolchains

`std::normal_distribution` is not specified to produce any particular sequence. libstdc++ and libc++ turned the same `std::mt19937_64` stream into different normals, so MPPI explored a different rollout set depending on the standard library: a seed was reproducible on one platform only, and a tolerance-based integration test could not be tuned once and trusted elsewhere.

The engine was never the problem — `mt19937_64` is fully specified — so only the transform needed pinning. `PortableNormal` (`xmnav/mppi/portable_normal.hpp`) maps the top 53 bits of each draw onto `[0, 1)` exactly and applies Box-Muller, and backs all four samplers. The quadrotor integration test's own disturbance injection had the same flaw and uses it too.

This changed the sample stream on **every** platform, Linux included — the draws are different numbers, not a reordering. Nothing had been tuned to the old stream and the full suite passes unchanged, but it is the part of this work most worth knowing about.

Confirmed by measurement rather than assertion. The same 128-sample rollout now yields:

| Toolchain | Final position error |
|---|---|
| macOS / AppleClang / libc++ | `0.37119544195691168` |
| Linux / GCC / libstdc++ | `0.37119544195691295` |

Identical to 13 significant figures — about `1e-15`, ordinary last-ulp noise.

`test_portable_normal` pins the guarantee so it cannot regress silently: `mt19937_64`'s standard-mandated 10000th value, a golden 8-draw stream, per-seed repeatability, `reset()` semantics, and N(0,1) moments over 200k draws so determinism cannot be faked by returning a constant. The golden stream is compared to `1e-12` rather than exactly, because libm's `sqrt`/`log`/`sin`/`cos` are not required to be correctly rounded and two C libraries may differ in the last ulp.

## What changed, by component

Several of these were latent bugs that Linux masked rather than macOS-specific work, and they make the Linux build more correct too. Those are marked **(latent)**.

**xmBase.** `-Wno-error=maybe-uninitialized` names a GCC-only diagnostic, and Clang rejects unknown warning options outright, which under `-Werror` failed the build before compiling anything; it is now gated on the compiler. Two private fields are read only from paths that do not always compile — `EventCount::shared_` on the Linux futex branch, `RegionStorage::size_` by an assert that compiles out under `NDEBUG` — and are now referenced explicitly rather than annotated.

**xmTelemetry.** The library was already portable: it detects the unavailable black box and logs *"falling back to the heap channel"*. The test harness was not. `SpawnScenarioChild` re-exec'd through `/proc/self/exe`, so every scenario child died at exec; it now asks dyld on macOS, resolved before `fork()` since only async-signal-safe calls are legal after it. `TempBlackBoxPath` hardcoded `/dev/shm` and now falls back to `TMPDIR`. `ForkS8` exec'd `/bin/true`, which is `/usr/bin/true` on macOS, and now relies on `PATH`. `ChurnS9` compared `getrusage`'s `ru_maxrss` against a kilobyte budget, but Darwin reports **bytes** and Linux **kilobytes**.

**xmViewer.** `object_feedback_handler.hpp` included `<GL/gl.h>` unguarded, unlike the two files that already selected glad. glad's vendored `khrplatform.h` sat in `include/glad/`, so `<KHR/khrplatform.h>` resolved on Linux only because Mesa happens to install one — moving it to `include/KHR/` removes that undeclared system dependency **(latent)**. glm was never referenced in CMake at all, resolving implicitly from `/usr/include` **(latent)**; it now uses `find_package(glm)` and defines `GLM_ENABLE_EXPERIMENTAL`, which glm ≥ 1.0 requires for the GTX extensions the renderables use.

The PCL loader treated a load as successful whenever PCL did not return `-1`, but PCL 1.15 parses a malformed file into a zero-point cloud and returns success, so garbage loaded silently **(latent — Ubuntu ships PCL 1.12/1.14 and will hit this on its next bump)**. It now validates the header, keyed on the declared `x`/`y`/`z` fields rather than the point count, because a malformed file and a legitimately empty one both yield zero points.

**xmNavigation.** `MotionPrimitive` declared a virtual `Evaluate()` with `StateLattice` deriving from it, but a non-virtual destructor, so destroying a derived object through a base handle was undefined behaviour; Clang's `-Wdelete-non-abstract-non-virtual-dtor` caught what GCC does not report **(latent)**. `boost/numeric/odeint.hpp` was found only because Debian puts Boost in `/usr/include`; three targets now link `Boost::headers` **(latent)**. `quadprog++` was missing from the vendored-SYSTEM list, so its headers gated first-party translation units. `map_processing` added PCL's include directories non-SYSTEM, which let them precede the project's own and shadow the vendored googletest headers while the vendored library still linked — an ABI mismatch visible only as undefined `testing::internal` symbols.

**xmSimulator.** MuJoCo ships macOS as a `.dmg` holding `mujoco.framework` rather than the `include/` + `lib/` tarball, so the fetch script mounts it and remaps the layout, then re-signs ad-hoc because `install_name_tool` invalidates the signature and arm64 refuses to load an unsigned dylib. `CMakeLists.txt` linked `libmujoco.so` unconditionally.

**xmMessaging.** The M8-A3 dependency-closure gate shelled out to `ldd`, so on macOS the test failed on the missing tool rather than on the closure — the gate was not being evaluated at all. It now uses `otool -L`, whose output the existing substring check handles identically.

### Why the Debian include prefixes were kept

The sources include `<eigen3/Eigen/...>` and `<opencv4/opencv2/...>`, which resolve out of the box only where those directories sit directly in `/usr/include`. Rewriting them to plain `<Eigen/...>` is the conventional fix and was tried across all 45 files, then reverted: Homebrew's PCL depends on Eigen 5 while this project builds against `eigen@3`, and an unprefixed `<Eigen/Core>` binds to whichever tree lands on the path first, mixing two Eigen trees in one translation unit and producing redefinition errors throughout Eigen's internals. The prefix makes the include unambiguous, so it is load-bearing wherever a second Eigen is installed. The parent directory is derived from each package's own include directory in CMake instead.

## Notes for anyone porting further

Things the macOS lanes surfaced that local runs and the Ubuntu lanes did not:

- `[[maybe_unused]]` on a non-static data member silences Clang but **GCC ignores it and warns `-Wattributes`**, which `-Werror` makes fatal. Reference the field, or delete it.
- `gtest_discover_tests` enumerates cases by running each test binary at build time with a 5-second timeout, and **deletes the executable** when that is exceeded — surfacing much later as a confusing `<target>_NOT_BUILT` failure. Binaries linking PCL/OpenCV take about 73 seconds to start under Homebrew's ~158 dylibs. Use `PRE_TEST` discovery.
- The hosted macOS runner is headless, and unlike Linux, GLFW initialises fine there (Cocoa is always present) and fails only later at window creation, so a GUI test aborts rather than degrading. Benchmarks are excluded from the viewer's macOS lane for this reason.
- Timing assertions with tight upper bounds fail on loaded runners. `ThreadSafeQueueTest.PopTimeout` required a 50 ms wait to return within 100 ms and measured 143 ms; that is a claim about OS scheduling, not about the queue.

## Known gaps

- **xmViewer's GUI is unexercised.** There is no automated suite for it and the samples need a display, so only compilation and the non-GUI tests are covered.
- **xmViewer's `PCLLoaderTest` fixture shares a temp directory**, so it races under `ctest -j` — 9 failures in parallel against 0 serial. Both the macOS and Ubuntu lanes run ctest serially, so it is latent on Linux too.
- **xmTelemetry is private**, so its macOS lane cannot be observed without repository access.
