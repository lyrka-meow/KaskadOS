#######################################
# Effect

set(slide_SOURCES
    main.cpp
    slide.cpp
    springmotion.cpp
)

kconfig_add_kcfg_files(slide_SOURCES
    slideconfig.kcfgc
)

kwin_add_builtin_effect(slide ${slide_SOURCES})
target_link_libraries(slide PRIVATE
    kaskad_compositor

    KF6::ConfigGui
)
