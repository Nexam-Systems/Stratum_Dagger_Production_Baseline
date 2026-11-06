import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

ColumnLayout {
    id:                 control
    spacing:            _margins / 2
    implicitWidth:      _contentLayout.implicitWidth + (_margins * 2)
    implicitHeight:     headingLayout.implicitHeight + (outerRect.visible ? outerRect.implicitHeight + spacing : 0)

    default property alias contentItem: _contentLayout.data

    property alias contentSpacing: _contentLayout.spacing

    property string defaultBorderColor  : QGroundControl.globalPalette.groupBorder
    property string outerBorderColor    : defaultBorderColor

    property string defaultHeadingPointSize:    ScreenTools.defaultFontPointSize + 1
    property string headingPointSize:           defaultHeadingPointSize

    property string heading
    property string headingDescription
    property bool   showDividers:       true
    property bool   showBorder:         true
    property bool   collapsible:        false
    property bool   expanded:           true

    property real _margins: ScreenTools.defaultFontPixelHeight / 2

    // We work with a y sorted list of children for divider visibility checks
    property var _ySortedChildren: {
        let arr = []
        for (let c of _contentLayout.children)
            arr.push(c)
        arr.sort((a, b) => a.y - b.y)
        return arr
    }

    ColumnLayout {
        id:                 headingLayout
        Layout.leftMargin:  _margins
        Layout.fillWidth:   true
        spacing:            0
        visible:            heading !== ""

        QGCLabel {
            Layout.fillWidth: true
            visible:        !control.collapsible
            text:           heading
            wrapMode:       Text.WordWrap
            font.pointSize: headingPointSize
            font.bold:      true
        }

        Button {
            id: headingButton
            objectName: "settings_groupToggle"
            Layout.fillWidth: true
            implicitHeight: Math.max(40, contentItem.implicitHeight + topPadding + bottomPadding)
            visible: control.collapsible
            text: control.heading
            Accessible.name: text
            Accessible.role: Accessible.CheckBox
            checkable: true
            checked: control.expanded
            onClicked: control.expanded = checked

            background: Rectangle {
                color: headingButton.hovered ? QGroundControl.globalPalette.windowShade : "transparent"
                border.width: headingButton.activeFocus ? 1 : 0
                border.color: QGroundControl.globalPalette.brandingPurple
            }
            contentItem: RowLayout {
                QGCLabel {
                    text: control.expanded ? "-" : "+"
                    font.bold: true
                }
                QGCLabel {
                    Layout.fillWidth: true
                    text: control.heading
                    font.pointSize: control.headingPointSize
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        QGCLabel {
            Layout.fillWidth:   true
            text:               headingDescription
            wrapMode:           Text.WordWrap
            font.pointSize:     ScreenTools.smallFontPointSize
            visible:            headingDescription !== "" && (!control.collapsible || control.expanded)
        }
    }

    Rectangle {
        id:                 outerRect
        visible:            !control.collapsible || control.expanded
        Layout.fillWidth:   true
        implicitWidth:      _contentLayout.implicitWidth + (showBorder ? _margins * 2 : 0)
        implicitHeight:     _contentLayout.implicitHeight + (showBorder ? _margins * 2: 0)
        color:              "transparent"
        border.color:       outerBorderColor
        border.width:       showBorder ? 1 : 0
        radius:             ScreenTools.defaultFontPixelHeight / 2

        // STRATUM: 3-px accent rail on the leading edge of every settings card. Makes
        // each panel visually distinct at a glance in the graphite palette and gives
        // the tactical look real presence instead of a single-hex-shift refresh.
        Rectangle {
            visible:    showBorder
            width:      3
            height:     parent.height - (parent.radius * 2)
            anchors.left:               parent.left
            anchors.verticalCenter:     parent.verticalCenter
            color:      QGroundControl.globalPalette.brandingPurple
            opacity:    0.9
            radius:     1
        }

        Repeater {
            model: showDividers ? _ySortedChildren.length : 0

            Rectangle {
                x:          showBorder ? _margins : 0
                y:          _contentItem ? (_contentItem.y + _contentItem.height + _margins + (showBorder ? _margins : 0)) : 0
                width:      parent.width - (showBorder ? _margins * 2 : 0)
                height:     1
                color:      QGroundControl.globalPalette.groupBorder
                visible:    _contentItem ? _isContentItemVisible() : false

                property var _contentItem: index < _ySortedChildren.length ? _ySortedChildren[index] : undefined

                function _isRepeater(item) {
                    return item && item.toString().startsWith("QQuickRepeater");
                }

                function _isContentItemVisible() {
                    if (!_contentItem || !_contentItem.visible || _isRepeater(_contentItem)) {
                        return false
                    }
                    // Any children after this one visually from top to bottom must be visible to show divider
                    for (let i = index + 1; i < _ySortedChildren.length; ++i) {
                        if (!_ySortedChildren[i] || _isRepeater(_ySortedChildren[i])) {
                            continue
                        }
                        if (_ySortedChildren[i].visible) {
                            return true
                        }
                    }
                    return false
                }
            }
        }

        ColumnLayout {
            id:                 _contentLayout
            x:                  showBorder ? _margins : 0
            y:                  showBorder ? _margins : 0
            width:              parent.width - (showBorder ? _margins * 2 : 0)
            spacing:            _margins * (showDividers ? 2 : 1)
        }
    }
}
