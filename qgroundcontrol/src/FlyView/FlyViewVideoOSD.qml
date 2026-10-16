import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM — HUD-style On-Screen Display for the video streamer.
// Green, military-HUD aesthetic: a heading tape across the top, speed and
// altitude tapes flanking a center reticle, a REC indicator, and corner
// telemetry readouts. Bound to the active vehicle facts. Purely passive
// (enabled:false) so gimbal / tracking input passes through to the video.
Item {
    id: _root

    anchors.fill: parent
    enabled: false

    property var  _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool _hasVehicle:    _activeVehicle !== null

    // Smaller / reduced HUD when the video is in the picture-in-picture corner.
    property bool compact: false
    property bool _full:   !compact

    visible: _hasVehicle && QGroundControl.videoManager.hasVideo

    // ---- HUD palette --------------------------------------------------------
    QGCPalette { id: contrastPalette; colorGroupEnabled: true }
    readonly property string _green:    contrastPalette.highContrast ? "#D6FF85" : "#3DFFA6"
    readonly property string _greenDim: contrastPalette.highContrast ? "#F5FFE9" : "#1FB97D"

    on_GreenChanged: {
        headingTape.requestPaint()
        speedTape.canvas.requestPaint()
        altTape.canvas.requestPaint()
    }
    readonly property string _shadow:   "rgba(0,0,0,0.9)"
    readonly property string _noVal:    "--"

    // ---- Sizing -------------------------------------------------------------
    readonly property real _labelPt:   (compact ? ScreenTools.smallFontPointSize   : ScreenTools.defaultFontPointSize) * 0.80
    readonly property real _valuePt:   (compact ? ScreenTools.smallFontPointSize   : ScreenTools.defaultFontPointSize) * 1.10
    readonly property real _tapeFontPx: ScreenTools.defaultFontPixelHeight * (compact ? 0.60 : 0.72)
    readonly property real _margin:     ScreenTools.defaultFontPixelHeight * (compact ? 0.6 : 1.0)

    // ---- Live numeric values (drive the tapes; repaint on change) -----------
    property real hdg:  _hasVehicle ? _activeVehicle.heading.value          : 0
    property real spd:  _hasVehicle ? _activeVehicle.groundSpeed.value      : 0
    property real altv: _hasVehicle ? _activeVehicle.altitudeRelative.value : 0

    onHdgChanged:  headingTape.requestPaint()
    onSpdChanged:  speedTape.canvas.requestPaint()
    onAltvChanged: altTape.canvas.requestPaint()

    property var _battery: (_hasVehicle && _activeVehicle.batteries.count > 0) ? _activeVehicle.batteries.get(0) : null

    // ====================== corner readout field =============================
    component HUDField : ColumnLayout {
        property string label: ""
        property string value: _root._noVal
        property string units: ""
        property int    hAlign: Text.AlignLeft
        spacing: 0

        Text {
            text:                label
            color:               _root._greenDim
            style:               Text.Outline
            styleColor:          "black"
            font.pointSize:      _root._labelPt
            font.family:         ScreenTools.normalFontFamily
            font.letterSpacing:  1.5
            horizontalAlignment: hAlign
            Layout.fillWidth:    true
            visible:             label !== ""
        }
        Text {
            text:                units === "" ? value : (value + " " + units)
            color:               _root._green
            style:               Text.Outline
            styleColor:          "black"
            font.pointSize:      _root._valuePt
            font.bold:           true
            font.family:         ScreenTools.fixedFontFamily
            horizontalAlignment: hAlign
            Layout.fillWidth:    true
        }
    }

    // ====================== vertical tape (speed / altitude) =================
    component VTape : Item {
        id: vt
        property real    value:     0
        property real    range:     30      // total units visible top-to-bottom
        property int     minorStep: 1
        property int     majorStep: 5
        property bool    boxOnRight: true   // value box / caret on reticle-facing edge
        property string  units:     ""
        property alias   canvas:    tapeCanvas

        Canvas {
            id: tapeCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext('2d'); ctx.reset()
                var w = width, h = height, cy = h / 2
                var ppu = h / vt.range
                ctx.strokeStyle = _root._green
                ctx.fillStyle   = _root._green
                ctx.lineWidth   = 1
                ctx.shadowColor = _root._shadow
                ctx.shadowBlur  = 3
                ctx.font        = _root._tapeFontPx + "px monospace"
                ctx.textBaseline = "middle"

                var v0 = vt.value - vt.range / 2
                var v1 = vt.value + vt.range / 2
                var start = Math.ceil(v0 / vt.minorStep) * vt.minorStep
                for (var v = start; v <= v1; v += vt.minorStep) {
                    var y = cy - (v - vt.value) * ppu
                    var major = (Math.round(v) % vt.majorStep === 0)
                    var len = major ? 12 : 6
                    var x0 = vt.boxOnRight ? 0 : w
                    var x1 = vt.boxOnRight ? len : w - len
                    ctx.globalAlpha = major ? 1.0 : 0.55
                    ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke()
                    if (major && Math.abs(y - cy) > _root._tapeFontPx) {
                        ctx.textAlign = vt.boxOnRight ? "left" : "right"
                        ctx.fillText("" + Math.round(v), vt.boxOnRight ? len + 3 : w - len - 3, y)
                    }
                }
                // center caret pointing toward the reticle
                ctx.globalAlpha = 1.0
                var pe  = vt.boxOnRight ? w : 0
                var tip = vt.boxOnRight ? w + 7 : -7
                ctx.beginPath()
                ctx.moveTo(pe, cy - 7); ctx.lineTo(pe, cy + 7); ctx.lineTo(tip, cy); ctx.closePath()
                ctx.fill()
            }
        }
        onValueChanged:  tapeCanvas.requestPaint()
        onWidthChanged:  tapeCanvas.requestPaint()
        onHeightChanged: tapeCanvas.requestPaint()

        // current-value box on the reticle-facing edge
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right:          vt.boxOnRight ? parent.right : undefined
            anchors.left:           vt.boxOnRight ? undefined : parent.left
            width:                  valueText.contentWidth + ScreenTools.defaultFontPixelWidth * 1.4
            height:                 valueText.contentHeight + ScreenTools.defaultFontPixelHeight * 0.4
            color:                  contrastPalette.highContrast ? "#FF050A06" : "#A0000000"
            border.color:           _root._green
            border.width:           1
            Text {
                id: valueText
                anchors.centerIn: parent
                text:             Math.round(vt.value)
                color:            _root._green
                font.bold:        true
                font.family:      ScreenTools.fixedFontFamily
                font.pointSize:   _root._valuePt
            }
        }
    }

    // ====================== REC indicator (top center) =======================
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:              parent.top
        anchors.topMargin:        _margin * 0.6
        spacing:                  ScreenTools.defaultFontPixelWidth
        visible:                  QGroundControl.videoManager.recording

        Rectangle {
            width:  ScreenTools.defaultFontPixelHeight * 0.5
            height: width
            radius: width / 2
            color:  "#FF3B30"
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
                running: true; loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.25; duration: 700 }
                NumberAnimation { from: 0.25; to: 1.0; duration: 700 }
            }
        }
        Text {
            text:           "REC"
            color:          "#FF3B30"
            font.bold:      true
            font.family:    ScreenTools.fixedFontFamily
            font.pointSize: _root._labelPt
            style:          Text.Outline
            styleColor:     "black"
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ====================== heading tape (top center) ========================
    Canvas {
        id: headingTape
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:              parent.top
        anchors.topMargin:        _margin * 1.9
        width:                    Math.min(_root.width * 0.55, ScreenTools.defaultFontPixelWidth * 60)
        height:                   ScreenTools.defaultFontPixelHeight * (compact ? 1.8 : 2.2)
        visible:                  _full
        onWidthChanged:           requestPaint()

        onPaint: {
            var ctx = getContext('2d'); ctx.reset()
            var w = width, h = height, cx = w / 2
            var range = 80                       // degrees visible across the tape
            var ppd = w / range
            var top = h * 0.30
            ctx.strokeStyle = _root._green
            ctx.fillStyle   = _root._green
            ctx.lineWidth   = 1
            ctx.shadowColor = _root._shadow
            ctx.shadowBlur  = 3
            ctx.textAlign   = "center"
            ctx.font        = _root._tapeFontPx + "px monospace"

            var start = Math.ceil((_root.hdg - range / 2) / 5) * 5
            for (var d = start; d <= _root.hdg + range / 2; d += 5) {
                var x  = cx + (d - _root.hdg) * ppd
                var dd = ((Math.round(d) % 360) + 360) % 360
                var major = (dd % 10 === 0)
                ctx.globalAlpha = major ? 1.0 : 0.55
                ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, top + (major ? 10 : 5)); ctx.stroke()
                if (major) {
                    var lbl = dd === 0 ? "N" : dd === 90 ? "E" : dd === 180 ? "S" : dd === 270 ? "W" : ("" + dd)
                    ctx.fillText(lbl, x, top + 12 + _root._tapeFontPx)
                }
            }
            // center index triangle
            ctx.globalAlpha = 1.0
            ctx.beginPath()
            ctx.moveTo(cx - 6, top - 9); ctx.lineTo(cx + 6, top - 9); ctx.lineTo(cx, top - 1); ctx.closePath()
            ctx.fill()
        }

        // numeric heading box centered above the tape
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom:           parent.top
            width:                    hdgText.contentWidth + ScreenTools.defaultFontPixelWidth * 1.6
            height:                   hdgText.contentHeight + ScreenTools.defaultFontPixelHeight * 0.3
            color:                    contrastPalette.highContrast ? "#FF050A06" : "#A0000000"
            border.color:             _root._green
            border.width:             1
            Text {
                id: hdgText
                anchors.centerIn: parent
                text:             _hasVehicle ? (("00" + Math.round(_root.hdg)).slice(-3) + "°") : _noVal
                color:            _root._green
                font.bold:        true
                font.family:      ScreenTools.fixedFontFamily
                font.pointSize:   _root._valuePt
            }
        }
    }

    // ====================== center reticle ===================================
    Canvas {
        id: reticle
        anchors.centerIn: parent
        width:  Math.max(80, Math.min(_root.width, _root.height) * 0.16)
        height: width
        visible: _full
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext('2d'); ctx.reset()
            var w = width, h = height, cx = w / 2, cy = h / 2, r = w / 2 - 4
            ctx.strokeStyle = _root._green
            ctx.lineWidth   = 1.5
            ctx.shadowColor = _root._shadow
            ctx.shadowBlur  = 3
            ctx.setLineDash([6, 6])
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
            ctx.setLineDash([])
            var t = 14, g = 8
            ctx.beginPath()
            ctx.moveTo(cx - r, cy);     ctx.lineTo(cx - r + t, cy)
            ctx.moveTo(cx + r, cy);     ctx.lineTo(cx + r - t, cy)
            ctx.moveTo(cx, cy - r);     ctx.lineTo(cx, cy - r + t)
            ctx.moveTo(cx, cy + r);     ctx.lineTo(cx, cy + r - t)
            ctx.moveTo(cx - g, cy);     ctx.lineTo(cx + g, cy)
            ctx.moveTo(cx, cy - g);     ctx.lineTo(cx, cy + g)
            ctx.stroke()
        }
    }

    // ====================== speed tape (left of reticle) =====================
    VTape {
        id:           speedTape
        boxOnRight:   true
        value:        _root.spd
        range:        24
        minorStep:    1
        majorStep:    5
        width:        ScreenTools.defaultFontPixelWidth * 8
        height:       Math.min(_root.height * 0.46, ScreenTools.defaultFontPixelHeight * 16)
        visible:      _full
        anchors.verticalCenter: parent.verticalCenter
        anchors.right:          reticle.left
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 4
    }
    Text {
        anchors.horizontalCenter: speedTape.horizontalCenter
        anchors.top:              speedTape.bottom
        anchors.topMargin:        2
        visible:                  _full
        text:                     "GS " + (_hasVehicle ? _activeVehicle.groundSpeed.units : "")
        color:                    _root._greenDim
        style:                    Text.Outline
        styleColor:               "black"
        font.family:              ScreenTools.normalFontFamily
        font.pointSize:           _root._labelPt
    }

    // ====================== altitude tape (right of reticle) =================
    VTape {
        id:           altTape
        boxOnRight:   false
        value:        _root.altv
        range:        40
        minorStep:    2
        majorStep:    10
        width:        ScreenTools.defaultFontPixelWidth * 9
        height:       Math.min(_root.height * 0.46, ScreenTools.defaultFontPixelHeight * 16)
        visible:      _full
        anchors.verticalCenter: parent.verticalCenter
        anchors.left:           reticle.right
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 4
    }
    Text {
        anchors.horizontalCenter: altTape.horizontalCenter
        anchors.top:              altTape.bottom
        anchors.topMargin:        2
        visible:                  _full
        text:                     "ALT " + (_hasVehicle ? _activeVehicle.altitudeRelative.units : "")
        color:                    _root._greenDim
        style:                    Text.Outline
        styleColor:               "black"
        font.family:              ScreenTools.normalFontFamily
        font.pointSize:           _root._labelPt
    }

    // ====================== TOP-LEFT : status ================================
    ColumnLayout {
        anchors.left:    parent.left
        anchors.top:     parent.top
        anchors.margins: _margin
        spacing:         _margin * 0.5

        HUDField { label: qsTr("FLIGHT MODE"); value: _hasVehicle ? _activeVehicle.flightMode : _noVal }
        HUDField { label: qsTr("ARMED");       value: _hasVehicle ? (_activeVehicle.armed ? qsTr("ARMED") : qsTr("DISARMED")) : _noVal }
        HUDField { label: qsTr("GPS SATS");    value: _hasVehicle && _activeVehicle.gps && _activeVehicle.gps.count ? _activeVehicle.gps.count.valueString : _noVal }
        HUDField { label: qsTr("HDOP");        value: _hasVehicle && _activeVehicle.gps && _activeVehicle.gps.hdop ? _activeVehicle.gps.hdop.valueString : _noVal }
    }

    // ====================== TOP-RIGHT : power / link =========================
    ColumnLayout {
        anchors.right:   parent.right
        anchors.top:     parent.top
        anchors.margins: _margin
        spacing:         _margin * 0.5
        width:           ScreenTools.defaultFontPixelWidth * 18

        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("BATTERY");  value: _battery ? _battery.percentRemaining.valueString : _noVal; units: "%" }
        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("VOLTAGE");  value: _battery ? _battery.voltage.valueString : _noVal; units: _battery ? _battery.voltage.units : "" }
        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("CURRENT");  value: _battery ? _battery.current.valueString : _noVal; units: _battery ? _battery.current.units : "" }
        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("RC RSSI");  value: _hasVehicle && _activeVehicle.rcRSSI ? _activeVehicle.rcRSSI.valueString : _noVal; units: "%" }
    }

    // ====================== BOTTOM-LEFT : target / time ======================
    ColumnLayout {
        anchors.left:    parent.left
        anchors.bottom:  parent.bottom
        anchors.margins: _margin
        spacing:         _margin * 0.5

        HUDField { label: qsTr("LATITUDE");    value: _hasVehicle && _activeVehicle.gps && _activeVehicle.gps.lat ? _activeVehicle.gps.lat.valueString : _noVal }
        HUDField { label: qsTr("LONGITUDE");   value: _hasVehicle && _activeVehicle.gps && _activeVehicle.gps.lon ? _activeVehicle.gps.lon.valueString : _noVal }
        HUDField { label: qsTr("FLIGHT TIME"); value: _hasVehicle ? _activeVehicle.flightTime.valueString : _noVal }
    }

    // ====================== BOTTOM-RIGHT : nav / control =====================
    ColumnLayout {
        anchors.right:   parent.right
        anchors.bottom:  parent.bottom
        anchors.margins: _margin
        width:           ScreenTools.defaultFontPixelWidth * 18
        spacing:         _margin * 0.5

        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("DIST HOME"); value: _hasVehicle ? _activeVehicle.distanceToHome.valueString : _noVal; units: _hasVehicle ? _activeVehicle.distanceToHome.units : "" }
        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("THROTTLE");  value: _hasVehicle ? _activeVehicle.throttlePct.valueString : _noVal; units: "%" }
        HUDField { Layout.fillWidth: true; hAlign: Text.AlignRight; label: qsTr("CLIMB");     value: _hasVehicle ? _activeVehicle.climbRate.valueString : _noVal; units: _hasVehicle ? _activeVehicle.climbRate.units : "" }
    }
}
