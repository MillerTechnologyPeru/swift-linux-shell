# The thin C shim over wlroots. Linked into the compositor, so it isn't
# installed. One wlroots release is pinned: 0.18.

find_package(PkgConfig REQUIRED)
pkg_check_modules(WLROOTS REQUIRED IMPORTED_TARGET wlroots-0.18)
pkg_check_modules(WAYLAND_SERVER REQUIRED IMPORTED_TARGET wayland-server)
pkg_check_modules(XKBCOMMON REQUIRED IMPORTED_TARGET xkbcommon)

add_library(CWLRoots STATIC
  animation.c
  appmenu.c
  dock.c
  layer.c
  protocols.c
  server.c
  shadow.c
  spaces.c
  titlebar.c
  toplevel.c)

target_compile_definitions(CWLRoots PRIVATE
  WLR_USE_UNSTABLE)

# The public header includes nothing from wlroots, so Swift sees only it.
target_include_directories(CWLRoots
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(CWLRoots PRIVATE
  CShellProtocols
  PkgConfig::WLROOTS
  PkgConfig::WAYLAND_SERVER
  PkgConfig::XKBCOMMON
  # The shadow's falloff.
  m)
