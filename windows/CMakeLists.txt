# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(netcrux LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "netcrux")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# === elk_ffi native library (Rust FFI) ===
# The schematic layout engine: the vendored elkrs port of the Eclipse Layout
# Kernel behind a C ABI (native/elk_ffi), a raw cdylib with no Flutter plugin
# wrapper, so nothing in the default Windows build compiles or bundles it.
# This mirrors the macOS Runner's cargo phase and linux/CMakeLists.txt: build
# elk_ffi.dll, copy it next to the runner exe (runner/CMakeLists.txt), and
# bundle it on install. Without it, DynamicLibrary.open('elk_ffi.dll') finds
# nothing and every layout falls back to elkjs on the QuickJS interpreter.
#
# This target is defined BEFORE add_subdirectory("runner") so the runner's
# CMakeLists can attach the exe-bound add_dependencies and POST_BUILD copy.
set(ELK_FFI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/elk_ffi")
set(ELK_FFI_DLL "${ELK_FFI_DIR}/target/release/elk_ffi.dll")

# The VS/CMake environment frequently lacks ~/.cargo/bin on PATH, so hint the
# rustup default install location explicitly.
find_program(CARGO_EXECUTABLE cargo
  HINTS "$ENV{USERPROFILE}/.cargo/bin" "$ENV{HOME}/.cargo/bin")
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR
    "cargo not found. Install Rust from https://rustup.rs so the elk_ffi "
    "layout engine can be built for the Windows desktop target.")
endif()

# Always build --release: the loader probes target/release first and a release
# cdylib has a stable ABI independent of the Flutter build mode. cargo is
# incremental, so this is near-free once built. Re-run whenever the wrapper's
# manifest, lockfile or sources, or the vendored elkrs sources, are newer.
set(ELKRS_DIR "${ELK_FFI_DIR}/../vendor/elkrs")
file(GLOB_RECURSE ELK_FFI_SRCS CONFIGURE_DEPENDS
  "${ELK_FFI_DIR}/src/*.rs"
  "${ELK_FFI_DIR}/build.rs"
  "${ELKRS_DIR}/src/*.rs")
add_custom_command(
  OUTPUT "${ELK_FFI_DLL}"
  COMMAND "${CARGO_EXECUTABLE}" build --release
  WORKING_DIRECTORY "${ELK_FFI_DIR}"
  DEPENDS "${ELK_FFI_DIR}/Cargo.toml" "${ELK_FFI_DIR}/Cargo.lock"
          "${ELKRS_DIR}/Cargo.toml"
          ${ELK_FFI_SRCS}
  COMMENT "Building elk_ffi.dll (cargo build --release)"
  VERBATIM)
add_custom_target(elk_ffi DEPENDS "${ELK_FFI_DLL}")

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Bundle the elk_ffi cdylib beside the executable, where the loader looks.
install(FILES "${ELK_FFI_DLL}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
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
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
