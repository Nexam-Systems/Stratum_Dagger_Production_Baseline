import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

GridLayout {
    id: row

    default property alias editorContent: editor.data
    property string label
    property string description
    property real editorPreferredWidth: ScreenTools.defaultFontPixelWidth * 24
    property bool fillEditor: false
    readonly property real minimumLabelWidth: ScreenTools.defaultFontPixelWidth * 20
    Accessible.role: Accessible.Grouping
    Accessible.name: label

    columns: width >= minimumLabelWidth + editorPreferredWidth + columnSpacing ? 2 : 1
    columnSpacing: ScreenTools.defaultFontPixelWidth * 2
    rowSpacing: ScreenTools.defaultFontPixelHeight / 2

    SettingsTheme { id: theme }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: row.minimumLabelWidth
        spacing: ScreenTools.defaultFontPixelHeight / 4

        QGCLabel {
            Layout.fillWidth: true
            text: row.label
            font.bold: true
            font.pointSize: ScreenTools.defaultFontPointSize * 1.1
            color: theme.text
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
        QGCLabel {
            Layout.fillWidth: true
            text: row.description
            color: theme.secondaryText
            font.pointSize: ScreenTools.defaultFontPointSize
            Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 60
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    RowLayout {
        id: editor
        Layout.fillWidth: row.columns === 1 || row.fillEditor
        Layout.minimumWidth: 0
        Layout.preferredWidth: row.editorPreferredWidth
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    }
}
