cmake_minimum_required(VERSION 3.16)
project(xMotion VERSION 0.1.0 LANGUAGES CXX)

# ---------------------------------------------------------------------------
# xMotion superbuild
#
# This umbrella assembles the xMotion software components, each maintained in
# its own repository and vendored here as a git submodule under components/,
# pinned to an exact commit. Every component also builds standalone; this
# superbuild simply configures a known-good combination together.
#
# Components are added only when their submodule is present, so the umbrella
# configures cleanly before the submodules are wired (see docs/adr/0002).
# ---------------------------------------------------------------------------

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# -- Output layout ------------------------------------------------------------
# The assembly follows the family bin/lib placement convention: every
# executable lands in build/bin and every library in build/lib, regardless
# of which component produced it. Guarded so a parent project embedding
# this superbuild keeps its own layout. Components that already anchor
# their outputs to CMAKE_BINARY_DIR (driver, navigation) align with this
# automatically; the rest inherit it.
if(NOT CMAKE_RUNTIME_OUTPUT_DIRECTORY)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()
if(NOT CMAKE_LIBRARY_OUTPUT_DIRECTORY)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()
if(NOT CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()

# -- Options ----------------------------------------------------------------
# xmBase (foundation) is always built. The rest are opt-in so a consumer only
# pays for the dependency footprint it actually needs.
option(XMOTION_WITH_TELEMETRY "Build xmTelemetry (observability SDK)"    ON)
option(XMOTION_WITH_DRIVER    "Build xmDriver (host hardware drivers)"   ON)
option(XMOTION_WITH_NAVIGATION "Build xmNavigation (motion algorithms)"    ON)
option(XMOTION_WITH_VIEWER "Build xmViewer (visualization)"        OFF)
option(XMOTION_WITH_MESSAGING "Build xmMessaging (communication layer)" OFF)
option(XMOTION_WITH_SIMULATOR "Build xmSimulator (physics simulation)"  OFF)
option(BUILD_TESTING      "Build component tests"                OFF)

# -- Helper: add a component submodule if it is present ---------------------
function(xmotion_add_component name dir)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${dir}/CMakeLists.txt")
    message(STATUS "xMotion: adding component '${name}' (${dir})")
    add_subdirectory(${dir})
  else()
    message(STATUS "xMotion: component '${name}' not present yet — skipping "
                   "(run: git submodule update --init ${dir})")
  endif()
endfunction()

# -- Assemble (dependency order: foundation first) --------------------------
xmotion_add_component(xmBase components/base)

if(XMOTION_WITH_TELEMETRY)
  xmotion_add_component(xmTelemetry components/telemetry)
endif()

if(XMOTION_WITH_DRIVER)
  xmotion_add_component(xmDriver components/driver)
endif()

if(XMOTION_WITH_NAVIGATION)
  xmotion_add_component(xmNavigation components/navigation)
endif()

if(XMOTION_WITH_VIEWER)
  xmotion_add_component(xmViewer components/viewer)
endif()

# xmMessaging (ADR 0006): v0.1.0 — in-process + POSIX-shm reaches. Default
# OFF until an umbrella consumer composes with it.
if(XMOTION_WITH_MESSAGING)
  xmotion_add_component(xmMessaging components/messaging)
endif()

# xmSimulator: MuJoCo-backed physics simulation (world · sensors · dynamics).
# Default OFF — it pulls the MuJoCo dependency; opt-in for apps that simulate.
if(XMOTION_WITH_SIMULATOR)
  xmotion_add_component(xmSimulator components/simulator)
endif()

message(STATUS "xMotion ${PROJECT_VERSION}: configured "
               "(TELEMETRY=${XMOTION_WITH_TELEMETRY} DRIVER=${XMOTION_WITH_DRIVER} "
               "NAVIGATION=${XMOTION_WITH_NAVIGATION} VIEWER=${XMOTION_WITH_VIEWER} "
               "MESSAGING=${XMOTION_WITH_MESSAGING} SIMULATOR=${XMOTION_WITH_SIMULATOR})")
