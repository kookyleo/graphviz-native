cmake_minimum_required(VERSION 3.22.1)
project(graphviz_jni)

# Build the graphviz_api C library from source
set(GRAPHVIZ_API_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../../src")

add_library(graphviz_api SHARED
    "${GRAPHVIZ_API_SRC}/graphviz_api.c"
    jni/graphviz_jni.c
)

target_include_directories(graphviz_api PRIVATE
    "${GRAPHVIZ_API_SRC}"
)

# Link against the prebuilt Graphviz libraries for Android
set(GRAPHVIZ_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../graphviz")

target_include_directories(graphviz_api PRIVATE
    "${GRAPHVIZ_PREBUILT}/include"
)

# Link Android log library for JNI
find_library(log-lib log)
target_link_libraries(graphviz_api ${log-lib})
