kwin_add_builtin_effect(hidecursor)

target_sources(hidecursor PRIVATE
    hidecursor.cpp
    main.cpp
)

kconfig_add_kcfg_files(hidecursor
    hidecursorconfig.kcfgc
)

target_link_libraries(hidecursor PRIVATE
    kaskad_compositor

    KF6::ConfigGui
)
