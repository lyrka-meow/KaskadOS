#######################################
# Effect

set(blur_SOURCES
    blur.cpp
    blur.qrc
    main.cpp
)

kconfig_add_kcfg_files(blur_SOURCES
    blurconfig.kcfgc
)

kwin_add_builtin_effect(blur ${blur_SOURCES})
target_link_libraries(blur PRIVATE
    kaskad_compositor

    KF6::ConfigGui

    KDecoration3::KDecoration
)
