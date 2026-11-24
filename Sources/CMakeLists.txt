add_subdirectory(CacaoShellKit)
add_subdirectory(CacaoSettings)

if(CACAO_SHELL_BUILD_APPS)
  add_subdirectory(CacaoMenuBar)
  add_subdirectory(CacaoDock)
  add_subdirectory(CacaoDesktop)
endif()

if(CACAO_SHELL_BUILD_COMPOSITOR)
  add_subdirectory(CShellProtocols)
  add_subdirectory(CWLRoots)
  add_subdirectory(CacaoWindowServer)
endif()
