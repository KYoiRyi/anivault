cmake_minimum_required(VERSION 3.10)
project(anivault_mpv_smoke)

set(CMAKE_CXX_STANDARD 17)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

add_executable(anivault_mpv_smoke main.cpp)

target_link_libraries(anivault_mpv_smoke ${CMAKE_CURRENT_SOURCE_DIR}/libmpv.dll.a)
