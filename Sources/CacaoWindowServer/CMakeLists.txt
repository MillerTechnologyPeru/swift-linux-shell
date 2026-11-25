# The compositor: window policy in Swift over the CWLRoots shim.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_executable(CacaoWindowServer ${sources})

target_link_libraries(CacaoWindowServer PRIVATE
  CacaoShellKit
  CWLRoots
  DBus)
