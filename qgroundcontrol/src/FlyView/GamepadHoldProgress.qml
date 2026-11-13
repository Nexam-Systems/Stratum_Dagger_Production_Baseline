import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    readonly property string command: completed ? safetyState.completedHoldCommand : safetyState.pendingCommand
    readonly property bool completed: safetyState.modeEnabled && safetyState._nowMs < safetyState.completedHoldUntilMs
    readonly property real progress: completed ? 1 : safetyState.holdProgress
    required property var safetyState

    border.color: command === "Abort" ? "#FFB454" : "#3DFFA6"
    border.width: 1
    color: "#EE1A2024"
    implicitHeight: content.implicitHeight + 16
    radius: 4
    visible: safetyState.holdActive || completed

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Label {
            Layout.fillWidth: true
            color: "#E4EAEC"
            text: root.completed ? qsTr("%1 request sent").arg(root.command) : (root.command === "Abort" ? qsTr("Abort — hold L1 + Circle (1 s)") : qsTr("Engage — hold L2 + R1 (3 s)"))
            wrapMode: Text.WordWrap
        }

        ProgressBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            from: 0
            to: 1
            value: root.progress

            background: Rectangle {
                color: "#485258"
                radius: 2
            }
            contentItem: Item {
                Rectangle {
                    color: root.command === "Abort" ? "#FFB454" : "#3DFFA6"
                    height: parent.height
                    radius: 2
                    width: parent.width * root.progress
                }
            }
        }
    }
}
