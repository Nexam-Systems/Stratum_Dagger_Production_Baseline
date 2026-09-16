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

    // STRATUM: the standoff / AOP entry commands now live in the centre of this ribbon
    // (moved off the left command strip). The handlers are wired in FlyView.qml, which
    // owns the widget layer that hosts the standoff panel and the AOP map editor.
    signal defineAOP()
    signal setStandoff()

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property bool   _communicationLost: _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property real   _leftRightMargin:   ScreenTools.defaultFontPixelWidth * 0.75
    property var    _guidedController:  globals.guidedControllerFlyView

    // STRATUM: solid ribbon colour reflects operational state. Kept in lock-step with
    // FlyViewToolStrip.qml and FlightMap/MapItems/VehicleMapItem.qml.
    readonly property string _abortModeName:      qsTr("Abort")
    readonly property string _engagementModeName: qsTr("Engagement")
    readonly property string _holdModeName:       _activeVehicle ? _activeVehicle.pauseFlightMode : qsTr("Hold")
    property color _ribbonColor: {
        if (!_activeVehicle) {
            return "#6B7280"                    // disconnected / no vehicle
        }
        if (_communicationLost) {
            return "#6B7280"                    // disconnected
        }
        var mode = _activeVehicle.flightMode
        if (mode === _abortModeName) {
            return "#F59E0B"                    // abort
        }
        if (mode === _engagementModeName) {
            return "#DC2626"                    // engagement
        }
        if (mode === qsTr("Standoff") || mode === qsTr("Takeoff") || mode === _holdModeName || _activeVehicle.flying) {
            return "#22C55E"                    // normal operations
        }
        return "#1E88E5"                        // connected, on the ground / ready
    }
    // STRATUM: all ribbon content (logo, status text, mode, telemetry) renders black.
    readonly property color _ribbonTextColor: "#000000"

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
        anchors.fill:       parent
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

                        MainStatusIndicator {
                            id:                 mainStatusIndicator
                            objectName:         "toolbar_mainStatusIndicator"
                            Layout.fillHeight:  true
                            ribbonTextColor:    _ribbonTextColor
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
                        visible:            _activeVehicle
                        ribbonTextColor:    _ribbonTextColor
                    }
                }
            }
            Item {
                id:     centerPanel
                // STRATUM: centre of the ribbon carries the Define AOP and Set Standoff
                // command buttons (relocated from the left command strip).
                width:  Math.max(0, control.width - (leftPanel.width + rightPanel.width))
                height: parent.height

                Row {
                    anchors.centerIn:   parent
                    spacing:            ScreenTools.defaultFontPixelWidth

                    QGCButton {
                        text:       qsTr("Define AOP")
                        onClicked:  control.defineAOP()
                    }

                    QGCButton {
                        text:       qsTr("Set Standoff")
                        onClicked:  control.setStandoff()
                    }
                }
            }

            Item {
                id:     rightPanel
                width:  flyViewIndicators.width
                height: parent.height

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
