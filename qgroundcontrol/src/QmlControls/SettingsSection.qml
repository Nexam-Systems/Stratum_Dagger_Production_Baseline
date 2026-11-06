import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Rectangle {
    id: section

    default property alias contentItem: body.contentItem
    property string heading
    property string headingDescription
    property string sectionNumber
    property url iconSource
    property bool collapsible: true
    property bool expanded: true
    readonly property real padding: ScreenTools.defaultFontPixelWidth * 2

    implicitWidth: body.implicitWidth + padding * 2
    implicitHeight: sectionLayout.implicitHeight + 2
    color: theme.panel
    border.color: theme.border
    border.width: theme.highContrast ? 2 : 1
    radius: 6

    SettingsTheme { id: theme }

    ColumnLayout {
        id: sectionLayout
        x: 1
        y: 1
        width: section.width - 2
        spacing: 0

        Button {
            id: header
            objectName: "settings_groupToggle"
            Layout.fillWidth: true
            implicitHeight: Math.max(44, ScreenTools.defaultFontPixelHeight * 2.8)
            leftPadding: section.padding
            rightPadding: section.padding
            checkable: section.collapsible
            checked: section.expanded
            onClicked: if (section.collapsible) section.expanded = checked
            Accessible.name: section.heading
            Accessible.role: Accessible.CheckBox

            background: Rectangle {
                color: header.hovered ? theme.input : theme.header
                radius: section.radius
                border.width: header.activeFocus ? 2 : 0
                border.color: theme.accent
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    visible: section.expanded
                    color: theme.border
                }
            }

            contentItem: RowLayout {
                spacing: ScreenTools.defaultFontPixelWidth * 1.5
                QGCLabel {
                    visible: section.sectionNumber !== ""
                    text: section.sectionNumber
                    color: theme.accent
                    font.bold: true
                    font.pointSize: ScreenTools.defaultFontPointSize * 1.1
                }
                QGCColoredImage {
                    Layout.preferredWidth: ScreenTools.defaultFontPixelHeight * 1.5
                    Layout.preferredHeight: Layout.preferredWidth
                    source: section.iconSource
                    visible: source.toString() !== ""
                    color: theme.accent
                }
                QGCLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: section.heading.toUpperCase()
                    color: theme.accent
                    font.bold: true
                    font.pointSize: ScreenTools.defaultFontPointSize * 1.1
                    wrapMode: Text.WordWrap
                }
                QGCColoredImage {
                    Layout.preferredWidth: ScreenTools.defaultFontPixelHeight
                    Layout.preferredHeight: Layout.preferredWidth
                    source: "/InstrumentValueIcons/cheveron-up.svg"
                    rotation: section.expanded ? 0 : 180
                    visible: section.collapsible
                    color: theme.text
                }
            }
        }

        QGCLabel {
            Layout.fillWidth: true
            Layout.margins: section.padding
            visible: section.expanded && section.headingDescription !== ""
            text: section.headingDescription
            color: theme.secondaryText
            wrapMode: Text.WordWrap
        }

        SettingsGroupLayout {
            id: body
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.margins: section.padding
            showBorder: false
            visible: section.expanded
        }
    }
}
