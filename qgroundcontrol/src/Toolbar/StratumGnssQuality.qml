import QtQuick

// STRATUM KAN-26 (#63): GNSS quality classifier for the top status-bar badge. Pure QtQuick
// (no QGC singletons) so it mounts standalone for unit tests. Applies the company-provided
// thresholds with weakest-link logic (never averaging) plus temporal hysteresis, evaluated
// once per second. Inputs are injected; this is presentation-only and never commands flight.
Item {
    id: root

    // --- Injected telemetry. eph/epv are horizontal/vertical accuracy in METRES (not DOP);
    //     hdop is the dimensionless HDOP; fixType is MAVLink GPS_RAW_INT.fix_type. ---
    property bool connected:    false
    property int  fixType:      0       // >= 3 is 3D or better
    property int  satellites:   -1      // < 0 means "no data"
    property real hdop:         NaN
    property real ephM:         NaN
    property real epvM:         NaN
    property real sampleAgeSec: 0       // age of the latest GPS sample, seconds

    // --- Company-provided thresholds (GOOD = minimum, BEST = tighter). ---
    property int  goodSats: 8
    property int  bestSats: 12
    property real goodHdop: 2.0
    property real bestHdop: 1.0
    property real goodEphM: 5.0
    property real bestEphM: 1.5
    property real goodEpvM: 8.0
    property real bestEpvM: 3.0
    property int  minFix3D: 3

    // --- Temporal rules (evaluated at 1 Hz). ---
    property real staleSec:       3.0
    property int  promoteCount:   3     // consecutive evals to upgrade (BAD->GOOD, GOOD->BEST)
    property int  downgradeCount: 2     // consecutive evals for a minor (threshold) downgrade

    // --- Published outputs. ---
    property string quality: "BAD"      // BAD | GOOD | BEST
    property string reason:  "DISCONNECTED"   // LOST_FIX | STALE | MISSING_FIELD | BELOW_THRESHOLD | VALID | DISCONNECTED

    property string _pendingTarget: ""
    property int    _pendingCount:  0

    function _rank(q) { return (q === "BEST") ? 2 : ((q === "GOOD") ? 1 : 0) }

    // Instantaneous classification with no hysteresis.
    function _instant() {
        if (!connected)
            return { "q": "BAD", "reason": "DISCONNECTED" }
        if (satellites < 0 || isNaN(hdop) || isNaN(ephM) || isNaN(epvM))
            return { "q": "BAD", "reason": "MISSING_FIELD" }
        if (sampleAgeSec > staleSec)
            return { "q": "BAD", "reason": "STALE" }
        if (fixType < minFix3D)
            return { "q": "BAD", "reason": "LOST_FIX" }
        if (satellites >= bestSats && hdop <= bestHdop && ephM <= bestEphM && epvM <= bestEpvM)
            return { "q": "BEST", "reason": "VALID" }
        if (satellites >= goodSats && hdop <= goodHdop && ephM <= goodEphM && epvM <= goodEpvM)
            return { "q": "GOOD", "reason": "VALID" }
        return { "q": "BAD", "reason": "BELOW_THRESHOLD" }
    }

    // Fix loss, staleness, missing data and disconnect are safety-significant: they downgrade
    // immediately and bypass the debounce.
    function _isImmediate(r) {
        return r === "DISCONNECTED" || r === "MISSING_FIELD" || r === "STALE" || r === "LOST_FIX"
    }

    // One 1 Hz evaluation step; applies hysteresis to `quality`/`reason`.
    function evaluate() {
        var inst = _instant()

        if (_isImmediate(inst.reason)) {
            _pendingTarget = ""
            _pendingCount = 0
            quality = "BAD"
            reason = inst.reason
            return
        }

        var rawRank = _rank(inst.q)
        var dispRank = _rank(quality)

        // Already at the instantaneous level: cancel any pending transition (recovery cancels downgrade).
        if (rawRank === dispRank) {
            _pendingTarget = ""
            _pendingCount = 0
            reason = inst.reason
            return
        }

        var required = (rawRank > dispRank) ? promoteCount : downgradeCount

        if (_pendingTarget !== inst.q) {
            _pendingTarget = inst.q
            _pendingCount = 1
        } else {
            _pendingCount += 1
        }

        if (_pendingCount >= required) {
            quality = inst.q
            reason = inst.reason
            _pendingTarget = ""
            _pendingCount = 0
        }
    }

    // Clear cached hysteresis state and readings (call on vehicle change/disconnect).
    function reset() {
        _pendingTarget = ""
        _pendingCount = 0
        quality = "BAD"
        reason = connected ? "STALE" : "DISCONNECTED"
    }

    // 1 Hz driver. Disable (`running: false`) in unit tests to step evaluate() deterministically.
    property bool running: true
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.evaluate()
    }

    onConnectedChanged: if (!connected) reset()
}
