import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM camera / gimbal control cluster. Self-contained: every button drives
// QGroundControl.videoManager.sendCameraAction() directly (the YunZhuo/Skydroid
// TOP protocol over UDP), mirroring the UAV-VAS web UI camera panel:
//   * TV / IR feed select
//   * Pan / Tilt cross (arrow glyphs, hold-to-move -> stop on release)
//   * Zoom - / +
//   * Capture / Record (toggle) / Track (toggle)
//   * False-colour palette
//
// Reused in two places (FlyViewDropperPanel camera section, and the maximized
// video overlay in FlyView) so the controls follow the camera when it is the
// maximized window and fold back into the dropper when the map is maximized.
Item {
    id: root

    // overlayMode: translucent card drawn over the live video (maximized camera).
    // Otherwise it renders flush for embedding inside the dropper panel.
    property bool overlayMode: false
    // compact: tighter spacing / fonts for the picture-in-picture / panel context.
    property bool compact: false
    // daggerMode: when true (Dagger airframe with C12), TV/IR toggle drives the
    // daggerC12TvRtspUrl / daggerC12IrRtspUrl settings instead of tvRtspUrl / irRtspUrl.
    property bool daggerMode: false

    // Emitted after every command so the host (dropper panel / overlay) can show feedback.
    signal statusMessage(string text)

    readonly property var _vs: QGroundControl.settingsManager.videoSettings
    readonly property bool _c12Active: _vs && _vs.daggerCamera.rawValue === 1
    // Profile-scoped URL pair. Kept as readonly properties so QML change-tracking follows
    // the daggerMode flag automatically.
    readonly property string _tvUrl: daggerMode ? _vs.daggerC12TvRtspUrl.rawValue : _vs.tvRtspUrl.rawValue
    readonly property string _irUrl: daggerMode ? _vs.daggerC12IrRtspUrl.rawValue : _vs.irRtspUrl.rawValue
    // Active feed is derived from which stored URL the live rtspUrl currently matches,
    // so the dropper panel and the video overlay always show the same TV/IR state.
    readonly property bool _feedIrActive: _irUrl !== "" && _vs.rtspUrl.rawValue === _irUrl
    // STRATUM: derive REC/Track state directly from VideoManager so the button
    // labels stay in sync whether recording/tracking was toggled from this
    // control or somewhere else (e.g. tracking started by a video click).
    readonly property bool _recActive:   QGroundControl.videoManager.recording
    readonly property bool _trackActive: QGroundControl.videoManager.c12TrackingActive

    // Local recording bookkeeping — the filename VideoManager gave us on the
    // most recent recordingStarted signal. Used to move the completed file to
    // wherever the operator picks in the save dialog.
    property string _pendingRecordFile: ""
    property bool _saveDialogOpen: false
    property bool _absoluteAnglesExpanded: false
    property double _nowMs: Date.now()

    readonly property var _vehicleFacts: QGroundControl.multiVehicleManager.activeVehicle
                                         ? QGroundControl.multiVehicleManager.activeVehicle.vehicle : null

    readonly property var _admin: QGroundControl.settingsManager.adminSettings
    readonly property int _c12MaxSpeed: {
        if (!_admin) return 100
        var raw = Number(_admin.c12GimbalMaxSpeed.rawValue)
        if (!isFinite(raw)) return 100
        return Math.max(1, Math.min(127, Math.round(raw)))
    }

    readonly property color _accent:    "#3DFFA6"
    readonly property color _accentDim:  "#1FB97D"
    readonly property real  _btnHeight:  ScreenTools.defaultFontPixelHeight * (compact ? 1.9 : 2.3)
    readonly property real  _iconSize:   Math.round(_btnHeight * 0.45)
    readonly property real  _spacing:    ScreenTools.defaultFontPixelWidth * 0.7
    // Inner padding — only in overlay mode (the bordered card over the video).
    readonly property real  _pad:        overlayMode ? ScreenTools.defaultFontPixelWidth * 0.75 : 0

    // Include the padding so the content is never compressed / clipped by the border.
    implicitWidth:  contentColumn.implicitWidth + (_pad * 2)
    implicitHeight: contentColumn.implicitHeight + (_pad * 2)

    function _send(cameraAction) {
        const sent = QGroundControl.videoManager.sendCameraAction(cameraAction)
        if (!sent) {
            root.statusMessage(qsTr("Camera command failed"))
        }
        return sent
    }

    function _selectFeed(feed) {
        const url = (feed === "IR") ? _irUrl : _tvUrl
        if (!url) {
            root.statusMessage(qsTr("No %1 URL set — configure it in Application Settings ▸ Video").arg(feed))
            return
        }
        if (_vs.rtspUrl.rawValue !== url) {
            const vehicle = QGroundControl.multiVehicleManager.activeVehicle
            if (vehicle) {
                vehicle.sendTargetSelect(0, 0, 0, 0, 0)
                if (vehicle.targetTrack) {
                    vehicle.targetTrack.clear()
                }
            }
            if (root._c12Active) {
                QGroundControl.videoManager.stopC12Track()
            }
        }
        // Ensure the RTSP source is active, then point it at the chosen feed. Writing
        // rtspUrl restarts the stream (VideoManager listens on its rawValueChanged), so
        // the video swaps between the TV and IR URLs — matching the web UI TV/IR buttons.
        if (_vs.videoSource.rawValue !== _vs.rtspVideoSource) {
            _vs.videoSource.rawValue = _vs.rtspVideoSource
        }
        _vs.rtspUrl.rawValue = url
        root.statusMessage(qsTr("%1 feed selected").arg(feed))
    }

    // STRATUM: record the RTSP stream locally via VideoManager instead of asking
    // the C12 to record to its SD card. On stop we open a save-as dialog and move
    // the temp file to the operator-chosen path.
    function _toggleRec() {
        if (QGroundControl.videoManager.recording) {
            QGroundControl.videoManager.stopRecording()
            root.statusMessage(qsTr("■ Recording stopped — pick a save location"))
        } else {
            _pendingRecordFile = ""
            QGroundControl.videoManager.startRecording()
            root.statusMessage(qsTr("● Recording started (local)"))
        }
    }

    function _toggleTrack() {
        if (QGroundControl.videoManager.c12TrackingActive) {
            if (!QGroundControl.videoManager.sendCameraAction("track-stop")) {
                root.statusMessage(qsTr("Tracking stop failed"))
                return
            }
            root.statusMessage(qsTr("✕ Tracking off"))
        } else {
            if (!QGroundControl.videoManager.sendCameraAction("track-center")) {
                root.statusMessage(qsTr("Tracking start failed"))
                return
            }
            root.statusMessage(qsTr("◎ Tracker locked on centre region"))
        }
    }

    function _fmtAngle(v) {
        return isFinite(v) ? Number(v).toFixed(1) : "--"
    }

    function _factAngle(fact) {
        return fact ? _fmtAngle(Number(fact.rawValue)) : "--"
    }

    function _gimbalStatusText() {
        const ts = Number(QGroundControl.videoManager.c12AttitudeTimestampMs)
        if (!isFinite(ts) || ts <= 0) {
            return qsTr("Gimbal: waiting for attitude stream")
        }
        const ageMs = Math.max(0, root._nowMs - ts)
        return ageMs < 1500 ? qsTr("Gimbal: live")
                            : qsTr("Gimbal: stale (%1 s)").arg((ageMs / 1000).toFixed(1))
    }

    // Single click: absolute gimbal pitch to -90° (straight down), yaw unchanged.
    function _lookDown() {
        const sent = QGroundControl.videoManager.setC12GimbalPitch(-90, root._c12MaxSpeed)
        root.statusMessage(sent ? qsTr("Gimbal pitch set to −90°") : qsTr("Look down command failed"))
    }

    // Remember the temp file VideoManager wrote so we can move it on stop.
    Connections {
        target: QGroundControl.videoManager
        function onRecordingStarted(filename) { root._pendingRecordFile = filename }
        function onRecordingChanged(active) {
            if (!active && root._pendingRecordFile !== "" && !root._saveDialogOpen) {
                root._saveDialogOpen = true
                saveRecordingDialog.currentFile = "file:///" + root._pendingRecordFile
                saveRecordingDialog.selectedFile = "file:///" + root._pendingRecordFile
                saveRecordingDialog.open()
            }
        }
    }

    FileDialog {
        id: saveRecordingDialog
        title: qsTr("Save recording as…")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Video files (*.mkv *.mp4)", "All files (*)"]
        onAccepted: {
            var ok = QGroundControl.videoManager.moveRecordedFile(
                "file:///" + root._pendingRecordFile, saveRecordingDialog.selectedFile)
            root.statusMessage(ok ? qsTr("💾 Saved") : qsTr("Save failed — recording kept at temp path"))
            root._saveDialogOpen = false
            root._pendingRecordFile = ""
        }
        onRejected: {
            root.statusMessage(qsTr("Recording kept at: %1").arg(root._pendingRecordFile))
            root._saveDialogOpen = false
            root._pendingRecordFile = ""
        }
    }

    QGCPalette { id: btnPal; colorGroupEnabled: true }

    // Icon (or short text) button with the content centred and a hover tooltip.
    component IconButton : Button {
        id: iconBtn
        property string tip: ""
        property string iconSource: ""
        property bool primary: false
        readonly property bool _highlight: enabled && (pressed || checked)
        readonly property color _fg: _highlight ? btnPal.buttonHighlightText
                                                : (primary ? btnPal.primaryButtonText : btnPal.buttonText)
        hoverEnabled: !ScreenTools.isMobile
        focusPolicy: Qt.ClickFocus
        padding: 0
        implicitHeight: root._btnHeight
        implicitWidth: root._btnHeight
        Layout.fillWidth: true
        Layout.preferredHeight: root._btnHeight
        ToolTip.visible: hovered && tip !== ""
        ToolTip.text: tip
        ToolTip.delay: 400

        background: Rectangle {
            radius: ScreenTools.defaultBorderRadius
            border.width: 1
            border.color: btnPal.buttonBorder
            color: iconBtn.primary ? btnPal.primaryButton : btnPal.button
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: btnPal.buttonHighlight
                opacity: iconBtn._highlight ? 1 : (iconBtn.enabled && iconBtn.hovered ? 0.4 : 0)
            }
        }

        contentItem: Item {
            QGCColoredImage {
                anchors.centerIn: parent
                visible: iconBtn.iconSource !== ""
                source: iconBtn.iconSource
                width: root._iconSize
                height: root._iconSize
                sourceSize.height: root._iconSize
                fillMode: Image.PreserveAspectFit
                color: iconBtn._fg
            }
            QGCLabel {
                anchors.centerIn: parent
                visible: iconBtn.iconSource === "" && iconBtn.text !== ""
                text: iconBtn.text
                color: iconBtn._fg
            }
        }
    }

    component SectionLabel : QGCLabel {
        color: root._accentDim
        font.pointSize: ScreenTools.smallFontPointSize
        font.bold: true
    }

    // Non-modal, draggable floating panel shown above the fly view so it does not
    // push the camera controls around. Body is loaded only while open.
    component FloatingPanel : Popup {
        id: panel
        property string title: ""
        property Component body: null
        property bool _placed: false
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape
        padding: ScreenTools.defaultFontPixelWidth
        // Keeps the panel inside the window even when dragged or initially placed off-edge.
        margins: ScreenTools.defaultFontPixelWidth
        // Popups render in the window overlay layer; x/y are relative to the
        // controls card. First open places the panel to the left of the card.
        onOpened: {
            if (!_placed) {
                x = -(implicitWidth + ScreenTools.defaultFontPixelWidth * 2)
                y = 0
                _placed = true
            }
        }
        background: Rectangle {
            color: Qt.rgba(0.05, 0.06, 0.07, 0.94)
            radius: ScreenTools.defaultBorderRadius
            border.color: root._accent
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: ScreenTools.defaultFontPixelHeight / 3

            Item {
                Layout.fillWidth: true
                implicitWidth: panelHeaderRow.implicitWidth
                implicitHeight: panelHeaderRow.implicitHeight

                MouseArea {
                    property point pressPos: Qt.point(0, 0)
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: (mouse) => { pressPos = Qt.point(mouse.x, mouse.y) }
                    onPositionChanged: (mouse) => {
                        panel.x += mouse.x - pressPos.x
                        panel.y += mouse.y - pressPos.y
                    }
                }

                RowLayout {
                    id: panelHeaderRow
                    anchors.fill: parent
                    QGCLabel {
                        Layout.fillWidth: true
                        text: panel.title
                        font.bold: true
                        color: root._accent
                    }
                    IconButton {
                        Layout.fillWidth: false
                        Layout.preferredWidth: root._btnHeight * 0.8
                        Layout.preferredHeight: root._btnHeight * 0.8
                        iconSource: "/InstrumentValueIcons/close.svg"
                        tip: qsTr("Close")
                        onClicked: panel.close()
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: panel.visible
                sourceComponent: panel.body
            }
        }
    }

    // Hold-to-move gimbal button: repeats the pan/tilt command while held, sends
    // "stop" on release (matches web UI camStart / camStop, 200 ms interval).
    component PtzButton : IconButton {
        id: ptzButton
        property string ptzAction
        onPressedChanged: {
            if (pressed) {
                root._send(ptzAction)
                ptzHoldTimer.restart()
            } else {
                ptzHoldTimer.stop()
                root._send("stop")
            }
        }
        Timer {
            id: ptzHoldTimer
            interval: 200
            repeat: true
            onTriggered: root._send(ptzButton.ptzAction)
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: anglesPanel.visible
        onTriggered: root._nowMs = Date.now()
    }

    FloatingPanel {
        id: anglesPanel
        title: qsTr("Gimbal / UAV angles")
        body: Component {
            GridLayout {
                columns: 4
                columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                rowSpacing: ScreenTools.defaultFontPixelHeight / 4

                QGCLabel { text: "" }
                QGCLabel { text: qsTr("Yaw°"); font.bold: true }
                QGCLabel { text: qsTr("Pitch°"); font.bold: true }
                QGCLabel { text: qsTr("Roll°"); font.bold: true }

                QGCLabel { text: qsTr("Gimbal"); color: root._accent }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._fmtAngle(QGroundControl.videoManager.c12YawDegrees) }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._fmtAngle(QGroundControl.videoManager.c12PitchDegrees) }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._fmtAngle(QGroundControl.videoManager.c12RollDegrees) }

                QGCLabel { text: qsTr("UAV"); color: root._accent }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._factAngle(root._vehicleFacts ? root._vehicleFacts.heading : null) }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._factAngle(root._vehicleFacts ? root._vehicleFacts.pitch : null) }
                QGCLabel { font.family: ScreenTools.fixedFontFamily; text: root._factAngle(root._vehicleFacts ? root._vehicleFacts.roll : null) }

                QGCLabel {
                    Layout.columnSpan: 4
                    color: root._accentDim
                    font.pointSize: ScreenTools.smallFontPointSize
                    text: root._gimbalStatusText() + "   " + (root._vehicleFacts ? qsTr("UAV yaw = heading (0–360°)") : qsTr("UAV: no vehicle"))
                }
            }
        }
    }

    FloatingPanel {
        id: targetGpsPanel
        title: qsTr("Target GPS estimate")
        body: Component {
            TargetGpsEstimate {
                implicitWidth: ScreenTools.defaultFontPixelWidth * 55
                vehicle: QGroundControl.multiVehicleManager.activeVehicle
                tracker: vehicle ? vehicle.targetTrack : null
                gimbalYawDegrees: QGroundControl.videoManager.c12YawDegrees
                gimbalPitchDegrees: QGroundControl.videoManager.c12PitchDegrees
                gimbalTimestampMs: QGroundControl.videoManager.c12AttitudeTimestampMs
                selectedCameraSource: tracker ? tracker.selectionVideoSource : -1
                activeCameraSource: root._feedIrActive ? 1 : 0
                selectionTimestampMs: tracker ? tracker.selectionTimestampMs : 0
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.overlayMode
        color: Qt.rgba(0, 0, 0, 0.72)
        radius: ScreenTools.defaultBorderRadius
        border.color: root._accent
        border.width: 1
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._spacing

        // ---- Camera feed select: TV / IR -----------------------------------
        SectionLabel { text: qsTr("CAMERA") }

        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            IconButton {
                text: qsTr("TV")
                tip: qsTr("Daylight (TV) video feed")
                primary: !root._feedIrActive
                onClicked: root._selectFeed("TV")
            }
            IconButton {
                text: qsTr("IR")
                tip: qsTr("Thermal (IR) video feed")
                primary: root._feedIrActive
                onClicked: root._selectFeed("IR")
            }
        }

        // ---- Gimbal: pan / tilt cross (hold-to-move) -----------------------
        SectionLabel { text: qsTr("GIMBAL") }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: root._spacing
            rowSpacing: root._spacing

            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
            PtzButton { iconSource: "/InstrumentValueIcons/arrow-thick-up.svg"; tip: qsTr("Gimbal up (hold)"); ptzAction: "pan-up" }
            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }

            PtzButton { iconSource: "/InstrumentValueIcons/arrow-thick-left.svg"; tip: qsTr("Gimbal left (hold)"); ptzAction: "tilt-left" }
            IconButton {
                iconSource: "/InstrumentValueIcons/home.svg"
                tip: qsTr("Centre gimbal (return to home position)")
                onClicked: { if (root._send("center")) root.statusMessage(qsTr("Gimbal centred")) }
            }
            PtzButton { iconSource: "/InstrumentValueIcons/arrow-thick-right.svg"; tip: qsTr("Gimbal right (hold)"); ptzAction: "tilt-right" }

            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
            PtzButton { iconSource: "/InstrumentValueIcons/arrow-thick-down.svg"; tip: qsTr("Gimbal down (hold)"); ptzAction: "pan-down" }
            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
        }

        // ---- Zoom: out / in, then presets ----------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            IconButton {
                iconSource: "/InstrumentValueIcons/zoom-out.svg"
                tip: qsTr("Zoom out")
                onClicked: { if (root._send("zoom-out")) root.statusMessage(qsTr("Zoom out")) }
            }
            IconButton {
                iconSource: "/InstrumentValueIcons/zoom-in.svg"
                tip: qsTr("Zoom in")
                onClicked: { if (root._send("zoom-in")) root.statusMessage(qsTr("Zoom in")) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            Repeater {
                model: [1, 2, 3, 4]
                IconButton {
                    required property int modelData
                    text: qsTr("%1x").arg(modelData)
                    tip: qsTr("Zoom preset %1x").arg(modelData)
                    onClicked: {
                        const sent = QGroundControl.videoManager.setC12ZoomPreset(modelData)
                        root.statusMessage(sent ? qsTr("Zoom preset %1x").arg(modelData) : qsTr("Zoom preset command failed"))
                    }
                }
            }
        }

        QGCLabel {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root._accentDim
            font.pointSize: ScreenTools.smallFontPointSize
            text: qsTr("Yaw %1°   Pitch %2°   Roll %3°")
                    .arg(root._fmtAngle(QGroundControl.videoManager.c12YawDegrees))
                    .arg(root._fmtAngle(QGroundControl.videoManager.c12PitchDegrees))
                    .arg(root._fmtAngle(QGroundControl.videoManager.c12RollDegrees))
        }

        // ---- Tracking / media ----------------------------------------------
        SectionLabel { text: qsTr("TRACKING") }

        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            IconButton {
                iconSource: root._trackActive ? "/InstrumentValueIcons/close-outline.svg" : "/InstrumentValueIcons/target.svg"
                tip: root._trackActive ? qsTr("Stop tracking") : qsTr("Track target at frame centre")
                primary: root._trackActive
                onClicked: root._toggleTrack()
            }
            IconButton {
                iconSource: "/InstrumentValueIcons/arrow-base-down.svg"
                tip: qsTr("Look down — set gimbal pitch to −90°")
                onClicked: root._lookDown()
            }
            IconButton {
                iconSource: "/InstrumentValueIcons/camera.svg"
                tip: qsTr("Capture photo (saved locally)")
                onClicked: {
                    QGroundControl.videoManager.grabImage()
                    root.statusMessage(qsTr("📷 Photo saved locally"))
                }
            }
            IconButton {
                iconSource: root._recActive ? "/InstrumentValueIcons/pause-solid.svg" : "/InstrumentValueIcons/video-camera.svg"
                tip: root._recActive ? qsTr("Stop recording and save") : qsTr("Start local video recording")
                primary: root._recActive
                onClicked: root._toggleRec()
            }
        }

        // ---- Tools: angles panel / target GPS / absolute angles ------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            IconButton {
                iconSource: "/InstrumentValueIcons/dashboard.svg"
                tip: qsTr("Show gimbal and UAV yaw / pitch / roll panel")
                primary: anglesPanel.visible
                onClicked: anglesPanel.visible ? anglesPanel.close() : anglesPanel.open()
            }
            IconButton {
                visible: root._c12Active
                iconSource: "/InstrumentValueIcons/location.svg"
                tip: qsTr("Target GPS estimate")
                primary: targetGpsPanel.visible
                onClicked: targetGpsPanel.visible ? targetGpsPanel.close() : targetGpsPanel.open()
            }
            IconButton {
                visible: root._c12Active && !root.compact
                iconSource: "/InstrumentValueIcons/tuning.svg"
                tip: qsTr("Set absolute gimbal yaw / pitch")
                primary: root._absoluteAnglesExpanded
                onClicked: root._absoluteAnglesExpanded = !root._absoluteAnglesExpanded
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            visible: root._c12Active && !root.compact && root._absoluteAnglesExpanded
            QGCLabel { text: qsTr("Yaw °") }
            QGCTextField {
                id: absoluteYawField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                text: "0"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            QGCLabel { text: qsTr("−90 to +90") }
            QGCLabel { text: qsTr("Pitch °") }
            QGCTextField {
                id: absolutePitchField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                text: "-45"
                inputMethodHints: Qt.ImhFormattedNumbersOnly
            }
            QGCButton {
                text: qsTr("Go")
                onClicked: {
                    var yaw = Number(absoluteYawField.text)
                    var pitch = Number(absolutePitchField.text)
                    if (!isFinite(yaw) || !isFinite(pitch) || yaw < -90 || yaw > 90 || pitch < -90 || pitch > 90) {
                        root.statusMessage(qsTr("Yaw and pitch must be between −90° and +90°"))
                        return
                    }
                    var sent = QGroundControl.videoManager.setC12GimbalAngles(yaw, pitch, root._c12MaxSpeed)
                    root.statusMessage(sent ? qsTr("Absolute gimbal angles sent") : qsTr("Gimbal angle command failed"))
                }
            }
        }

        // ---- AI ------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            Switch {
                text: qsTr("AI")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Enable / disable on-camera AI detection")
                ToolTip.delay: 400
                checked: QGroundControl.videoManager.c12AiEnabled
                onClicked: {
                    var enabled = !QGroundControl.videoManager.c12AiEnabled
                    var sent = QGroundControl.videoManager.setC12AiEnabled(enabled)
                    checked = Qt.binding(function() { return QGroundControl.videoManager.c12AiEnabled })
                    root.statusMessage(sent
                        ? (enabled ? qsTr("AI enable command sent") : qsTr("AI disable command sent"))
                        : qsTr("AI command failed"))
                }
            }

            IconButton {
                iconSource: "/InstrumentValueIcons/block.svg"
                tip: qsTr("Force AI off (resend disable command)")
                onClicked: {
                    var sent = QGroundControl.videoManager.setC12AiEnabled(false)
                    root.statusMessage(sent ? qsTr("AI disable command sent") : qsTr("AI command failed"))
                }
            }
        }

        // ---- False-colour palette -----------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCColoredImage {
                source: "/InstrumentValueIcons/color-palette.svg"
                color: root._accentDim
                Layout.preferredHeight: root._iconSize
                Layout.preferredWidth: root._iconSize
                sourceSize.height: root._iconSize
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: paletteIconHover }
                ToolTip.visible: paletteIconHover.hovered
                ToolTip.text: qsTr("Thermal false-colour palette")
                ToolTip.delay: 400
            }
            QGCComboBox {
                id: paletteCombo
                Layout.fillWidth: true
                textRole: "text"
                model: ListModel {
                    ListElement { text: qsTr("Normal");        code: "palette-off" }
                    ListElement { text: qsTr("White Hot");     code: "palette-01" }
                    ListElement { text: qsTr("Black Hot");     code: "palette-0b" }
                    ListElement { text: qsTr("Red Hot");       code: "palette-08" }
                    ListElement { text: qsTr("Iron Red");      code: "palette-04" }
                    ListElement { text: qsTr("Rainbow");       code: "palette-05" }
                    ListElement { text: qsTr("Glimmer Night"); code: "palette-06" }
                    ListElement { text: qsTr("Aurora");        code: "palette-07" }
                    ListElement { text: qsTr("Sepia");         code: "palette-03" }
                    ListElement { text: qsTr("Jungle");        code: "palette-09" }
                    ListElement { text: qsTr("Medical");       code: "palette-0a" }
                    ListElement { text: qsTr("Glory Hot");     code: "palette-0c" }
                }
                onActivated: (index) => {
                    const code = model.get(index).code
                    if (root._send(code)) {
                        root.statusMessage(qsTr("Palette: %1").arg(model.get(index).text))
                    }
                }
            }
        }
    }
}
