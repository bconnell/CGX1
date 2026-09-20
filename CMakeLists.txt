cmake_minimum_required(VERSION 3.20)
project(cgx1 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

enable_testing()

add_subdirectory(source/model)
add_subdirectory(source/isa)

add_executable(cgx1_firmware_tests
    source/firmware/cgx1_power.c
    source/firmware/test_power.c)
target_include_directories(cgx1_firmware_tests PRIVATE source/firmware)
add_test(NAME cgx1_firmware_power_checks COMMAND cgx1_firmware_tests)
