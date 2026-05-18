cmake_minimum_required(VERSION 3.20)
project(cola_translate CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Sensible llama.cpp options for an embedded library.
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON   OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS    OFF CACHE BOOL "" FORCE)
set(GGML_CCACHE          OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP          OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE       OFF CACHE BOOL "" FORCE)

# Disable GPU backends — we run on CPU only on mobile.
set(GGML_METAL  OFF CACHE BOOL "" FORCE)
set(GGML_CUDA   OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_BLAS   OFF CACHE BOOL "" FORCE)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../third_party/llama.cpp llama_cpp_build)

option(COLA_SHARED "Build cola_translate as a shared library (for Android FFI)" OFF)

if(COLA_SHARED)
    add_library(cola_translate SHARED cola_translate.cpp)
    # Force all symbols from llama / ggml static archives into the shared lib so
    # downstream consumers only need libcola_translate.so.
    if(APPLE)
        target_link_options(cola_translate PRIVATE "-Wl,-all_load")
    else()
        target_link_options(cola_translate PRIVATE
            "-Wl,--whole-archive"
            "$<TARGET_FILE:llama>"
            "$<TARGET_FILE:ggml>"
            "$<TARGET_FILE:ggml-base>"
            "$<TARGET_FILE:ggml-cpu>"
            "-Wl,--no-whole-archive")
        add_dependencies(cola_translate llama ggml ggml-base ggml-cpu)
    endif()
else()
    add_library(cola_translate STATIC cola_translate.cpp)
endif()

target_include_directories(cola_translate PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(cola_translate PUBLIC llama)

if(COLA_BUILD_TEST)
    add_executable(cola_test cola_test.cpp)
    target_link_libraries(cola_test PRIVATE cola_translate)
endif()
