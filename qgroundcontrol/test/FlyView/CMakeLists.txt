# ============================================================================
# FlyView Unit Tests
# ============================================================================

target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        StandoffGeometryTest.cc
        StandoffGeometryTest.h
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_qgc_test(StandoffGeometryTest LABELS Unit Utilities)
