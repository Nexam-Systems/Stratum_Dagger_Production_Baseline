import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

ToolStrip {
    id: _root

    // STRATUM: the fly-view command strip uses accent-filled buttons so AOP /
    // Takeoff / Return / Land present as discrete command buttons.
    accentButtons: true

    // STRATUM: a little wider than the default strip so two-word command labels
    // ("Define AOP", "Max Speed") read comfortably.
    width: ScreenTools.defaultFontPixelWidth * 9

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var engagementController    // STRATUM: forwarded to the Engage trigger
    property bool cameraMaximized: false // STRATUM: forwarded to the dropper's camera section
    property var standoffController      // STRATUM: forwarded to the dropper's drop safety check

    QGCPalette { id: qgcPal }

    // STRATUM: state-accent mapping. SINGLE SOURCE OF TRUTH - kept in lock-step with
    // the identical mapping in FlightMap/MapItems/VehicleMapItem.qml (vehicle icon
    // tint) and Toolbar/FlyViewToolBar.qml (ribbon). Abort -> amber, any engagement
    // mode -> red, flying / takeoff / hold / standoff -> green, on the ground -> blue,
    // no vehicle -> olive branding. White content on the saturated state colours, dark on olive.
    //
    // All THREE engagement modes share the red accent. The colour encodes "committed to
    // a terminal run", which is a property of the operational state, not of the guidance
    // law -- so coordinate Engagement, Vision Engagement and PN Engagement are treated
    // alike. When a fourth engagement mode appears, extend this list and both mirrors
    // in the same commit.
    accentColor:     !_activeVehicle ? "#6B7280" :
                         _activeVehicle.flightMode === qsTr("Abort") ? "#F59E0B" :
                         (_activeVehicle.flightMode === qsTr("Engagement") ||
                          _activeVehicle.flightMode === qsTr("Vision Engagement") ||
                          _activeVehicle.flightMode === qsTr("PN Engagement")) ? "#DC2626" :
                             (_activeVehicle.flightMode === qsTr("Standoff") ||
                              _activeVehicle.flightMode === qsTr("Takeoff") ||
                              _activeVehicle.flightMode === _activeVehicle.pauseFlightMode ||
                              _activeVehicle.flying) ? "#22C55E" : "#1E88E5"
    accentTextColor: _activeVehicle ? "#FFFFFF" : "#1A1A1A"

    signal displayPreFlightChecklist
    signal defineAOP
    signal setStandoff    // STRATUM: forwarded to FlyViewWidgetLayer's standoff panel
    signal fetchCameraTarget

    FlyViewToolStripActionList {
        id: flyViewToolStripActionList

        engagementController:        _root.engagementController
        cameraMaximized:             _root.cameraMaximized
        standoffController:          _root.standoffController
        onDisplayPreFlightChecklist: _root.displayPreFlightChecklist()
        onDefineAOP:                 _root.defineAOP()
        onSetStandoff:               _root.setStandoff()
        onFetchCameraTarget:         _root.fetchCameraTarget()
    }

    model: flyViewToolStripActionList.model
}
