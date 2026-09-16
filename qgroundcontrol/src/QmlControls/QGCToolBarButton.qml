import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Important Note: Toolbar buttons must manage their checked state manually in order to support
// view switch prevention. This means they can't be checkable or autoExclusive.

Button {
    id:                 button
    height:             ScreenTools.defaultFontPixelHeight * 3
    leftPadding:        _horizontalMargin
    rightPadding:       _horizontalMargin
    checkable:          false
    // STRATUM: enable hover so the ribbon logo/status buttons reveal an affordance
    // (a subtle darkening) when the operator points at them; without hoverEnabled
    // the ribbon reads as passive labels instead of buttons.
    hoverEnabled:       !ScreenTools.isMobile

    property bool logo: false
    // STRATUM: when set to an opaque colour, the logo SVG is tinted (monochrome) with it
    // instead of rendering its native multi-colour form. Transparent = native (default).
    property color logoColor: "#00000000"

    property real _horizontalMargin: ScreenTools.defaultFontPixelWidth

    onCheckedChanged: checkable = false

    background: Rectangle {
        anchors.fill:   parent
        color:          button.checked ? qgcPal.buttonHighlight : Qt.rgba(0,0,0,0)
        border.color:   "red"
        border.width:   QGroundControl.corePlugin.showTouchAreas ? 3 : 0

        // STRATUM: hover affordance -- a soft dark tint so operators can see the
        // ribbon icons are real click targets. Sits above the state-driven ribbon
        // colour and below the icon.
        Rectangle {
            anchors.fill:   parent
            color:          Qt.rgba(0, 0, 0, 0.18)
            visible:        button.hovered && !button.checked
        }
    }

    contentItem: Row {
        spacing:                ScreenTools.defaultFontPixelWidth
        anchors.verticalCenter: button.verticalCenter
        // Logo buttons render the multi-color SVG natively via VectorImage; non-logo buttons
        // tint their monochrome icon through QGCColoredImage. Plain `Row` skips visible:false items.
        QGCVectorImage {
            visible:                button.logo && button.logoColor.a === 0
            height:                 ScreenTools.defaultFontPixelHeight * 2
            width:                  height
            source:                 visible ? button.icon.source : ""
            anchors.verticalCenter: parent.verticalCenter
        }
        QGCColoredImage {
            visible:                !button.logo || button.logoColor.a > 0
            height:                 ScreenTools.defaultFontPixelHeight * 2
            width:                  height
            sourceSize.height:      parent.height
            fillMode:               Image.PreserveAspectFit
            color:                  button.logo ? button.logoColor : (button.checked ? qgcPal.buttonHighlightText : qgcPal.buttonText)
            source:                 visible ? button.icon.source : ""
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id:                     _label
            visible:                text !== ""
            text:                   button.text
            color:                  button.checked ? qgcPal.buttonHighlightText : qgcPal.buttonText
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
