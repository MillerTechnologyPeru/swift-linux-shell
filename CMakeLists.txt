# Builds the shell for a system image (Buildroot and the like): the
# executables, CacaoShellKit as a shared Swift library beside Cacao's, and
# the session's data files.
#
# SwiftPM (Package.swift) stays the way to develop and test the shell.
#
# Cacao and PureSwift/DBus are expected where the compiler finds them: in
# the Swift resource directory on a system image, or in a directory passed
# with -I and -L in CMAKE_Swift_FLAGS. .github/scripts/build-cmake-dependencies.sh
# builds them into one such directory.
#
# The Ninja generator is required: CMake builds Swift with Ninja only.

cmake_minimum_required(VERSION 3.26)

if(POLICY CMP0157)
  # Swift's new build model: modules are emitted on their own, in parallel.
  cmake_policy(SET CMP0157 NEW)
endif()

project(CacaoShell
  LANGUAGES C Swift)

if(NOT CMAKE_GENERATOR MATCHES "Ninja")
  message(FATAL_ERROR "The Ninja generator is required for Swift; run cmake with -G Ninja.")
endif()

list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake/modules)

option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(CACAO_SHELL_BUILD_APPS "Build the menu bar and dock, which need Cacao and SDL3" ON)
if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  option(CACAO_SHELL_BUILD_COMPOSITOR "Build CacaoWindowServer, which needs wlroots 0.18" ON)
else()
  # It needs wlroots and libwayland-server.
  set(CACAO_SHELL_BUILD_COMPOSITOR OFF)
endif()

set(CMAKE_Swift_LANGUAGE_VERSION 6)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

include(CacaoShellSupport)

add_subdirectory(Sources)
add_subdirectory(Data)

install(FILES
    LICENSE
  DESTINATION ${CMAKE_INSTALL_DATADIR}/doc/CacaoShell)
