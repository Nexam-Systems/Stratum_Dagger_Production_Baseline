import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightMap
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var actionModel: []
    readonly property var activeHold: abortButton.holding ? abortButton : engageButton.holding ? engageButton : null
    property bool cameraPrimary: false
    property bool contextActive: true
    required property var engagementController
    property string feedback: ""
    required property var guidedController
    readonly property bool headingFresh: linkReady && vehicle.vehicle.attitudeTimestampMs > 0 && nowMs - vehicle.vehicle.attitudeTimestampMs < 2000 && isFinite(Number(vehicle.vehicle.heading.rawValue))
    property string completedCommand: ""
    readonly property string holdCommand: activeHold ? activeHold.command : completedCommand
    readonly property real holdProgress: activeHold ? activeHold.holdProgress : (completedCommand !== "" ? 1 : 0)
    readonly property bool holdComplete: !activeHold && completedCommand !== ""
    readonly property bool linkReady: vehicle && vehicle.initialConnectComplete && !vehicle.vehicleLinkManager.communicationLost
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

    function actionFill(role) {
        if (role === "engage") return "#7C202C"
        if (role === "abort") return "#441B26"
        if (role === "operation") return "#073E37"
        return "#102D43"
    }

    function actionBorder(role) {
        if (role === "engage") return "#FF7A89"
        if (role === "abort") return "#F07484"
        if (role === "operation") return "#3BAE99"
        return "#64B7E0"
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

    ScrollView {
        id: actionScroll

        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        anchors.bottom: previewSection.top
        anchors.left: parent.left
        anchors.margins: 6
        anchors.right: parent.right
        anchors.top: parent.top
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            height: implicitHeight
            spacing: 5
            width: actionScroll.availableWidth

            QGCLabel {
                font.bold: true
                text: qsTr("MISSION CONTROLS")
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 6
                columnSpacing: 4
                columns: 2
                rowSpacing: 4
                uniformCellWidths: true

                PrimaryCommand {
                    enabled: root.linkReady && root.guidedController && root.guidedController.showTakeoff
                    iconSource: "/InstrumentValueIcons/arrow-thick-up.svg"
                    objectName: "missionTakeoff"
                    visualRole: "operation"
                    text: qsTr("Takeoff")

                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.takeoffRequested();
                    }
                }

                HoldCommand {
                    id: abortButton

                    command: qsTr("Abort")
                    enabled: root.linkReady && root.vehicle.armed && root.engagementController && root.vehicle.flightModes.indexOf(root.engagementController.abortModeName) >= 0
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

                PrimaryCommand {
                    enabled: !!root.vehicle
                    iconSource: "/qmlimages/StandoffMarker.svg"
                    objectName: "missionStandoff"
                    visualRole: "operation"
                    text: qsTr("Standoff")

                    onClicked: {
                        root.cancelHolds();
                        actionPopup.close();
                        root.standoffRequested();
                    }
                }

                HoldCommand {
                    id: engageButton

                    command: qsTr("Engage")
                    enabled: root.linkReady && root.vehicle.armed && root.vehicle.flying && root.engagementController && root.vehicle.flightModes.indexOf(root.engagementController.engagementModeName) >= 0 && root.vehicle.flightMode !== root.engagementController.engagementModeName
                    holdDuration: 3000
                    iconSource: "/res/chevron-double-right.svg"
                    objectName: "missionEngage"
                    visualRole: "engage"
                    text: qsTr("Engage")

                    onCommitted: {
                        if (!enabled || !root.linkReady)
                            return;
                        root.engagementController.engage();
                        root.feedback = qsTr("Engage requested — awaiting vehicle response");
                        root.completedCommand = qsTr("Engage");
                        completionTimer.restart();
                    }
                }

            }

            QGCCompassWidget {
                Layout.alignment: Qt.AlignHCenter
                objectName: "missionCompass"
                size: 72
                vehicle: root.headingFresh ? root.vehicle : null
                visible: root.headingFresh
            }

            QGCLabel {
                Layout.alignment: Qt.AlignHCenter
                text: root.headingFresh ? qsTr("%1°").arg(Number(root.vehicle.vehicle.heading.rawValue).toFixed(0)) : qsTr("Heading unavailable")
            }

            GridLayout {
                Layout.fillWidth: true
                columnSpacing: 4
                columns: 1
                rowSpacing: 4

                CommandButton {
                    iconSource: "/InstrumentValueIcons/map.svg"
                    objectName: "missionDefineAOP"
                    text: qsTr("Define AOP")

                    onClicked: {
                        root.cancelHolds();
                        root.aopRequested();
                    }
                }

                Repeater {
                    model: root.actionModel

                    CommandButton {
                        readonly property var entry: modelData
                        required property var modelData

                        enabled: entry.enabled
                        iconSource: entry.iconSource
                        objectName: "missionSecondary_" + entry.text
                        text: entry.text
                        visualRole: entry.text === qsTr("Land") ? "operation" : "navigation"
                        visible: entry.visible && [qsTr("Takeoff"), qsTr("Standoff"), qsTr("Abort"), qsTr("Engage")].indexOf(entry.text) < 0

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

            QGCLabel {
                Layout.fillWidth: true
                color: panelPalette.warningText
                text: root.feedback
                visible: text !== ""
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                color: panelPalette.groupBorder
                height: 1
            }

            QGCLabel {
                font.bold: true
                text: qsTr("NAVIGATION")
            }

        }
    }

    Column {
        id: previewSection

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 6
        anchors.right: parent.right
        spacing: 4

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

        function hide() {
            close();
        }

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
        contentItem: ScrollView {
            clip: true
            contentWidth: availableWidth

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

        onTriggered: root.nowMs = Date.now()
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
        background: Rectangle {
            readonly property color baseFill: actionButton.enabled ? root.actionFill(actionButton.visualRole) : "#172A34"
            color: panelPalette.highContrast ? ((actionButton.down || actionButton.checked) ? commandPalette.buttonHighlight : commandPalette.button)
                   : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82)
            border.color: panelPalette.highContrast ? commandPalette.buttonBorder : (actionButton.enabled ? root.actionBorder(actionButton.visualRole) : "#617886")
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
            border.color: panelPalette.highContrast ? panelPalette.buttonBorder : (holdButton.enabled ? root.actionBorder(holdButton.visualRole) : "#617886")
            border.width: 2
            readonly property color baseFill: holdButton.enabled ? root.actionFill(holdButton.visualRole) : "#172A34"
            color: panelPalette.highContrast ? (holdButton.down ? panelPalette.windowShadeLight : panelPalette.button)
                     : Qt.rgba(baseFill.r, baseFill.g, baseFill.b, 0.82)
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
