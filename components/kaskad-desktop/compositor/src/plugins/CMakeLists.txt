# Add a CMake-time check for python3 to avoid failures during build.
find_package (Python3 COMPONENTS Interpreter)
add_feature_info("Python3" Python3_Interpreter_FOUND "Required to strip effects metadata")
set(KSEM_EXE "${CMAKE_CURRENT_SOURCE_DIR}/strip-effect-metadata.py")

function (kwin_strip_builtin_effect_metadata target metadata)
    set(stripped_metadata "${CMAKE_CURRENT_BINARY_DIR}/${metadata}.stripped")

    set(command ${KSEM_EXE} --source=${metadata} --output=${stripped_metadata})
    add_custom_command(
        OUTPUT ${stripped_metadata}
        COMMAND ${command}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${metadata}
        COMMENT "Stripping ${metadata}..."
    )
    set_property(TARGET ${target} APPEND PROPERTY AUTOGEN_TARGET_DEPENDS ${stripped_metadata})
endfunction()

macro(kwin_add_builtin_effect name)
    kcoreaddons_add_plugin(${name} STATIC SOURCES ${ARGN} INSTALL_NAMESPACE "kwin/effects/plugins")
    target_compile_definitions(${name} PRIVATE -DTRANSLATION_DOMAIN=\"kwin\")
    kwin_strip_builtin_effect_metadata(${name} metadata.json)
    install(FILES metadata.json DESTINATION ${KDE_INSTALL_DATADIR}/kwin-wayland/builtin-effects/ RENAME ${name}.json)
endmacro()

function(kwin_add_scripted_effect name source)
    kpackage_install_package(${source} ${name} effects kwin-wayland)

    # necessary so tests are found without installing
    file(COPY ${source}/contents ${source}/metadata.json DESTINATION ${CMAKE_BINARY_DIR}/bin/kwin-wayland/effects/${name})
endfunction()

if (KASKAD_INSTALLER_MINIMAL)
    # The live installer needs only the compositor-owned Qt integration.
    # Effects, scripts, screencasting, accessibility helpers and shell-facing
    # services belong to the installed desktop session and stay out of the ISO
    # installer's dedicated process.
    add_subdirectory(idletime)
    add_subdirectory(qpa)
    add_subdirectory(windowsystem)
    return()
endif()

add_subdirectory(blendchanges)
add_subdirectory(blur)
add_subdirectory(colorblindnesscorrection)
add_subdirectory(dialogparent)
add_subdirectory(diminactive)
add_subdirectory(dimscreen)
add_subdirectory(eyeonscreen)
add_subdirectory(fade)
add_subdirectory(fadedesktop)
add_subdirectory(fadingpopups)
add_subdirectory(frozenapp)
add_subdirectory(fullscreen)
add_subdirectory(hidecursor)
add_subdirectory(highlightwindow)
add_subdirectory(idletime)
add_subdirectory(invert)
add_subdirectory(kpackage)
add_subdirectory(kscreen)
add_subdirectory(login)
add_subdirectory(logout)
add_subdirectory(magnifier)
add_subdirectory(maximize)
add_subdirectory(qpa)
add_subdirectory(scale)
add_subdirectory(screentransform)
add_subdirectory(sessionquit)
add_subdirectory(shakecursor)
add_subdirectory(slide)
add_subdirectory(slidingnotifications)
add_subdirectory(slidingpopups)
add_subdirectory(squash)
add_subdirectory(systembell)
add_subdirectory(translucency)
add_subdirectory(windowaperture)
add_subdirectory(windowsystem)
add_subdirectory(zoom)

if (PipeWire_FOUND)
    add_subdirectory(screencast)
endif()
if(TARGET K::KGlobalAccelD)
    add_subdirectory(kglobalaccel)
endif()
