# The session's data files: the portal backend's registration and D-Bus
# activation, and the sessions: on CacaoWindowServer, and on sway as a
# fallback.

# The settings service starts on demand under either name: the portal
# backend's, when xdg-desktop-portal first needs it, and its own, when the
# Settings app or the shell changes a setting.
foreach(service
    org.freedesktop.impl.portal.desktop.cacao
    org.pureswift.Cacao.Settings)
  configure_file(${service}.service.in
    ${CMAKE_CURRENT_BINARY_DIR}/${service}.service
    @ONLY)
  install(FILES
      ${CMAKE_CURRENT_BINARY_DIR}/${service}.service
    DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
endforeach()

install(FILES
    cacao.portal
  DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal/portals)
install(FILES
    cacao-portals.conf
  DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal)

# The session on CacaoWindowServer, and on sway as a fallback.
install(FILES
    cacao.desktop
    cacao-sway.desktop
  DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions)
install(PROGRAMS
    cacao-session
  DESTINATION ${CMAKE_INSTALL_BINDIR})
# cacao-session --sway looks for it here, under /usr.
install(FILES
    sway/config
  DESTINATION ${CMAKE_INSTALL_DATADIR}/cacao/sway)
