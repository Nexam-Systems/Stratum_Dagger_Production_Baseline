import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.PlanView

FlightMap {
    id:                         _root
    allowGCSLocationCenter:     true
    allowVehicleLocationCenter: !_keepVehicleCentered
    planView:                   false
    zoomLevel:                  QGroundControl.flightMapZoom
    center:                     QGroundControl.flightMapPosition

    property Item   pipView
    property Item   pipState:                   _pipState
    property var    rightPanelWidth
    property var    planMasterController
    property bool   pipMode:                    false   // true: map is shown in a small pip mode
    property var    toolInsets                          // Insets for the center viewport area

    property var    _activeVehicle:             QGroundControl.multiVehicleManager.activeVehicle
    property var    _planMasterController:      planMasterController
    property var    _geoFenceController:        planMasterController.geoFenceController
    property var    _rallyPointController:      planMasterController.rallyPointController
    property var    _activeVehicleCoordinate:   _activeVehicle ? _activeVehicle.coordinate : QtPositioning.coordinate()
    property real   _toolButtonTopMargin:       parent.height - mainWindow.height + (ScreenTools.defaultFontPixelHeight / 2)
    property real   _toolsMargin:               ScreenTools.defaultFontPixelWidth * 0.75
    property var    _flyViewSettings:           QGroundControl.settingsManager.flyViewSettings
    property bool   _keepMapCenteredOnVehicle:  _flyViewSettings.keepMapCenteredOnVehicle.rawValue

    property bool   _disableVehicleTracking:    false
    property bool   _keepVehicleCentered:       pipMode ? true : false
    property bool   _saveZoomLevelSetting:      true

    // STRATUM: usable map viewport. The TOP is inset below the STRATUM command
    // toolbar. QGCMapPolygonVisuals anchors its editing toolbar (Basic / Circular /
    // Trace / Load KML-SHP) at centerViewport.top; with a full-height rect that top
    // is y=0, hiding those tools behind the toolbar overlay. Insetting fixes that and
    // also keeps any default-polygon reset inside the visible area. FlyViewMap (unlike
    // PlanView's editorMap) declares no centerViewport, so define one here.
    property real   _aopTopInset:               (toolInsets ? toolInsets.topEdgeCenterInset : 0) + ScreenTools.defaultFontPixelHeight
    property rect   centerViewport:             Qt.rect(0, _aopTopInset, width, height - _aopTopInset)

    // STRATUM: Area-Of-Operations (AOP) edit state. When true the inclusion
    // geofence polygon becomes interactive (draggable vertices, add/remove)
    // and the Apply/Cancel bar is shown. The AOP is a polygon inclusion fence.
    property bool   _aopEditMode:               false
    // STRATUM: latched true when the last Apply was rejected because an AOP vertex sat
    // farther than flyViewSettings.maxAOPDistance from the enforcement anchor. Consumed
    // by the edit-bar warning in FlyViewWidgetLayer.qml; cleared on the next Apply and
    // on cancel.
    property bool   _aopRangeReject:            false

    // STRATUM: Standoff target pick mode. Driven by the Set Standoff panel in
    // FlyViewWidgetLayer: while active the map cursor is a crosshair and a left
    // click reports the clicked coordinate through standoffTargetPicked() instead
    // of opening the guided-action menu. The panel owns the lifecycle via
    // startStandoffPick() / stopStandoffPick().
    property bool   _standoffPickMode:          false

    // STRATUM: standoff command controller, exposed so the widget-layer panel can
    // commit through beginStandoff().
    readonly property var standoffCmdController: standoffController

    // STRATUM: interim target while the Set Standoff panel is open. Fed by the panel
    // (map pick or valid manual lat/lon entry - the panel is the single writer) and
    // rendered as the BLUE pending marker. Cleared when pick mode ends; on commit the
    // controller's _targetCoordinate takes over and the marker turns red (engaged).
    property var    _standoffPendingCoordinate: QtPositioning.coordinate()

    signal standoffTargetPicked(var coordinate)

    // STRATUM: emitted by the map-click "Set Standoff here" menu item. Handled in
    // FlyView.qml by opening the Set Standoff panel pre-filled with the coordinate.
    signal setStandoffHereRequested(var coordinate)

    function startStandoffPick() { _standoffPickMode = true }
    function stopStandoffPick() {
        _standoffPickMode = false
        _standoffPendingCoordinate = QtPositioning.coordinate()
    }
    function setStandoffPendingCoordinate(coordinate) {
        _standoffPendingCoordinate = coordinate
    }

    // STRATUM: true when the fence model already holds an inclusion polygon with
    // enough vertices to be a real, visible area. A connected vehicle whose fence is
    // empty (or a zero-vertex placeholder) returns false, so we seed our own AOP
    // rather than leave the operator with the edit bar and no shape.
    function _hasUsableAOPPolygon() {
        if (!_geoFenceController) {
            return false
        }
        for (var i = 0; i < _geoFenceController.polygons.count; i++) {
            var poly = _geoFenceController.polygons.get(i)
            if (poly && poly.count >= 3) {
                return true
            }
        }
        return false
    }

    // STRATUM: AOP enforcement for coordinate-bearing commands (e.g. standoff). Mirrors
    // the web UI's isInsideAOP rejection: returns true if the coordinate is allowed —
    // either no usable AOP inclusion polygon is defined, or the coordinate falls inside
    // one. Returns false only when an AOP exists and the coordinate is outside all of it.
    function isCoordinateInsideAOP(coordinate) {
        if (!_geoFenceController || !coordinate || !coordinate.isValid) {
            return true
        }
        var haveAOP = false
        for (var i = 0; i < _geoFenceController.polygons.count; i++) {
            var poly = _geoFenceController.polygons.get(i)
            if (poly && poly.inclusion && poly.count >= 3) {
                haveAOP = true
                if (poly.containsCoordinate(coordinate)) {
                    return true
                }
            }
        }
        return !haveAOP
    }

    // STRATUM: seed the default AOP box from the map CENTRE using fixed metric
    // offsets, NOT pixel->coordinate conversion. toCoordinate() returns an invalid
    // coordinate whenever the 2D map is not the actively rendered surface (3D viewer
    // up) or not yet laid out, which collapses addInclusionPolygon() to a zero-area,
    // invisible polygon. The map centre is always valid while the map exists.
    function _seedAOPPolygon() {
        if (!_geoFenceController) {
            return false
        }
        var center = _root.center
        if (!center || !center.isValid) {
            console.log("STRATUM AOP: map centre invalid; cannot seed polygon")
            return false
        }
        var halfBox          = 750  // metres; addInclusionPolygon insets this ~0.75
        var topLeftCoord     = center.atDistanceAndAzimuth(halfBox, -90).atDistanceAndAzimuth(halfBox, 0)
        var bottomRightCoord = center.atDistanceAndAzimuth(halfBox, 90).atDistanceAndAzimuth(halfBox, 180)
        _geoFenceController.addInclusionPolygon(topLeftCoord, bottomRightCoord)
        return true
    }

    function _makeAOPPolygonsInteractive() {
        for (var i = 0; i < _geoFenceController.polygons.count; i++) {
            _geoFenceController.polygons.get(i).interactive = true
        }
    }

    // Enter AOP edit mode. Seed a default inclusion polygon unless the vehicle/plan
    // already holds a usable one, then make the fence polygons interactive.
    function startAOPEdit() {
        if (!_geoFenceController) {
            console.log("STRATUM AOP: no geoFenceController; cannot start edit")
            return
        }
        if (!_hasUsableAOPPolygon()) {
            _seedAOPPolygon()
        }
        _makeAOPPolygonsInteractive()
        _aopEditMode = true
        _aopRangeReject = false
    }

    // STRATUM: enforcement anchor for the max-AOP-distance check. Home wins when
    // it is valid, then the live vehicle coordinate, then the map centre as an offline
    // fallback. Returning an invalid coordinate disables the check entirely.
    function _aopRangeAnchor() {
        var v = QGroundControl.multiVehicleManager.activeVehicle
        if (v) {
            if (v.homePosition && v.homePosition.isValid) {
                return v.homePosition
            }
            if (v.coordinate && v.coordinate.isValid) {
                return v.coordinate
            }
        }
        if (_root.center && _root.center.isValid) {
            return _root.center
        }
        return QtPositioning.coordinate()
    }

    // STRATUM: returns true if every inclusion-polygon vertex sits within
    // flyViewSettings.maxAOPDistance metres of _aopRangeAnchor(). An invalid anchor
    // (no vehicle and no map centre) short-circuits to true so the check never blocks
    // a genuinely offline layout.
    function _aopVerticesWithinRange() {
        if (!_geoFenceController) {
            return true
        }
        var anchor = _aopRangeAnchor()
        if (!anchor.isValid) {
            return true
        }
        var maxMeters = QGroundControl.settingsManager.flyViewSettings.maxAOPDistance.rawValue
        for (var i = 0; i < _geoFenceController.polygons.count; i++) {
            var poly = _geoFenceController.polygons.get(i)
            if (!poly || !poly.inclusion) {
                continue
            }
            var path = poly.path
            for (var v = 0; v < path.length; v++) {
                var vertex = path[v]
                if (!vertex || !vertex.isValid) {
                    continue
                }
                if (anchor.distanceTo(vertex) > maxMeters) {
                    return false
                }
            }
        }
        return true
    }

    // Commit the AOP: lock the polygon and, when a vehicle is connected, upload
    // it as an inclusion geofence so the flight controller enforces the boundary.
    // With no vehicle the boundary is simply locked locally (planning only).
    function applyAOPEdit() {
        if (!_geoFenceController) {
            return
        }
        // STRATUM: reject the commit if any vertex is farther than
        // flyViewSettings.maxAOPDistance from the anchor. Do NOT drop interactivity
        // or leave edit mode - the operator must pull the offending vertex in.
        if (!_aopVerticesWithinRange()) {
            _aopRangeReject = true
            return
        }
        _aopRangeReject = false
        for (var i = 0; i < _geoFenceController.polygons.count; i++) {
            _geoFenceController.polygons.get(i).interactive = false
        }
        // STRATUM: leave edit mode and drop interactivity BEFORE the upload. If
        // sendToVehicle() ever fails (rejected geofence, no link), the view must
        // still unwind — otherwise _aopEditMode stays true and the map-click guard
        // permanently suppresses the guided-action ("Go here") panel.
        _aopEditMode = false
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            _geoFenceController.sendToVehicle()
        }
    }

    // Abandon edits. If a vehicle is connected, restore the boundary it holds;
    // otherwise just drop interactivity and leave the local boundary untouched.
    function cancelAOPEdit() {
        _aopRangeReject = false
        if (!_geoFenceController) {
            _aopEditMode = false
            return
        }
        _geoFenceController.clearAllInteractive()
        _aopEditMode = false
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            _geoFenceController.loadFromVehicle()
        }
    }

    // STRATUM: in the Fly view the GeoFenceController treats the CONNECTED vehicle as
    // the source of truth and rebuilds the polygon model from the vehicle on every
    // manager loadComplete (_setFenceFromManager -> clearAndDeleteContents). That
    // silently destroys the client-seeded AOP polygon, so once a vehicle is connected
    // the operator sees the edit bar but no shape. While AOP edit mode is active,
    // re-seed whenever the model loses its usable polygon. Deferred through a 0ms timer
    // so it runs AFTER the manager's clear+repopulate fully unwinds - this avoids
    // re-entrancy and lets a real vehicle-held fence win over our default seed.
    Connections {
        target: _geoFenceController ? _geoFenceController.polygons : null
        function onCountChanged() {
            if (_root._aopEditMode) {
                _aopReseedTimer.restart()
            }
        }
    }

    Timer {
        id:         _aopReseedTimer
        interval:   0
        repeat:     false
        onTriggered: {
            if (_root._aopEditMode && !_hasUsableAOPPolygon()) {
                if (_seedAOPPolygon()) {
                    _makeAOPPolygonsInteractive()
                }
            }
        }
    }

    function _adjustMapZoomForPipMode() {
        _saveZoomLevelSetting = false
        if (pipMode) {
            if (QGroundControl.flightMapZoom > 3) {
                zoomLevel = QGroundControl.flightMapZoom - 3
            }
        } else {
            zoomLevel = QGroundControl.flightMapZoom
        }
        _saveZoomLevelSetting = true
    }

    onPipModeChanged: _adjustMapZoomForPipMode()

    onVisibleChanged: {
        if (visible) {
            // Synchronize center position with Plan View
            center = QGroundControl.flightMapPosition
        }
    }

    onZoomLevelChanged: {
        if (_saveZoomLevelSetting) {
            QGroundControl.flightMapZoom = _root.zoomLevel
        }
    }
    onCenterChanged: {
        QGroundControl.flightMapPosition = _root.center
    }

    // We track whether the user has panned or not to correctly handle automatic map positioning
    onMapPanStart:  _disableVehicleTracking = true
    onMapPanStop:   panRecenterTimer.restart()

    function pointInRect(point, rect) {
        return point.x > rect.x &&
                point.x < rect.x + rect.width &&
                point.y > rect.y &&
                point.y < rect.y + rect.height;
    }

    property real _animatedLatitudeStart
    property real _animatedLatitudeStop
    property real _animatedLongitudeStart
    property real _animatedLongitudeStop
    property real animatedLatitude
    property real animatedLongitude

    onAnimatedLatitudeChanged: _root.center = QtPositioning.coordinate(animatedLatitude, animatedLongitude)
    onAnimatedLongitudeChanged: _root.center = QtPositioning.coordinate(animatedLatitude, animatedLongitude)

    NumberAnimation on animatedLatitude { id: animateLat; from: _animatedLatitudeStart; to: _animatedLatitudeStop; duration: 1000 }
    NumberAnimation on animatedLongitude { id: animateLong; from: _animatedLongitudeStart; to: _animatedLongitudeStop; duration: 1000 }

    function animatedMapRecenter(fromCoord, toCoord) {
        _animatedLatitudeStart = fromCoord.latitude
        _animatedLongitudeStart = fromCoord.longitude
        _animatedLatitudeStop = toCoord.latitude
        _animatedLongitudeStop = toCoord.longitude
        animateLat.start()
        animateLong.start()
    }

    // returns the rectangle formed by the four center insets
    // used for checking if vehicle is under ui, and as a target for recentering the view
    function _insetCenterRect() {
        return Qt.rect(toolInsets.leftEdgeCenterInset,
                       toolInsets.topEdgeCenterInset,
                       _root.width - toolInsets.leftEdgeCenterInset - toolInsets.rightEdgeCenterInset,
                       _root.height - toolInsets.topEdgeCenterInset - toolInsets.bottomEdgeCenterInset)
    }

    // returns the four rectangles formed by the 8 corner insets
    // used for detecting if the vehicle has flown under the instrument panel, virtual joystick etc
    function _insetCornerRects() {
        var rects = {
        "topleft":      Qt.rect(0,0,
                               toolInsets.leftEdgeTopInset,
                               toolInsets.topEdgeLeftInset),
        "topright":     Qt.rect(_root.width-toolInsets.rightEdgeTopInset,0,
                               toolInsets.rightEdgeTopInset,
                               toolInsets.topEdgeRightInset),
        "bottomleft":   Qt.rect(0,_root.height-toolInsets.bottomEdgeLeftInset,
                               toolInsets.leftEdgeBottomInset,
                               toolInsets.bottomEdgeLeftInset),
        "bottomright":  Qt.rect(_root.width-toolInsets.rightEdgeBottomInset,_root.height-toolInsets.bottomEdgeRightInset,
                               toolInsets.rightEdgeBottomInset,
                               toolInsets.bottomEdgeRightInset)}
        return rects
    }

    function recenterNeeded() {
        var vehiclePoint = _root.fromCoordinate(_activeVehicleCoordinate, false /* clipToViewport */)
        var centerRect = _insetCenterRect()
        //return !pointInRect(vehiclePoint,insetRect)

        // If we are outside the center inset rectangle, recenter
        if(!pointInRect(vehiclePoint, centerRect)){
            return true
        }

        // if we are inside the center inset rectangle
        // then additionally check if we are underneath one of the corner inset rectangles
        var cornerRects = _insetCornerRects()
        if(pointInRect(vehiclePoint, cornerRects["topleft"])){
            return true
        } else if(pointInRect(vehiclePoint, cornerRects["topright"])){
            return true
        } else if(pointInRect(vehiclePoint, cornerRects["bottomleft"])){
            return true
        } else if(pointInRect(vehiclePoint, cornerRects["bottomright"])){
            return true
        }

        // if we are inside the center inset rectangle, and not under any corner elements
        return false
    }

    function updateMapToVehiclePosition() {
        if (animateLat.running || animateLong.running) {
            return
        }
        // We let FlightMap handle first vehicle position
        if (!_keepMapCenteredOnVehicle && firstVehiclePositionReceived && _activeVehicleCoordinate.isValid && !_disableVehicleTracking) {
            if (_keepVehicleCentered) {
                _root.center = _activeVehicleCoordinate
            } else {
                if (firstVehiclePositionReceived && recenterNeeded()) {
                    // Move the map such that the vehicle is centered within the inset area
                    var vehiclePoint = _root.fromCoordinate(_activeVehicleCoordinate, false /* clipToViewport */)
                    var centerInsetRect = _insetCenterRect()
                    var centerInsetPoint = Qt.point(centerInsetRect.x + centerInsetRect.width / 2, centerInsetRect.y + centerInsetRect.height / 2)
                    var centerOffset = Qt.point((_root.width / 2) - centerInsetPoint.x, (_root.height / 2) - centerInsetPoint.y)
                    var vehicleOffsetPoint = Qt.point(vehiclePoint.x + centerOffset.x, vehiclePoint.y + centerOffset.y)
                    var vehicleOffsetCoord = _root.toCoordinate(vehicleOffsetPoint, false /* clipToViewport */)
                    animatedMapRecenter(_root.center, vehicleOffsetCoord)
                }
            }
        }
    }

    on_ActiveVehicleCoordinateChanged: {
        if (_keepMapCenteredOnVehicle && _activeVehicleCoordinate.isValid && !_disableVehicleTracking) {
            _root.center = _activeVehicleCoordinate
        }
    }

    PipState {
        id:         _pipState
        pipView:    _root.pipView
        isDark:     _isFullWindowItemDark
    }

    Timer {
        id:         panRecenterTimer
        interval:   10000
        running:    false
        onTriggered: {
            _disableVehicleTracking = false
            updateMapToVehiclePosition()
        }
    }

    Timer {
        interval:       500
        running:        true
        repeat:         true
        onTriggered:    updateMapToVehiclePosition()
    }

    QGCMapPalette { id: mapPal; lightColors: isSatelliteMap }

    Connections {
        target:                 _missionController
        ignoreUnknownSignals:   true
        function onNewItemsFromVehicle() {
            var visualItems = _missionController.visualItems
            if (visualItems && visualItems.count !== 1) {
                mapFitFunctions.fitMapViewportToMissionItems()
                firstVehiclePositionReceived = true
            }
        }
    }

    MapFitFunctions {
        id:                         mapFitFunctions // The name for this id cannot be changed without breaking references outside of this code. Beware!
        map:                        _root
        usePlannedHomePosition:     false
        planMasterController:       _planMasterController
    }

    ObstacleDistanceOverlayMap {
        id: obstacleDistance
        showText: !pipMode
    }

    // Add trajectory lines to the map
    MapPolyline {
        id:         trajectoryPolyline
        line.width: 3
        line.color: "red"
        z:          QGroundControl.zOrderTrajectoryLines
        visible:    !pipMode

        Connections {
            target:                 QGroundControl.multiVehicleManager
            function onActiveVehicleChanged(activeVehicle) {
                trajectoryPolyline.path = _activeVehicle ? _activeVehicle.trajectoryPoints.list() : []
            }
        }

        Connections {
            target:                             _activeVehicle ? _activeVehicle.trajectoryPoints : null
            function onPointAdded(coordinate) { trajectoryPolyline.addCoordinate(coordinate) }
            function onUpdateLastPoint(coordinate) { trajectoryPolyline.replaceCoordinate(trajectoryPolyline.pathLength() - 1, coordinate) }
            function onPointsCleared() { trajectoryPolyline.path = [] }
        }
    }

    // STRATUM: operator (GCS) situational awareness on the map.
    // Records the operator's movement, draws a tactical marker at the operator's
    // position, and shows a bearing/distance line from the operator to the active
    // vehicle. Populated by QGCPositionManager (same source as the base FlightMap
    // GCS icon), so nothing extra needs to be wired.
    property var  _gcsPosition:               QGroundControl.qgcPositionManger.gcsPosition
    property real _gcsHeading:                QGroundControl.qgcPositionManger.gcsHeading
    property var  _gcsTrail:                  []
    readonly property real _gcsTrailThresholdM: 2.0
    readonly property int  _gcsTrailMax:        5000

    Connections {
        target: QGroundControl.qgcPositionManger
        function onGcsPositionChanged(gcsPosition) {
            _root._gcsPosition = gcsPosition
            if (!gcsPosition.isValid) {
                return
            }
            var trail = _root._gcsTrail
            if (trail.length > 0) {
                var last = trail[trail.length - 1]
                if (last.distanceTo(gcsPosition) < _root._gcsTrailThresholdM) {
                    return
                }
            }
            trail = trail.concat([gcsPosition])
            if (trail.length > _root._gcsTrailMax) {
                trail = trail.slice(trail.length - _root._gcsTrailMax)
            }
            _root._gcsTrail = trail
            gcsTrailPolyline.path = trail
        }
    }

    // Operator movement trail (accent cyan, dim).
    MapPolyline {
        id:         gcsTrailPolyline
        line.width: 2
        line.color: "#48D6FF"
        opacity:    0.55
        z:          QGroundControl.zOrderTrajectoryLines
        visible:    _root._gcsTrail.length >= 2 && !pipMode
    }

    // Bearing line: operator -> active vehicle (amber, distinguishes it from the
    // red trajectory and the green operator trail).
    MapPolyline {
        id:         gcsBearingLine
        line.width: 2
        line.color: "#F59E0B"
        opacity:    0.85
        z:          QGroundControl.zOrderTrajectoryLines
        visible:    !pipMode && _root._gcsPosition && _root._gcsPosition.isValid &&
                    _root._activeVehicleCoordinate && _root._activeVehicleCoordinate.isValid
        path:       visible ? [_root._gcsPosition, _root._activeVehicleCoordinate] : []
    }

    // STRATUM operator marker: concentric accent-cyan rings + heading wedge + "OP"
    // label. Layered above the base FlightMap GCS logo so it reads clearly in
    // daylight. When QGCPositionManager provides a valid direction (gcsHeading is
    // not NaN, i.e. the GPS source reports movement bearing) the wedge points along
    // that heading, matching the vehicle icon's heading behaviour.
    MapQuickItem {
        id:             gcsMarker
        coordinate:     _root._gcsPosition
        visible:        _root._gcsPosition && _root._gcsPosition.isValid && !pipMode
        anchorPoint.x:  sourceItem.width  / 2
        anchorPoint.y:  sourceItem.height / 2
        z:              QGroundControl.zOrderVehicles

        sourceItem: Item {
            width:  ScreenTools.defaultFontPixelHeight * 2.6
            height: ScreenTools.defaultFontPixelHeight * 2.6

            Rectangle {
                anchors.centerIn: parent
                width:            parent.width  * 0.85
                height:           parent.height * 0.85
                radius:           width / 2
                color:            "#3348D6FF"
                border.color:     "#48D6FF"
                border.width:     2
            }
            Rectangle {
                anchors.centerIn: parent
                width:            parent.width  * 0.42
                height:           parent.height * 0.42
                radius:           width / 2
                color:            "#48D6FF"
                border.color:     "#001622"
                border.width:     1
            }

            // Rotating heading wedge rendered on top of the rings so the chevron
            // reads as a compass needle. Hidden when the GPS source does not report
            // a bearing (gcsHeading = NaN).
            Item {
                id:                 gcsHeadingWedge
                anchors.fill:       parent
                visible:            !isNaN(_root._gcsHeading)
                rotation:           isNaN(_root._gcsHeading) ? 0 : _root._gcsHeading

                Canvas {
                    id:             gcsHeadingCanvas
                    anchors.fill:   parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx    = width / 2
                        var tip   = 0
                        var baseY = height * 0.28
                        var half  = width * 0.13
                        ctx.beginPath()
                        ctx.moveTo(cx,        tip)
                        ctx.lineTo(cx - half, baseY)
                        ctx.lineTo(cx + half, baseY)
                        ctx.closePath()
                        ctx.fillStyle   = "#48D6FF"
                        ctx.strokeStyle = "#001622"
                        ctx.lineWidth   = 1.5
                        ctx.fill()
                        ctx.stroke()
                    }
                    onWidthChanged:  requestPaint()
                    onHeightChanged: requestPaint()
                }
            }

            QGCLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top:              parent.bottom
                anchors.topMargin:        1
                text:                     qsTr("OP")
                font.pointSize:           ScreenTools.smallFontPointSize
                font.bold:                true
                color:                    "#48D6FF"
                style:                    Text.Outline
                styleColor:               "#000000"
            }
        }
    }

    // Bearing / distance chip anchored at midpoint of the operator->vehicle line.
    MapQuickItem {
        id:             gcsBearingChip
        visible:        gcsBearingLine.visible
        coordinate:     visible ? QtPositioning.coordinate(
                                    (_root._gcsPosition.latitude  + _root._activeVehicleCoordinate.latitude)  / 2,
                                    (_root._gcsPosition.longitude + _root._activeVehicleCoordinate.longitude) / 2)
                                : QtPositioning.coordinate()
        anchorPoint.x:  sourceItem.width  / 2
        anchorPoint.y:  sourceItem.height / 2
        z:              QGroundControl.zOrderVehicles

        sourceItem: Rectangle {
            color:          "#CC101418"
            border.color:   "#F59E0B"
            border.width:   1
            radius:         3
            implicitWidth:  chipRow.implicitWidth  + ScreenTools.defaultFontPixelWidth
            implicitHeight: chipRow.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.25)

            Row {
                id:                 chipRow
                anchors.centerIn:   parent
                spacing:            ScreenTools.defaultFontPixelWidth * 0.5

                QGCLabel {
                    text: {
                        if (!gcsBearingLine.visible) return ""
                        var az = _root._gcsPosition.azimuthTo(_root._activeVehicleCoordinate)
                        if (az < 0) az += 360
                        var s = Math.round(az).toString()
                        while (s.length < 3) s = "0" + s
                        return s + "\u00B0"
                    }
                    color:          "#F59E0B"
                    font.bold:      true
                    font.pointSize: ScreenTools.smallFontPointSize
                }
                QGCLabel {
                    text: {
                        if (!gcsBearingLine.visible) return ""
                        var d = _root._gcsPosition.distanceTo(_root._activeVehicleCoordinate)
                        if (d >= 1000) return (d / 1000).toFixed(2) + " km"
                        return Math.round(d) + " m"
                    }
                    color:          "#F1F4F7"
                    font.pointSize: ScreenTools.smallFontPointSize
                }
            }
        }
    }

    // Add the vehicles to the map
    MapItemView {
        model: QGroundControl.multiVehicleManager.vehicles
        delegate: VehicleMapItem {
            vehicle:        object
            coordinate:     object.coordinate
            map:            _root
            size:           pipMode ? ScreenTools.defaultFontPixelHeight : ScreenTools.defaultFontPixelHeight * 3
            z:              QGroundControl.zOrderVehicles
        }
    }
    // Add distance sensor view
    MapItemView{
        model: QGroundControl.multiVehicleManager.vehicles
        delegate: ProximityRadarMapView {
            vehicle:        object
            coordinate:     object.coordinate
            map:            _root
            z:              QGroundControl.zOrderVehicles
        }
    }
    // Add ADSB vehicles to the map
    MapItemView {
        model: QGroundControl.adsbVehicleManager.adsbVehicles
        delegate: VehicleMapItem {
            coordinate:     object.coordinate
            altitude:       object.altitude
            callsign:       object.callsign
            heading:        object.heading
            alert:          object.alert
            map:            _root
            size:           pipMode ? ScreenTools.defaultFontPixelHeight : ScreenTools.defaultFontPixelHeight * 2.5
            z:              QGroundControl.zOrderVehicles
        }
    }

    // Add the items associated with each vehicles flight plan to the map
    Repeater {
        model: QGroundControl.multiVehicleManager.vehicles

        PlanMapItems {
            map:                    _root
            largeMapView:           !pipMode
            planMasterController:   masterController
            vehicle:                _vehicle

            property var _vehicle: object

            PlanMasterController {
                id: masterController
                Component.onCompleted: startStaticActiveVehicle(object)
            }
        }
    }

    // Allow custom builds to add map items
    CustomMapItems {
        map:            _root
        largeMapView:   !pipMode
    }

    GeoFenceMapVisuals {
        id:                     geoFenceMapVisuals
        map:                    _root
        myGeoFenceController:   _geoFenceController
        // STRATUM: editable only while defining the AOP.
        interactive:            _root._aopEditMode
        planView:               false
        homePosition:           _activeVehicle && _activeVehicle.homePosition.isValid ? _activeVehicle.homePosition :  QtPositioning.coordinate()
    }

    // STRATUM: AOP highlight. GeoFenceMapVisuals draws the inclusion polygon
    // border but leaves its interior transparent. We add a translucent fill so
    // the defined area-of-operations reads as a highlighted zone. Bound to the
    // live polygon path, so it updates while the operator drags vertices.
    MapItemView {
        model: _geoFenceController ? _geoFenceController.polygons : null

        delegate: MapPolygon {
            path:           object.path
            color:          Qt.rgba(0.16, 0.55, 1, 0.18)
            border.width:   0
            z:              QGroundControl.zOrderMapItems - 1
            visible:        object.inclusion
        }
    }

    // Rally points on map
    MapItemView {
        model: _rallyPointController.points

        delegate: MapQuickItem {
            id:             itemIndicator
            anchorPoint.x:  sourceItem.anchorPointX
            anchorPoint.y:  sourceItem.anchorPointY
            coordinate:     object.coordinate
            z:              QGroundControl.zOrderMapItems

            sourceItem: MissionItemIndexLabel {
                id:         itemIndexLabel
                label:      qsTr("R", "rally point map item label")
            }
        }
    }

    // Camera trigger points
    MapItemView {
        model: _activeVehicle ? _activeVehicle.cameraTriggerPoints : 0

        delegate: CameraTriggerIndicator {
            coordinate:     object.coordinate
            z:              QGroundControl.zOrderTopMost
        }
    }

    // GoTo Location forward flight circle visuals
    QGCMapCircleVisuals {
        id:                 fwdFlightGotoMapCircle
        mapControl:         parent
        mapCircle:          _fwdFlightGotoMapCircle
        radiusLabelVisible: true
        visible:            gotoLocationItem.visible && _activeVehicle &&
                            _activeVehicle.inFwdFlight &&
                            !_activeVehicle.orbitActive

        property alias coordinate: _fwdFlightGotoMapCircle.center
        property alias radius: _fwdFlightGotoMapCircle.radius
        property alias clockwiseRotation: _fwdFlightGotoMapCircle.clockwiseRotation

        Component.onCompleted: {
            // Only allow editing the radius, not the position
            centerDragHandleVisible = false

            globals.guidedControllerFlyView.fwdFlightGotoMapCircle = this
        }

        Binding {
            target: _fwdFlightGotoMapCircle
            property: "center"
            value: gotoLocationItem.coordinate
        }

        function startLoiterRadiusEdit() {
            _fwdFlightGotoMapCircle.interactive = true
        }

        // Called when loiter edit is confirmed
        function actionConfirmed() {
            _fwdFlightGotoMapCircle.interactive = false
            _fwdFlightGotoMapCircle._commitRadius()
        }

        // Called when loiter edit is cancelled
        function actionCancelled() {
            _fwdFlightGotoMapCircle.interactive = false
            _fwdFlightGotoMapCircle._restoreRadius()
        }

        QGCMapCircle {
            id:                 _fwdFlightGotoMapCircle
            interactive:        false
            showRotation:       true
            clockwiseRotation:  true

            property real _defaultLoiterRadius: _flyViewSettings.forwardFlightGoToLocationLoiterRad.value
            property real _committedRadius;

            onCenterChanged: {
                radius.rawValue = _defaultLoiterRadius
                // Don't commit the radius in case this operation is undone
            }

            Component.onCompleted: {
                radius.rawValue = _defaultLoiterRadius
                _commitRadius()
            }

            function _commitRadius() {
                _committedRadius = radius.rawValue
            }

            function _restoreRadius() {
                radius.rawValue = _committedRadius
            }
        }
    }

    // GoTo Location visuals
    MapQuickItem {
        id:             gotoLocationItem
        visible:        false
        z:              QGroundControl.zOrderMapItems
        anchorPoint.x:  sourceItem.anchorPointX
        anchorPoint.y:  sourceItem.anchorPointY
        sourceItem: MissionItemIndexLabel {
            checked:    true
            index:      -1
            label:      qsTr("Go here", "Go to location waypoint")
        }

        property bool inGotoFlightMode: _activeVehicle ? _activeVehicle.flightMode === _activeVehicle.gotoFlightMode : false

        property var _committedCoordinate: null

        onInGotoFlightModeChanged: {
            if (!inGotoFlightMode && gotoLocationItem.visible) {
                // Hide goto indicator when vehicle falls out of guided mode
                hide()
            }
        }

        function show(coord) {
            gotoLocationItem.coordinate = coord
            gotoLocationItem.visible = true
        }

        function hide() {
            gotoLocationItem.visible = false
        }

        function actionConfirmed() {
            _commitCoordinate()

            // Commit the new radius which possibly changed
            fwdFlightGotoMapCircle.actionConfirmed()

            // We leave the indicator visible. The handling for onInGuidedModeChanged will hide it.
        }

        function actionCancelled() {
            _restoreCoordinate()

            // Also restore the loiter radius
            fwdFlightGotoMapCircle.actionCancelled()
        }

        function _commitCoordinate() {
            // Must deep copy
            _committedCoordinate = QtPositioning.coordinate(
                coordinate.latitude,
                coordinate.longitude
            );
        }

        function _restoreCoordinate() {
            if (_committedCoordinate) {
                coordinate = _committedCoordinate
            } else {
                hide()
            }
        }
    }

    // Orbit editing visuals
    QGCMapCircleVisuals {
        id:             orbitMapCircle
        mapControl:     parent
        mapCircle:      _mapCircle
        visible:        false

        property alias center:              _mapCircle.center
        property alias clockwiseRotation:   _mapCircle.clockwiseRotation
        readonly property real defaultRadius: 30

        Connections {
            target: QGroundControl.multiVehicleManager
            function onActiveVehicleChanged(activeVehicle) {
                if (!activeVehicle) {
                    orbitMapCircle.visible = false
                }
            }
        }

        function show(coord) {
            _mapCircle.radius.rawValue = defaultRadius
            orbitMapCircle.center = coord
            orbitMapCircle.visible = true
        }

        function hide() {
            orbitMapCircle.visible = false
        }

        function actionConfirmed() {
            // Live orbit status is handled by telemetry so we hide here and telemetry will show again.
            hide()
        }

        function actionCancelled() {
            hide()
        }

        function radius() {
            return _mapCircle.radius.rawValue
        }

        Component.onCompleted: globals.guidedControllerFlyView.orbitMapCircle = orbitMapCircle

        QGCMapCircle {
            id:                 _mapCircle
            interactive:        true
            radius.rawValue:    30
            showRotation:       true
            clockwiseRotation:  true
        }
    }

    // ROI Location visuals
    MapQuickItem {
        id:             roiLocationItem
        visible:        _activeVehicle && _activeVehicle.isROIEnabled
        z:              QGroundControl.zOrderMapItems
        anchorPoint.x:  sourceItem.anchorPointX
        anchorPoint.y:  sourceItem.anchorPointY

        Connections {
            target: _activeVehicle
            function onRoiCoordChanged(centerCoord) {
                roiLocationItem.show(centerCoord)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: (position) => {
                position = Qt.point(position.x, position.y)
                var clickCoord = _root.toCoordinate(position, false /* clipToViewPort */)
                // For some strange reason using mainWindow in mapToItem doesn't work, so we use globals.parent instead which also gets us mainWindow
                position = mapToItem(globals.parent, position)
                var dropPanel = roiEditDropPanelComponent.createObject(mainWindow, { clickRect: Qt.rect(position.x, position.y, 0, 0) })
                dropPanel.open()
            }
        }

        sourceItem: MissionItemIndexLabel {
            checked:    true
            index:      -1
            label:      qsTr("ROI here", "Make this a Region Of Interest")
        }

        //-- Visibilty controlled by actual state
        function show(coord) {
            roiLocationItem.coordinate = coord
        }
    }

    // Orbit telemetry visuals
    QGCMapCircleVisuals {
        id:             orbitTelemetryCircle
        mapControl:     parent
        mapCircle:      _activeVehicle ? _activeVehicle.orbitMapCircle : null
        visible:        _activeVehicle ? _activeVehicle.orbitActive : false
    }

    MapQuickItem {
        id:             orbitCenterIndicator
        anchorPoint.x:  sourceItem.anchorPointX
        anchorPoint.y:  sourceItem.anchorPointY
        coordinate:     _activeVehicle ? _activeVehicle.orbitMapCircle.center : QtPositioning.coordinate()
        visible:        orbitTelemetryCircle.visible && !gotoLocationItem.visible

        sourceItem: MissionItemIndexLabel {
            checked:    true
            index:      -1
            label:      qsTr("Orbit", "Orbit waypoint")
        }
    }

    // STRATUM: standoff command controller. Sends the orbit params + activate commands
    // to the bridge (web UI contract) and owns the on-map surveillance circle state.
    StandoffController {
        id:                 standoffController
        guidedController:   globals.guidedControllerFlyView
    }

    // STRATUM: standoff surveillance area. Crimson circle centred on the target,
    // radius = standoff distance, depicting the area under surveillance. Shown
    // whenever a standoff hold / orbit is active.
    MapCircle {
        id:             standoffSurveillanceCircle
        center:         standoffController._targetCoordinate
        radius:         Math.max(standoffController._standoffDistance, 1)
        color:          Qt.rgba(0.82, 0.10, 0.21, 0.15)  // crimson fill, low opacity
        border.color:   "#D11A35"                        // crimson outline
        border.width:   2
        visible:        standoffController._standoffActive
        z:              QGroundControl.zOrderMapItems
    }

    // STRATUM: target markers. A simple "T" in a circle whose CENTRE anchors exactly
    // on the coordinate; the monochrome SVG is tinted per state through QGCColoredImage.
    // BLUE = target being set (panel open, valid coordinate, OK not yet pressed).
    // RED  = standoff engaged; the target position is currently being served.
    // The icon scales with map zoom inside fixed bounds (~1.25x per level, clamped
    // [0.7, 1.9], zoomLevel 16 -> 1.0x) so it neither vanishes nor swamps the view.
    component StandoffTargetMarker : MapQuickItem {
        id:             targetMarkerRoot
        anchorPoint.x:  sourceItem.width  / 2
        anchorPoint.y:  sourceItem.height / 2   // square icon: geometric centre on target
        z:              QGroundControl.zOrderMapItems + 1

        property color markerColor: "#D11A35"
        property string markerLabel: qsTr("Target")

        property real _zoomScale: Math.max(0.7, Math.min(1.9, Math.pow(1.25, _root.zoomLevel - 16)))
        property real _iconSize:  ScreenTools.defaultFontPixelHeight * 2.0 * _zoomScale

        sourceItem: Item {
            width:  targetMarkerIcon.width
            height: targetMarkerIcon.height

            QGCColoredImage {
                id:                 targetMarkerIcon
                source:             "/qmlimages/StandoffMarker.svg"
                color:              targetMarkerRoot.markerColor
                width:              targetMarkerRoot._iconSize
                height:             targetMarkerRoot._iconSize
                sourceSize.width:   targetMarkerRoot._iconSize * 2   // crisp on hi-DPI displays
                fillMode:           Image.PreserveAspectFit
                mipmap:             true
            }

            QGCMapLabel {
                anchors.top:                targetMarkerIcon.bottom
                anchors.topMargin:          ScreenTools.defaultFontPixelHeight * 0.15
                anchors.horizontalCenter:   targetMarkerIcon.horizontalCenter
                map:                        _root
                text:                       targetMarkerRoot.markerLabel
                font.pointSize:             ScreenTools.smallFontPointSize
            }
        }
    }

    // Interim marker: follows the panel's pending coordinate while setting.
    StandoffTargetMarker {
        coordinate:     _root._standoffPendingCoordinate
        visible:        _root._standoffPickMode && _root._standoffPendingCoordinate.isValid
        markerColor:    "#1E88E5"
        markerLabel:    qsTr("Target")
    }

    // Engaged marker: the committed target the standoff is serving.
    StandoffTargetMarker {
        coordinate:     standoffController._targetCoordinate
        visible:        standoffController._standoffActive && standoffController._targetCoordinate.isValid
        markerColor:    "#D11A35"
        markerLabel:    qsTr("Target")
    }

    // STRATUM: XC25 fetched-target marker. Plotted on demand by the "Fetch Target"
    // tool-strip button (QGroundControl.targetFetch). A red reticle centred exactly
    // on the target coordinate; scales gently with map zoom.
    MapQuickItem {
        id:             xc25TargetMarker
        coordinate:     QGroundControl.targetFetch.targetCoordinate
        visible:        QGroundControl.targetFetch.targetValid && QGroundControl.targetFetch.targetCoordinate.isValid
        anchorPoint.x:  sourceItem.width  / 2
        anchorPoint.y:  sourceItem.height / 2
        z:              QGroundControl.zOrderMapItems + 2

        property real _zoomScale: Math.max(0.7, Math.min(1.8, Math.pow(1.25, _root.zoomLevel - 16)))
        property real _size:      ScreenTools.defaultFontPixelHeight * 2.6 * _zoomScale

        sourceItem: Item {
            width:  xc25TargetMarker._size
            height: xc25TargetMarker._size

            Image {
                anchors.fill:       parent
                source:             "/qmlimages/TargetLocation.svg"
                sourceSize.width:   width * 2
                fillMode:           Image.PreserveAspectFit
                mipmap:             true
                smooth:             true
            }

            QGCMapLabel {
                anchors.bottom:             parent.top
                anchors.bottomMargin:       ScreenTools.defaultFontPixelHeight * 0.1
                anchors.horizontalCenter:   parent.horizontalCenter
                map:                        _root
                text:                       qsTr("XC25 Target")
                font.pointSize:             ScreenTools.smallFontPointSize
            }
        }
    }

    QGCPopupDialogFactory {
        id: roiEditPositionDialogFactory

        dialogComponent: roiEditPositionDialogComponent
    }

    Component {
        id: roiEditPositionDialogComponent

        EditPositionDialog {
            title:                  qsTr("Edit ROI Position")
            coordinate:             roiLocationItem.coordinate
            onCoordinateChanged: {
                roiLocationItem.coordinate = coordinate
                _activeVehicle.guidedModeROI(coordinate)
            }
        }
    }

    Component {
        id: roiEditDropPanelComponent

        DropPanel {
            id: roiEditDropPanel

            sourceComponent: Component {
                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelWidth / 2

                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Cancel ROI")
                        onClicked: {
                            _activeVehicle.stopGuidedModeROI()
                            roiEditDropPanel.close()
                        }
                    }

                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Edit Position")
                        onClicked: {
                            roiEditPositionDialogFactory.open()
                            roiEditDropPanel.close()
                        }
                    }
                }
            }
        }
    }

    Component {
        id: mapClickDropPanelComponent

        DropPanel {
            id: mapClickDropPanel

            property var mapClickCoord

            sourceComponent: Component {
                ColumnLayout {
                    spacing: ScreenTools.defaultFontPixelWidth / 2

                    // STRATUM: the legacy guided map actions (Go to location, Orbit at
                    // location, ROI at location) are retired. The Standoff command now
                    // lives on the left tool strip ("Set Standoff" -> entry panel with
                    // manual lat/lon or crosshair map pick); this menu keeps only the
                    // remaining point-anchored utilities.
                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Set home here")
                        visible:            globals.guidedControllerFlyView.showSetHome
                        onClicked: {
                            mapClickDropPanel.close()
                            globals.guidedControllerFlyView.confirmAction(globals.guidedControllerFlyView.actionSetHome, mapClickCoord)
                        }
                    }

                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Set Estimator Origin")
                        visible:            globals.guidedControllerFlyView.showSetEstimatorOrigin
                        onClicked: {
                            mapClickDropPanel.close()
                            globals.guidedControllerFlyView.confirmAction(globals.guidedControllerFlyView.actionSetEstimatorOrigin, mapClickCoord)
                        }
                    }

                    // STRATUM: opens the Set Standoff panel pre-filled with the clicked
                    // coordinate. Same entry surface as the ribbon's "Set Standoff" button.
                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Set standoff here")
                        onClicked: {
                            mapClickDropPanel.close()
                            _root.setStandoffHereRequested(mapClickCoord)
                        }
                    }

                    QGCButton {
                        Layout.fillWidth:   true
                        text:               qsTr("Set Heading")
                        visible:            globals.guidedControllerFlyView.showChangeHeading
                        onClicked: {
                            mapClickDropPanel.close()
                            globals.guidedControllerFlyView.confirmAction(globals.guidedControllerFlyView.actionChangeHeading, mapClickCoord)
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        QGCLabel { text: qsTr("Lat: %1").arg(mapClickCoord.latitude.toFixed(6)) }
                        QGCLabel { text: qsTr("Lon: %1").arg(mapClickCoord.longitude.toFixed(6)) }
                    }
                }
            }
        }
    }

    onMapClicked: (position) => {
        // STRATUM: standoff pick mode wins the click. Report the coordinate to the
        // Set Standoff panel and suppress the guided-action menu entirely.
        if (_root._standoffPickMode) {
            _root.standoffTargetPicked(_root.toCoordinate(Qt.point(position.x, position.y), false /* clipToViewPort */))
            return
        }
        // STRATUM: while defining the AOP, map clicks belong to the polygon
        // editor (vertex add/drag); suppress the guided-action drop panel.
        if (_root._aopEditMode) {
            return
        }
        if (!globals.guidedControllerFlyView.guidedUIVisible &&
            (globals.guidedControllerFlyView.showGotoLocation || globals.guidedControllerFlyView.showOrbit ||
             globals.guidedControllerFlyView.showROI || globals.guidedControllerFlyView.showSetHome ||
             globals.guidedControllerFlyView.showSetEstimatorOrigin || _activeVehicle)) {

            position = Qt.point(position.x, position.y)
            var clickCoord = _root.toCoordinate(position, false /* clipToViewPort */)
            // For some strange reason using mainWindow in mapToItem doesn't work, so we use globals.parent instead which also gets us mainWindow
            position = _root.mapToItem(globals.parent, position)
            var dropPanel = mapClickDropPanelComponent.createObject(mainWindow, { mapClickCoord: clickCoord, clickRect: Qt.rect(position.x, position.y, 0, 0) })
            dropPanel.open()
        }
    }

    // STRATUM: crosshair cursor while the Set Standoff panel is picking a target.
    // acceptedButtons: NoButton keeps the area event-transparent, so clicks still
    // reach the map's own click handling; the area exists purely for the cursor.
    MouseArea {
        anchors.fill:    parent
        visible:         _root._standoffPickMode
        acceptedButtons: Qt.NoButton
        cursorShape:     Qt.CrossCursor
        z:               QGroundControl.zOrderTopMost
    }

    MapScale {
        id:                 mapScale
        anchors.margins:    _toolsMargin
        anchors.left:       parent.left
        anchors.top:        parent.top
        mapControl:         _root
        visible:            !ScreenTools.isTinyScreen && QGroundControl.corePlugin.options.flyView.showMapScale && mapControl.pipState.state === mapControl.pipState.windowState
    }

    // STRATUM: The AOP edit toolbar lives in FlyViewWidgetLayer.qml (vehicle-aware
    // "Apply changes" / "Cancel" bar). It was previously duplicated here as a second
    // top-center bar bound to the same _aopEditMode, producing two overlapping bars.
}
