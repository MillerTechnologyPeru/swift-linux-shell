# The settings daemon and portal backend.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_executable(CacaoSettings ${sources})

target_link_libraries(CacaoSettings PRIVATE
  CacaoShellKit
  DBus)
