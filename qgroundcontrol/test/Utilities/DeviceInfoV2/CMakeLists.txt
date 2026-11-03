# ============================================================================
# Device Information Protocol V2 Unit Tests
# ============================================================================

target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        DeviceInfoV2Test.cc
        DeviceInfoV2Test.h
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE DeviceInfoV2)

add_qgc_test(DeviceInfoV2Test LABELS Unit Utilities)
