qt_add_library(DeviceInfoV2 STATIC
    AES128.cc
    AES128.h
    DeviceInfoV2.cc
    DeviceInfoV2.h
    FF1.cc
    FF1.h
)

target_link_libraries(DeviceInfoV2
    PUBLIC
        Qt6::Core
)

target_include_directories(DeviceInfoV2
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE DeviceInfoV2)
