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
# xmSigma (foundation) is always built. The rest are opt-in so a consumer only
# pays for the dependency footprint it actually needs.
option(XMOTION_WITH_MU    "Build xmMu (host hardware drivers)"   ON)
option(XMOTION_WITH_NABLA "Build xmNabla (motion algorithms)"    ON)
option(XMOTION_WITH_GAMMA "Build xmGamma (visualization)"        OFF)
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
xmotion_add_component(xmSigma components/sigma)

if(XMOTION_WITH_MU)
  xmotion_add_component(xmMu components/mu)
endif()

if(XMOTION_WITH_NABLA)
  xmotion_add_component(xmNabla components/nabla)
endif()

if(XMOTION_WITH_GAMMA)
  xmotion_add_component(xmGamma components/gamma)
endif()

message(STATUS "xMotion ${PROJECT_VERSION}: configured "
               "(MU=${XMOTION_WITH_MU} NABLA=${XMOTION_WITH_NABLA} "
               "GAMMA=${XMOTION_WITH_GAMMA})")
