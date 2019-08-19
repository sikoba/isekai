cmake_minimum_required (VERSION 3.0)
project (judge CXX)
set (CMAKE_CXX_STANDARD 11)

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU" OR
    "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang"
)
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pedantic -Wpedantic -Wall -Wextra")
endif ()

set (CURVE "BN128" CACHE STRING "Default curve: one of ALT_BN128, BN128, EDWARDS, MNT4, MNT6")
add_definitions (-DCURVE_${CURVE})

add_executable (judge main.cpp)

find_library (LIBSNARK snark PATHS "${CMAKE_CURRENT_SOURCE_DIR}/../lib/libsnarc")
find_library (LIBFF ff PATHS "${CMAKE_CURRENT_SOURCE_DIR}/../lib/libsnarc")
find_library (LIBZM zm PATHS "${CMAKE_CURRENT_SOURCE_DIR}/../lib/libsnarc")

target_link_libraries (judge ${LIBSNARK} ${LIBFF} ${LIBZM} gmp m procps)

target_include_directories (
    judge
    PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../zkp/libsnark/depends/libff"
    "${CMAKE_CURRENT_SOURCE_DIR}/../zkp/libsnark")
