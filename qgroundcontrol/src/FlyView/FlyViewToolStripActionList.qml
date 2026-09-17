import QtQml.Models
import QtQuick.Controls
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Viewer3D

ToolStripActionList {
    id: _root

    property var engagementController    // STRATUM: engagement/abort safety-loop controller
    property bool cameraMaximized: false // STRATUM: true when the video is the maximized window
    property var standoffController      // STRATUM: supplies the standoff target for the drop safety check

    // STRATUM: active vehicle profile (1 = Dropper, 2 = Dagger) read straight from the
    // settings singleton so it resolves regardless of QML id scope.
    readonly property bool _stratumIsDropper: QGroundControl.settingsManager.appSettings.stratumProfile.rawValue === 1
    readonly property bool _stratumIsDagger:  QGroundControl.settingsManager.appSettings.stratumProfile.rawValue === 2

    signal displayPreFlightChecklist
    signal defineAOP      // retained: emitters relocated to the ribbon (FlyViewToolBar)
    signal setStandoff    // retained: emitters relocated to the ribbon (FlyViewToolBar)

    // STRATUM: Land / Hold command a flight-mode change the same way the flight-mode
    // dropdown does (a direct, reliable write to Vehicle.flightMode by its advertised
    // name), behind a simple confirm dialog. The old slide-to-confirm bar path was
    // fragile in this fork, so these commands no longer depend on it.
    function _commandFlightMode(modeName) {
        if (!QGroundControl.multiVehicleManager.activeVehicle) {
            return
        }
        QGroundControl.showMessageDialog(
            mainWindow,
            modeName,
            qsTr("Switch the vehicle to %1 flight mode?").arg(modeName),
            Dialog.Ok | Dialog.Cancel,
            function() {
                const vehicle = QGroundControl.multiVehicleManager.activeVehicle
                if (vehicle) {
                    vehicle.flightMode = modeName
                }
            })
    }

    // STRATUM: the command strip is gated by the active vehicle profile.
    //   Common (both):  Standoff (target panel), Land, Hold.
    //   Dropper only:   Dropper (payload + camera) panel.
    //   Dagger only:    Takeoff, Abort, Engage, Vision Engage.
    // Abort/Engage/Vision are Dagger features and no longer appear in the Dropper profile.
    // Define AOP and Set Standoff live on the top ribbon.
    model: [
        // Dagger: guided Takeoff (opens the altitude dialog, MAV_CMD_NAV_TAKEOFF).
        GuidedActionTakeoff {
            visible: _root._stratumIsDagger
        },
        // Common: Standoff opens the Set Standoff target-entry panel, which commits via
        // the web-UI contract (cmd 31010 params + 31011 activate to the bridge).
        ToolStripAction {
            text:        qsTr("Standoff")
            iconSource:  "/qmlimages/StandoffMarker.svg"
            visible:     true
            enabled:     !!QGroundControl.multiVehicleManager.activeVehicle
            onTriggered: _root.setStandoff()
        },
        // Common: Land (direct flight-mode change, confirm dialog).
        ToolStripAction {
            text:        qsTr("Land")
            iconSource:  "/res/land.svg"
            visible:     true
            enabled:     !!QGroundControl.multiVehicleManager.activeVehicle
            onTriggered: _root._commandFlightMode(qsTr("Land"))
        },
        // Common: Hold (direct flight-mode change, confirm dialog).
        ToolStripAction {
            text:        qsTr("Hold")
            iconSource:  "/res/pause-mission.svg"
            visible:     true
            enabled:     !!QGroundControl.multiVehicleManager.activeVehicle
            onTriggered: _root._commandFlightMode(qsTr("Hold"))
        },
        // STRATUM: Flight-mode picker (replaces the top-ribbon dropdown, which is
        // now a read-only mode display). Opens a drop panel listing the whitelisted
        // modes; each entry confirms then writes Vehicle.flightMode.
        FlyViewFlightModeAction { },
        // Dagger: Abort flight mode (DO_SET_MODE sub=22), hold-to-confirm.
        GuidedActionAbort {
            visible: _root._stratumIsDagger
        },
        // Dagger: Engagement flight mode (sub=21), armed-on-engage via the controller.
        EngageAction {
            visible: _root._stratumIsDagger
            onTriggered: {
                if (_root.engagementController) {
                    _root.engagementController.engage()
                } else if (QGroundControl.multiVehicleManager.activeVehicle) {
                    QGroundControl.multiVehicleManager.activeVehicle.flightMode = qsTr("Engagement")
                }
            }
        },
        // Dagger: Vision Engagement flight mode (sub=23), camera-guided, no map target.
        VisionEngageAction {
            // STRATUM: hidden per operator UX spec. Flip back to _root._stratumIsDagger to restore.
            visible: false
            onTriggered: {
                if (_root.engagementController) {
                    _root.engagementController.visionEngage()
                } else if (QGroundControl.multiVehicleManager.activeVehicle) {
                    QGroundControl.multiVehicleManager.activeVehicle.flightMode = qsTr("Vision Engagement")
                }
            }
        },
        // STRATUM: PX4 custom "PN Engagement" flight mode (sub=24 -> nav_state 30) --
        // proportional navigation plus a closing-speed regulator against the LATCHED
        // standoff target. Unlike Engage and Vision above this is a hold-to-confirm
        // action (GuidedActionPnEngage -> actionPnEngage), which still reaches
        // EngagementController.pnEngage() and therefore still arms the abort
        // destination; see the header of GuidedActionPnEngage.qml.
        GuidedActionPnEngage {
            // STRATUM: hidden per operator UX spec. Flip back to _root._stratumIsDagger to restore.
            visible: false
        },
        // STRATUM: Tracking on/off toggle -- enables/disables the already-running
        // companion tracker via Vehicle.setTrackerEnabled(bool) (NEXAM_TRACKER_CONFIG 42005).
        // Dagger-only feature (tracker lives on the strike/targeting airframe's companion).
        TrackingToggleAction {
            // STRATUM: hidden per operator UX spec. Flip back to _root._stratumIsDagger to restore.
            visible: false
        },
        // STRATUM: one-time ping to register this machine with the pod (press once,
        // before connecting the main GCS). Does not hold control of the camera.
        // Dagger-only.
        ConnectPodAction {
            // STRATUM: hidden per operator UX spec. Flip back to _root._stratumIsDagger to restore.
            visible:     false
            onTriggered: QGroundControl.targetFetch.pingPod()
        },
        // STRATUM: fetch the XC25 pod's target and plot it on the map. Runs 30 s,
        // re-reading every 2 s and replacing the marker each time. Dagger-only.
        FetchTargetAction {
            // STRATUM: hidden per operator UX spec. Flip back to _root._stratumIsDagger to restore.
            visible:     false
            onTriggered: QGroundControl.targetFetch.fetchTarget()
        },
        // Dropper: payload + camera control panel.
        FlyViewDropperAction {
            visible:            _root._stratumIsDropper
            cameraMaximized:    _root.cameraMaximized
            standoffController: _root.standoffController
        }
    ]
}
