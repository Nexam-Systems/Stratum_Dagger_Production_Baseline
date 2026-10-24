import QtQuick

// STRATUM Issue #42 / Block-1: Layer 1 RTL & Abort gating on top of the PNR estimator.
//
// Read-only: it only computes whether the RTL ("Safe Recovery") and Abort controls should
// be ENABLED or grayed. It never commands a flight mode; PX4 failsafes remain the only
// enforced floor. Gate source follows the PNR model-quality degradation ladder:
//   * VALIDATED               -> PNR energy margin is the gate.
//   * PROVISIONAL (default)   -> simple time policy AND PNR advisory (logical AND to enable).
//   * UNKNOWN                 -> simple time policy alone (+ PX4 native failsafe).
//
// Pure QtQuick (no QGC singletons) so it mounts standalone for unit tests; inputs injected.
// Call advance(dtSeconds) to recompute (internal timer drives it; tests call it directly).
Item {
    id: root

    property var estimator   // RTLPointOfNoReturnEstimator (Layer 0)
    property var vehicle

    // ---- Simple time policy (§4) + abort budget (§5) constants (provisional; configurable) --
    property real maxFlightMinutes:  25     // max mission flight time
    property real backstopUsedMin:   13     // "used > 13 min AND distance > 8 km" backstop
    property real backstopDistKm:    8
    property int  maxAborts:         3      // PROVISIONAL cap -- confirm with issue #42 §5
    property real abortChargeMin:    1      // each abort charges 1 min against the budget
    property int  pnrFloorSeconds:   5      // latency margin: gray RTL when timeToPnr <= floor
    property real hysteresisSeconds: 3      // debounce enable<->gray to avoid flicker
    property bool autoTick:          true   // internal driver; disable for deterministic tests

    // ---- Published gate outputs ----
    readonly property bool rtlAllowed:      _rtlCommitted
    readonly property bool abortAllowed:    _abortCommitted
    readonly property int  abortsDone:      _abortsDone
    readonly property int  abortsRemaining: Math.max(0, maxAborts - _abortsDone)

    // ---- Backing state ----
    property bool   _rtlCommitted:   true
    property bool   _abortCommitted: true
    property real   _rtlPending:     0
    property real   _abortPending:   0
    property int    _abortsDone:     0
    property string _prevMode:       ""
    property double _lastMs:         0

    readonly property var _facts: (vehicle && vehicle.vehicle) ? vehicle.vehicle : null

    function _num(fact) { return (fact && fact.rawValue !== undefined) ? Number(fact.rawValue) : Number.NaN }

    function _airborne() { return !!vehicle && vehicle.armed === true && vehicle.flying === true }

    function _elapsedMin() {
        var s = _facts ? _num(_facts.flightTime) : Number.NaN
        return isFinite(s) ? s / 60 : Number.NaN
    }
    function _usedMin()     { return _elapsedMin() + _abortsDone * abortChargeMin }
    function _effRemainMin(){ return maxFlightMinutes - _usedMin() }

    function _distanceKm() {
        var d = estimator ? estimator.distanceFromHomeM : Number.NaN
        if (!isFinite(d) && vehicle && vehicle.coordinate && vehicle.coordinate.isValid
                && vehicle.homePosition && vehicle.homePosition.isValid)
            d = vehicle.coordinate.distanceTo(vehicle.homePosition)
        return isFinite(d) ? d / 1000 : Number.NaN
    }

    // Simple time policy (§4): gray if ANY rule fails. Rules apply only where data exists so
    // RTL is never wrongly disabled on missing telemetry (PX4 failsafe is the floor).
    function _simplePolicyEnable() {
        var eff = _effRemainMin()
        if (isFinite(eff) && eff <= 0) return false
        var dist = _distanceKm()
        if (isFinite(eff) && isFinite(dist)) {
            if (_usedMin() > backstopUsedMin && dist > backstopDistKm) return false
            if (eff <= dist) return false
        }
        return true
    }

    // PNR layer says stop (reached, battery critical, or inside the latency floor).
    function _pnrSaysStop() {
        if (!estimator) return false
        if (estimator.pnrStatus === "PNR_REACHED") return true
        if (estimator.batteryCritical === true) return true
        var t = estimator.pnrCountdownSeconds
        if (t >= 0 && t <= pnrFloorSeconds) return true
        return false
    }

    function _computeRtlAllowed() {
        if (!_airborne()) return true   // RTL stays available pre-flight / on the ground
        var validated = estimator ? estimator.modelValidated === true : false
        var status    = estimator ? estimator.pnrStatus : "UNKNOWN"
        if (validated && status !== "UNKNOWN")
            return !_pnrSaysStop()                       // VALIDATED row: PNR energy gate
        if (status === "UNKNOWN")
            return _simplePolicyEnable()                 // time policy alone
        return _simplePolicyEnable() && !_pnrSaysStop()  // PROVISIONAL: AND of both
    }

    function _computeAbortAllowed() {
        if (!_airborne()) return true
        if (_abortsDone >= maxAborts) return false       // budget exhausted
        var eff = _effRemainMin()
        if (isFinite(eff) && eff <= abortChargeMin) return false  // no room to charge another
        return true
    }

    // Advance the gate by dtSeconds: update the abort counter, recompute, apply hysteresis.
    function advance(dtSeconds) {
        var dt = (dtSeconds > 0 && dtSeconds < 10) ? dtSeconds : 0

        var mode = vehicle ? vehicle.flightMode : ""
        if (!vehicle || vehicle.armed !== true) {
            _abortsDone = 0                               // reset between flights
        } else if (mode === "Abort" && _prevMode !== "Abort") {
            _abortsDone += 1                             // count each entry into Abort
        }
        _prevMode = mode

        var rawRtl = _computeRtlAllowed()
        if (rawRtl === _rtlCommitted) {
            _rtlPending = 0
        } else {
            _rtlPending += dt
            if (_rtlPending >= hysteresisSeconds) { _rtlCommitted = rawRtl; _rtlPending = 0 }
        }

        var rawAbort = _computeAbortAllowed()
        if (rawAbort === _abortCommitted) {
            _abortPending = 0
        } else {
            _abortPending += dt
            if (_abortPending >= hysteresisSeconds) { _abortCommitted = rawAbort; _abortPending = 0 }
        }
    }

    Timer {
        interval: 250
        repeat:   true
        running:  root.autoTick
        onTriggered: {
            var now = Date.now()
            var dt  = root._lastMs > 0 ? (now - root._lastMs) / 1000 : 0.25
            root._lastMs = now
            root.advance(dt)
        }
    }
}
