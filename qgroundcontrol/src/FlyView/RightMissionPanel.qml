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
    readonly property var activeHold: abortButton.holding ? abortButton : engageButton.holding ? engageButton : null
    property bool cameraPrimary: false
    property bool contextActive: true
    // STRATUM #42: Layer-1 gate -> grays the RTL / Abort buttons when it says stop.
    property var rtlAbortGate: null
    required property var engagementController
    property string feedback: ""
    required property var guidedController
    readonly property bool headingFresh: linkReady && vehicle.vehicle.attitudeTimestampMs > 0 && nowMs - vehicle.vehicle.attitudeTimestampMs < 2000 && isFinite(Number(vehicle.vehicle.heading.rawValue))
    property string completedCommand: ""
    readonly property string holdCommand: activeHold ? activeHold.command : completedCommand
    readonly property real holdProgress: activeHold ? activeHold.holdProgress : (completedCommand !== "" ? 1 : 0)
    readonly property bool holdComplete: !activeHold && completedCommand !== ""
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

    function cancelHolds() {
        abortButton.cancelHold();
        engageButton.cancelHold();
    }

    // STRATUM KAN-21: direct flight-mode change behind a confirm dialog (mirrors the
    // Land/Hold command path). displayName is what the operator sees ("Manual", "RTL");
    // modeName is the advertised firmware mode actually written to Vehicle.flightMode.
    function commandFlightMode(modeName, displayName) {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (!v) return
        cancelHolds()
        actionPopup.close()
        QGroundControl.showMessageDialog(
            mainWindow,
            displayName,
            qsTr("Switch the vehicle to %1 flight mode?").arg(displayName),
            Dialog.Ok | Dialog.Cancel,
            function() {
                var vv = QGroundControl.multiVehicleManager.activeVehicle
                if (vv) vv.flightMode = modeName
            })
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

    // STRATUM KAN-21: button theming. Engage reads red and Abort reads orange in BOTH
    // the normal and high-contrast themes (safety-critical, must stay recognisable);
    // every other command uses the neutral theme button colour. A coloured edge glow is
    // kept on all buttons. accentGlow follows the active theme accent.
    readonly property color accentGlow: panelPalette.highContrast ? "#2EE62E" : "#79CBE8"
    function actionSpecial(role) { return role === "engage" || role === "abort" }

    function actionFill(role) {
        if (role === "engage") return "#7C202C"
        if (role === "abort")  return "#7A3E12"
        return panelPalette.button
    }

    function actionBorder(role) {
        if (role === "engage") return "#FF7A89"
        if (role === "abort")  return "#FF9F45"
        return root.accentGlow
    }

    border.color: panelPalette.groupBorder
    border.width: 1
    color: panelPalette.highContrast ? panelPalette.window : Qt.rgba(panelPalette.window.r, panelPalette.window.g, panelPalette.window.b, 0.80)

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
            spacing: 5

            // STRATUM KAN-21: single ordered vertical command list. Engage reads red,
            // Abort reads orange, every other command uses the neutral theme colour; all
            // keep the edge glow. The flight-mode picker was removed in favour of explicit
            // Manual + RTL buttons. Engage no longer needs an enable toggle -- the 3 s
            // hold-to-confirm is the safety interlock.
            ColumnLayout {
                id: commandColumn
                Layout.fillWidth: true
                spacing: 4

                CommandButton {
                    iconSource: "/InstrumentValueIcons/map.svg"
                    objectName: "missionDefineAOP"
                    visualRole: "navigation"
                    text: qsTr("Define AOP")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.aopRequested();
                    }
                }

                CommandButton {
                    enabled: !!root.vehicle
                    iconSource: "/InstrumentValueIcons/target.svg"
                    objectName: "missionFetchTarget"
                    visualRole: "navigation"
                    text: qsTr("Fetch Target")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.fetchRequested();
                    }
                }

                PrimaryCommand {
                    enabled: root.linkReady && root.guidedController && root.guidedController.showTakeoff
                    iconSource: "/InstrumentValueIcons/arrow-thick-up.svg"
                    objectName: "missionTakeoff"
                    visualRole: "navigation"
                    text: qsTr("Takeoff")
                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.takeoffRequested();
                    }
                }

                CommandButton {
                    enabled: root.linkReady
                    iconSource: "/res/land.svg"
                    objectName: "missionLand"
                    visualRole: "navigation"
                    text: qsTr("Land")
                    onClicked: root.commandFlightMode(qsTr("Land"), qsTr("Land"))
                }

                CommandButton {
                    enabled: root.linkReady
                    iconSource: "/res/pause-mission.svg"
                    objectName: "missionHold"
                    visualRole: "navigation"
                    text: qsTr("Hold")
                    onClicked: root.commandFlightMode(qsTr("Hold"), qsTr("Hold"))
                }

                CommandButton {
                    enabled: root.linkReady
                    iconSource: "/qmlimages/FlightModesComponentIcon.png"
                    objectName: "missionManual"
                    visualRole: "navigation"
                    text: qsTr("Manual")
                    onClicked: root.commandFlightMode(qsTr("Position"), qsTr("Manual"))
                }

                CommandButton {
                    // STRATUM #42: grayed when the Layer-1 gate forbids RTL.
                    enabled: root.linkReady && root.rtlAllowed
                    iconSource: "/res/rtl.svg"
                    objectName: "missionRTL"
                    visualRole: "navigation"
                    text: qsTr("RTL")
                    onClicked: root.commandFlightMode(root.rtlModeName(), qsTr("RTL"))
                }

                PrimaryCommand {
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
                        root.feedback = qsTr("Abort requested — awaiting vehicle response");
                        root.completedCommand = qsTr("Abort");
                        completionTimer.restart();
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
                        root.feedback = qsTr("Engage requested — awaiting vehicle response");
                        root.completedCommand = qsTr("Engage");
                        completionTimer.restart();
                    }
                }

                // STRATUM: any remaining profile-specific actions from the model (e.g. the
                // Dropper payload panel). The commands rendered explicitly above are excluded
                // so they are not duplicated.
                Repeater {
                    model: root.actionModel

                    CommandButton {
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
        anchors.bottomMargin: 18
        anchors.right: parent.right
        spacing: 6

        Rectangle {
            width: parent.width
            color: panelPalette.groupBorder
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
            text: root.headingFresh ? qsTr("%1°").arg(Number(root.vehicle.vehicle.heading.rawValue).toFixed(0)) : qsTr("Heading unavailable")
        }

        QGCLabel {
            font.bold: true
            text: root.cameraPrimary ? qsTr("MAP PREVIEW") : qsTr("CAMERA FEED")
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

        implicitWidth: panelItem ? panelItem.implicitWidth + padding * 2 : ScreenTools.defaultFontPixelWidth * 24
        implicitHeight: panelItem ? panelItem.implicitHeight + padding * 2 : ScreenTools.defaultFontPixelHeight * 8
        height: parent ? Math.min(implicitHeight, parent.height - 16) : implicitHeight
        modal: true
        padding: 12
        parent: Overlay.overlay
        width: parent ? Math.min(implicitWidth, parent.width - 16) : implicitWidth
        x: parent ? Math.max(8, parent.width - root.width - width - 20) : 8
        y: parent ? Math.max(8, (parent.height - height) / 2) : 8

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
        readonly property color foreground: !enabled ? (panelPalette.highContrast ? "#B5BDB0" : "#9FB1BE")
                                                     : (panelPalette.highContrast && (down || checked) ? panelPalette.buttonHighlightText : panelPalette.buttonText)
        textColor: foreground
        Accessible.name: text
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        _horizontalPadding: 3
        pointSize: ScreenTools.smallFontPointSize
        wrapMode: Text.WordWrap
        contentItem: Column {
            spacing: 2

            QGCColoredImage {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 16
                height: 16
                source: actionButton.iconSource
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                color: actionButton.foreground
                visible: actionButton.iconSource !== ""
            }

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: actionButton.text
                color: actionButton.foreground
                font.pointSize: ScreenTools.smallFontPointSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
        background: Rectangle {
            readonly property bool _special: root.actionSpecial(actionButton.visualRole)
            readonly property color baseFill: actionButton.enabled ? root.actionFill(actionButton.visualRole) : "#172A34"
            // Engage(red)/Abort(orange) keep their saturated fill in BOTH themes; every
            // other button uses the neutral theme button colour.
            color: _special ? (panelPalette.highContrast ? baseFill : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.9))
                            : (panelPalette.highContrast ? ((actionButton.down || actionButton.checked) ? commandPalette.buttonHighlight : commandPalette.button)
                                                         : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82))
            border.color: !actionButton.enabled ? "#617886"
                          : _special ? root.actionBorder(actionButton.visualRole)
                                      : (panelPalette.highContrast ? commandPalette.buttonBorder : root.actionBorder(actionButton.visualRole))
            border.width: 2
            radius: 4

            Rectangle {
                readonly property color glowColor: root.actionBorder(actionButton.visualRole)
                anchors.fill: parent
                anchors.margins: -3
                color: Qt.rgba(glowColor.r, glowColor.g, glowColor.b, actionButton.enabled ? (actionButton.hovered ? 0.42 : 0.20) : 0)
                radius: 7
                z: -1
            }
        }
    }
    component HoldCommand: MissionHoldButton {
        id: holdButton
        property string iconSource: ""
        property string visualRole: "navigation"
        readonly property color foreground: enabled ? panelPalette.buttonText : (panelPalette.highContrast ? "#B5BDB0" : "#9FB1BE")

        Layout.fillWidth: true
        Layout.preferredHeight: 46
        contextActive: root.contextActive && root.visible && !actionPopup.visible
        font.family: ScreenTools.normalFontFamily
        font.pointSize: ScreenTools.smallFontPointSize
        vehicleIdentity: root.vehicle

        background: Rectangle {
            readonly property bool _special: root.actionSpecial(holdButton.visualRole)
            readonly property color baseFill: holdButton.enabled ? root.actionFill(holdButton.visualRole) : "#172A34"
            // Abort(orange)/Engage(red) keep their saturated fill in BOTH themes.
            color: _special ? (panelPalette.highContrast ? baseFill : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, holdButton.down ? 1.0 : 0.9))
                            : (panelPalette.highContrast ? (holdButton.down ? panelPalette.windowShadeLight : panelPalette.button)
                                                         : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82))
            border.color: !holdButton.enabled ? "#617886"
                          : _special ? root.actionBorder(holdButton.visualRole)
                                      : (panelPalette.highContrast ? panelPalette.buttonBorder : root.actionBorder(holdButton.visualRole))
            border.width: 2
            radius: 4

            Rectangle {
                readonly property color glowColor: root.actionBorder(holdButton.visualRole)
                anchors.fill: parent
                anchors.margins: -3
                color: Qt.rgba(glowColor.r, glowColor.g, glowColor.b, holdButton.enabled ? (holdButton.hovered ? 0.42 : 0.20) : 0)
                radius: 7
                z: -1
            }
        }
        contentItem: Column {
            QGCColoredImage {
                anchors.horizontalCenter: parent.horizontalCenter
                color: holdButton.foreground
                fillMode: Image.PreserveAspectFit
                height: 16
                source: parent.parent.iconSource
                sourceSize.height: height
                width: 16
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: holdButton.foreground
                font: parent.parent.font
                horizontalAlignment: Text.AlignHCenter
                text: parent.parent.text
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }
        }
    }
    component PrimaryCommand: CommandButton {
        id: primaryButton
        contentItem: Column {
            QGCColoredImage {
                anchors.horizontalCenter: parent.horizontalCenter
                color: primaryButton.foreground
                fillMode: Image.PreserveAspectFit
                height: 16
                source: parent.parent.iconSource
                sourceSize.height: height
                width: 16
            }

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pointSize: ScreenTools.smallFontPointSize
                text: parent.parent.text
                color: primaryButton.foreground
            }
        }
    }
}
