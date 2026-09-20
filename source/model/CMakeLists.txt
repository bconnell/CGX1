add_executable(cgx1_model main.cpp)
add_executable(cgx1_model_tests tests.cpp)

target_include_directories(cgx1_model PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(cgx1_model_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_test(NAME cgx1_model_checks COMMAND cgx1_model_tests)
