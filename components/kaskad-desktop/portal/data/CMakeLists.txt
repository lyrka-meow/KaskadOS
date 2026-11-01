set(KASKAD_PORTAL_DATA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../session")
set(KASKAD_PORTAL_EXECUTABLE "${CMAKE_INSTALL_FULL_LIBEXECDIR}/xdg-desktop-portal-kaskad")

configure_file(
    "${KASKAD_PORTAL_DATA_DIR}/org.freedesktop.impl.portal.desktop.kaskad.desktop.in"
    org.freedesktop.impl.portal.desktop.kaskad.desktop
    @ONLY)
configure_file(
    "${KASKAD_PORTAL_DATA_DIR}/org.freedesktop.impl.portal.desktop.kaskad.service.in"
    org.freedesktop.impl.portal.desktop.kaskad.service
    @ONLY)
configure_file(
    "${KASKAD_PORTAL_DATA_DIR}/xdg-desktop-portal-kaskad.service.in"
    xdg-desktop-portal-kaskad.service
    @ONLY)

install(FILES "${KASKAD_PORTAL_DATA_DIR}/kaskad.portal"
    DESTINATION ${KDE_INSTALL_DATADIR}/xdg-desktop-portal/portals)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.impl.portal.desktop.kaskad.service
    DESTINATION ${KDE_INSTALL_DBUSSERVICEDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.impl.portal.desktop.kaskad.desktop
    DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/xdg-desktop-portal-kaskad.service
    DESTINATION ${KDE_INSTALL_SYSTEMDUSERUNITDIR})
