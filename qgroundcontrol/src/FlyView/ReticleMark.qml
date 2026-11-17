import QtQuick
import QtQuick.Shapes

// STRATUM: minimal reticle glyph used for both the camera crosshair and the tracking box.
// Thin, open-centre cross: a short arm at the middle of each edge of the item, with a small
// end-cap on the left/right arms. Size the item to size the reticle (square for the
// crosshair, the target box for tracking). Drawn with a dark under-stroke so it stays
// readable on bright and dark video.
Item {
    id: root

    property color color:     "white"
    property real  lineWidth: 1.5
    property real  armLength: Math.max(6, Math.min(40, Math.min(width, height) * 0.25))

    component ReticlePath : ShapePath {
        property real rw:  0
        property real rh:  0
        property real arm: 0

        fillColor: "transparent"
        capStyle:  ShapePath.FlatCap

        // left arm + end-cap
        PathMove { x: 0;        y: rh / 2 }
        PathLine { x: arm;      y: rh / 2 }
        PathMove { x: 0;        y: rh / 2 - arm / 2 }
        PathLine { x: 0;        y: rh / 2 + arm / 2 }
        // right arm + end-cap
        PathMove { x: rw;       y: rh / 2 }
        PathLine { x: rw - arm; y: rh / 2 }
        PathMove { x: rw;       y: rh / 2 - arm / 2 }
        PathLine { x: rw;       y: rh / 2 + arm / 2 }
        // top / bottom arms
        PathMove { x: rw / 2;   y: 0 }
        PathLine { x: rw / 2;   y: arm }
        PathMove { x: rw / 2;   y: rh }
        PathLine { x: rw / 2;   y: rh - arm }
    }

    Shape {
        anchors.fill:          parent
        antialiasing:          true
        preferredRendererType: Shape.CurveRenderer

        ReticlePath {
            rw: root.width; rh: root.height; arm: root.armLength
            strokeColor: Qt.rgba(0, 0, 0, 0.85)
            strokeWidth: root.lineWidth + 2
        }
        ReticlePath {
            rw: root.width; rh: root.height; arm: root.armLength
            strokeColor: root.color
            strokeWidth: root.lineWidth
        }
    }
}
