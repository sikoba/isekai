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

add_executable (judge judge.cpp)

set (REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

find_library (LIBSNARK snark PATHS "${REPO_ROOT}/lib/libsnarc")
find_library (LIBFF ff PATHS "${REPO_ROOT}/lib/libsnarc")
find_library (LIBZM zm PATHS "${REPO_ROOT}/lib/libsnarc")

target_link_libraries (judge ${LIBSNARK} ${LIBFF} ${LIBZM} gmp m procps)

target_include_directories (
    judge
    PUBLIC
    "${REPO_ROOT}/zkp/libsnark/depends/libff"
    "${REPO_ROOT}/zkp/libsnark")

add_executable (rng rng.cpp)
