import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

Button {
    id:             control
    objectName:     toolStripAction ? toolStripAction.objectName : ""
    width:          contentLayoutItem.contentWidth + (contentMargins * 2)
    height:         width
    hoverEnabled:   !ScreenTools.isMobile
    enabled:        toolStripAction ? toolStripAction.enabled : true
    visible:        toolStripAction ? toolStripAction.visible : true
    imageSource:    (toolStripAction && modelData) ? (toolStripAction.showAlternateIcon ? modelData.alternateIconSource : modelData.iconSource) : ""
    text:           toolStripAction ? toolStripAction.text : ""
    checked:        toolStripAction ? toolStripAction.checked : false
    checkable:      toolStripAction ? (toolStripAction.dropPanelComponent || (modelData && modelData.checkable)) : false

    property var    toolStripAction:    undefined
    property var    dropPanel:          undefined
    property alias  radius:             buttonBkRect.radius
    property alias  fontPointSize:      innerText.font.pointSize
    property alias  imageSource:        innerImage.source
    property alias  contentWidth:       innerText.contentWidth

    property bool forceImageScale11: false
    property real imageScale:        forceImageScale11 && (text == "") ? 0.8 : 0.6
    property real contentMargins:    innerText.height * 0.1
    // STRATUM: when true, idle buttons carry a solid accent fill so they read as
    // discrete command buttons rather than transparent icon affordances.
    property bool accentButtons:     false
    // STRATUM: accent fill + content colour, supplied by the owning ToolStrip so the
    // strip can encode live vehicle state (green flying / red engagement / blue on
    // ground) while keeping the olive default for the no-vehicle case.
    property color accentColor:      qgcPal.brandingPurple
    property color accentTextColor:  "#1A1A1A"

    // STRATUM: optional per-action accent override. A QML ToolStripAction may declare
    // accentColorOverride / accentTextColorOverride (e.g. the crimson Set Standoff
    // command); plain C++ ToolStripActions lack the properties, the lookup yields
    // undefined, and the button falls through to the strip-wide accent.
    property color _accentFill:      (toolStripAction && toolStripAction.accentColorOverride)     ? toolStripAction.accentColorOverride     : accentColor
    property color _accentContent:   (toolStripAction && toolStripAction.accentTextColorOverride) ? toolStripAction.accentTextColorOverride : accentTextColor

    // STRATUM: on accent buttons the content colour is paired with the fill by the
    // caller (dark on the light olive default, white on the saturated state colours).
    property color _currentContentColor:  qgcPal.highContrast ? ((checked || pressed) ? qgcPal.buttonHighlightText : qgcPal.buttonText) : accentButtons ? _accentContent :
                                              ((checked || pressed) ? qgcPal.buttonHighlightText : qgcPal.text)
    property color _currentContentColorSecondary:  (checked || pressed) ? qgcPal.text : qgcPal.buttonHighlight

    signal dropped(int index)

    onCheckedChanged: { if (toolStripAction) toolStripAction.checked = checked }

    onClicked: {
        if (mainWindow.allowViewSwitch()) {
            dropPanel.hide()
            if (!toolStripAction.dropPanelComponent) {
                toolStripAction.triggered(this)
            } else if (checked) {
                var panelEdgeTopPoint = mapToItem(_root, width, 0)
                dropPanel.show(panelEdgeTopPoint, toolStripAction.dropPanelComponent, this)
                checked = true
                control.dropped(index)
            }
        } else if (checkable) {
            checked = !checked
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: control.enabled }

    contentItem: Item {
        id:                 contentLayoutItem
        anchors.fill:       parent
        anchors.margins:    contentMargins

        Column {
            anchors.centerIn:   parent
            spacing:            0

            Image {
                id:                         innerImageColorful
                height:                     contentLayoutItem.height * imageScale
                width:                      contentLayoutItem.width  * imageScale
                smooth:                     true
                mipmap:                     true
                fillMode:                   Image.PreserveAspectFit
                antialiasing:               true
                sourceSize.height:          height
                sourceSize.width:           width
                anchors.horizontalCenter:   parent.horizontalCenter
                source:                     control.imageSource
                visible:                    source != "" && !!modelData && modelData.fullColorIcon
            }

            QGCColoredImage {
                id:                         innerImage
                height:                     contentLayoutItem.height * imageScale
                width:                      contentLayoutItem.width  * imageScale
                smooth:                     true
                mipmap:                     true
                color:                      _currentContentColor
                fillMode:                   Image.PreserveAspectFit
                antialiasing:               true
                sourceSize.height:          height
                sourceSize.width:           width
                anchors.horizontalCenter:   parent.horizontalCenter
                visible:                    source != "" && !(modelData && modelData.fullColorIcon)

                QGCColoredImage {
                    id:                         innerImageSecondColor
                    source:                     modelData ? modelData.alternateIconSource : ""
                    height:                     contentLayoutItem.height * imageScale
                    width:                      contentLayoutItem.width  * imageScale
                    smooth:                     true
                    mipmap:                     true
                    color:                      _currentContentColorSecondary
                    fillMode:                   Image.PreserveAspectFit
                    antialiasing:               true
                    sourceSize.height:          height
                    sourceSize.width:           width
                    anchors.horizontalCenter:   parent.horizontalCenter
                    visible:                    source != "" && !!modelData && modelData.biColorIcon
                }
            }

            QGCLabel {
                id:                         innerText
                text:                       control.text
                color:                      _currentContentColor
                // STRATUM: wrap to two lines and centre so multi-word command labels
                // (e.g. "Define AOP", "Max Speed") fit inside the square button rather
                // than truncating. Bind to the externally-anchored button width (minus a
                // constant inset) rather than contentLayoutItem.width, which would form a
                // binding loop via contentMargins -> label height -> label width.
                width:                      control.width - ScreenTools.defaultFontPixelWidth
                horizontalAlignment:        Text.AlignHCenter
                wrapMode:                   Text.WordWrap
                maximumLineCount:           2
                elide:                      Text.ElideRight
                anchors.horizontalCenter:   parent.horizontalCenter
                font.bold:                  !innerImage.visible && !innerImageColorful.visible
                opacity:                    qgcPal.highContrast ? 1.0 : (!innerImage.visible ? 0.8 : 1.0)
            }
        }
    }

    background: Rectangle {
        id:     buttonBkRect
        color:  qgcPal.highContrast ? ((control.checked || control.pressed) ? qgcPal.buttonHighlight : qgcPal.button) : (control.checked || control.pressed) ?
                    qgcPal.buttonHighlight :
                    ((control.enabled && control.hovered) ? qgcPal.toolStripHoverColor :
                        (control.accentButtons ? control._accentFill : "transparent"))
        // STRATUM: dim the accent fill when the action is unavailable so disabled
        // commands remain visibly inert rather than reading as armed.
        opacity: qgcPal.highContrast ? 1.0 : ((control.accentButtons && !control.enabled) ? 0.35 : 1.0)
        border.width: qgcPal.highContrast ? 2 : 0
        border.color: qgcPal.buttonBorder
    }
}
