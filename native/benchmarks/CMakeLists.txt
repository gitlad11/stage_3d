cmake_minimum_required(VERSION 3.20)

add_executable(stage_native_filament_demo WIN32
  stage_native_filament_demo.cpp
  ../core/stage_engine.cpp
  ../platform/windows/stage_filament_renderer.cpp
)

target_compile_features(stage_native_filament_demo PRIVATE cxx_std_20)
target_compile_definitions(stage_native_filament_demo PRIVATE UNICODE _UNICODE NOMINMAX)
target_include_directories(stage_native_filament_demo
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../platform/windows"
)
target_link_libraries(stage_native_filament_demo PRIVATE windowscodecs.lib)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/StageFilamentWindows.cmake")
stage_enable_filament_windows(stage_native_filament_demo)

if(STAGE_FILAMENT_ROOT AND EXISTS "${STAGE_FILAMENT_ROOT}/bin")
  add_custom_command(
    TARGET stage_native_filament_demo
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_directory
      "${STAGE_FILAMENT_ROOT}/bin"
      "$<TARGET_FILE_DIR:stage_native_filament_demo>"
    VERBATIM
  )
endif()
