add_executable(lab4_cuda src/main.cu)

set_target_properties(lab4_cuda PROPERTIES
    CUDA_STANDARD 17
    CUDA_STANDARD_REQUIRED ON
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    CXX_MODULE_STD OFF
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lab_4"
)

if(MSVC)
    target_compile_options(lab4_cuda PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:--extended-lambda --expt-relaxed-constexpr>
    )
endif()