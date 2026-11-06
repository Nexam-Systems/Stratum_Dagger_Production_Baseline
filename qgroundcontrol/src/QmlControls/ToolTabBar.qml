import QtQuick
import QtQuick.Controls

import QGroundControl.Controls

QGCFlickable {
    id: control

    default property alias tabs: tabRow.data
    property bool equalWidthTabs: false
    readonly property real tabWidth: {
        var count = 0
        var minimum = 0
        for (var child of tabRow.children) {
            if (child.visible && typeof child.tabBar !== "undefined") {
                count++
                minimum = Math.max(minimum, child.implicitWidth)
            }
        }
        return count ? Math.max(minimum, (width - tabRow.spacing * (count - 1)) / count) : 0
    }

    implicitHeight: tabRow.implicitHeight + scrollBar.height
    contentWidth: tabRow.implicitWidth
    contentHeight: tabRow.implicitHeight
    flickableDirection: Flickable.HorizontalFlick

    function ensureVisible(tab) {
        var position = tab.mapToItem(tabRow, 0, 0).x
        if (position < contentX) {
            contentX = position
        } else if (position + tab.width > contentX + width) {
            contentX = position + tab.width - width
        }
        contentX = Math.max(0, Math.min(contentX, Math.max(0, contentWidth - width)))
    }

    Row {
        id: tabRow
        spacing: ScreenTools.defaultFontPixelWidth / 2
    }

    ScrollBar.horizontal: ScrollBar {
        id: scrollBar
        policy: ScrollBar.AsNeeded
    }
}
