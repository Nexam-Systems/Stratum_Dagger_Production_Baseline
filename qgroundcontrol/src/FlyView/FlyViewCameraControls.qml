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

    readonly property color _accent:    "#3DFFA6"
    readonly property color _accentDim:  "#1FB97D"
    readonly property real  _btnHeight:  ScreenTools.defaultFontPixelHeight * (compact ? 1.9 : 2.3)
    readonly property real  _spacing:    ScreenTools.defaultFontPixelWidth * 0.4
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

    // Remember the temp file VideoManager wrote so we can move it on stop.
    Connections {
        target: QGroundControl.videoManager
        function onRecordingStarted(filename) { root._pendingRecordFile = filename }
        function onRecordingChanged(active) {
            if (!active && root._pendingRecordFile !== "") {
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
            root._pendingRecordFile = ""
        }
        onRejected: {
            root.statusMessage(qsTr("Recording kept at: %1").arg(root._pendingRecordFile))
            root._pendingRecordFile = ""
        }
    }

    // Hold-to-move gimbal button: repeats the pan/tilt command while held, sends
    // "stop" on release (matches web UI camStart / camStop, 200 ms interval).
    component PtzButton : QGCButton {
        id: ptzButton
        property string ptzAction
        implicitHeight: root._btnHeight
        Layout.fillWidth: true
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

        // ---- Feed select: TV / IR ------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCButton {
                text: qsTr("TV")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                backRadius: ScreenTools.defaultBorderRadius
                showBorder: true
                primary: !root._feedIrActive
                onClicked: root._selectFeed("TV")
            }
            QGCButton {
                text: qsTr("IR")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                backRadius: ScreenTools.defaultBorderRadius
                showBorder: true
                primary: root._feedIrActive
                onClicked: root._selectFeed("IR")
            }
        }

        // ---- Pan / Tilt cross (arrow glyphs, hold-to-move) -----------------
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: root._spacing
            rowSpacing: root._spacing

            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
            PtzButton { text: qsTr("▲"); ptzAction: "pan-up" }
            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }

            PtzButton { text: qsTr("◄"); ptzAction: "tilt-left" }
            QGCButton {
                text: qsTr("⊙")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("center")) root.statusMessage(qsTr("Gimbal centred")) }
            }
            PtzButton { text: qsTr("►"); ptzAction: "tilt-right" }

            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
            PtzButton { text: qsTr("▼"); ptzAction: "pan-down" }
            Item { Layout.fillWidth: true; Layout.preferredHeight: root._btnHeight }
        }

        // ---- Zoom ----------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCLabel {
                text: qsTr("ZOOM")
                color: root._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                Layout.alignment: Qt.AlignVCenter
            }
            QGCButton {
                text: qsTr("−")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("zoom-out")) root.statusMessage(qsTr("Zoom out")) }
            }
            QGCButton {
                text: qsTr("+")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: { if (root._send("zoom-in")) root.statusMessage(qsTr("Zoom in")) }
            }
        }

        // ---- Media: Capture / Record --------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCButton {
                text: qsTr("📷 Capture")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                onClicked: {
                    QGroundControl.videoManager.grabImage()
                    root.statusMessage(qsTr("📷 Photo saved locally"))
                }
            }
            QGCButton {
                text: root._recActive ? qsTr("■ Stop") : qsTr("● Rec")
                implicitHeight: root._btnHeight
                Layout.fillWidth: true
                primary: root._recActive
                onClicked: root._toggleRec()
            }
        }

        // ---- Track ---------------------------------------------------------
        QGCButton {
            text: root._trackActive ? qsTr("✕ Stop Tracking") : qsTr("◎ Track")
            implicitHeight: root._btnHeight
            Layout.fillWidth: true
            primary: root._trackActive
            onClicked: root._toggleTrack()
        }

        // ---- False-colour palette -----------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: root._spacing

            QGCLabel {
                text: qsTr("PALETTE")
                color: root._accentDim
                font.pointSize: ScreenTools.smallFontPointSize
                Layout.alignment: Qt.AlignVCenter
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
