target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        EventHandler.cc
        EventHandler.h
        HealthAndArmingCheckReport.cc
        HealthAndArmingCheckReport.h
        logging.cpp
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

#===========================================================================#

CPMAddPackage(
    NAME libevents
    GITHUB_REPOSITORY mavlink/libevents
    # Pinned: libevents main (0ef305fa, 2026-09-27 "support 32 bit system IDs") needs a newer
    # MAVLink than v5.0.8 ships (mavlink_msg_target_field). Same commit upstream QGC master pins.
    GIT_TAG 840a88ea226d4eb0fd4c391ce860317422756435
    SOURCE_SUBDIR libs/cpp
)

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE libevents)
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${libevents_SOURCE_DIR}/libs/cpp)
