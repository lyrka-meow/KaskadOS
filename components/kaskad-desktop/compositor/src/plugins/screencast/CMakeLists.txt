target_sources(kaskad_compositor PRIVATE
    filteredsceneview.cpp
    outputscreencastsource.cpp
    pipewirecore.cpp
    regionscreencastsource.cpp
    screencastbuffer.cpp
    screencastlayer.cpp
    screencastmanager.cpp
    screencastsource.cpp
    screencaststream.cpp
    windowscreencastsource.cpp
)

target_include_directories(kaskad_compositor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)

ecm_qt_declare_logging_category(kaskad_compositor
    HEADER kwinscreencast_logging.h
    IDENTIFIER KWIN_SCREENCAST
    CATEGORY_NAME kwin_screencast
    DEFAULT_SEVERITY Warning
)

target_link_libraries(kaskad_compositor PRIVATE KF6::I18n PkgConfig::PipeWire Libdrm::Libdrm)
