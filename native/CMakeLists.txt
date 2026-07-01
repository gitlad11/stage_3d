cmake_minimum_required(VERSION 3.20)

project(stage_native_core LANGUAGES CXX)

option(STAGE_BUILD_TESTS "Build Stage native core tests." ON)
option(STAGE_BUILD_NATIVE_DEMO "Build standalone native Filament demo." OFF)

add_library(stage_native_core OBJECT
  core/stage_engine.cpp
)

target_include_directories(stage_native_core
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(stage_native_core PUBLIC cxx_std_17)
set_target_properties(stage_native_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(STAGE_BUILD_TESTS)
  enable_testing()

  add_executable(stage_native_core_test
    tests/stage_engine_test.cpp
  )
  target_link_libraries(stage_native_core_test PRIVATE stage_native_core)

  add_test(NAME stage_native_core_test COMMAND stage_native_core_test)
endif()

if(STAGE_BUILD_NATIVE_DEMO AND WIN32)
  add_subdirectory(benchmarks)
endif()
