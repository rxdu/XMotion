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

# -- Options ----------------------------------------------------------------
# xmBase (foundation) is always built. The rest are opt-in so a consumer only
# pays for the dependency footprint it actually needs.
option(XMOTION_WITH_DRIVER    "Build xmDriver (host hardware drivers)"   ON)
option(XMOTION_WITH_NAVIGATION "Build xmNavigation (motion algorithms)"    ON)
option(XMOTION_WITH_VIEWER "Build xmViewer (visualization)"        OFF)
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
xmotion_add_component(xmBase components/sigma)

if(XMOTION_WITH_DRIVER)
  xmotion_add_component(xmDriver components/mu)
endif()

if(XMOTION_WITH_NAVIGATION)
  xmotion_add_component(xmNavigation components/nabla)
endif()

if(XMOTION_WITH_VIEWER)
  xmotion_add_component(xmViewer components/gamma)
endif()

message(STATUS "xMotion ${PROJECT_VERSION}: configured "
               "(DRIVER=${XMOTION_WITH_DRIVER} NAVIGATION=${XMOTION_WITH_NAVIGATION} "
               "VIEWER=${XMOTION_WITH_VIEWER})")
