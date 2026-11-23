# The dock, the app grid and launcher entries.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_executable(CacaoDock PARSE_AS_LIBRARY ${sources})

target_link_libraries(CacaoDock PRIVATE
  CacaoShellKit
  Cacao
  CacaoSDL)
