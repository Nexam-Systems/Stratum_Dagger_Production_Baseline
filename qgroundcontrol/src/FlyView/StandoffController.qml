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

    // Committed standoff state. _standoffDistance drives the on-map standoff ring.
    property var    _targetCoordinate:  QtPositioning.coordinate()
    property real   _standoffDistance:  0    // orbit distance / radius [m]
    property real   _standoffHeight:    0    // height AGL [m]
    property real   _standoffSpeed:     0    // [km/h]  (Dropper only)
    property real   _standoffDirection: 0    // compass bearing [deg], 0 = N, clockwise
    // True from the moment a standoff is committed until it is cancelled. Drives the
    // on-map standoff display (target, ring centred on it, slot at the standoff bearing).
    property bool   _standoffActive:    false

    // STRATUM #98 slot lifecycle (Dagger). Set Standoff only SENDS the command; the standoff
    // becomes active (slot "en route") when the vehicle acknowledges it as accepted:
    //   awaitingAck  - command sent, waiting for COMMAND_ACK (the draft stays on the map/panel)
    //   rejected     - ACK was a rejection, or no ACK arrived: the draft is kept for correction
    // A previously accepted standoff stays active while a new command is pending or rejected.
    property bool   awaitingAck:        false
    property bool   rejected:           false
    property string rejectReason:       ""     // why the last command was rejected (incl. firmware STATUSTEXT)
    property string statusMessage:      ""     // firmware STATUSTEXT shown after an Abort

    signal standoffAccepted()                  // command acknowledged (or, on Dropper, sent): panel can close

    // STRATUM #108 holding detection (Dagger). After an accepted command the slot is "en route".
    // It becomes "holding" only when the vehicle went from Standoff to Hold (the firmware's own
    // arrival signal) AND stays within the capture tolerance of the slot for the dwell time. Hold
    // from the operator or a failsafe elsewhere therefore does not count. If a holding vehicle
    // leaves the tolerance the slot goes back to en route. Other modes (Engagement, Abort, RTL,
    // manual) leave the slot as it was; the vehicle icon carries the mode badge.
    property bool   holding:            false
    property var    slotCoordinate:     QtPositioning.coordinate()   // set by the map from StandoffGeometry
    readonly property string vehicleMode: _activeVehicle ? _activeVehicle.flightMode : ""
    // True while the vehicle is flying or holding the standoff (not in Engagement, Abort, RTL, ...).
    readonly property bool   inStandoffOrHold: _activeVehicle && (vehicleMode === "Standoff" || vehicleMode === _activeVehicle.pauseFlightMode)

    property bool   _holdArmed:         false  // seen in Standoff mode since the command was accepted
    property double _inToleranceSinceMs: 0

    property var    _pending:           null   // request awaiting its ACK
    property double _rejectedAtMs:      0
    property double _abortedAtMs:       0
    property var    _recentText:        []     // [{ atMs, text }] last STATUSTEXT messages

    on_ActiveVehicleChanged: {
        _targetCoordinate = QtPositioning.coordinate()
        _standoffActive = false
        _standoffDistance = 0
        _standoffHeight = 0
        _resetHold()
        _resetAck()
        clearRejected()
        statusMessage = ""
    }

    // STRATUM: bridge companion computer + standoff command ids (Dropper web UI contract).
    readonly property int _bridgeComponentId:   191
    readonly property int _cmdStandoffParams:   31010
    readonly property int _cmdStandoffActivate: 31011

    readonly property int _statusTextWindowMs:  2000    // STATUSTEXT this close to a reject/abort belongs to it
    readonly property int _ackSafetyTimeoutMs:  5000    // backstop if the command queue never reports a result

    function clearRejected() {
        rejected = false
        rejectReason = ""
        _rejectedAtMs = 0
    }

    function _resetAck() {
        awaitingAck = false
        _pending = null
        ackSafetyTimer.stop()
    }

    function _resetHold() {
        holding = false
        _holdArmed = false
        _inToleranceSinceMs = 0
    }

    function _nowMs() {
        return Date.now()
    }

    function _flyViewSettings() {
        return QGroundControl.settingsManager.flyViewSettings
    }

    // Vehicle within the capture tolerance of the slot: horizontal from the position, vertical from
    // the height above home (the slot height is sent, and so compared, as height above home).
    function _withinTolerance() {
        var vehicle = _activeVehicle
        if (!vehicle || !slotCoordinate.isValid || !vehicle.coordinate.isValid) {
            return false
        }
        var altitude = Number(vehicle.altitudeRelative.rawValue)
        if (isNaN(altitude)) {
            return false
        }
        var settings = _flyViewSettings()
        return vehicle.coordinate.distanceTo(slotCoordinate) <= Number(settings.standoffHoldHorizontalTolerance.rawValue)
                && Math.abs(altitude - _standoffHeight) <= Number(settings.standoffHoldVerticalTolerance.rawValue)
    }

    // Re-evaluated on mode and position changes, and by a timer so the dwell can complete while
    // the vehicle hovers without new position updates.
    function _evaluateHold() {
        if (!_standoffActive || !_isDagger || !_activeVehicle) {
            return
        }
        if (vehicleMode === "Standoff") {
            // On its way to the slot.
            _holdArmed = true
            holding = false
            _inToleranceSinceMs = 0
            return
        }
        if (vehicleMode !== _activeVehicle.pauseFlightMode) {
            // Engagement, Abort, RTL, manual ...: the slot stays as it was.
            _holdArmed = false
            _inToleranceSinceMs = 0
            return
        }
        // Hold: only counts when it followed Standoff mode, and only inside the tolerance.
        if (!_holdArmed || !_withinTolerance()) {
            holding = false
            _inToleranceSinceMs = 0
            return
        }
        var now = _nowMs()
        if (_inToleranceSinceMs === 0) {
            _inToleranceSinceMs = now
        }
        if (now - _inToleranceSinceMs >= Number(_flyViewSettings().standoffHoldDwellTime.rawValue) * 1000) {
            holding = true
        }
    }

    // Firmware messages received within the window before `nowMs`, oldest first.
    function _statusTextBefore(nowMs) {
        var out = []
        for (var i = 0; i < _recentText.length; ++i) {
            if (nowMs - _recentText[i].atMs <= _statusTextWindowMs) {
                out.push(_recentText[i].text)
            }
        }
        return out
    }

    function _appendUnique(base, texts) {
        var result = base
        for (var i = 0; i < texts.length; ++i) {
            if (result.indexOf(texts[i]) === -1) {
                result += (result.length > 0 ? "\n" : "") + texts[i]
            }
        }
        return result
    }

    function _ackReason(ackResult, failureCode) {
        if (failureCode === 1) {
            return qsTr("The vehicle did not respond.")
        }
        if (failureCode === 2) {
            return qsTr("A previous standoff command is still waiting for a response.")
        }
        switch (ackResult) {
        case 1:  return qsTr("The vehicle temporarily rejected the command.")
        case 2:  return qsTr("The vehicle denied the command.")
        case 3:  return qsTr("The vehicle does not support the command.")
        case 6:  return qsTr("The command was cancelled.")
        default: return qsTr("The vehicle could not run the command.")
        }
    }

    function _reject(reason) {
        _resetAck()
        rejected = true
        _rejectedAtMs = Date.now()
        rejectReason = _appendUnique(reason, _statusTextBefore(_rejectedAtMs))
    }

    // The vehicle accepted the command: the standoff is now active (slot en route).
    function _commit(p) {
        _targetCoordinate  = p.target
        _standoffDistance  = p.distance
        _standoffHeight    = p.height
        _standoffSpeed     = p.speed
        _standoffDirection = p.direction
        _standoffActive    = true
        _resetHold()
        clearRejected()
        standoffAccepted()
    }

    Timer {
        interval:   500
        repeat:     true
        running:    root._standoffActive && root._isDagger
        onTriggered: root._evaluateHold()
    }

    Timer {
        id:         ackSafetyTimer
        interval:   root._ackSafetyTimeoutMs
        onTriggered: if (root.awaitingAck) root._reject(qsTr("The vehicle did not respond."))
    }

    Connections {
        target:                 root._activeVehicle
        ignoreUnknownSignals:   true

        // COMMAND_ACK (and queue failures such as no response) for the standoff command.
        function onMavCommandResult(vehicleId, targetComponent, command, ackResult, failureCode) {
            if (!root.awaitingAck || command !== root._cmdStandoffParams || vehicleId !== root._activeVehicle.id) {
                return
            }
            var pending = root._pending
            if (ackResult === 0 /* MAV_RESULT_ACCEPTED */) {
                root._resetAck()
                // Geometry was accepted first; only now switch the vehicle into Standoff mode.
                root._activeVehicle.flightMode = "Standoff"
                root._commit(pending)
            } else {
                root._reject(root._ackReason(ackResult, failureCode))
            }
        }

        // STATUSTEXT: keep the last few, and attach them to a rejection or an abort.
        function onTextMessageReceived(sysid, componentid, severity, text, description) {
            if (severity > 6) {
                return    // ignore debug noise
            }
            var now = Date.now()
            var kept = []
            for (var i = 0; i < root._recentText.length; ++i) {
                if (now - root._recentText[i].atMs <= 10000) {
                    kept.push(root._recentText[i])
                }
            }
            kept.push({ atMs: now, text: text })
            root._recentText = kept

            if (root.rejected && now - root._rejectedAtMs <= root._statusTextWindowMs) {
                root.rejectReason = root._appendUnique(root.rejectReason, [text])
            }
            if (root._abortedAtMs > 0 && now - root._abortedAtMs <= root._statusTextWindowMs * 2) {
                root.statusMessage = root._appendUnique(root.statusMessage, [text])
                statusClearTimer.restart()
            }
        }

        // Entering Abort while a standoff is active: show what the firmware said.
        function onCoordinateChanged() {
            root._evaluateHold()
        }

        function onFlightModeChanged(flightMode) {
            root._evaluateHold()
            if (flightMode === "Abort" && root._standoffActive) {
                root._abortedAtMs = Date.now()
                root.statusMessage = root._appendUnique("", root._statusTextBefore(root._abortedAtMs))
                if (root.statusMessage.length > 0) {
                    statusClearTimer.restart()
                }
            } else if (flightMode !== "Abort") {
                root._abortedAtMs = 0
            }
        }
    }

    Timer {
        id:         statusClearTimer
        interval:   10000
        onTriggered: root.statusMessage = ""
    }

    // distanceMeters / heightMeters are in METERS, speed in KM/H (Dropper), direction is
    // a compass bearing in DEGREES (0 = N, increasing clockwise). targetCoordinate carries the target designated
    // in the Set Standoff panel (manual lat/lon entry or crosshair map pick).
    // Returns true when the request was SENT, false if it was refused up front (bad vehicle,
    // invalid coordinate, a command still awaiting its ACK, or the Vehicle::guidedModeStandoff
    // distance check). On a false return NOTHING is mutated.
    // Dagger: the standoff only becomes active (standoffAccepted) after the vehicle's ACK.
    // Dropper: the bridge contract has no per-command ACK handling here, so it is active on send.
    function beginStandoff(distanceMeters, heightMeters, speed, direction, targetCoordinate) {
        if (!_activeVehicle || awaitingAck) {
            return false
        }
        var target = _targetCoordinate
        if (targetCoordinate !== undefined && targetCoordinate.isValid) {
            target = targetCoordinate
        }
        if (!target.isValid) {
            return false
        }

        var request = { target: target, distance: distanceMeters, height: heightMeters, speed: speed, direction: direction }

        if (_isDagger) {
            // Dagger path: hand PX4 the TARGET point + geometry. guidedModeStandoff
            // range-checks against flyViewSettings.maxGoToLocationDistance and returns
            // false (with a toast) when the hold point is too far from the aircraft.
            // direction is already a compass bearing in degrees (0=N, clockwise); normalise to [0,360).
            var bearingDeg = ((direction % 360) + 360) % 360
            if (!_activeVehicle.guidedModeStandoff(target, distanceMeters, bearingDeg, heightMeters)) {
                return false
            }
            clearRejected()
            _pending = request
            awaitingAck = true
            ackSafetyTimer.restart()
            return true
        }

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
        _commit(request)
        return true
    }

    // Abort the standoff/orbit. On Dropper this fires 31011 activate=0 to the bridge; on
    // Dagger the flight-mode change alone is enough — PX4 exits Standoff when a new mode
    // is commanded, and there is no bridge command to abort. Both paths clear the
    // active standoff display.
    function cancelStandoff() {
        if (!_isDagger && _activeVehicle) {
            _activeVehicle.sendCommand(_bridgeComponentId, _cmdStandoffActivate, true,
                                       0, 0, 0, 0, 0, 0, 0)
        }
        _resetAck()
        clearRejected()
        _resetHold()
        _standoffActive = false
    }
}
