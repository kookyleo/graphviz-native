cmake_minimum_required(VERSION 3.16)
project(graphviz_api C)

# Find installed Graphviz
find_package(PkgConfig)
if(PkgConfig_FOUND)
    pkg_check_modules(GVC libgvc)
    pkg_check_modules(CGRAPH libcgraph)
endif()

# Fallback: use GRAPHVIZ_PREFIX
if(NOT GVC_FOUND)
    if(DEFINED GRAPHVIZ_PREFIX)
        set(GVC_INCLUDE_DIRS "${GRAPHVIZ_PREFIX}/include" "${GRAPHVIZ_PREFIX}/include/graphviz")
        set(GVC_LIBRARY_DIRS "${GRAPHVIZ_PREFIX}/lib")
        set(GVC_LIBRARIES gvc cgraph cdt)
    else()
        message(FATAL_ERROR "Graphviz not found. Set GRAPHVIZ_PREFIX or install Graphviz development files.")
    endif()
endif()

add_library(graphviz_api SHARED graphviz_api.c)

target_include_directories(graphviz_api PRIVATE ${GVC_INCLUDE_DIRS})
target_link_directories(graphviz_api PRIVATE ${GVC_LIBRARY_DIRS})
target_link_libraries(graphviz_api PRIVATE ${GVC_LIBRARIES})

target_compile_definitions(graphviz_api PRIVATE
    GRAPHVIZ_API_EXPORTS
    PACKAGE_VERSION="${PROJECT_VERSION}"
)

set_target_properties(graphviz_api PROPERTIES
    C_VISIBILITY_PRESET hidden
    VERSION 1.0.0
    SOVERSION 1
)

install(TARGETS graphviz_api
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
install(FILES graphviz_api.h DESTINATION include)
