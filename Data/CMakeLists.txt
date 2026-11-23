# The session's data files: the portal backend's registration and D-Bus
# activation, and the session that runs sway until CacaoWindowServer
# replaces it.

configure_file(org.freedesktop.impl.portal.desktop.cacao.service.in
  ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.impl.portal.desktop.cacao.service
  @ONLY)

install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.impl.portal.desktop.cacao.service
  DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
install(FILES
    cacao.portal
  DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal/portals)
install(FILES
    cacao-portals.conf
  DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal)

install(FILES
    cacao.desktop
  DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions)
install(PROGRAMS
    cacao-session
  DESTINATION ${CMAKE_INSTALL_BINDIR})
# cacao-session looks for it here, under /usr.
install(FILES
    sway/config
  DESTINATION ${CMAKE_INSTALL_DATADIR}/cacao/sway)
