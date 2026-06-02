cmake_minimum_required(VERSION 3.20)

project(jolt_ffi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Keep the demo library small and avoid optional Jolt tooling in the APK.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(INTERPROCEDURAL_OPTIMIZATION OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(ENABLE_OBJECT_STREAM OFF CACHE BOOL "" FORCE)

add_subdirectory(third_party/JoltPhysics/Build JoltPhysics)

add_library(jolt_ffi SHARED jolt_ffi.cpp)
target_link_libraries(jolt_ffi PRIVATE Jolt)
target_include_directories(jolt_ffi PRIVATE third_party/JoltPhysics)

