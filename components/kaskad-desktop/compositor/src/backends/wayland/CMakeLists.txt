target_sources(kaskad_compositor PRIVATE
    color_manager.cpp
    wayland_backend.cpp
    wayland_display.cpp
    wayland_egl_backend.cpp
    wayland_layer.cpp
    wayland_logging.cpp
    wayland_output.cpp
    wayland_qpainter_backend.cpp
)

target_link_libraries(kaskad_compositor PRIVATE Plasma::KWaylandClient Wayland::Client gbm::gbm)
