# ============================================================================
# Video Manager Module
# Handles video streaming and subtitle generation
# ============================================================================

target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        SubtitleWriter.cc
        SubtitleWriter.h
        VideoManager.cc
        VideoManager.h
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# STRATUM #84: Test Pairing uses the Win32 ICMP echo API (IcmpSendEcho / InetPtonA) to ping
# the vehicle and camera host IPs. These live in iphlpapi and ws2_32.
if(WIN32)
    target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE iphlpapi ws2_32)
endif()

# ----------------------------------------------------------------------------
# Video Receiver Subsystem
# ----------------------------------------------------------------------------
add_subdirectory(VideoReceiver)
