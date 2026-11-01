#######################################
# Effect

set(diminactive_SOURCES
    diminactive.cpp
    main.cpp
)

kconfig_add_kcfg_files(diminactive_SOURCES
    diminactiveconfig.kcfgc
)

kwin_add_builtin_effect(diminactive ${diminactive_SOURCES})
target_link_libraries(diminactive PRIVATE
    kaskad_compositor

    KF6::ConfigGui
)
