# ============================================================================
# Flight Display Module
# In-flight view, telemetry displays, and vehicle control UI
# ============================================================================

qt_add_library(FlyViewModule STATIC)

qt_add_qml_module(FlyViewModule
    URI QGroundControl.FlyView
    VERSION 1.0
    RESOURCE_PREFIX /qml
    QML_FILES
        ConnectPodAction.qml
        CustomGuidedActionsController.qml
        DefaultChecklist.qml
        EngageAction.qml
        FetchTargetAction.qml
        EngageDialog.qml
        EngagementAbortOverlay.qml
        EngagementController.qml
        EngagementCountdown.qml
        VisionEngageAction.qml
        VisionEngagementOverlay.qml
        VisionEngagementStatus.qml
        FixedWingChecklist.qml
        FlightDisplayViewDummy.qml
        FlightDisplayViewVideoOutput.qml
        FlightDisplayViewQtMultimedia.qml
        FlightDisplayViewUVC.qml
        FlightDisplayViewVideo.qml
        FlyView.qml
        FlyViewAdditionalActionsButton.qml
        FlyViewAdditionalActionsList.qml
        FlyViewAdditionalActionsPanel.qml
        FlyViewAdditionalCustomActionsList.qml
        FlyViewAOPAction.qml
        FlyViewBottomRightRowLayout.qml
        FlyViewCustomLayer.qml
        FlyViewCameraControls.qml
        FlyViewCameraControlsDagger.qml
        FlyViewCameraControlsDaggerRoot.qml
        FlyViewDropperAction.qml
        FlyViewDropperPanel.qml
        FlyViewFlightModeAction.qml
        FlyViewInsetViewer.qml
        FlyViewInstrumentPanel.qml
        FlyViewGripperButton.qml
        FlyViewGripperDropPanel.qml
        FlyViewMap.qml
        FlyViewMissionCompleteDialog.qml
        FlyViewPreFlightChecklistPopup.qml
        FlyViewStandoffAction.qml
        FlyViewToolStrip.qml
        FlyViewToolStripActionList.qml

        FlyViewTopRightColumnLayout.qml
        FlyViewTopRightPanel.qml
        FlyViewVideo.qml
        FlyViewVideoOSD.qml
        FlyViewWidgetLayer.qml
        GuidedActionAbort.qml
        GuidedActionChangeAltitude.qml
        GuidedActionChangeSpeed.qml
        GuidedActionConfirm.qml
        GuidedActionHold.qml
        GuidedActionLand.qml
        GuidedActionPause.qml
        GuidedActionPnEngage.qml
        GuidedActionRTL.qml
        GuidedActionStandoffMode.qml
        GuidedActionsController.qml
        GuidedActionTakeoff.qml
        GuidedActionTakeoffDialog.qml
        GuidedToolStripAction.qml
        GuidedValueSlider.qml
        MultiRotorChecklist.qml
        MultiVehicleList.qml
        ObstacleDistanceOverlay.qml
        ObstacleDistanceOverlayMap.qml
        ObstacleDistanceOverlayVideo.qml
        OnScreenCameraTrackingController.qml
        OnScreenGimbalController.qml
        TargetTrackingOverlay.qml
        TargetGpsEstimate.qml
        TrackerRoiOverlay.qml
        PreFlightBatteryCheck.qml
        PreFlightCheckList.qml
        PreFlightCheckListShowAction.qml
        PreFlightGPSCheck.qml
        PreFlightRCCheck.qml
        PreFlightSensorsHealthCheck.qml
        PreFlightSoundCheck.qml
        ProximityRadarValues.qml
        ProximityRadarVideoView.qml
        RoverChecklist.qml
        StandoffController.qml
        StandoffOrbitDialog.qml
        SubChecklist.qml
        TelemetryValuesBar.qml
        TerrainProgress.qml
        TrackingToggleAction.qml
        VehicleWarnings.qml
        VirtualJoystick.qml
        VTOLChecklist.qml
    NO_PLUGIN
)

# C++ QML types must live in the main target; FlyViewModule is QML-only (NO_PLUGIN).
target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        CameraGeolocation.cc
        CameraGeolocation.h
        CameraGroundRay.h
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE GeographicLib::GeographicLib)

qt_add_resources(FlyViewModule flyview_resources
    PREFIX "/res"
    BASE "${CMAKE_SOURCE_DIR}/resources"
    FILES
        "${CMAKE_SOURCE_DIR}/resources/DropArrow.svg"
        "${CMAKE_SOURCE_DIR}/resources/Gripper.svg"
        "${CMAKE_SOURCE_DIR}/resources/land.svg"
        "${CMAKE_SOURCE_DIR}/resources/NoVideoBackground.jpg"
        "${CMAKE_SOURCE_DIR}/resources/pause-mission.svg"
)

qt_add_resources(FlyViewModule flyview_qmlimages
    PREFIX "/qmlimages"
    BASE "${CMAKE_SOURCE_DIR}/resources"
    FILES
        "${CMAKE_SOURCE_DIR}/resources/check.svg"
        "${CMAKE_SOURCE_DIR}/resources/TargetLocation.svg"
)
