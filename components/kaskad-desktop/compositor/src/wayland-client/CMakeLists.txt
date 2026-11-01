target_sources(kaskad_compositor PRIVATE
    linuxdmabuf.cpp
    viewporter.cpp
)
ecm_qt_declare_logging_category(kaskad_compositor
    HEADER waylandclientlogging.h
    IDENTIFIER KWIN_WAYLAND_CLIENT
    CATEGORY_NAME kwin_wayland_client
)
