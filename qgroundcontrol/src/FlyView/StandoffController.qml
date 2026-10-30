import QtQuick
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

// STRATUM: Standoff command controller.
//
// Two wire contracts, gated on the active STRATUM profile:
//
//   * Dropper (profile == 1) — UAV-VAS web UI contract. Two COMMAND_LONG messages
//     addressed to the bridge companion computer (component 191):
//       31010 (params):   p1 = target latitude   [deg]
//                         p2 = target longitude  [deg]
//                         p3 = distance          [m]
//                         p4 = height AGL        [m]
//                         p5 = speed             [km/h]
//                         p6 = direction         (compass bearing degrees, 0 = N, clockwise)
//       31011 (activate): p1 = 1  -> begin orbit   (p1 = 0 -> abort)
//     The bridge owns the orbit math and flight-mode handling.
//
//   * Dagger  (profile == 2) — direct PX4 Standoff flight mode. We hand PX4 the TARGET
//     coordinate plus geometry (distance, bearing, RELATIVE height) via
//     Vehicle.guidedModeStandoff() and then switch flightMode = "Standoff". PX4 owns
//     the offset math and yaws to face the target itself. Matches the Dagger_main fork.
Item {
    id: root

    property var    guidedController
    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle

    // STRATUM: 1 = Dropper, 2 = Dagger. Read from the settings singleton so it resolves
    // regardless of QML id scope.
    readonly property int  _stratumProfile: QGroundControl.settingsManager.appSettings.stratumProfile.rawValue
    readonly property bool _isDagger:       _stratumProfile === 2

    // Committed standoff state. _standoffDistance drives the on-map surveillance circle.
    property var    _targetCoordinate:  QtPositioning.coordinate()
    property real   _standoffDistance:  0    // orbit distance / radius [m]
    property real   _standoffHeight:    0    // height AGL [m]
    property real   _standoffSpeed:     0    // [km/h]  (Dropper only)
    property real   _standoffDirection: 0    // compass bearing [deg], 0 = N, clockwise
    // True from the moment a standoff is committed until it is cancelled. Drives the
    // on-map surveillance circle (centre = target, radius = standoff distance).
    property bool   _standoffActive:    false
    on_ActiveVehicleChanged: {
        _targetCoordinate = QtPositioning.coordinate()
        _standoffActive = false
        _standoffDistance = 0
        _standoffHeight = 0
    }

    // STRATUM: bridge companion computer + standoff command ids (Dropper web UI contract).
    readonly property int _bridgeComponentId:   191
    readonly property int _cmdStandoffParams:   31010
    readonly property int _cmdStandoffActivate: 31011

    // distanceMeters / heightMeters are in METERS, speed in KM/H (Dropper), direction is
    // a compass bearing in DEGREES (0 = N, increasing clockwise). targetCoordinate carries the target designated
    // in the Set Standoff panel (manual lat/lon entry or crosshair map pick).
    // Returns true on commit, false if the request was rejected (bad vehicle, invalid
    // coordinate, or Vehicle::guidedModeStandoff distance check). On a false return
    // NOTHING is mutated: no flight-mode switch, no surveillance circle.
    function beginStandoff(distanceMeters, heightMeters, speed, direction, targetCoordinate) {
        if (!_activeVehicle) {
            return false
        }
        var target = _targetCoordinate
        if (targetCoordinate !== undefined && targetCoordinate.isValid) {
            target = targetCoordinate
        }
        if (!target.isValid) {
            return false
        }

        if (_isDagger) {
            // Dagger path: hand PX4 the TARGET point + geometry. guidedModeStandoff
            // range-checks against flyViewSettings.maxGoToLocationDistance and returns
            // false (with a toast) when the hold point is too far from the aircraft.
            // direction is already a compass bearing in degrees (0=N, clockwise); normalise to [0,360).
            var bearingDeg = ((direction % 360) + 360) % 360
            if (!_activeVehicle.guidedModeStandoff(target, distanceMeters, bearingDeg, heightMeters)) {
                return false
            }
            _activeVehicle.flightMode = "Standoff"
        } else {
            // Dropper path: web UI contract to the bridge companion computer.
            _activeVehicle.sendCommand(_bridgeComponentId, _cmdStandoffParams, true,
                                       target.latitude,
                                       target.longitude,
                                       distanceMeters,
                                       heightMeters,
                                       speed,
                                       direction,
                                       0)
            _activeVehicle.sendCommand(_bridgeComponentId, _cmdStandoffActivate, true,
                                       1, 0, 0, 0, 0, 0, 0)
        }

        _targetCoordinate  = target
        _standoffDistance  = distanceMeters
        _standoffHeight    = heightMeters
        _standoffSpeed     = speed
        _standoffDirection = direction
        _standoffActive    = true
        return true
    }

    // Abort the standoff/orbit. On Dropper this fires 31011 activate=0 to the bridge; on
    // Dagger the flight-mode change alone is enough — PX4 exits Standoff when a new mode
    // is commanded, and there is no bridge command to abort. Both paths clear the
    // surveillance circle.
    function cancelStandoff() {
        if (!_isDagger && _activeVehicle) {
            _activeVehicle.sendCommand(_bridgeComponentId, _cmdStandoffActivate, true,
                                       0, 0, 0, 0, 0, 0, 0)
        }
        _standoffActive = false
    }
}
