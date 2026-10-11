cmake_minimum_required(VERSION 3.16)

project(lab3_mpi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(MPI REQUIRED COMPONENTS CXX)

add_executable(lab3_mpi src/main.cpp)

target_link_libraries(lab3_mpi PRIVATE MPI::MPI_CXX)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(lab3_mpi PRIVATE -Wall -Wextra)
elseif(MSVC)
    target_compile_options(lab3_mpi PRIVATE /W4)
endif()