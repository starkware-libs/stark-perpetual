cmake_minimum_required (VERSION 3.22)

project(StarkEx-Perpetual VERSION 0.1.0)

include(CMakeLists_common.txt)
include("src/starkware/cairo/lang/cairo_cmake_rules.cmake")


add_subdirectory(src)
