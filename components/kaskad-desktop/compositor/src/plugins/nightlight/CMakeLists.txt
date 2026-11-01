set(nightlight_source_dir "${CMAKE_CURRENT_LIST_DIR}")

target_sources(kaskad_compositor PRIVATE
    "${nightlight_source_dir}/nightlightdbusinterface.cpp"
    "${nightlight_source_dir}/nightlightmanager.cpp"
)

target_include_directories(kaskad_compositor PRIVATE
    "${nightlight_source_dir}"
    ${CMAKE_CURRENT_BINARY_DIR}
)

ecm_qt_declare_logging_category(kaskad_compositor
    HEADER nightlightlogging.h
    IDENTIFIER KWIN_NIGHTLIGHT
    CATEGORY_NAME kwin_nightlight
    DEFAULT_SEVERITY Critical
)

kconfig_add_kcfg_files(kaskad_compositor
    "${nightlight_source_dir}/nightlightsettings.kcfgc"
)

kconfig_target_kcfg_file(kaskad_compositor
    FILE "${nightlight_source_dir}/nightlightstate.kcfg"
    CLASS_NAME NightLightState
    MUTATORS
)

set(nightlight_xml_SOURCES)
qt_add_dbus_adaptor(nightlight_xml_SOURCES
    "${nightlight_source_dir}/org.kde.KWin.NightLight.xml"
    "${nightlight_source_dir}/nightlightdbusinterface.h"
    KWin::NightLightDBusInterface
)
target_sources(kaskad_compositor PRIVATE ${nightlight_xml_SOURCES})

target_link_libraries(kaskad_compositor PRIVATE
    KNightTime
    KF6::ConfigGui
    KF6::GlobalAccel
    KF6::I18n
)

install(FILES "${nightlight_source_dir}/nightlightsettings.kcfg" DESTINATION ${KDE_INSTALL_KCFGDIR})
install(FILES "${nightlight_source_dir}/org.kde.KWin.NightLight.xml" DESTINATION ${KDE_INSTALL_DBUSINTERFACEDIR})
