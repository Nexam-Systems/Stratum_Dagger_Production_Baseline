import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM Dagger camera-panel wrapper. The Dagger airframe can carry either the SIYI
// A2 mini (single-axis FPV gimbal) or the C12 dual-optical gimbal. This wrapper shows
// a segmented A2 mini / C12 selector at the top; picking one:
//   * writes videoSettings.daggerCamera (0 = A2 mini, 1 = C12), which triggers
//     VideoSettings::_applyStratumProfileToRtsp to swap the active RTSP feed
//   * swaps the visible control cluster to match the selected camera
Item {
    id: root

    property bool overlayMode: false
    property bool compact: false
    function stopMotion() { if (clusterLoader.item && clusterLoader.item.stopMotion) clusterLoader.item.stopMotion() }
    onVisibleChanged: if (!visible) stopMotion()
    Component.onDestruction: stopMotion()

    signal statusMessage(string text)

    readonly property var _vs: QGroundControl.settingsManager.videoSettings
    readonly property int _cam: _vs.daggerCamera.rawValue    // 0 = A2 mini, 1 = C12

    QGCPalette { id: contrastPalette; colorGroupEnabled: true }
    readonly property color _accent:    contrastPalette.highContrast ? contrastPalette.buttonBorder : "#79CBE8"
    readonly property color _accentDim: contrastPalette.highContrast ? contrastPalette.text : "#BCD7E4"
    readonly property real  _spacing:   ScreenTools.defaultFontPixelWidth * 0.4
    readonly property real  _pad:       overlayMode ? ScreenTools.defaultFontPixelWidth * 0.75 : 0

    implicitWidth:  contentColumn.implicitWidth + (_pad * 2)
    implicitHeight: contentColumn.implicitHeight + (_pad * 2)

    Rectangle {
        anchors.fill: parent
        visible: root.overlayMode
        color: contrastPalette.highContrast ? contrastPalette.window : Qt.rgba(0, 0, 0, 0.72)
        radius: ScreenTools.defaultBorderRadius
        border.color: root._accent
        border.width: 1
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._spacing

        // ---- Camera-type selector ------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing
            QGCButton {
                text: qsTr("A2 mini")
                implicitHeight: ScreenTools.defaultFontPixelHeight * (root.compact ? 1.7 : 2.0)
                Layout.fillWidth: true
                primary: root._cam === 0
                onClicked: {
                    root._vs.daggerCamera.rawValue = 0
                    root.statusMessage(qsTr("Dagger camera: A2 mini"))
                }
            }
            QGCButton {
                text: qsTr("C12")
                implicitHeight: ScreenTools.defaultFontPixelHeight * (root.compact ? 1.7 : 2.0)
                Layout.fillWidth: true
                primary: root._cam === 1
                onClicked: {
                    root._vs.daggerCamera.rawValue = 1
                    root.statusMessage(qsTr("Dagger camera: C12"))
                }
            }
        }

        // ---- Active control cluster ---------------------------------
        Loader {
            id: clusterLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // FlyViewCameraControls (C12) already reads its RTSP URLs from tvRtspUrl / irRtspUrl;
            // on Dagger it is driven by daggerC12TvRtspUrl / daggerC12IrRtspUrl instead, so the
            // wrapper passes those via property aliases below.
            sourceComponent: root._cam === 1 ? c12Component : a2MiniComponent
            onLoaded: {
                if (item && item.statusMessage) {
                    item.statusMessage.connect(function(text) { root.statusMessage(text) })
                }
            }
        }
        Component {
            id: a2MiniComponent
            FlyViewCameraControlsDagger {
                overlayMode: false      // outer wrapper draws the card
                compact: root.compact
            }
        }
        Component {
            id: c12Component
            FlyViewCameraControls {
                overlayMode: false      // outer wrapper draws the card
                compact: root.compact
                daggerMode: true        // pull daggerC12* URLs instead of tv/irRtspUrl
            }
        }
    }
}
