import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM Dagger camera-panel wrapper. The Dagger airframe carries the C12 dual-optical
// gimbal (C12 PRO). This wrapper hosts the C12 control cluster, which reads its TV/IR
// feeds from daggerC12TvRtspUrl / daggerC12IrRtspUrl (daggerMode).
Item {
    id: root

    property bool overlayMode: false
    property bool compact: false
    function stopMotion() { if (clusterLoader.item && clusterLoader.item.stopMotion) clusterLoader.item.stopMotion() }
    onVisibleChanged: if (!visible) stopMotion()
    Component.onDestruction: stopMotion()
    // STRATUM: only the C12 PRO ships now (A2 mini removed). Pin the camera selection
    // to C12 so VideoSettings resolves the C12 RTSP feeds.
    Component.onCompleted: if (_vs.daggerCamera.rawValue !== 1) _vs.daggerCamera.rawValue = 1

    signal statusMessage(string text)

    readonly property var _vs: QGroundControl.settingsManager.videoSettings

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

        // ---- Active control cluster (C12 PRO only) ------------------
        Loader {
            id: clusterLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // FlyViewCameraControls (C12) already reads its RTSP URLs from tvRtspUrl / irRtspUrl;
            // on Dagger it is driven by daggerC12TvRtspUrl / daggerC12IrRtspUrl instead, so the
            // wrapper passes those via property aliases below.
            sourceComponent: c12Component
            onLoaded: {
                if (item && item.statusMessage) {
                    item.statusMessage.connect(function(text) { root.statusMessage(text) })
                }
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
