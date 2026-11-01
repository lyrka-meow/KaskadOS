cmake_minimum_required(VERSION 3.24)

project(kaskados-material3-comparison VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.6 REQUIRED COMPONENTS Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(kaskados-material3-comparison
    main.cpp
)

qt_add_qml_module(kaskados-material3-comparison
    URI KaskadOS.Material3Comparison
    VERSION 1.0
    QML_FILES
        Main.qml
        ComparisonPane.qml
        MaterialSlider.qml
        MaterialSwitch.qml
)

target_link_libraries(kaskados-material3-comparison PRIVATE Qt6::Quick Qt6::QuickControls2)
target_compile_options(kaskados-material3-comparison PRIVATE -Wall -Wextra -Wpedantic)

install(TARGETS kaskados-material3-comparison RUNTIME DESTINATION bin)
