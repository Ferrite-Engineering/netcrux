# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "netcrux")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.ferriteengineering.netcrux")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# === elk_ffi native library (Rust FFI) ===
# The schematic layout engine: the vendored elkrs port of the Eclipse Layout
# Kernel behind a C ABI (native/elk_ffi). It is a raw cdylib with no Flutter
# plugin wrapper, so nothing in the default Linux build compiles or bundles
# it. Build it with cargo and install libelk_ffi.so into the bundle lib/ dir,
# which is on the executable's $ORIGIN/lib rpath, so the runtime
# DynamicLibrary.open('libelk_ffi.so') resolves it. Mirrors the macOS Runner
# cargo phase and the windows/CMakeLists integration, and WaveCrux's
# wellen_ffi, the pattern this copies.
set(ELK_FFI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/elk_ffi")
set(ELK_FFI_SO "${ELK_FFI_DIR}/target/release/libelk_ffi.so")
find_program(CARGO_EXECUTABLE cargo HINTS "$ENV{HOME}/.cargo/bin")
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR
    "cargo not found. Install Rust from https://rustup.rs so the elk_ffi "
    "layout engine can be built for the Linux desktop target.")
endif()
# Re-run cargo whenever the wrapper's manifest, lockfile or sources, or the
# vendored elkrs sources, are newer than the built library. CONFIGURE_DEPENDS
# re-globs at build time so newly added sources are tracked.
set(ELKRS_DIR "${ELK_FFI_DIR}/../vendor/elkrs")
file(GLOB_RECURSE ELK_FFI_SRCS CONFIGURE_DEPENDS
  "${ELK_FFI_DIR}/src/*.rs"
  "${ELK_FFI_DIR}/build.rs"
  "${ELKRS_DIR}/src/*.rs")
add_custom_command(
  OUTPUT "${ELK_FFI_SO}"
  COMMAND "${CARGO_EXECUTABLE}" build --release
  WORKING_DIRECTORY "${ELK_FFI_DIR}"
  DEPENDS "${ELK_FFI_DIR}/Cargo.toml" "${ELK_FFI_DIR}/Cargo.lock"
          "${ELKRS_DIR}/Cargo.toml"
          ${ELK_FFI_SRCS}
  COMMENT "Building libelk_ffi.so (cargo build --release)"
  VERBATIM)
add_custom_target(elk_ffi DEPENDS "${ELK_FFI_SO}")
add_dependencies(${BINARY_NAME} elk_ffi)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# flutter_js dlopens its QuickJS bridge at runtime from a prebuilt shared
# library the package ships (linux/shared/libquickjs_c_bridge_plugin.so), and
# the schematic layout engine (elkjs inside a QuickJS isolate) cannot start
# without it. The plugin's own CMakeLists exports that path under its
# pre-rename variable name (`flutter_qjs_bundled_libraries`), which the
# generated bundling loop never reads, and its install() rule targets the
# plugin's own build tree. So the library reached no Linux bundle, and the app
# opened to "elkjs isolate init failed" on every layout. Bundle it by hand;
# the Linux build script checks that it landed.
set(QUICKJS_BRIDGE
  "${FLUTTER_MANAGED_DIR}/ephemeral/.plugin_symlinks/flutter_js/linux/shared/libquickjs_c_bridge_plugin.so")
if(NOT EXISTS "${QUICKJS_BRIDGE}")
  message(FATAL_ERROR
    "flutter_js no longer ships ${QUICKJS_BRIDGE}; the layout engine would fail at runtime")
endif()
list(APPEND PLUGIN_BUNDLED_LIBRARIES "${QUICKJS_BRIDGE}")


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Bundle the elk_ffi cdylib into the bundle lib/ dir ($ORIGIN/lib rpath).
install(FILES "${ELK_FFI_SO}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
