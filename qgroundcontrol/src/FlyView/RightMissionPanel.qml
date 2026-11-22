import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Rectangle {
    id: root

    property var actionModel: []
    // KAN-53: whichever hold button is currently being held (any HoldCommand reports itself here).
    property var activeHold: null
    property var _holdButtons: []
    property bool cameraPrimary: false
    // STRATUM KAN-51: opacity (0..1) of the panel background, border and separator; set from the
    // hidden Admin panel. 0 leaves only the buttons, compass heading and camera/map preview.
    property real backgroundOpacity: 1.0
    property bool contextActive: true
    // STRATUM #42: Layer-1 gate -> grays the RTL / Abort buttons when it says stop.
    property var rtlAbortGate: null
    required property var engagementController
    property string feedback: ""
    required property var guidedController
    readonly property bool headingFresh: linkReady && vehicle.vehicle.attitudeTimestampMs > 0 && nowMs - vehicle.vehicle.attitudeTimestampMs < 2000 && isFinite(Number(vehicle.vehicle.heading.rawValue))
    property string completedCommand: ""
    // KAN-53: role ("engage", "abort", "navigation" ...) of the button whose hold just completed.
    property string completedRole: "navigation"
    readonly property string holdCommand: activeHold ? activeHold.command : completedCommand
    readonly property real holdProgress: activeHold ? activeHold.holdProgress : (completedCommand !== "" ? 1 : 0)
    readonly property bool holdComplete: !activeHold && completedCommand !== ""
    // KAN-53: colour of the hold bar. The normal accent while the button is still being held; once the
    // hold has COMPLETED (the bar is full and it is safe to lift the finger) it takes the colour of the
    // button that was held: red for Engage, orange for Abort, the neutral accent for the other commands.
    readonly property color holdColor: holdComplete ? actionBorder(completedRole) : accentGlow
    readonly property bool linkReady: vehicle && vehicle.initialConnectComplete && !vehicle.vehicleLinkManager.communicationLost
    readonly property bool engageEligible: linkReady && vehicle.armed && vehicle.flying && engagementController && vehicle.flightModes.indexOf(engagementController.engagementModeName) >= 0 && vehicle.flightMode !== engagementController.engagementModeName
    // STRATUM #42: RTL (Safe Recovery) and Abort availability from the Layer-1 gate.
    readonly property bool rtlAllowed:   !rtlAbortGate || rtlAbortGate.rtlAllowed
    readonly property bool abortAllowed: !rtlAbortGate || rtlAbortGate.abortAllowed
    property double nowMs: Date.now()
    property alias previewSlot: previewSlot
    property alias additionalControlsSlot: additionalControlsSlot
    required property var vehicle

    signal aopRequested
    signal fetchRequested
    signal standoffRequested
    signal takeoffRequested
    signal viewSelected

    // STRATUM KAN-53: where a box opened from `item` (a panel button) should sit: a rect in window
    // coordinates covering the panel's left edge at the button's height. The box opens just left of
    // it, vertically centred on the button, so a touch-screen operator can stay at the screen edge.
    function anchorRectFor(item) {
        var panelTopLeft = root.mapToItem(null, 0, 0);
        var buttonTopLeft = item.mapToItem(null, 0, 0);
        return Qt.rect(panelTopLeft.x, buttonTopLeft.y, root.width, item.height);
    }

    // Vertical centre of the Standoff button in the coordinates of this panel's parent (the Set
    // Standoff panel is a sibling and lines up with it).
    function standoffAnchorCenterY() {
        return standoffButton.mapToItem(root.parent, 0, standoffButton.height / 2).y;
    }

    function cancelHolds() {
        for (var i = 0; i < _holdButtons.length; ++i) {
            _holdButtons[i].cancelHold();
        }
    }

    // STRATUM KAN-53: shows the completed state on the hold bar for a moment, in the colour of the
    // button that was held (role: "engage", "abort", or "navigation" for the neutral commands).
    function holdCommitted(commandName, role) {
        root.completedRole = role ? role : "navigation";
        root.completedCommand = commandName;
        completionTimer.restart();
    }

    // STRATUM KAN-21 / KAN-53: direct flight-mode change. The 1-second hold on the button is the
    // confirmation, so there is no dialog. modeName is the advertised firmware mode actually
    // written to Vehicle.flightMode ("Position" for the Manual button, "Safe Recovery" for RTL).
    function commandFlightMode(modeName, displayName) {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (!v) return
        actionPopup.close()
        v.flightMode = modeName
        holdCommitted(displayName)
    }

    // STRATUM: RTL is PX4 "Safe Recovery" (StandardModes) or "Return"; pick whichever
    // the firmware advertises. Labelled "RTL" in the UI.
    function rtlModeName() {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (v && v.flightModes) {
            if (v.flightModes.indexOf(qsTr("Safe Recovery")) !== -1) return qsTr("Safe Recovery")
            if (v.flightModes.indexOf(qsTr("Return")) !== -1) return qsTr("Return")
        }
        return qsTr("Safe Recovery")
    }

    // STRATUM KAN-21 / KAN-50: button theming. Engage and Emergency Kill share the same crimson red
    // and Abort reads orange in BOTH the normal and high-contrast themes (safety-critical, must
    // stay recognisable); every other command uses the neutral theme button colour. A coloured
    // edge glow is kept on all buttons. accentGlow follows the active theme accent.
    readonly property color accentGlow: panelPalette.lightTheme ? panelPalette.brandingPurple : (panelPalette.highContrast ? "#2EE62E" : "#79CBE8")
    function actionSpecial(role) { return role === "engage" || role === "abort" || role === "kill" || role === "killActive" }

    function actionFill(role) {
        if (panelPalette.lightTheme) {
            if (role === "killActive") return Qt.tint(panelPalette.window, Qt.rgba(panelPalette.colorRed.r, panelPalette.colorRed.g, panelPalette.colorRed.b, 0.55))
            if (role === "kill" || role === "engage") return Qt.tint(panelPalette.window, Qt.rgba(panelPalette.colorRed.r, panelPalette.colorRed.g, panelPalette.colorRed.b, 0.28))
            if (role === "abort") return Qt.tint(panelPalette.window, Qt.rgba(panelPalette.colorOrange.r, panelPalette.colorOrange.g, panelPalette.colorOrange.b, 0.12))
        }
        if (role === "killActive") return "#E3162B"
        if (role === "kill" || role === "engage") return "#B3141F"
        if (role === "abort")  return "#7A3E12"
        return panelPalette.button
    }

    function actionBorder(role) {
        if (panelPalette.lightTheme) {
            if (role === "kill" || role === "killActive" || role === "engage") return panelPalette.colorRed
            if (role === "abort") return panelPalette.colorOrange
        }
        if (role === "killActive") return "#FFFFFF"
        if (role === "kill" || role === "engage") return "#FF3B3B"
        if (role === "abort")  return "#FF9F45"
        return root.accentGlow
    }

    border.color: Qt.rgba(panelPalette.groupBorder.r, panelPalette.groupBorder.g, panelPalette.groupBorder.b, panelPalette.groupBorder.a * root.backgroundOpacity)
    border.width: 1
    // STRATUM KAN-51: only the panel chrome (background, border, separator) follows backgroundOpacity;
    // the buttons, compass heading and camera/map preview are separate items and keep their look.
    color: {
        var base = panelPalette.highContrast || panelPalette.lightTheme ? panelPalette.window : Qt.rgba(panelPalette.window.r, panelPalette.window.g, panelPalette.window.b, 0.80)
        return Qt.rgba(base.r, base.g, base.b, base.a * root.backgroundOpacity)
    }

    onContextActiveChanged: if (!contextActive)
        cancelHolds()
    onVehicleChanged: {
        cancelHolds();
        feedback = "";
        completedCommand = "";
        actionPopup.close();
    }
    onVisibleChanged: if (!visible) {
        cancelHolds();
        actionPopup.close();
    }

    QGCPalette {
        id: panelPalette

        colorGroupEnabled: true
    }

    DeadMouseArea {
        anchors.fill: parent
    }

    Item {
        id: actionScroll

        anchors.bottom: previewSection.top
        anchors.left: parent.left
        anchors.margins: 6
        anchors.right: parent.right
        anchors.top: parent.top
        clip: true

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            // STRATUM KAN-49: never scrollable. When the buttons do not fit (short window) the
            // layout is capped to the available height and the buttons shrink towards their
            // minimum height instead of being clipped.
            height: Math.min(implicitHeight, parent.height)
            spacing: 5

            // STRATUM KAN-21 / KAN-51: ordered command column of circular buttons (icon + short label
            // inside the circle). Engage and Emergency Kill read red, Abort reads orange, every other
            // command uses the neutral theme colour; all keep the edge glow. The flight-mode picker was
            // removed in favour of explicit Manual + RTL buttons. Engage no longer needs an enable
            // toggle -- the 3 s hold-to-confirm is the safety interlock.
            ColumnLayout {
                id: commandColumn
                Layout.fillWidth: true
                spacing: 2

                // KAN-53: Define AOP, Fetch Target, Land, Hold, Manual and RTL send after a 1-second hold;
                // the hold is the confirmation, so there is no pop-up. Takeoff, Standoff and Change
                // Height open their input box straight away (the confirm button inside the box is held).
                HoldCommand {
                    command: qsTr("Define AOP")
                    holdDuration: 1000
                    // Defining the AOP needs no vehicle, so hold on this root when none is connected.
                    vehicleIdentity: root.vehicle ? root.vehicle : root
                    iconSource: "/InstrumentValueIcons/map.svg"
                    objectName: "missionDefineAOP"
                    visualRole: "navigation"
                    text: qsTr("Define AOP")
                    shortText: qsTr("AOP")
                    onCommitted: {
                        actionPopup.close();
                        root.aopRequested();
                        root.holdCommitted(command);
                    }
                }

                HoldCommand {
                    command: qsTr("Fetch Target")
                    enabled: !!root.vehicle
                    holdDuration: 1000
                    iconSource: "/InstrumentValueIcons/target.svg"
                    objectName: "missionFetchTarget"
                    visualRole: "navigation"
                    text: qsTr("Fetch Target")
                    shortText: qsTr("Target")
                    onCommitted: {
                        if (!enabled)
                            return;
                        actionPopup.close();
                        root.fetchRequested();
                        root.holdCommitted(command);
                    }
                }

                PrimaryCommand {
                    id: takeoffButton

                    enabled: root.linkReady && root.guidedController && root.guidedController.showTakeoff
                    iconSource: "/InstrumentValueIcons/arrow-thick-up.svg"
                    objectName: "missionTakeoff"
                    visualRole: "navigation"
                    text: qsTr("Takeoff")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.guidedController.popupAnchorRect = root.anchorRectFor(takeoffButton);
                        root.takeoffRequested();
                    }
                }

                HoldCommand {
                    command: qsTr("Land")
                    enabled: root.linkReady
                    holdDuration: 1000
                    iconSource: "/InstrumentValueIcons/inbox-download.svg"
                    objectName: "missionLand"
                    visualRole: "navigation"
                    text: qsTr("Land")
                    onCommitted: {
                        if (enabled)
                            root.commandFlightMode(qsTr("Land"), qsTr("Land"));
                    }
                }

                HoldCommand {
                    command: qsTr("Hold")
                    enabled: root.linkReady
                    holdDuration: 1000
                    iconSource: "/InstrumentValueIcons/pause-solid.svg"
                    objectName: "missionHold"
                    visualRole: "navigation"
                    text: qsTr("Hold")
                    onCommitted: {
                        if (enabled)
                            root.commandFlightMode(qsTr("Hold"), qsTr("Hold"));
                    }
                }

                HoldCommand {
                    command: qsTr("Manual")
                    enabled: root.linkReady
                    holdDuration: 1000
                    iconSource: "/qmlimages/PanelGamepad.svg"
                    objectName: "missionManual"
                    visualRole: "navigation"
                    text: qsTr("Manual")
                    onCommitted: {
                        if (enabled)
                            root.commandFlightMode(qsTr("Position"), qsTr("Manual"));
                    }
                }

                HoldCommand {
                    command: qsTr("RTL")
                    // STRATUM #42: grayed when the Layer-1 gate forbids RTL.
                    enabled: root.linkReady && root.rtlAllowed
                    holdDuration: 1000
                    iconSource: "/InstrumentValueIcons/home.svg"
                    objectName: "missionRTL"
                    visualRole: "navigation"
                    text: qsTr("RTL")
                    onCommitted: {
                        if (enabled)
                            root.commandFlightMode(root.rtlModeName(), qsTr("RTL"));
                    }
                }

                PrimaryCommand {
                    id: standoffButton

                    enabled: !!root.vehicle
                    iconSource: "/qmlimages/StandoffMarker.svg"
                    objectName: "missionStandoff"
                    visualRole: "navigation"
                    text: qsTr("Standoff")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.standoffRequested();
                    }
                }

                HoldCommand {
                    id: abortButton

                    command: qsTr("Abort")
                    // STRATUM #42: Layer-1 abort budget / feasibility gate.
                    enabled: root.linkReady && root.vehicle.armed && root.engagementController && root.vehicle.flightModes.indexOf(root.engagementController.abortModeName) >= 0 && root.abortAllowed
                    holdDuration: 1000
                    iconSource: "/res/Stop.svg"
                    objectName: "missionAbort"
                    visualRole: "abort"
                    text: qsTr("Abort")

                    onCommitted: {
                        if (!enabled || !root.linkReady)
                            return;
                        root.engagementController.abort();
                        root.feedback = qsTr("Abort requested â€” awaiting vehicle response");
                        root.holdCommitted(qsTr("Abort"), "abort");
                    }
                }

                HoldCommand {
                    id: engageButton

                    command: qsTr("Engage")
                    // STRATUM KAN-21: enabled by default when eligible -- the 3 s hold is the confirm.
                    enabled: root.engageEligible
                    holdDuration: 3000
                    iconSource: "/res/chevron-double-right.svg"
                    objectName: "missionEngage"
                    visualRole: "engage"
                    text: qsTr("Engage")

                    onCommitted: {
                        if (!enabled || !root.engageEligible)
                            return;
                        root.engagementController.engage();
                        root.feedback = qsTr("Engage requested â€” awaiting vehicle response");
                        root.holdCommitted(qsTr("Engage"), "engage");
                    }
                }

                // STRATUM #83 / KAN-45: change the vehicle's height in flight. Opens a small
                // "Change Height" pop-up (like Takeoff) prefilled with the current height and
                // limited to the guided min/max; pressing its "Change Height" button computes the
                // delta from altitudeRelative and calls guidedModeChangeAltitude(). Enabled only
                // while flying/armed/guided-capable (showChangeAlt).
                CommandButton {
                    id: changeHeightButton

                    enabled: root.guidedController && root.guidedController.showChangeAlt
                    iconSource: "/res/chevron-up.svg"
                    objectName: "missionChangeHeight"
                    visualRole: "navigation"
                    text: qsTr("Change Height")
                    shortText: qsTr("Height")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.guidedController.popupAnchorRect = root.anchorRectFor(changeHeightButton);
                        root.guidedController.confirmAction(root.guidedController.actionChangeAlt);
                    }
                }

                // STRATUM KAN-49: dedicated Emergency Kill, a LATCHING toggle like the joystick kill
                // switch. First press force-disarms and holds the kill (Vehicle.killSwitchEngaged:
                // MANUAL_CONTROL button bit, works with or without a joystick) until it is pressed
                // again to release. Deliberately NO confirmation, hold or flight-mode / arm gating:
                // it is a safety control and must act on the first click whenever a vehicle is
                // connected. Shown in both the Dev and Client builds.
                CommandButton {
                    readonly property bool killEngaged: !!root.vehicle && root.vehicle.killSwitchEngaged === true

                    enabled: !!root.vehicle
                    iconSource: "/qmlimages/PanelAlert.svg"
                    objectName: "missionEmergencyKill"
                    visualRole: killEngaged ? "killActive" : "kill"
                    text: killEngaged ? qsTr("Release Kill") : qsTr("Emergency Kill")
                    shortText: killEngaged ? qsTr("Release") : qsTr("E-Kill")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        if (root.vehicle)
                            root.vehicle.setKillSwitchEngaged(!killEngaged);
                    }
                }

                // STRATUM: any remaining profile-specific actions from the model (e.g. the
                // Dropper payload panel). The commands rendered explicitly above are excluded
                // so they are not duplicated.
                Repeater {
                    model: root.actionModel

                    CommandButton {
                        id: secondaryButton

                        readonly property var entry: modelData
                        required property var modelData

                        enabled: entry.enabled
                        iconSource: entry.iconSource
                        objectName: "missionSecondary_" + entry.text
                        visualRole: "navigation"
                        text: entry.text
                        visible: entry.visible && [qsTr("Takeoff"), qsTr("Standoff"), qsTr("Abort"), qsTr("Engage"),
                                                   qsTr("Fetch Target"), qsTr("Land"), qsTr("Hold"), qsTr("Flight Mode")].indexOf(entry.text) < 0

                        onClicked: {
                            root.cancelHolds();
                            if (entry.dropPanelComponent) {
                                actionLoader.sourceComponent = entry.dropPanelComponent;
                                // KAN-53: open beside the panel, lined up with this button.
                                actionPopup.anchorCenterY = secondaryButton.mapToItem(null, 0, secondaryButton.height / 2).y;
                                actionPopup.open();
                            } else
                                entry.triggered(this);
                        }
                    }
                }
            }

            Item {
                id: additionalControlsSlot
                Layout.fillWidth: true
                implicitHeight: childrenRect.height
                Layout.preferredHeight: implicitHeight
            }
        }
    }

    Column {
        id: previewSection

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.bottomMargin: 10
        anchors.right: parent.right
        spacing: 6

        Rectangle {
            width: parent.width
            color: Qt.rgba(panelPalette.groupBorder.r, panelPalette.groupBorder.g, panelPalette.groupBorder.b, panelPalette.groupBorder.a * root.backgroundOpacity)
            height: 1
        }

        QGCCompassWidget {
            anchors.horizontalCenter: parent.horizontalCenter
            objectName: "missionCompass"
            size: 72
            showHeadingLabel: false
            vehicle: root.headingFresh ? root.vehicle : null
            visible: root.headingFresh
        }

        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.headingFresh ? qsTr("%1").arg(Number(root.vehicle.vehicle.heading.rawValue).toFixed(0)) : qsTr("Heading unavailable")
        }

        Item {
            id: previewSlot

            height: width * 9 / 16
            width: parent.width

            Rectangle {
                anchors.fill: parent
                border.color: panelPalette.groupBorder
                color: panelPalette.windowShade
            }

            QGCLabel {
                anchors.centerIn: parent
                font.pointSize: ScreenTools.smallFontPointSize
                text: qsTr("Waiting for video")
            }
        }
    }

    Popup {
        id: actionPopup

        readonly property var panelItem: actionLoader.item

        function hide() {
            close();
        }

        // KAN-53: window-coordinate centre of the button that opened this box; NaN = centred.
        property real anchorCenterY: NaN

        implicitWidth: panelItem ? panelItem.implicitWidth + padding * 2 : ScreenTools.defaultFontPixelWidth * 24
        implicitHeight: panelItem ? panelItem.implicitHeight + padding * 2 : ScreenTools.defaultFontPixelHeight * 8
        height: parent ? Math.min(implicitHeight, parent.height - 16) : implicitHeight
        modal: true
        padding: 12
        parent: Overlay.overlay
        width: parent ? Math.min(implicitWidth, parent.width - 16) : implicitWidth
        x: parent ? Math.max(8, parent.width - root.width - width - 20) : 8
        y: parent ? Math.max(8, Math.min(parent.height - height - 8, isNaN(anchorCenterY) ? (parent.height - height) / 2 : anchorCenterY - height / 2)) : 8

        background: Rectangle {
            border.color: panelPalette.buttonBorder
            border.width: 2
            color: panelPalette.window
            radius: 4
        }
        contentItem: Flickable {
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            contentWidth: actionLoader.width
            contentHeight: actionLoader.height
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar {}

            Loader {
                id: actionLoader

                property var dropPanel: actionPopup
            }
        }

        onClosed: actionLoader.sourceComponent = null
        onOpened: root.cancelHolds()
    }

    Timer {
        interval: 200
        repeat: true
        running: root.visible

        onTriggered: {
            root.nowMs = Date.now()
        }
    }

    Timer {
        id: completionTimer
        interval: 700
        onTriggered: root.completedCommand = ""
    }

    component CommandButton: QGCButton {
        id: actionButton
        QGCPalette { id: commandPalette; colorGroupEnabled: actionButton.enabled }
        property string visualRole: "navigation"
        readonly property color foreground: panelPalette.lightTheme ? (enabled && !root.actionSpecial(visualRole) && (down || checked) ? commandPalette.buttonHighlightText : commandPalette.buttonText)
                                                     : !enabled ? (panelPalette.highContrast ? "#B5BDB0" : "#9FB1BE")
                                                     : (panelPalette.highContrast && (down || checked) ? panelPalette.buttonHighlightText : panelPalette.buttonText)
        textColor: foreground
        Accessible.name: text
        Layout.fillWidth: true
        // Circular button (KAN-51): icon + short label inside the circle. The cell is as tall as the
        // circle is wide; fill + cap at 60 px lets the circles shrink (down to 32 px) on a short
        // window so every button stays visible without scrolling, but never grow past 60.
        Layout.fillHeight: true
        Layout.preferredHeight: 60
        Layout.minimumHeight: 32
        Layout.maximumHeight: 60
        property string shortText: text                     // label shown inside the circle
        readonly property real circleSize: Math.max(0, Math.min(width, height))
        padding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        _horizontalPadding: 3
        pointSize: ScreenTools.smallFontPointSize
        wrapMode: Text.WordWrap
        contentItem: CircleContent { control: actionButton }
        background: Rectangle {
            readonly property bool _special: root.actionSpecial(actionButton.visualRole)
            readonly property color baseFill: actionButton.enabled ? root.actionFill(actionButton.visualRole)
                                             : panelPalette.lightTheme ? commandPalette.button : "#172A34"
            x: (actionButton.width - width) / 2
            y: 0
            width: actionButton.circleSize
            height: width
            // Engage(red)/Abort(orange) keep their saturated fill in BOTH themes; every
            // other button uses the neutral theme button colour.
            color: panelPalette.lightTheme ? (_special ? Qt.darker(baseFill, actionButton.down ? 1.08 : actionButton.hovered ? 1.04 : 1)
                                                       : actionButton.down || actionButton.checked ? commandPalette.buttonHighlight
                                                       : actionButton.hovered && actionButton.enabled ? commandPalette.toolStripHoverColor : baseFill)
                            : _special ? (panelPalette.highContrast ? baseFill : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.9))
                            : (panelPalette.highContrast ? ((actionButton.down || actionButton.checked) ? commandPalette.buttonHighlight : commandPalette.button)
                                                         : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82))
            border.color: !actionButton.enabled ? (panelPalette.lightTheme ? commandPalette.buttonBorder : "#617886")
                          : _special ? root.actionBorder(actionButton.visualRole)
                                      : (panelPalette.highContrast ? commandPalette.buttonBorder : root.actionBorder(actionButton.visualRole))
            border.width: 2
            radius: width / 2

            Rectangle {
                readonly property color glowColor: root.actionBorder(actionButton.visualRole)
                anchors.fill: parent
                anchors.margins: -3
                color: Qt.rgba(glowColor.r, glowColor.g, glowColor.b, actionButton.enabled ? (actionButton.hovered ? 0.42 : 0.20) : 0)
                radius: width / 2
                z: -1
            }
        }
    }
    // Icon and short label stacked inside the circle; shared by every panel button. Sizes follow the
    // circle: icon 36 % of the diameter, label font scales down with the circle and shrinks further
    // only when its longest word would not fit the circle (e.g. "Standoff" in a small circle).
    component CircleContent: Item {
        required property var control
        readonly property real _d: control.circleSize
        readonly property real _labelWidth: _d * 0.84

        TextMetrics {
            id: longestWord
            font.pointSize: ScreenTools.smallFontPointSize * Math.max(0.55, Math.min(1, _d / 60))
            text: control.shortText.split(" ").reduce(function (a, b) { return b.length > a.length ? b : a }, "")
        }

        Column {
            anchors.centerIn: parent
            spacing: 1

            QGCColoredImage {
                anchors.horizontalCenter: parent.horizontalCenter
                width: _d * 0.36
                height: width
                source: control.iconSource
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                color: control.foreground
                visible: control.iconSource !== ""
            }

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                width: _labelWidth
                text: control.shortText
                color: control.foreground
                font.pointSize: longestWord.font.pointSize * Math.min(1, _labelWidth / Math.max(1, longestWord.advanceWidth))
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
        }
    }
    component HoldCommand: MissionHoldButton {
        id: holdButton
        QGCPalette { id: holdPalette; colorGroupEnabled: holdButton.enabled }
        property string iconSource: ""
        property string visualRole: "navigation"
        readonly property color foreground: panelPalette.lightTheme ? holdPalette.buttonText
                                            : enabled ? panelPalette.buttonText : (panelPalette.highContrast ? "#B5BDB0" : "#9FB1BE")

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 60
        Layout.minimumHeight: 32
        Layout.maximumHeight: 60
        property string shortText: text
        readonly property real circleSize: Math.max(0, Math.min(width, height))
        padding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        contextActive: root.contextActive && root.visible && !actionPopup.visible
        font.family: ScreenTools.normalFontFamily
        font.pointSize: ScreenTools.smallFontPointSize
        vehicleIdentity: root.vehicle

        // KAN-53: every hold button registers with the panel, so cancelHolds() reaches all of them
        // and the hold bar follows whichever one is being held.
        Component.onCompleted: root._holdButtons.push(holdButton)
        onHoldingChanged: {
            if (holding) {
                root.activeHold = holdButton;
            } else if (root.activeHold === holdButton) {
                root.activeHold = null;
            }
        }

        background: Rectangle {
            readonly property bool _special: root.actionSpecial(holdButton.visualRole)
            readonly property color baseFill: holdButton.enabled ? root.actionFill(holdButton.visualRole)
                                             : panelPalette.lightTheme ? holdPalette.button : "#172A34"
            x: (holdButton.width - width) / 2
            y: 0
            width: holdButton.circleSize
            height: width
            // Abort(orange)/Engage(red) keep their saturated fill in BOTH themes.
            color: panelPalette.lightTheme ? (_special ? Qt.darker(baseFill, holdButton.down ? 1.08 : 1)
                                                       : holdButton.down ? holdPalette.toolStripHoverColor : baseFill)
                            : _special ? (panelPalette.highContrast ? baseFill : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, holdButton.down ? 1.0 : 0.9))
                            : (panelPalette.highContrast ? (holdButton.down ? panelPalette.windowShadeLight : panelPalette.button)
                                                         : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82))
            border.color: !holdButton.enabled ? (panelPalette.lightTheme ? holdPalette.buttonBorder : "#617886")
                          : _special ? root.actionBorder(holdButton.visualRole)
                                      : (panelPalette.highContrast ? panelPalette.buttonBorder : root.actionBorder(holdButton.visualRole))
            border.width: 2
            radius: width / 2

            Rectangle {
                readonly property color glowColor: root.actionBorder(holdButton.visualRole)
                anchors.fill: parent
                anchors.margins: -3
                color: Qt.rgba(glowColor.r, glowColor.g, glowColor.b, holdButton.enabled ? (holdButton.hovered ? 0.42 : 0.20) : 0)
                radius: width / 2
                z: -1
            }
        }
        contentItem: CircleContent { control: holdButton }
    }
    component PrimaryCommand: CommandButton {
    }
}
