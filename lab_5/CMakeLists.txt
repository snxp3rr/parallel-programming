cmake_minimum_required(VERSION 4.2)

project(lab5_mandelbrot_threads LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Threads REQUIRED)

add_executable(mandelbrot
    src/main.cpp
    src/mandelbrotSerial.cpp
    src/mandelbrotThread.cpp
    common/ppm.cpp
)

target_include_directories(mandelbrot PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/common
)

target_link_libraries(mandelbrot PRIVATE
    Threads::Threads
)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(mandelbrot PRIVATE
        -Wall
        -Wextra
        -O3
    )

    if(UNIX)
        target_link_libraries(mandelbrot PRIVATE m)
    endif()
elseif(MSVC)
    target_compile_options(mandelbrot PRIVATE /W4 /O2)
endif()