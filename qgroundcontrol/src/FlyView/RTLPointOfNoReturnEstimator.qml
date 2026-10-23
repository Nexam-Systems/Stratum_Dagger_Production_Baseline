import QtQuick

// STRATUM Issue #4 / Phase 0: Dynamic battery-aware RTL "Point of No Return" (PNR)
// decision countdown.
//
// Answers: "given live battery state, measured power, actual motion and position, how
// many seconds can I continue on my current path before initiating RTL is predicted to
// exceed the energy reserve OR the 15 km total-distance budget?"
//
// This is the FIRST-RELEASE direct-home approximation: a 1 Hz forward simulation along
// the current ground track with a straight-line return to PX4 home. All assumptions are
// provisional, so the status is reported as UNCALIBRATED until flight-validated. The
// estimate is ADVISORY: it never disables RTL and never overrides PX4 failsafes.
//
// Inputs are injected (vehicle) rather than read from singletons so the estimator is
// unit-testable. Call advance(dtSeconds) to integrate + recompute; the internal 1 Hz
// timer drives it in production, tests call it with deterministic dt.
Item {
    id: root

    property var vehicle

    // ---- Configuration (aircraft contract defaults; all overridable) ----------------
    property real packNominalEnergyWh:  570     // 22.8 V x 25 Ah reference (UNCALIBRATED)
    property real packCapacityAh:       25
    property real nominalVoltageV:      22.8
    property real reserveFraction:      0.20     // protected reserve, subtracted ONCE
    property real totalDistanceLimitM:  15000    // total route budget incl. return leg
    property real returnSpeedMS:        27.78     // 100 km/h target return speed (provisional)
    property real returnPowerOverrideW: 0         // 0 => use measured filtered power
    property real rtlOverheadWh:        20        // climb/descent/landing overhead (illustrative)
    property int  lookaheadSeconds:     600
    property real powerFilterTauSec:    10        // EWMA time constant; <=0 => instantaneous
    property bool modelValidated:       false     // flip to true only after flight validation
    property bool autoTick:             true      // internal 1 Hz driver; disable for deterministic tests

    // Calibration / test overrides (NaN/0 => use live telemetry).
    property real energyRemainingOverrideWh: Number.NaN
    property real homeRadialRateOverrideMS:  Number.NaN

    // ---- Published outputs (QML contract, contract Section 8) ------------------------
    readonly property int    pnrCountdownSeconds: _pnrCountdownSeconds
    readonly property string pnrStatus:           _pnrStatus
    readonly property string pnrReason:           _pnrReason
    readonly property string pnrUnknownReason:    _pnrUnknownReason
    readonly property real   batteryVoltageV:     _voltageV
    readonly property real   batteryCurrentA:     _currentA
    readonly property real   filteredPowerW:      _filteredPowerW
    readonly property real   remainingEnergyWh:   _remainingEnergyWh
    readonly property real   groundSpeedMS:       _groundSpeedMS
    readonly property real   distanceFromHomeM:   _distanceFromHomeM
    property real            distanceFlownM:       0
    readonly property real   rtlRequiredEnergyWh:  _rtlRequiredEnergyWh
    readonly property real   rtlEstimatedTimeSeconds: _rtlEstimatedTimeSeconds
    readonly property real   energyMarginWh:       _energyMarginWh
    readonly property real   predictedTotalDistanceM: _predictedTotalDistanceM
    readonly property real   consumedEnergyWh:     _consumedEnergyWh

    // ---- Backing state --------------------------------------------------------------
    property int    _pnrCountdownSeconds: -1
    property string _pnrStatus: "UNKNOWN"
    property string _pnrReason: "NONE"
    property string _pnrUnknownReason: "NO_VEHICLE"
    property real   _voltageV: Number.NaN
    property real   _currentA: Number.NaN
    property real   _filteredPowerW: 0
    property bool   _filteredInit: false
    property real   _remainingEnergyWh: Number.NaN
    property real   _groundSpeedMS: Number.NaN
    property real   _distanceFromHomeM: Number.NaN
    property real   _rtlRequiredEnergyWh: Number.NaN
    property real   _rtlEstimatedTimeSeconds: Number.NaN
    property real   _energyMarginWh: Number.NaN
    property real   _predictedTotalDistanceM: Number.NaN
    property real   _consumedEnergyWh: 0
    property real   _homeRadialRateMS: 0
    property real   _prevHomeDistM: Number.NaN
    property double _lastTickMs: 0
    property bool   _flownValid: false   // flown-distance track trusted since a verified takeoff
    property bool   _sawGround: false    // observed on-ground on the live link this session
    property bool   _wasAirborne: false

    readonly property bool connected: !!vehicle && vehicle.initialConnectComplete === true
        && (!vehicle.vehicleLinkManager || vehicle.vehicleLinkManager.communicationLost !== true)
    readonly property bool airborne: !!vehicle && vehicle.armed === true && vehicle.flying === true

    readonly property var _battery: (vehicle && vehicle.batteries && vehicle.batteries.count > 0) ? vehicle.batteries.get(0) : null
    readonly property var _facts:   vehicle ? vehicle.vehicle : null

    // PX4 battery charge-state passthrough (MAV_BATTERY_CHARGE_STATE: 3=CRITICAL..5=FAILED).
    readonly property int  batteryChargeState: (_battery && _battery.chargeState) ? _num(_battery.chargeState) : -1
    readonly property bool batteryCritical:    batteryChargeState >= 3 && batteryChargeState <= 5

    function _num(fact) {
        return (fact && fact.rawValue !== undefined) ? fact.rawValue : Number.NaN
    }

    // Reset per-flight integrators (new flight / vehicle change).
    function resetFlight() {
        distanceFlownM = 0
        _consumedEnergyWh = 0
        _filteredPowerW = 0
        _filteredInit = false
        _homeRadialRateMS = 0
        _prevHomeDistM = Number.NaN
    }

    onConnectedChanged: if (!connected) resetFlight()

    // Advance the estimate by dtSeconds using the current telemetry snapshot.
    function advance(dtSeconds) {
        var dt = dtSeconds
        if (!(dt > 0) || dt > 10)   // reject non-positive / stale gaps
            dt = 0

        // Issue #4 / Phase 0 guardrail: reset the flown-distance track ONLY on a verified
        // takeoff observed on a live link; never zero it on (re)connection. A reconnect
        // while airborne without a fresh ground->takeoff leaves the track untrusted.
        if (!connected) {
            _sawGround = false
            _flownValid = false
            _wasAirborne = false
        } else {
            if (!airborne)
                _sawGround = true
            if (airborne && !_wasAirborne && _sawGround) {
                resetFlight()
                _flownValid = true
            }
            _wasAirborne = airborne
        }

        _voltageV = _battery ? _num(_battery.voltage) : Number.NaN
        _currentA = _battery ? _num(_battery.current) : Number.NaN
        _groundSpeedMS = _facts ? _num(_facts.groundSpeed) : Number.NaN

        var pct = _battery ? _num(_battery.percentRemaining) : Number.NaN

        // Home distance: prefer the fact, fall back to coordinates.
        _distanceFromHomeM = _resolveHomeDistance()

        // Instantaneous electrical power.
        var power = (!isNaN(_voltageV) && !isNaN(_currentA) && _voltageV > 0 && _currentA >= 0)
            ? _voltageV * _currentA : Number.NaN

        if (!isNaN(power)) {
            if (!_filteredInit) {
                _filteredPowerW = power
                _filteredInit = true
            } else if (dt > 0) {
                var alpha = powerFilterTauSec > 0 ? (1 - Math.exp(-dt / powerFilterTauSec)) : 1
                _filteredPowerW = alpha * power + (1 - alpha) * _filteredPowerW
            }
            if (dt > 0)
                _consumedEnergyWh += power * dt / 3600   // unfiltered integration
        }

        // Track distance flown only while connected and airborne.
        if (dt > 0 && connected && airborne && !isNaN(_groundSpeedMS) && _groundSpeedMS >= 0)
            distanceFlownM += _groundSpeedMS * dt

        // Signed radial rate of home distance (away = +).
        if (dt > 0 && !isNaN(_distanceFromHomeM) && !isNaN(_prevHomeDistM)) {
            var inst = (_distanceFromHomeM - _prevHomeDistM) / dt
            var a = powerFilterTauSec > 0 ? (1 - Math.exp(-dt / powerFilterTauSec)) : 1
            _homeRadialRateMS = a * inst + (1 - a) * _homeRadialRateMS
        }
        if (!isNaN(_distanceFromHomeM))
            _prevHomeDistM = _distanceFromHomeM

        // Remaining energy: calibrated override, else SOC-scaled nominal (uncalibrated).
        if (!isNaN(energyRemainingOverrideWh) && energyRemainingOverrideWh > 0)
            _remainingEnergyWh = energyRemainingOverrideWh
        else if (!isNaN(pct) && pct >= 0)
            _remainingEnergyWh = packNominalEnergyWh * Math.max(0, Math.min(100, pct)) / 100
        else
            _remainingEnergyWh = Number.NaN

        _recompute(pct)
    }

    function _resolveHomeDistance() {
        if (_facts && _facts.distanceToHome) {
            var d = _num(_facts.distanceToHome)
            if (!isNaN(d) && d >= 0)
                return d
        }
        if (vehicle && vehicle.coordinate && vehicle.homePosition
                && vehicle.coordinate.isValid && vehicle.homePosition.isValid)
            return vehicle.coordinate.distanceTo(vehicle.homePosition)
        return Number.NaN
    }

    function _returnPowerW() {
        return returnPowerOverrideW > 0 ? returnPowerOverrideW : _filteredPowerW
    }

    // Forward simulation: find the earliest future second at which initiating RTL would
    // breach the energy-after-reserve margin or the total-distance budget.
    function _recompute(pct) {
        var unknownReason = ""
        if (!connected)                      unknownReason = "NO_VEHICLE"
        else if (_battery === null)          unknownReason = "NO_BATTERY"
        else if (!(_filteredPowerW > 0))     unknownReason = "NO_POWER"
        else if (isNaN(_remainingEnergyWh))  unknownReason = "NO_ENERGY_BASELINE"
        else if (isNaN(_distanceFromHomeM))  unknownReason = "NO_HOME"
        else if (isNaN(_groundSpeedMS))      unknownReason = "NO_VELOCITY"
        else if (airborne && !_flownValid)   unknownReason = "MISSING_FLOWN_DISTANCE"
        else if (!(returnSpeedMS > 0))       unknownReason = "NO_RETURN_MODEL"

        if (unknownReason !== "") {
            _pnrStatus = "UNKNOWN"
            _pnrReason = "NONE"
            _pnrUnknownReason = unknownReason
            _pnrCountdownSeconds = -1
            _rtlRequiredEnergyWh = Number.NaN
            _rtlEstimatedTimeSeconds = Number.NaN
            _energyMarginWh = Number.NaN
            _predictedTotalDistanceM = Number.NaN
            return
        }
        _pnrUnknownReason = ""

        var reserveWh = reserveFraction * packNominalEnergyWh
        var retPow = _returnPowerW()
        var v = Math.max(0, _groundSpeedMS)
        var radial = !isNaN(homeRadialRateOverrideMS) ? homeRadialRateOverrideMS : _homeRadialRateMS

        // t = 0 snapshot (published for the operator).
        var dHome0 = _distanceFromHomeM
        var retTime0 = dHome0 / returnSpeedMS
        var retE0 = retPow * retTime0 / 3600 + rtlOverheadWh
        var me0 = _remainingEnergyWh - retE0 - reserveWh
        var dtot0 = distanceFlownM + dHome0
        _rtlRequiredEnergyWh = retE0
        _rtlEstimatedTimeSeconds = retTime0
        _energyMarginWh = me0
        _predictedTotalDistanceM = dtot0

        // Already past a limit now?
        var energyHit0 = me0 <= 0
        var distHit0 = (totalDistanceLimitM - dtot0) <= 0
        if (energyHit0 || distHit0) {
            _pnrReason = (energyHit0 && distHit0) ? "BOTH" : (energyHit0 ? "ENERGY" : "DISTANCE")
            _pnrStatus = "PNR_REACHED"
            _pnrCountdownSeconds = 0
            return
        }

        var prevME = me0
        var prevMD = totalDistanceLimitM - dtot0
        var tEnergy = -1, tDist = -1
        for (var t = 1; t <= lookaheadSeconds; ++t) {
            var dHome = Math.max(0, _distanceFromHomeM + radial * t)
            var outE = _filteredPowerW * t / 3600
            var retTime = dHome / returnSpeedMS
            var retE = retPow * retTime / 3600 + rtlOverheadWh
            var me = _remainingEnergyWh - outE - retE - reserveWh
            var dtot = distanceFlownM + v * t + dHome
            var md = totalDistanceLimitM - dtot

            if (tEnergy < 0 && me <= 0)
                tEnergy = (t - 1) + prevME / (prevME - me)     // interpolate crossing
            if (tDist < 0 && md <= 0)
                tDist = (t - 1) + prevMD / (prevMD - md)
            if (tEnergy >= 0 && tDist >= 0)
                break
            prevME = me
            prevMD = md
        }

        if (tEnergy < 0 && tDist < 0) {
            _pnrStatus = "BEYOND_HORIZON"
            _pnrReason = "NONE"
            _pnrCountdownSeconds = -1
            return
        }

        var tCross, reason
        if (tEnergy >= 0 && (tDist < 0 || tEnergy <= tDist)) {
            tCross = tEnergy
            reason = (tDist >= 0 && Math.abs(tDist - tEnergy) < 0.5) ? "BOTH" : "ENERGY"
        } else {
            tCross = tDist
            reason = "DISTANCE"
        }
        _pnrReason = reason
        _pnrCountdownSeconds = Math.max(0, Math.floor(tCross))
        _pnrStatus = modelValidated ? "VALIDATED" : "UNCALIBRATED"
    }

    Timer {
        interval: 1000
        repeat:   true
        running:  root.autoTick
        onTriggered: {
            var now = Date.now()
            var dt = root._lastTickMs > 0 ? (now - root._lastTickMs) / 1000 : 1
            root._lastTickMs = now
            root.advance(dt)
        }
    }
}
