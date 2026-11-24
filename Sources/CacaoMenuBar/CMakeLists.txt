# The menu bar, and the status bar in tablet and phone modes.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_executable(CacaoMenuBar PARSE_AS_LIBRARY ${sources})

target_link_libraries(CacaoMenuBar PRIVATE
  CacaoShellKit
  Cacao
  CacaoSDL
  CacaoDBusMenu
  DBus)

# The focused window, from the compositor's window list.
if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  target_link_libraries(CacaoMenuBar PRIVATE
    CToplevelList
    CacaoHost)
endif()
