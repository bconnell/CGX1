add_executable(cgx1_isa_tests tests.cpp)
target_include_directories(cgx1_isa_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
add_test(NAME cgx1_isa_encoding_checks COMMAND cgx1_isa_tests)
