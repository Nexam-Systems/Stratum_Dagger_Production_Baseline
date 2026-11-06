import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Button {
    id: control

    property bool setupComplete: true
    property ToolTabBar tabBar

    implicitHeight: Math.max(48, ScreenTools.defaultFontPixelHeight * 3)
    width: tabBar && tabBar.equalWidthTabs ? tabBar.tabWidth : implicitWidth
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
    SettingsTheme { id: theme }

    background: Rectangle {
        radius: 3
        color: control.checked || control.hovered ? theme.input : theme.header
        border.width: control.activeFocus || theme.highContrast ? 2 : 1
        border.color: control.activeFocus ? theme.accent : theme.border

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            visible: control.checked
            color: theme.accent
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: ScreenTools.defaultFontPixelHeight * 0.18
            visible: control.checked
            color: theme.accent
        }
    }

    contentItem: Item {
        implicitWidth: tabContent.implicitWidth
        implicitHeight: tabContent.implicitHeight

        RowLayout {
            id: tabContent
            anchors.centerIn: parent
            spacing: ScreenTools.defaultFontPixelWidth * 1.5

            Rectangle {
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth
                Layout.preferredHeight: width
                radius: width / 2
                visible: !control.setupComplete
                color: palette.colorOrange
            }

            QGCColoredImage {
                Layout.preferredWidth: ScreenTools.defaultFontPixelHeight * 1.5
                Layout.preferredHeight: Layout.preferredWidth
                source: control.icon.source
                visible: source.toString() !== ""
                color: control.checked ? theme.accent : theme.text
            }

            QGCLabel {
                text: control.text.toUpperCase()
                color: control.checked ? theme.accent : theme.text
                font.bold: control.checked
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
