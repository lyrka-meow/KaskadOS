#######################################
# Effect

set(invert_SOURCES
    invert.cpp
    invert.qrc
    main.cpp
)

kwin_add_builtin_effect(invert ${invert_SOURCES})
target_link_libraries(invert PRIVATE
    kaskad_compositor

    KF6::GlobalAccel
    KF6::I18n
)
