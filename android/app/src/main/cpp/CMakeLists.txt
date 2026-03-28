cmake_minimum_required(VERSION 3.22.1)
project(aiim_mnn_jni)

# Prefer Gradle-passed absolute path (Windows path resolution from cpp/ is fragile).
if(NOT DEFINED AIIM_REPO_ROOT OR "${AIIM_REPO_ROOT}" STREQUAL "")
  get_filename_component(REPO_ROOT "${CMAKE_SOURCE_DIR}/../../../.." ABSOLUTE)
else()
  set(REPO_ROOT "${AIIM_REPO_ROOT}")
endif()
set(MNN_ROOT "${REPO_ROOT}/third_party/MNN")

if(NOT EXISTS ${MNN_ROOT}/include/MNN/Interpreter.hpp)
  message(FATAL_ERROR "MNN headers missing. Clone: git clone --depth 1 -b 3.4.1 https://github.com/alibaba/MNN.git third_party/MNN && cd third_party/MNN && git sparse-checkout set include transformers/llm/engine/include")
endif()

include_directories(
  ${MNN_ROOT}/include
  ${MNN_ROOT}/transformers/llm/engine/include
)

add_library(${CMAKE_PROJECT_NAME} SHARED aiim_mnn_jni.cpp)

set(JNI_LIBS_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(MNN SHARED IMPORTED)
set_target_properties(MNN PROPERTIES IMPORTED_LOCATION ${JNI_LIBS_DIR}/libMNN.so)

add_library(MNN_Express SHARED IMPORTED)
set_target_properties(MNN_Express PROPERTIES IMPORTED_LOCATION ${JNI_LIBS_DIR}/libMNN_Express.so)

add_library(llm SHARED IMPORTED)
set_target_properties(llm PROPERTIES IMPORTED_LOCATION ${JNI_LIBS_DIR}/libllm.so)

target_link_libraries(${CMAKE_PROJECT_NAME}
  llm
  MNN
  MNN_Express
  android
  log
)

target_link_options(${CMAKE_PROJECT_NAME} PRIVATE "-Wl,-z,max-page-size=16384")
