import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.FactControls
import QGroundControl.Controls

Item {
    id: root

    default property alias contentItem: mainLayout.data
    property int sectionFilter: -1
    property bool responsiveColumns: false
    property string pageTitle
    property string pageDescription
    readonly property color secondaryTextColor: settingsTheme.secondaryText
    readonly property int columnCount: mainLayout.columns
    readonly property real minimumColumnWidth: ScreenTools.defaultFontPixelWidth * 55
    SettingsTheme { id: settingsTheme }

    QGCFlickable {
        anchors.fill:   parent
        contentWidth:   mainLayout.width
        contentHeight:  mainLayout.height
        flickableDirection: root.responsiveColumns ? Flickable.VerticalFlick : Flickable.AutoFlickDirection

        GridLayout {
            id:         mainLayout
            objectName: "settings_grid"
            x:          Math.max(0, root.width / 2 - width / 2)
            width:      root.responsiveColumns ? root.width : Math.max(implicitWidth, ScreenTools.defaultFontPixelWidth * 50)
            columns:    root.responsiveColumns && width >= root.minimumColumnWidth * 2 + columnSpacing ? 2 : 1
            uniformCellWidths: true
            columnSpacing: ScreenTools.defaultFontPixelHeight
            rowSpacing: ScreenTools.defaultFontPixelHeight
        }
    }
}
