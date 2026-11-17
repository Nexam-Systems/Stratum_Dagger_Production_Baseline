import QtQuick

// STRATUM — minimal camera overlay. This is not a first-person-view layout, so the video
// carries only the centre crosshair (the tracking reticle is drawn by the tracking overlays).
// Purely passive (enabled:false) so gimbal / tracking input passes through to the video.
Item {
    id: _root

    anchors.fill: parent
    enabled: false

    property bool compact: false

    ReticleMark {
        anchors.centerIn: parent
        visible:          !_root.compact
        width:            Math.max(48, Math.min(_root.width, _root.height) * 0.08)
        height:           width
    }
}
