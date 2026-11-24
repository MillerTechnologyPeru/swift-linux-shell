# The desktop's wallpaper, until the file manager owns the desktop.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_executable(CacaoDesktop PARSE_AS_LIBRARY ${sources})

target_link_libraries(CacaoDesktop PRIVATE
  Cacao
  CacaoSDL)
