# What the shell processes share: form factor, desktop entries, D-Bus names
# and settings, and the Swift side of the dock protocol.

file(GLOB sources CONFIGURE_DEPENDS *.swift)

cacao_shell_add_library(CacaoShellKit ${sources})

# Its public API uses DBus's types.
target_link_libraries(CacaoShellKit PUBLIC
  DBus)
