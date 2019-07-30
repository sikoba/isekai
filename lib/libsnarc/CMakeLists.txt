cmake_minimum_required(VERSION 3.0)


project(isekai)


set(
  CURVE
  "BN128"
  CACHE
  STRING
  "Default curve: one of ALT_BN128, BN128, EDWARDS, MNT4, MNT6"
)

add_definitions(
  -DCURVE_${CURVE}
)

if(${CURVE} STREQUAL "BN128")
  add_definitions(
    -DBN_SUPPORT_SNARK=1
  )
endif()

option(
  BINARY_OUTPUT
  "In serialization, output raw binary data (instead of decimal), which is smaller and faster."
  ON
)
option(
  MONTGOMERY_OUTPUT
  "Serialize Fp elements as their Montgomery representations (faster but not human-readable)"
  ON
)
option(
  USE_PT_COMPRESSION
  "Use point compression"
  ON
)
option(
  WITH_SUPERCOP
  "Support for Ed25519 signatures required by ADSNARK"
  ON
)

option(
  WITH_PROCPS
  "Use procps for memory profiling"
  ON
)
option(
  USE_ASM
  "Use architecture-specific optimized assembly code"
  ON
)

set(
  OPT_FLAGS
  ""
  CACHE
  STRING
  "Override C++ compiler optimization flags"
)
if(CMAKE_COMPILER_IS_GNUCXX OR "${CMAKE_CXX_COMPILER_ID}" STREQUAL "Clang")
  # Common compilation flags and warning configuration
  set(
    CMAKE_CXX_FLAGS
    "${CMAKE_CXX_FLAGS} -std=c++11 -Wall -Wextra -Wfatal-errors"
  )
  if("${MULTICORE}")
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fopenmp")
  endif()
  # Default optimizations flags (to override, use -DOPT_FLAGS=...)
  if("${OPT_FLAGS}" STREQUAL "")
    set(
      OPT_FLAGS
      "-ggdb3 -O2 -march=native -mtune=native"
    )
  endif()
endif()

set(
  CMAKE_CXX_FLAGS
  "${CMAKE_CXX_FLAGS} ${OPT_FLAGS}"
)



if("${DEBUG}")
  add_definitions(-DDEBUG=1)
endif()

if("${LOWMEM}")
  add_definitions(-DLOWMEM=1)
endif()

if("${MULTICORE}")
  add_definitions(-DMULTICORE=1)
endif()

if("${BINARY_OUTPUT}")
  add_definitions(-DBINARY_OUTPUT)
endif()

if("${MONTGOMERY_OUTPUT}")
  add_definitions(-DMONTGOMERY_OUTPUT)
endif()

if(NOT "${USE_PT_COMPRESSION}")
  add_definitions(-DNO_PT_COMPRESSION=1)
endif()

if("${PROFILE_OP_COUNTS}")
  add_definitions(-DPROFILE_OP_COUNTS=1)
endif()

if("${USE_MIXED_ADDITION}")
  add_definitions(-DUSE_MIXED_ADDITION=1)
endif()

if("${CPPDEBUG}")
  add_definitions(-D_GLIBCXX_DEBUG -D_GLIBCXX_DEBUG_PEDANTIC)
endif()

if("${PERFORMANCE}")
  add_definitions(-DNDEBUG)
  set(
    CMAKE_CXX_FLAGS
    "${CMAKE_CXX_FLAGS} -flto -fuse-linker-plugin"
  )
  set(
    CMAKE_EXE_LINKER_FLAGS
    "${CMAKE_EXE_LINKER_FLAGS} -flto"
  )
endif()

if("${USE_ASM}")
  add_definitions(-DUSE_ASM)
endif()


add_library(
  snarc
  STATIC

  src/Util.hpp
  src/Util.cpp
  src/CircuitReader.hpp
  src/CircuitReader.cpp
  src/r1cs_utils.hpp
  src/r1cs_utils.cpp
  src/cwrapper.cpp
)


find_library(LIBSNARK snark
	PATHS ${CMAKE_CURRENT_SOURCE_DIR}
)
target_link_libraries(
  snarc

	${LIBSNARK}
)

target_include_directories(
    snarc

    PUBLIC
	${CMAKE_CURRENT_SOURCE_DIR}/../../zkp/libsnark
	${CMAKE_CURRENT_SOURCE_DIR}/../../zkp/libsnark/depends/libff
	${CMAKE_CURRENT_SOURCE_DIR}/../../zkp/libsnark/depends/libfqfft
  )
  
  set_target_properties(snarc PROPERTIES
		 ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

