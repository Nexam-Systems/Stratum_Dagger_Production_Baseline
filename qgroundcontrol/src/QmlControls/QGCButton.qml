import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Standard push button control:
///     If there is both an icon and text the icon will be to the left of the text
///     If icon only, icon will be centered
Button {
    property bool primary: false
    // STRATUM: always draw a hairline border in dark theme too so the button silhouette
    // is legible in direct sunlight against the graphite panel stack. Callers can still
    // override showBorder: false where an unadorned pill/chip is desired.
    property bool showBorder: qgcPal.globalTheme === QGCPalette.Light || qgcPal.globalTheme === QGCPalette.Dark
    property real backRadius: ScreenTools.defaultBorderRadius
    property real heightFactor: 0.5
    property string iconSource: ""
    property real fontWeight: Font.Normal // default for qml Text
    property real pointSize: ScreenTools.defaultFontPointSize

    property alias wrapMode: text.wrapMode
    property alias horizontalAlignment: text.horizontalAlignment
    property alias backgroundColor: backRect.color
    property alias textColor: text.color

    id: control
    hoverEnabled: !ScreenTools.isMobile
    topPadding: _verticalPadding
    bottomPadding: _verticalPadding
    leftPadding: _horizontalPadding
    rightPadding: _horizontalPadding
    focusPolicy: Qt.ClickFocus
    font.family: ScreenTools.normalFontFamily
    text: ""

    property bool _showHighlight: enabled && (pressed | checked)
    property int _horizontalPadding: ScreenTools.defaultFontPixelWidth * 2
    property int _verticalPadding: Math.round(ScreenTools.defaultFontPixelHeight * heightFactor) - (iconSource === "" ? 0 : (_iconHeight - ScreenTools.defaultFontPixelHeight)  / 2)
    property real _iconHeight: text.height * 1.5

    QGCPalette { id: qgcPal; colorGroupEnabled: control.enabled }

    background: Rectangle {
        id: backRect
        radius: backRadius
        implicitWidth: ScreenTools.implicitButtonWidth
        implicitHeight: ScreenTools.implicitButtonHeight
        border.width: showBorder ? 1 : 0
        border.color: qgcPal.buttonBorder
        color: primary ? qgcPal.primaryButton : qgcPal.button

        Rectangle {
            anchors.fill: parent
            color: qgcPal.buttonHighlight
            // STRATUM: bumped hover overlay from 0.2 -> 0.4 so hovered buttons visibly
            // glow accent-green in daylight; pressed / checked still full-opacity.
            opacity: _showHighlight ? 1 : control.enabled && control.hovered ? .4 : 0
            radius: parent.radius
        }
    }

    contentItem: RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth

        QGCColoredImage {
            id: icon
            Layout.alignment: Qt.AlignHCenter
            source: control.iconSource
            height: _iconHeight
            width: height
            color: text.color
            fillMode: Image.PreserveAspectFit
            sourceSize.height: height
            visible: control.iconSource !== ""
        }

        QGCLabel {
            id: text
            Layout.alignment: Qt.AlignHCenter
            text: control.text
            font.pointSize: control.pointSize
            font.family: control.font.family
            font.weight: fontWeight
            color: _showHighlight ? qgcPal.buttonHighlightText : (primary ? qgcPal.primaryButtonText : qgcPal.buttonText)
            visible: control.text !== ""
        }
    }
}
