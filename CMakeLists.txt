cmake_minimum_required(VERSION 4.4.0)

# 1. Устанавливаем стандарты
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 2. Включаем модули стандарта
set(CMAKE_CXX_MODULE_STD ON)

# 3. КРИТИЧЕСКИ ВАЖНО: Ставим правильный UUID ДО project().
# Согласно документации CMake master и твоему логу ошибок, 
# твоя версия CMake ожидает именно это значение.
# Старое значение d0edc3af... больше не подходит.
set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD "f35a9ac6-8463-4d38-8eec-5d6008153e7d")

# 4. Объявляем проект
project("pp" LANGUAGES CXX)

# 5. Флаги компилятора
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wall -Wextra)
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    if(CMAKE_CXX_FLAGS MATCHES "/W[0-4]")
        string(REGEX REPLACE "/W[0-4]" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    endif()
    add_compile_options(/utf-8 /W4)
endif()

# 6. Подпапки
add_subdirectory(lab_1)
add_subdirectory(extra)