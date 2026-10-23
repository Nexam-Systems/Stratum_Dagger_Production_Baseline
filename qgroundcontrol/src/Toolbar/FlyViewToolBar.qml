import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

Item {
    required property var guidedValueSlider

    id:     control
    width:  parent.width
    height: ScreenTools.toolbarHeight
    property var pendingTarget: null
    property var designatedTarget: null
    property var standoffController: null

    // STRATUM: the standoff / AOP entry commands now live in the centre of this ribbon
    // (moved off the left command strip). The handlers are wired in FlyView.qml, which
    // owns the widget layer that hosts the standoff panel and the AOP map editor.
    signal defineAOP()
    signal setStandoff()

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property bool   _communicationLost: _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property real   _leftRightMargin:   ScreenTools.defaultFontPixelWidth * 0.75
    property var    _guidedController:  globals.guidedControllerFlyView

    // STRATUM: the fly-view ribbon stays a single neutral chrome band so operators are
    // not conditioned to a rotating rainbow of state colours. Only the Engagement flight
    // mode -- the safety-critical live-fire state -- turns the ribbon solid red. Every
    // other state (Standoff, Takeoff, Hold, Manual, Abort, disconnected, ...) keeps the
    // same dark graphite background; individual telemetry chips (RSSI, comms, battery)
    // still colour themselves for warning/critical thresholds.
    readonly property string _engagementModeName: qsTr("Engagement")
    property color _ribbonColor: {
        if (_activeVehicle && _activeVehicle.flightMode === _engagementModeName) {
            return "#DC2626"                    // engagement (live-fire safety colour)
        }
        return qgcPal.window
    }
    // STRATUM: light-on-dark ribbon text. Red engagement bg still reads with light text.
    readonly property color _ribbonTextColor: qgcPal.text

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator();
    }

    QGCPalette { id: qgcPal }

    Rectangle {
        anchors.fill:   parent
        color:          _ribbonColor
    }

    // STRATUM: 2-px accent under-rule at the base of the toolbar. Reads the ribbon
    // as a discrete strip on the map background instead of a bare color band. Uses
    // the current branding accent so a palette re-tune propagates automatically.
    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height:         2
        color:          qgcPal.brandingPurple
        opacity:        0.85
        z:              10
    }

    QGCFlickable {
        anchors.top:        parent.top
        anchors.left:       parent.left
        anchors.right:      parent.right
        height:             ScreenTools.toolbarHeight
        contentWidth:       toolBarLayout.width
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id:         toolBarLayout
            height:     parent.height
            spacing:    0

            Item {
                id:     leftPanel
                width:  leftPanelLayout.implicitWidth
                height: parent.height

                RowLayout {
                    id:         leftPanelLayout
                    height:     parent.height
                    spacing:    ScreenTools.defaultFontPixelWidth * 2

                    RowLayout {
                        id:         mainStatusLayout
                        height:     parent.height
                        spacing:    0

                        QGCToolBarButton {
                            id:                 qgcButton
                            objectName:         "toolbar_qgcLogo"
                            Layout.fillHeight:  true
                            // STRATUM: NEXAM (NX) company mark on the left, tinted black to
                            // match the rest of the ribbon content.
                            icon.source:        "/res/NXLogo.svg"
                            logo:               true
                            logoColor:          _ribbonTextColor
                            onClicked:          mainWindow.showToolSelectDialog()
                        }

                        // STRATUM: dropdown chevron next to the NX mark so operators see
                        // the logo is a menu trigger (Fly / Configure / Settings / Close).
                        QGCLabel {
                            Layout.alignment:   Qt.AlignVCenter
                            Layout.leftMargin:  -ScreenTools.defaultFontPixelWidth * 0.6
                            text:               "\u25BE"
                            color:              _ribbonTextColor
                            font.pointSize:     ScreenTools.smallFontPointSize
                            opacity:            0.85
                            MouseArea {
                                anchors.fill:   parent
                                onClicked:      mainWindow.showToolSelectDialog()
                                cursorShape:    Qt.PointingHandCursor
                            }
                        }

                        MainStatusIndicator {
                            id:                 mainStatusIndicator
                            objectName:         "toolbar_mainStatusIndicator"
                            Layout.fillHeight:  true
                            ribbonTextColor:    _ribbonTextColor
                            visible:            false
                        }
                    }

                    QGCButton {
                        id:         disconnectButton
                        text:       qsTr("Disconnect")
                        onClicked:  _activeVehicle.closeVehicle()
                        visible:    _activeVehicle && _communicationLost
                    }

                    FlightModeIndicator {
                        objectName:         "toolbar_flightModeIndicator"
                        Layout.fillHeight:  true
                        visible:            false
                        ribbonTextColor:    _ribbonTextColor
                    }
                }
            }
            Item {
                id:     centerPanel
                width:  Math.max(0, control.width - (leftPanel.width + rightPanel.width))
                height: parent.height

                StratumStatusBar {
                    id: stratumStatusBar
                    anchors.fill: parent
                    vehicle: control._activeVehicle
                    pendingTarget: control.pendingTarget
                    designatedTarget: control.designatedTarget
                    standoffController: control.standoffController
                    videoLive: QGroundControl.videoManager.decoding
                    ribbonTextColor: _ribbonTextColor
                }
            }

            Item {
                id:      rightPanel
                width:   0
                height:  parent.height
                visible: false

                FlyViewToolBarIndicators {
                    id:                 flyViewIndicators
                    height:             parent.height
                    ribbonTextColor:    _ribbonTextColor
                }
            }
        }
    }

    // STRATUM: the guided-action confirm bar and its message display were moved to the
    // bottom edge of the fly view. See FlyView.qml (guidedActionConfirmBottomBar).

    ParameterDownloadProgress {
        anchors.fill: parent
    }
}
