import QtQuick
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

// STRATUM: Engagement / Abort safety-loop controller.
//
// Centralises the operator safety loop around a terminal engagement so the Engage
// trigger (tool strip) and the Abort control + countdown (FlyView overlay) share one
// piece of state:
//
//   * arm-on-engage  -- pushes the abort-destination params (ABRT_*) at least once
//                       this session BEFORE entering Engagement, so an abort issued
//                       immediately after engage always resolves to a destination
//                       (Task 7);
//   * engage()       -- commands the PX4 custom Engagement mode (DO_SET_MODE sub=21);
//   * abort()        -- commands the PX4 custom Abort mode (DO_SET_MODE sub=22).
//
// Abort rides existing plumbing only. The mode switch reuses the same setFlightMode
// path already used for Standoff/Engagement; the destination is a standard PARAM_SET
// driven through the parameter manager (FactPanelController), which owns the ack /
// retry / readback. No custom MAVLink dialect is required for abort -- the 42001
// ENGAGEMENT_STATUS countdown is a separate, additive concern wired elsewhere.
Item {
    id: root

    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle

    // Mode display names MUST match the PX4FirmwarePlugin registration strings
    // (PX4FirmwarePlugin.cc constructor + updateAvailableFlightModes re-injection).
    readonly property string engagementModeName:       qsTr("Engagement")
    readonly property string visionEngagementModeName: qsTr("Vision Engagement")
    // PN-ENG: custom sub_mode 24, which Commander maps to nav_state 30. The sub-mode
    // number and the nav_state number are unrelated -- 30 is the reclaimed EXTERNAL8
    // slot, taken because FailsafeFlags.msg's mode_req_* bitfield is uint32 and
    // nav_states 0-31 exhaust it. Do not infer one number from the other.
    readonly property string pnEngagementModeName:     qsTr("PN Engagement")
    readonly property string abortModeName:            qsTr("Abort")

    // Abort-destination selection, mirroring the PX4 ABRT_* parameters.
    //   abortDest 0 = recover to the last standoff point (no lat/lon needed)
    //   abortDest 1 = recover to an explicit abort station (lat/lon, optional alt)
    property int    abortDest:        0
    property var    abortStation:     QtPositioning.coordinate()
    property real   abortRecoveryAlt: -1            // < 0  => keep current altitude

    // Session arming state. Held against a specific vehicle so a freshly connected
    // airframe is never assumed armed from a previous session.
    property bool   abortArmed:       false
    property var    _armedVehicle:    null

    // Non-fatal status surfaced to the operator (e.g. a missing ABRT_* param). The
    // overlay may bind to this; it never blocks the abort path.
    property string statusText:       ""

    // UI gate: true while the vehicle is in the engagement mode. The countdown panel
    // and the live ABORT control key off this (and, once available, the
    // ENGAGEMENT_STATUS dive state) per the contract.
    readonly property bool engaged:
        !!_activeVehicle && _activeVehicle.flightMode === engagementModeName

    // UI gate: true while the vehicle is in the vision-engagement mode (sub 23). The
    // vision guidance panel and its (reused) ABORT control key off this and the
    // VISION_ENGAGEMENT_STATUS state per the contract. Vision Engagement is a SEPARATE
    // mode from coordinate Engagement; the two are mutually exclusive.
    readonly property bool visionEngaged:
        !!_activeVehicle && _activeVehicle.flightMode === visionEngagementModeName

    // UI gate: true while the vehicle is in PN Engagement (sub 24). PN-ENG is a THIRD,
    // mutually exclusive engagement mode: it takes a fixed lat/lon target from
    // standoff_setpoint (MAV_CMD_DO_STANDOFF, 31010) like coordinate Engagement, but
    // runs a proportional-navigation law plus a closing-speed regulator and publishes
    // an acceleration setpoint rather than an attitude. Panels keying off this should
    // also read PN_ENGAGEMENT_STATUS (42006): unlike the other two modes, PN-ENG can
    // enter and then decline to guide, holding hover on an entry-gate reject.
    readonly property bool pnEngaged:
        !!_activeVehicle && _activeVehicle.flightMode === pnEngagementModeName

    // Parameter access. A bare FactPanelController targets the active vehicle and
    // routes value writes through ParameterManager (confirmed PARAM_SET).
    FactPanelController { id: _params }

    // Any change to the selection invalidates the current arming so the next engage
    // re-pushes the params.
    onAbortDestChanged:        abortArmed = false
    onAbortStationChanged:     abortArmed = false
    onAbortRecoveryAltChanged: abortArmed = false

    // Push one ABRT_* param via the manager. Returns false (and records a status
    // message) if the vehicle does not expose the parameter, so a firmware without
    // the abort params degrades to "abort still switches mode, recovery uses the
    // firmware default" rather than asserting.
    function _pushParam(name, value) {
        if (!_params.parameterExists(-1, name)) {
            statusText = qsTr("Abort parameter %1 not found on vehicle; using firmware default.").arg(name)
            console.warn("EngagementController:", statusText)
            return false
        }
        _params.getParameterFact(-1, name).value = value
        return true
    }

    // Push the current abort-destination selection. Idempotent; safe to call often.
    function armAbort() {
        if (!_activeVehicle) {
            return false
        }
        statusText = ""
        var ok = _pushParam("ABRT_DEST", abortDest)
        if (abortDest === 1 && abortStation.isValid) {
            // Full float precision -- do not pre-round (contract A3 note).
            _pushParam("ABRT_LAT", abortStation.latitude)
            _pushParam("ABRT_LON", abortStation.longitude)
        }
        // Recovery altitude above home; < 0 keeps current altitude (firmware semantics).
        _pushParam("ABRT_ALT", abortRecoveryAlt)
        abortArmed     = true
        _armedVehicle  = _activeVehicle
        return ok
    }

    function _ensureArmed() {
        if (!abortArmed || _armedVehicle !== _activeVehicle) {
            armAbort()
        }
    }

    // Task 7: guarantee an abort destination has been pushed before committing.
    function engage() {
        if (!_activeVehicle) {
            return
        }
        _ensureArmed()
        _activeVehicle.flightMode = engagementModeName
    }

    // Vision Engagement (custom sub_mode 23): a camera-guided run with NO target
    // coordinate. STRATUM only commands the mode -- the vehicle takes its target from
    // the companion camera tracker. The abort loop and the arm-on-engage safety are
    // REUSED unchanged from coordinate Engagement (contract A2/Task 6): same
    // _ensureArmed() push, same abort() below. Do NOT send DO_STANDOFF here -- vision
    // engagement has no map target (contract A1).
    function visionEngage() {
        if (!_activeVehicle) {
            return
        }
        _ensureArmed()
        _activeVehicle.flightMode = visionEngagementModeName
    }

    // PN Engagement (custom sub_mode 24): proportional-navigation terminal guidance
    // against the LATCHED standoff target. The abort loop and arm-on-engage safety are
    // reused unchanged from coordinate Engagement.
    //
    // Deliberately does NOT send DO_STANDOFF. The firmware's standoff_setpoint is a
    // latched one-shot -- which is why PNE_TGT_TOUT defaults to 0 (timeout disabled)
    // and why that default is correct, not an oversight. Re-sending the designation on
    // engage would let a stale operator map selection silently redefine the target at
    // the moment of commit. Designation and commitment are separate operator acts:
    // Set Standoff designates, PN Engage commits.
    function pnEngage() {
        if (!_activeVehicle) {
            return
        }
        _ensureArmed()
        _activeVehicle.flightMode = pnEngagementModeName
    }

    // Operator-initiated break-off. Deliberately independent of any valid
    // time-to-impact estimate: abort must work even when the countdown is "computing".
    // It is only meaningful during an engagement, so it does nothing in any other mode
    // (this also covers the joystick Abort action).
    function abort() {
        if (!_activeVehicle || !(engaged || visionEngaged || pnEngaged)) {
            return
        }
        _activeVehicle.flightMode = abortModeName
    }
}
