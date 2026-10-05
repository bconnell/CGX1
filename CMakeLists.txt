cmake_minimum_required(VERSION 3.20)
project(cgx1 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(CGX1_STRICT_WARNINGS "Enable reviewed strict warnings for every CGX1 target" ON)
if(CGX1_STRICT_WARNINGS)
    if(MSVC)
        add_compile_options(/W4 /WX)
    elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(
            -Wall -Wextra -Wpedantic
            -Werror=return-type
            -Werror=implicit-fallthrough
            -Werror=switch
        )
    else()
        message(FATAL_ERROR "CGX1_STRICT_WARNINGS is unsupported by this compiler")
    endif()
endif()

option(CGX1_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
if(CGX1_ENABLE_SANITIZERS)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
        add_link_options(-fsanitize=address,undefined)
    else()
        message(FATAL_ERROR "CGX1_ENABLE_SANITIZERS requires GCC or Clang")
    endif()
endif()

enable_testing()

# This directory contains only a test-only helper header. Add it to the search
# path for repository targets; production code does not link a test library.
include_directories("${PROJECT_SOURCE_DIR}/source/testing")

option(CGX1_ENABLE_TEST_FAILURE_PROBE
    "Build the deliberately failing Release/NDEBUG test-check probe"
    OFF)

add_subdirectory(source/model)
add_subdirectory(source/isa)
add_subdirectory(source/matrix)
add_subdirectory(source/memory)
add_subdirectory(source/power)
add_subdirectory(source/control)

add_executable(cgx1_firmware_tests
    source/firmware/cgx1_power.c
    source/firmware/test_power.c)
target_include_directories(cgx1_firmware_tests PRIVATE source/firmware)
add_test(NAME cgx1_firmware_power_checks COMMAND cgx1_firmware_tests)

if(CGX1_ENABLE_TEST_FAILURE_PROBE)
    add_executable(cgx1_test_check_failure_probe
        source/testing/release_test_check_failure_probe.cpp)
    add_test(
        NAME cgx1_test_check_failure_probe
        COMMAND cgx1_test_check_failure_probe)
endif()
