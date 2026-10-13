import QtQuick

Item {
    id: root

    property double _nowMs: Date.now()
    property bool armMustRelease: true
    property double armStartedMs: 0
    property int buttons: 0
    readonly property bool commitReady: modeEnabled && inputReady && pendingCommand !== "" && safetyHeld && !armMustRelease && armStartedMs > 0 && _nowMs - armStartedMs >= 600
    property string completedHoldCommand: ""
    property double completedHoldUntilMs: 0
    property bool engageMustRelease: true
    property string feedback: qsTr("Joystick disabled")
    readonly property bool holdActive: modeEnabled && inputReady && holdStartedMs > 0 && holdDurationMs > 0
    readonly property int holdDurationMs: pendingCommand === "Engage" ? 3000 : pendingCommand === "Abort" ? 1000 : 0
    readonly property real holdProgress: holdStartedMs > 0 && holdDurationMs > 0 ? Math.min(1, Math.max(0, (_nowMs - holdStartedMs) / holdDurationMs)) : 0
    property double holdStartedMs: 0
    property bool inputReady: false
    property double lastSampleMs: 0
    property bool manualHeld: false
    property bool modeEnabled: false
    property string pendingCommand: ""
    property bool safetyHeld: false
    property double selectionDeadlineMs: 0

    signal committed(string command)
    signal navigationRequested(int horizontal, int vertical)
    signal selected(string command)

    function cancel(message) {
        pendingCommand = "";
        armStartedMs = 0;
        selectionDeadlineMs = 0;
        armMustRelease = true;
        feedback = message;
        holdStartedMs = 0;
        engageMustRelease = true;
    }

    function process(sampleButtons, sampleSafety, sampleManual, ready, timestamp) {
        const now = Date.now();
        if (!modeEnabled || timestamp < lastSampleMs || now - timestamp > 250 || timestamp > now)
            return;
        const pressed = sampleButtons & ~buttons;
        const previousSafety = safetyHeld;
        const previousReady = inputReady;
        const interrupted = lastSampleMs > 0 && timestamp - lastSampleMs > 250;
        buttons = sampleButtons;
        safetyHeld = sampleSafety;
        manualHeld = sampleManual;
        lastSampleMs = timestamp;
        _nowMs = now;
        inputReady = ready;
        if (interrupted && holdStartedMs > 0) {
            holdStartedMs = 0;
            engageMustRelease = true;
            if (pendingCommand === "Abort") {
                cancel(qsTr("Abort hold interrupted — release and retry"));
                return;
            }
        }
        if (!ready) {
            cancel(qsTr("Release all buttons and triggers"));
            return;
        }
        if (!previousReady)
            feedback = qsTr("Joystick enabled");
        if (manualHeld) {
            cancel(qsTr("Manual control active — R2 held"));
            return;
        }
        if (pendingCommand !== "" && now >= selectionDeadlineMs)
            cancel(qsTr("Selection expired"));
        const facePressed = pressed & 15;
        if (facePressed && (facePressed & (facePressed - 1))) {
            cancel(qsTr("Conflicting buttons — selection cancelled"));
            return;
        }
        if (pressed & 2) {
            if (sampleButtons & (1 << 9)) {
                select("Abort", timestamp);
                if (pendingCommand === "Abort")
                    holdStartedMs = timestamp;
            } else
                cancel(qsTr("Selection cancelled — no vehicle command sent"));
            return;
        }
        if (pressed & 8) {
            select((sampleButtons & (1 << 9)) ? "Engage" : "Takeoff", timestamp);
            return;
        }
        if (pressed & 4) {
            select("Standoff", timestamp);
            return;
        }
        if (pressed & 1) {
            select("RTL", timestamp);
            return;
        }
        if (pendingCommand === "Abort" || pendingCommand === "Engage") {
            const abortHeld = (sampleButtons & 2) !== 0 && (sampleButtons & (1 << 9)) !== 0;
            const engageHeld = safetyHeld && (sampleButtons & (1 << 10)) !== 0;
            if (pendingCommand === "Engage" && !safetyHeld && (sampleButtons & (1 << 10)) === 0)
                engageMustRelease = false;
            const held = pendingCommand === "Abort" ? abortHeld : engageHeld && !engageMustRelease;
            if (!held) {
                holdStartedMs = 0;
                if (pendingCommand === "Abort")
                    cancel(qsTr("Abort hold cancelled"));
            } else {
                if (holdStartedMs <= 0)
                    holdStartedMs = timestamp;
                if (timestamp - holdStartedMs >= holdDurationMs) {
                    const command = pendingCommand;
                    cancel(qsTr("%1 committed").arg(command));
                    completedHoldCommand = command;
                    completedHoldUntilMs = now + 700;
                    committed(command);
                }
            }
            return;
        }
        if (!safetyHeld) {
            armMustRelease = false;
            armStartedMs = 0;
        } else if (!previousSafety && !armMustRelease && pendingCommand !== "") {
            armStartedMs = timestamp;
        }
        if (pressed & (1 << 10)) {
            if (commitReady) {
                const command = pendingCommand;
                cancel(qsTr("%1 committed").arg(command));
                committed(command);
            } else if (pendingCommand !== "") {
                feedback = qsTr("Hold L2, then press R1 again");
            }
        }
        if (pendingCommand === "") {
            if (pressed & (1 << 11))
                navigationRequested(0, -1);
            if (pressed & (1 << 12))
                navigationRequested(0, 1);
            if (pressed & (1 << 13))
                navigationRequested(-1, 0);
            if (pressed & (1 << 14))
                navigationRequested(1, 0);
        }
    }

    function reset(message) {
        pendingCommand = "";
        armStartedMs = 0;
        selectionDeadlineMs = 0;
        armMustRelease = true;
        safetyHeld = false;
        manualHeld = false;
        inputReady = false;
        buttons = 0;
        lastSampleMs = 0;
        feedback = message;
        holdStartedMs = 0;
        engageMustRelease = true;
        completedHoldCommand = "";
        completedHoldUntilMs = 0;
    }

    function select(command, timestamp) {
        completedHoldCommand = "";
        completedHoldUntilMs = 0;
        selectionDeadlineMs = timestamp + 8000;
        armStartedMs = 0;
        armMustRelease = safetyHeld;
        holdStartedMs = 0;
        engageMustRelease = safetyHeld || (buttons & (1 << 10)) !== 0;
        feedback = qsTr("%1 selected").arg(command);
        pendingCommand = command;
        selected(command);
    }

    onModeEnabledChanged: reset(modeEnabled ? qsTr("Release all buttons and triggers") : qsTr("Joystick disabled"))

    Timer {
        interval: 100
        repeat: true
        running: root.modeEnabled

        onTriggered: {
            root._nowMs = Date.now();
            if (root.lastSampleMs > 0 && root._nowMs - root.lastSampleMs > 500) {
                root.reset(qsTr("Gamepad input lost"));
            } else if (root.pendingCommand !== "" && root._nowMs >= root.selectionDeadlineMs) {
                root.cancel(qsTr("Selection expired"));
            }
        }
    }
}
