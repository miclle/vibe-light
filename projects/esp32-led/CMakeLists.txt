cmake_minimum_required(VERSION 3.16)

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../esp32-common")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(vibe_light_led)
