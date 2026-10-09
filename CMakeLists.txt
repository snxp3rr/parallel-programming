cmake_minimum_required(VERSION 4.4.0)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_CXX_MODULE_STD ON)

set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD "f35a9ac6-8463-4d38-8eec-5d6008153e7d")


project("pp" LANGUAGES CXX)

find_package(OpenMP REQUIRED)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wall -Wextra)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    if(CMAKE_CXX_FLAGS MATCHES "/W[0-4]")
        string(REGEX REPLACE "/W[0-4]" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    endif()
    add_compile_options(/utf-8 /W4)
endif()

option(PP_ENABLE_CUDA "Build CUDA laboratory" OFF)

if(PP_ENABLE_CUDA)
    if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES OR CMAKE_CUDA_ARCHITECTURES STREQUAL "")
        set(CMAKE_CUDA_ARCHITECTURES native)
    endif()

    enable_language(CUDA)
    add_subdirectory(lab_4)
endif()

add_subdirectory(lab_1)
add_subdirectory(lab_2)
add_subdirectory(extra)