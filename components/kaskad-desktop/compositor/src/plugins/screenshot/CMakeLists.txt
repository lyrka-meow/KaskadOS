set(screenshot_source_dir "${CMAKE_CURRENT_LIST_DIR}")

set(screenshot_SOURCES
    "${screenshot_source_dir}/screenshot.cpp"
    "${screenshot_source_dir}/screenshotdbusinterface2.cpp"
    "${screenshot_source_dir}/screenshotlayer.cpp"
)

qt_add_dbus_adaptor(screenshot_SOURCES
    "${screenshot_source_dir}/org.kde.KWin.ScreenShot2.xml"
    "${screenshot_source_dir}/screenshotdbusinterface2.h"
    KWin::ScreenShotDBusInterface2
)

target_sources(kaskad_compositor PRIVATE ${screenshot_SOURCES})
set_source_files_properties(
    "${screenshot_source_dir}/screenshot.h"
    PROPERTIES SKIP_AUTOMOC ON
)
target_include_directories(kaskad_compositor PRIVATE
    "${screenshot_source_dir}"
    ${CMAKE_CURRENT_BINARY_DIR}
)
target_link_libraries(kaskad_compositor PRIVATE
    KF6::Service
    KF6::I18n

    Qt::DBus
)

ecm_qt_declare_logging_category(kaskad_compositor
    HEADER screenshotlogging.h
    IDENTIFIER KWIN_SCREENSHOT
    CATEGORY_NAME kwin_screenshot
    DEFAULT_SEVERITY Warning
)
