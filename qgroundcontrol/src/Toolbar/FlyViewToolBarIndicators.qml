import QtQuick

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Toolbar

Item {
    objectName:    "flyViewToolBarIndicators"
    implicitWidth: mainLayout.width + _widthMargin

    property var  _activeVehicle:           QGroundControl.multiVehicleManager.activeVehicle
    property color ribbonTextColor:         qgcPal.text
    property real _toolIndicatorMargins:    ScreenTools.defaultFontPixelHeight * 0.66
    property real _widthMargin:             _toolIndicatorMargins * 2

    Row {
        id:                 mainLayout
        anchors.margins:    _toolIndicatorMargins
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.bottom:     parent.bottom
        spacing:            ScreenTools.defaultFontPixelWidth * 1.75

        Repeater {
            id:     appRepeater
            model:  QGroundControl.corePlugin.toolBarIndicators
            Loader {
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                source:             modelData
                visible:            item.showIndicator
            }
        }

        Repeater {
            id:     toolIndicatorsRepeater
            model:  _activeVehicle ? _activeVehicle.toolIndicators : []

            Loader {
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                source:             modelData
                visible:            item.showIndicator
            }
        }

        Item {
            id:                     wordmarkContainer
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth:          wordmarkLabel.implicitWidth
            implicitHeight:         wordmarkLabel.implicitHeight

            property int _tapCount: 0
            property real _firstTapMs: 0

            QGCLabel {
                id:                 wordmarkLabel
                anchors.centerIn:   parent
                text:               "STRATUM"
                color:              ribbonTextColor
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize
                font.letterSpacing: 2
            }

            MouseArea {
                anchors.fill:   parent
                cursorShape:    Qt.ArrowCursor
                onClicked: {
                    var nowMs = Date.now()
                    if (wordmarkContainer._tapCount === 0 || (nowMs - wordmarkContainer._firstTapMs) > 3000) {
                        wordmarkContainer._tapCount = 1
                        wordmarkContainer._firstTapMs = nowMs
                        return
                    }
                    wordmarkContainer._tapCount += 1
                    if (wordmarkContainer._tapCount >= 7) {
                        wordmarkContainer._tapCount = 0
                        wordmarkContainer._firstTapMs = 0
                        adminDialogFactory.open()
                    }
                }
            }

            QGCPopupDialogFactory {
                id:              adminDialogFactory
                dialogComponent: adminDialogComponent
            }

            Component {
                id: adminDialogComponent
                AdminSettingsDialog { }
            }
        }
    }
}
