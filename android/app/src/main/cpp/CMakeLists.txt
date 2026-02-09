cmake_minimum_required(VERSION 3.10.2)
project(slowreverb_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(OBOE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/oboe)
set(SOUNDTOUCH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/soundtouch/soundtouch)

add_subdirectory(${OBOE_DIR} ${CMAKE_BINARY_DIR}/oboe)
add_subdirectory(${SOUNDTOUCH_DIR} ${CMAKE_BINARY_DIR}/soundtouch_build)

add_library(slowreverb_native SHARED
  audio_engine.cpp
  simple_reverb.cpp
  native_audio.cpp
)

target_include_directories(slowreverb_native
  PRIVATE
    ${OBOE_DIR}/include
    ${SOUNDTOUCH_DIR}/include
)

target_link_libraries(slowreverb_native
  PRIVATE
    oboe
    SoundTouch
    log
    android
    mediandk
)
