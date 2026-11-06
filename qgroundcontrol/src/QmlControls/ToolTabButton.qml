import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Button {
    id: control

    property bool setupComplete: true
    property ToolTabBar tabBar

    implicitHeight: Math.max(40, ScreenTools.defaultFontPixelHeight * 2.2)
    leftPadding: ScreenTools.defaultFontPixelWidth * 1.5
    rightPadding: leftPadding
    hoverEnabled: !ScreenTools.isMobile
    checkable: false

    function reveal() {
        if (tabBar && visible) {
            tabBar.ensureVisible(control)
        }
    }

    onCheckedChanged: if (checked) Qt.callLater(reveal)
    onActiveFocusChanged: if (activeFocus) reveal()

    QGCPalette { id: palette; colorGroupEnabled: control.enabled }

    background: Rectangle {
        color: control.checked ? palette.windowShade
               : (control.hovered ? palette.windowShadeDark : "transparent")
        border.width: control.activeFocus ? 1 : 0
        border.color: palette.brandingPurple

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: ScreenTools.defaultFontPixelHeight * 0.18
            visible: control.checked
            color: palette.brandingPurple
        }
    }

    contentItem: RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth / 2

        Rectangle {
            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth
            Layout.preferredHeight: width
            radius: width / 2
            visible: !control.setupComplete
            color: palette.colorOrange
        }

        QGCLabel {
            text: control.text.toUpperCase()
            color: control.checked ? palette.text : palette.buttonText
            font.bold: control.checked
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
