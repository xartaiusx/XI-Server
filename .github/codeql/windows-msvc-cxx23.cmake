# CMake 3.31 maps C++23 to a moving draft. Keep this override exclusive to
# the Windows security lane, after project(server) initializes its languages.
if(NOT PROJECT_NAME STREQUAL "server"
   OR NOT CMAKE_CXX_COMPILER_ID STREQUAL "MSVC"
   OR NOT CMAKE_CXX_COMPILER_VERSION MATCHES "^19\\.44\\.[0-9]+(\\.[0-9]+)?$"
   OR NOT MSVC_CXX_ARCHITECTURE_ID STREQUAL "x64")
    message(FATAL_ERROR "The C++23 security hook requires native MSVC19.44 x64.")
endif()

foreach(option CMAKE_CXX23_STANDARD_COMPILE_OPTION CMAKE_CXX23_EXTENSION_COMPILE_OPTION)
    if(NOT "${${option}}" STREQUAL "-std:c++latest")
        message(FATAL_ERROR "Unexpected native MSVC C++23 option; preserve exact mode.")
    endif()
    set(${option} "/std:c++23preview")
endforeach()
