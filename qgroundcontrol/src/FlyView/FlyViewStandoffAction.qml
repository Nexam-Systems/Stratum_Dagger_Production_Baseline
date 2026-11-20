import QGroundControl
import QGroundControl.Controls

// STRATUM: Tool-strip command that opens the standoff entry panel (FlyViewWidgetLayer).
// Replaces the retired map-click "Standoff here" menu entry: the operator presses this
// button, the panel opens beside the strip, and the target is entered manually or
// picked off the map with the crosshair cursor. Crimson styling matches the standoff
// target marker so the command and its map artifact share one visual identity.
ToolStripAction {
    text:       qsTr("Set Standoff")
    iconSource: "/qmlimages/StandoffMarker.svg"
    enabled:    true
    visible:    true

    // STRATUM: per-action accent override, honoured by ToolStripHoverButton. The strip's
    // state-encoded accent (green/blue/red) is bypassed for this one command button.
    property color accentColorOverride:     "#D11A35"
    property color accentTextColorOverride: "#FFFFFF"
}
