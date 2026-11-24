# The dock's client of the compositor's window list. Linked into the dock,
# so it isn't installed.

find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)

add_library(CToplevelList STATIC
  toplevels.c)

target_include_directories(CToplevelList
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(CToplevelList PRIVATE
  PkgConfig::WAYLAND_CLIENT)
