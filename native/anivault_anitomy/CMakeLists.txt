cmake_minimum_required(VERSION 3.14)
project(anivault_anitomy LANGUAGES CXX)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(anivault_anitomy STATIC
    anivault_anitomy.cpp
  )
else()
  add_library(anivault_anitomy SHARED
    anivault_anitomy.cpp
  )
endif()

target_include_directories(anivault_anitomy PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/anitomy/include"
)

target_compile_features(anivault_anitomy PRIVATE cxx_std_23)

if(NOT MSVC)
  target_compile_options(anivault_anitomy PRIVATE -std=c++23)
endif()

if(WIN32)
  target_compile_definitions(anivault_anitomy PRIVATE ANIVAULT_ANITOMY_EXPORTS)
endif()

if(MSVC)
  target_compile_options(anivault_anitomy PRIVATE /utf-8)
endif()
