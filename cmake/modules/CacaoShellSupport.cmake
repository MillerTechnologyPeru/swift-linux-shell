# Helpers for the shell's targets: where they install, matching Cacao's
# layout so the shell's libraries sit beside Cacao's in the Swift resource
# directory.

include(GNUInstallDirs)

# The Swift resource directory's name for the system: `linux`, `macosx`.
if(NOT SWIFT_SYSTEM_NAME)
  if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
    set(SWIFT_SYSTEM_NAME macosx)
  else()
    string(TOLOWER "${CMAKE_SYSTEM_NAME}" SWIFT_SYSTEM_NAME)
  endif()
endif()

# The directory of the resource directory that holds modules for the
# target's architecture. When cross compiling, set this (or
# CMAKE_SYSTEM_PROCESSOR) to the target's.
if(NOT SWIFT_SYSTEM_ARCH)
  set(SWIFT_SYSTEM_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(CACAO_SHELL_INSTALL_LIBDIR "lib/swift/${SWIFT_SYSTEM_NAME}" CACHE STRING
  "Where libraries install, under the prefix")
set(CACAO_SHELL_INSTALL_SWIFTMODULEDIR "${CACAO_SHELL_INSTALL_LIBDIR}/${SWIFT_SYSTEM_ARCH}" CACHE STRING
  "Where Swift modules install, under the prefix")

# Adds one of the shell's Swift libraries, named for its module.
#
#   cacao_shell_add_library(<name> [<source>...])
function(cacao_shell_add_library name)
  add_library(${name} ${ARGN})

  set_target_properties(${name} PROPERTIES
    Swift_MODULE_NAME ${name}
    INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

  install(TARGETS ${name}
    ARCHIVE DESTINATION ${CACAO_SHELL_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CACAO_SHELL_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
  install(FILES
      ${CMAKE_Swift_MODULE_DIRECTORY}/${name}.swiftmodule
      ${CMAKE_Swift_MODULE_DIRECTORY}/${name}.swiftdoc
    DESTINATION ${CACAO_SHELL_INSTALL_SWIFTMODULEDIR}
    OPTIONAL)
endfunction()

# Adds one of the shell's executables. Executables whose entry point is an
# `@main` type pass PARSE_AS_LIBRARY.
#
#   cacao_shell_add_executable(<name> [PARSE_AS_LIBRARY] <source>...)
function(cacao_shell_add_executable name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "PARSE_AS_LIBRARY" "" "")
  add_executable(${name} ${arg_UNPARSED_ARGUMENTS})

  if(arg_PARSE_AS_LIBRARY)
    target_compile_options(${name} PRIVATE -parse-as-library)
  endif()

  # CacaoShellKit and Cacao's libraries are found in the resource directory
  # on a system image; this finds CacaoShellKit for an install elsewhere.
  set_target_properties(${name} PROPERTIES
    INSTALL_RPATH "$ORIGIN/../${CACAO_SHELL_INSTALL_LIBDIR}")

  install(TARGETS ${name}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endfunction()
