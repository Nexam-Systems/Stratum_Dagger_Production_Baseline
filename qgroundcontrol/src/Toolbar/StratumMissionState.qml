import QtQuick

// STRATUM KAN-18: mission-lifecycle STATE classifier for the top status bar. Pure QtQuick
// (no QGC singletons) so it mounts standalone for unit tests. Exposes a stable `key` and a
// localized `text`; the status bar maps `key` to a theme colour. All inputs are injected.
//
// Precedence (first match wins) once armed: Abort > Engagement > RTL > Manual > Takeoff >
// Landing > Standoff(transit/at) > On Station > generic Armed. On Station / Transit / At
// Standoff are disambiguated geometrically because the autopilot reports Hold in several.
Item {
    id: root

    property var vehicle
    property var standoffController

    // Arrival tolerances (tunable). On Station = holding over home; At Standoff = established
    // on the standoff orbit (distance to target ~ orbit radius) at the commanded height.
    property real onStationRadiusM: 15
    property real standoffArrivalM: 30
    property real altToleranceM:    5
    property real minAirborneAltM:  2

    readonly property var  _facts: vehicle ? vehicle.vehicle : null
    readonly property bool _live:  !!vehicle && (!vehicle.vehicleLinkManager || vehicle.vehicleLinkManager.communicationLost !== true)

    function _num(fact) { return (fact && fact.rawValue !== undefined) ? Number(fact.rawValue) : Number.NaN }
    function _altRel()  { return _facts ? _num(_facts.altitudeRelative) : Number.NaN }

    function _distToHome() {
        if (vehicle && vehicle.coordinate && vehicle.coordinate.isValid
                && vehicle.homePosition && vehicle.homePosition.isValid)
            return vehicle.coordinate.distanceTo(vehicle.homePosition)
        return Number.NaN
    }
    function _overHome() {
        var d = _distToHome()
        return !isNaN(d) && d <= onStationRadiusM && _altRel() > minAirborneAltM
    }
    function _isRtlMode(mode) {
        if (mode === qsTr("Safe Recovery")) return true   // STRATUM StandardModes RTL name
        return !!vehicle && (mode === vehicle.rtlFlightMode || mode === vehicle.smartRTLFlightMode)
    }
    function _isManualMode(mode) {
        // PX4 "Position" (POSCTL) is presented to the operator as Manual; accept literal too.
        return mode === qsTr("Position") || mode === qsTr("Manual")
    }
    function _standoffEstablished() {
        if (!standoffController || !standoffController._targetCoordinate
                || !standoffController._targetCoordinate.isValid) return false
        if (!vehicle || !vehicle.coordinate || !vehicle.coordinate.isValid) return false
        var d = vehicle.coordinate.distanceTo(standoffController._targetCoordinate)
        var radiusOk = Math.abs(d - standoffController._standoffDistance) <= standoffArrivalM
        var h = standoffController._standoffHeight
        var altOk = (h > 0) ? Math.abs(_altRel() - h) <= altToleranceM : true
        return radiusOk && altOk
    }

    readonly property string key: {
        if (!vehicle)   return "DISCONNECTED"
        if (!_live)     return "COMMS_LOST"
        if (!vehicle.armed) {
            if (vehicle.readyToFlyAvailable && !vehicle.readyToFly) return "NOT_READY"
            if (!vehicle.allSensorsHealthy)                         return "NOT_READY"
            return "READY"
        }
        var mode = vehicle.flightMode
        if (mode === qsTr("Abort"))                                             return "ABORTING"
        if (mode === qsTr("Engagement") || mode === qsTr("Vision Engagement"))  return "ENGAGING"
        if (_isRtlMode(mode))                                                   return "RTL"
        if (_isManualMode(mode))                                                return "MANUAL"
        if (mode === qsTr("Takeoff"))                                           return "FLYING"
        if (vehicle.landing)                                                    return "LANDING"
        if (standoffController && standoffController._standoffActive === true)
            return _standoffEstablished() ? "AT_STDOFF" : "TRANSIT_STDOFF"
        if (_overHome())                                                        return "ON_STATION"
        return "ARMED"
    }

    readonly property string text: {
        switch (key) {
        case "DISCONNECTED":   return qsTr("DISCONNECTED")
        case "COMMS_LOST":     return qsTr("COMMS LOST")
        case "NOT_READY":      return qsTr("CONNECTED: NOT READY")
        case "READY":          return qsTr("CONNECTED: READY")
        case "FLYING":         return qsTr("FLYING")
        case "ON_STATION":     return qsTr("ON STATION")
        case "TRANSIT_STDOFF": return qsTr("TRANSIT TO STDOFF")
        case "AT_STDOFF":      return qsTr("AT STDOFF")
        case "ENGAGING":       return qsTr("ENGAGING")
        case "ABORTING":       return qsTr("ABORTING TO STDF")
        case "RTL":            return qsTr("RETURNING TO HOME")
        case "MANUAL":         return qsTr("MANUAL")
        case "LANDING":        return qsTr("LANDING")
        default:               return qsTr("ARMED")
        }
    }
}
