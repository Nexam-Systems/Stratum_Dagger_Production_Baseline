import QGroundControl
import QtQuick

Item {
    id: root

    property bool _changing: false
    property double _enabledAtMs: 0
    property int _generation: 0
    property var _joystick: null
    property var _request: null
    readonly property var activeJoystick: joystickManager.activeJoystick
    readonly property bool available: vehicle && activeJoystick && activeJoystick.isGamepad && activeJoystick.supportsProtectedGamepad() && activeJoystick.settings.calibrated.rawValue && vehicle.initialConnectComplete && !vehicle.vehicleLinkManager.communicationLost
    required property var engagementController
    required property var guidedController
    required property var joystickManager
    required property var mapControl
    property bool modeEnabled: false
    readonly property string selectionDetails: {
        if (safetyState.pendingCommand === "" || !_request)
            return "";
        if (_request.command === "Takeoff")
            return qsTr("Takeoff altitude: %1 m").arg(_request.altitude);
        if (_request.command === "Standoff") {
            const config = _request.config;
            const target = config.target;
            const coordinate = target ? Number(target.latitude).toFixed(6) + ", " + Number(target.longitude).toFixed(6) + "\n" : "";
            return coordinate + qsTr("Distance %1 m / Height %2 m").arg(config.distance).arg(config.height);
        }
        return "";
    }
    property alias state: safetyState
    property real takeoffAltitudeMeters: 20
    required property var vehicle
    required property var widgetLayer

    function attachJoystick() {
        if (!joystickManager)
            return;
        disable();
        if (_joystick && _joystick !== activeJoystick)
            _joystick.setProtectedGamepadMode(false);
        _joystick = activeJoystick && activeJoystick.isGamepad ? activeJoystick : null;
        if (_joystick)
            _generation = _joystick.setProtectedGamepadMode(true);
    }

    function disable() {
        if (_changing || !joystickManager)
            return;
        _changing = true;
        modeEnabled = false;
        if (_joystick || (activeJoystick && activeJoystick.isGamepad))
            joystickManager.activeJoystickEnabledForActiveVehicle = false;
        if (_joystick)
            _generation = _joystick.setProtectedGamepadMode(true);
        safetyState.reset(qsTr("Joystick disabled"));
        _request = null;
        _changing = false;
    }

    function enable() {
        if (!available)
            return;
        disable();
        _joystick = activeJoystick;
        _generation = _joystick.setProtectedGamepadMode(true, true);
        joystickManager.activeJoystickEnabledForActiveVehicle = true;
        _enabledAtMs = Date.now();
        modeEnabled = joystickManager.activeJoystickEnabledForActiveVehicle;
    }

    function execute(command) {
        const request = _request;
        _request = null;
        if (!request || request.command !== command || request.vehicle !== vehicle || !permitted(command)) {
            safetyState.completedHoldUntilMs = 0;
            safetyState.feedback = qsTr("Command rejected — vehicle or safety state changed");
            return;
        }
        if (command === "Takeoff") {
            if (request.altitude < vehicle.minimumTakeoffAltitudeMeters()) {
                safetyState.feedback = qsTr("Takeoff minimum changed — select again");
                return;
            }
            const altitude = QGroundControl.unitsConversion.metersToAppSettingsVerticalDistanceUnits(request.altitude);
            guidedController.executeAction(guidedController.actionTakeoff, undefined, altitude, false);
        } else if (command === "RTL") {
            guidedController.executeAction(guidedController.actionRTL, undefined, 0, false);
        } else if (command === "Standoff") {
            if (!widgetLayer.executeGamepadStandoff(request.config)) {
                safetyState.feedback = qsTr("Standoff rejected");
                return;
            }
        } else if (command === "Abort") {
            engagementController.abort();
        } else if (command === "Engage") {
            engagementController.engage();
        }
        safetyState.feedback = qsTr("%1 requested — awaiting vehicle response").arg(command);
    }

    function permitted(command) {
        if (!modeEnabled || !available || !joystickManager.activeJoystickEnabledForActiveVehicle)
            return false;
        if (command === "Takeoff")
            return guidedController.showTakeoff;
        if (command === "RTL")
            return guidedController.showRTL;
        if (command === "Standoff")
            return vehicle.armed && vehicle.flying && vehicle.supports.guidedMode;
        if (command === "Abort")
            return vehicle.armed && vehicle.flightModes.indexOf(engagementController.abortModeName) !== -1;
        if (command === "Engage")
            return vehicle.armed && vehicle.flying && vehicle.flightModes.indexOf(engagementController.engagementModeName) !== -1 && vehicle.flightMode !== engagementController.engagementModeName;
        return false;
    }

    function prepare(command) {
        _request = null;
        if (!permitted(command)) {
            safetyState.cancel(qsTr("%1 unavailable — vehicle safety checks").arg(command));
            return;
        }
        if (command === "Takeoff") {
            if (!isFinite(takeoffAltitudeMeters) || takeoffAltitudeMeters < vehicle.minimumTakeoffAltitudeMeters()) {
                safetyState.cancel(qsTr("Takeoff altitude is below the vehicle minimum"));
                return;
            }
            _request = {
                command: command,
                altitude: takeoffAltitudeMeters,
                vehicle: vehicle
            };
        } else if (command === "Standoff") {
            const config = widgetLayer.gamepadStandoffRequest();
            if (!config) {
                safetyState.cancel(qsTr("Configure a valid Standoff target inside the AOP"));
                return;
            }
            _request = {
                command: command,
                config: config,
                vehicle: vehicle
            };
        } else {
            _request = {
                command: command,
                vehicle: vehicle
            };
        }
    }

    Component.onCompleted: attachJoystick()
    Component.onDestruction: {
        if (_joystick)
            joystickManager.activeJoystickEnabledForActiveVehicle = false;
        if (_joystick)
            _joystick.setProtectedGamepadMode(false);
    }
    onActiveJoystickChanged: attachJoystick()
    onAvailableChanged: if (!available)
        disable()
    onVehicleChanged: disable()

    GamepadSafetyState {
        id: safetyState

        modeEnabled: root.modeEnabled

        onCommitted: command => root.execute(command)
        onNavigationRequested: (horizontal, vertical) => {
            if (root.modeEnabled && root.mapControl)
                root.mapControl.pan(horizontal * 40, vertical * 40);
        }
        onSelected: command => root.prepare(command)
    }

    Connections {
        function onProtectedGamepadState(buttons, safetyHeld, manualHeld, ready, generation, timestampMs) {
            if (!root.modeEnabled || generation !== root._generation)
                return;
            safetyState.process(buttons, safetyHeld, manualHeld, ready, timestampMs);
        }

        target: root.activeJoystick
    }

    Connections {
        function onActiveJoystickEnabledForActiveVehicleChanged() {
            if (!root._changing && !root.joystickManager.activeJoystickEnabledForActiveVehicle)
                root.disable();
        }

        target: root.joystickManager
    }

    Timer {
        interval: 200
        repeat: true
        running: root.modeEnabled

        onTriggered: if (!root.available || Date.now() - Math.max(safetyState.lastSampleMs, root._enabledAtMs) > 500)
            root.disable()
    }
}
