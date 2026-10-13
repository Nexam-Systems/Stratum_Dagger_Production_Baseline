import QGroundControl
import QGroundControl.Controls
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    readonly property color accent: "#3DFFA6"
    required property var controller
    readonly property real maximumHeight: parent ? Math.max(250, parent.height - y - padding) : 600
    property bool minimized: false
    readonly property real padding: ScreenTools.defaultFontPixelWidth
    readonly property var state: controller.state

    border.color: controller.modeEnabled ? accent : "#626C70"
    border.width: 1
    color: "#E61A2024"
    implicitHeight: content.implicitHeight + padding * 2
    radius: 6

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.margins: root.padding
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: ScreenTools.defaultFontPixelHeight * 0.3

        RowLayout {
            Layout.fillWidth: true

            QGCLabel {
                Layout.fillWidth: true
                color: "#E4EAEC"
                font.bold: true
                text: qsTr("Gamepad")
            }

            QGCButton {
                ToolTip.text: root.minimized ? qsTr("Expand gamepad") : qsTr("Minimize gamepad")
                ToolTip.visible: hovered
                iconSource: root.minimized ? "/InstrumentValueIcons/cheveron-down.svg" : "/InstrumentValueIcons/cheveron-up.svg"
                implicitHeight: ScreenTools.defaultFontPixelHeight * 2
                implicitWidth: ScreenTools.defaultFontPixelHeight * 2

                onClicked: root.minimized = !root.minimized
            }
        }

        QGCButton {
            id: enableButton

            property bool enabledThisPress: false

            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2.5
            enabled: root.controller.modeEnabled || root.controller.available
            primary: root.controller.modeEnabled
            text: root.controller.modeEnabled ? qsTr("Disable joystick") : qsTr("Hold to enable joystick")

            onClicked: if (root.controller.modeEnabled && !enabledThisPress)
                root.controller.disable()
            onPressed: enabledThisPress = false

            Timer {
                interval: 1500
                running: enableButton.down && !root.controller.modeEnabled && root.controller.available

                onTriggered: {
                    enableButton.enabledThisPress = true;
                    root.controller.enable();
                }
            }
        }

        QGCLabel {
            Layout.fillWidth: true
            color: root.controller.modeEnabled ? root.accent : "#CDD3D6"
            font.pointSize: ScreenTools.smallFontPointSize
            text: root.controller.modeEnabled ? root.state.feedback : (root.controller.available ? qsTr("Joystick disabled") : qsTr("Connect a calibrated gamepad and vehicle"))
            wrapMode: Text.WordWrap
        }

        QGCLabel {
            Layout.fillWidth: true
            color: "#E4EAEC"
            font.pointSize: ScreenTools.smallFontPointSize
            text: root.controller.selectionDetails
            visible: text !== ""
            wrapMode: Text.WordWrap
        }

        ScrollView {
            id: mappingScroll

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(mappingContent.implicitHeight, Math.max(100, root.maximumHeight - 180))
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true
            contentWidth: availableWidth
            visible: root.controller.modeEnabled && !root.minimized

            ColumnLayout {
                id: mappingContent

                spacing: ScreenTools.defaultFontPixelHeight * 0.3
                width: mappingScroll.availableWidth

                QGCLabel {
                    Layout.fillWidth: true
                    color: "#E4EAEC"
                    elide: Text.ElideRight
                    font.pointSize: ScreenTools.smallFontPointSize
                    text: root.controller.activeJoystick ? root.controller.activeJoystick.name : ""
                }

                RowLayout {
                    Layout.fillWidth: true

                    QGCLabel {
                        color: "#E4EAEC"
                        text: qsTr("Takeoff (m)")
                    }

                    SpinBox {
                        Layout.fillWidth: true
                        enabled: root.state.pendingCommand === ""
                        from: 1
                        to: 1000
                        value: root.controller.takeoffAltitudeMeters

                        onValueModified: root.controller.takeoffAltitudeMeters = value
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columnSpacing: 4
                    columns: 3
                    rowSpacing: 4

                    Item {
                        Layout.fillWidth: true
                    }

                    Mapping {
                        buttonIndex: 3
                        command: "Takeoff"
                        glyph: "\u25b3"
                        label: qsTr("Takeoff")
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Mapping {
                        buttonIndex: 2
                        command: "Standoff"
                        glyph: "\u25a1"
                        label: qsTr("Standoff")
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Mapping {
                        buttonIndex: 1
                        glyph: "\u25cb"
                        label: qsTr("Cancel")
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Mapping {
                        buttonIndex: 0
                        command: "RTL"
                        glyph: "\u00d7"
                        label: qsTr("RTL")
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    QGCLabel {
                        color: (root.state.buttons & (1 << 9)) ? root.accent : "#CDD3D6"
                        text: qsTr("L1 + \u25cb")
                    }

                    QGCLabel {
                        color: root.state.pendingCommand === "Abort" ? root.accent : "#CDD3D6"
                        text: qsTr("Hold Abort (1 s)")
                    }
                }

                QGCLabel {
                    Layout.fillWidth: true
                    color: root.state.pendingCommand === "Engage" ? root.accent : "#CDD3D6"
                    text: qsTr("L1 + Triangle: Select Engage")
                    wrapMode: Text.WordWrap
                }

                QGCLabel {
                    Layout.fillWidth: true
                    color: root.accent
                    text: qsTr("Hold L2 + R1 together (3 s)")
                    visible: root.state.pendingCommand === "Engage"
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.state.pendingCommand !== "Engage" && root.state.pendingCommand !== "Abort"

                    QGCLabel {
                        color: root.state.safetyHeld ? root.accent : "#CDD3D6"
                        text: qsTr("L2")
                    }

                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 600
                        value: root.state.armStartedMs > 0 ? Math.max(0, root.state._nowMs - root.state.armStartedMs) : 0
                    }

                    QGCLabel {
                        color: root.state.commitReady ? root.accent : "#CDD3D6"
                        font.bold: root.state.commitReady
                        text: qsTr("R1 Commit")
                    }
                }

                QGCLabel {
                    Layout.fillWidth: true
                    color: root.state.manualHeld ? root.accent : "#CDD3D6"
                    text: qsTr("R2 Manual")
                }

                QGCLabel {
                    Layout.fillWidth: true
                    color: "#E4EAEC"
                    font.pointSize: ScreenTools.smallFontPointSize
                    text: qsTr("D-pad Map / Sticks Flight")
                    wrapMode: Text.WordWrap
                }

                QGCButton {
                    Layout.fillWidth: true
                    iconSource: "/InstrumentValueIcons/tuning.svg"
                    text: qsTr("Standoff target")

                    onClicked: root.controller.widgetLayer.toggleStandoff()
                }
            }
        }
    }

    component Mapping: Rectangle {
        required property int buttonIndex
        property string command: ""
        required property string glyph
        required property string label
        readonly property bool pressed: (root.state.buttons & (1 << buttonIndex)) !== 0

        Layout.fillWidth: true
        Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 2.5
        border.color: command !== "" && root.state.pendingCommand === command ? root.accent : "#667074"
        border.width: 1
        color: pressed ? "#36594E" : "#252D32"
        radius: 4

        Column {
            anchors.centerIn: parent
            spacing: 2

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.accent
                text: parent.parent.glyph
            }

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#E4EAEC"
                font.pointSize: ScreenTools.smallFontPointSize
                text: parent.parent.label
            }
        }
    }
}
