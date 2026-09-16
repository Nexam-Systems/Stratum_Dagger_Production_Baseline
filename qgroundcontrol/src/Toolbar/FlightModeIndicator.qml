import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

Item {
    id:                     control
    Layout.preferredWidth:  mainLayout.width

    property bool   showIndicator:          true
    property bool   waitForParameters:      false
    property color  ribbonTextColor:        qgcPal.text   // STRATUM: black on the fly-view ribbon

    property real fontPointSize:    ScreenTools.largeFontPointSize
    property var  activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    property bool allowEditMode:    true
    property bool editMode:         false

    property bool _isVTOL:          activeVehicle ? activeVehicle.vtol : false
    property bool _vtolInFWDFlight: activeVehicle ? activeVehicle.vtolInFwdFlight : false
    property var  _vehicleInAir:    activeVehicle ? activeVehicle.flying || activeVehicle.landing : false

    // STRATUM: "TRACKING Active" ribbon cue. Derived state -- bound to the inbound
    // NEXAM_TARGET_TRACK (42004) fact group on Vehicle. status.value === 1 is
    // StatusTracking (see VehicleTargetTrackFactGroup.h). The fact group's 300 ms
    // staleness timeout clears status on stream loss, so this self-extinguishes without
    // extra logic. Guarded for a null vehicle and for the fact group being absent,
    // mirroring VisionEngagementStatus.qml's _hasGroup pattern. Dagger-only via
    // stratumProfile === 2 (the tracker only runs on the Dagger companion).
    readonly property bool _stratumIsDagger: QGroundControl.settingsManager.appSettings.stratumProfile.rawValue === 2
    property var  _targetTrack:     activeVehicle ? activeVehicle.targetTrack : null
    property bool _hasTrackGroup:   !!_targetTrack
    property bool _tracking:        _stratumIsDagger && _hasTrackGroup ? (_targetTrack.status.value === 1) : false

    QGCPalette { id: qgcPal }

    RowLayout {
        id:                     mainLayout
        anchors.verticalCenter: parent.verticalCenter
        spacing:                ScreenTools.defaultFontPixelWidth / 2

        QGCColoredImage {
            id:                     flightModeIcon
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 3
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight
            fillMode:               Image.PreserveAspectFit
            mipmap:                 true
            color:                  ribbonTextColor
            source:                 "/qmlimages/FlightModesComponentIcon.png"
        }

        QGCLabel {
            id:                 flightModeLabel
            // STRATUM: PX4's "Position" (POSCTL) is presented as "Manual" throughout the UI.
            text:               activeVehicle
                                ? (activeVehicle.flightMode === qsTr("Position") ? qsTr("Manual") : activeVehicle.flightMode)
                                : qsTr("N/A", "No data to display")
            color:              ribbonTextColor
            font.pointSize:     fontPointSize

        }

        QGCLabel {
            id:                     vtolModeLabel
            Layout.alignment:       Qt.AlignVCenter
            horizontalAlignment:    Text.AlignHCenter
            text:                   _vtolInFWDFlight ? qsTr("FW\nVTOL") : qsTr("MR\nVTOL")
            font.pointSize:         ScreenTools.smallFontPointSize
            wrapMode:               Text.WordWrap
            visible:                _isVTOL
        }

        // STRATUM: "TRACKING Active" pill, shown only while the companion tracker reports
        // StatusTracking (targetTrack.status === 1). Uses the ribbon text colour for the
        // outline/label so it reads correctly on the coloured fly-view ribbon.
        Rectangle {
            id:                     trackingIndicator
            Layout.alignment:       Qt.AlignVCenter
            Layout.leftMargin:      ScreenTools.defaultFontPixelWidth
            implicitWidth:          trackingLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.5
            implicitHeight:         trackingLabel.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.35
            radius:                 height / 2
            color:                  "transparent"
            border.color:           ribbonTextColor
            border.width:           1
            visible:                _tracking

            QGCLabel {
                id:                 trackingLabel
                anchors.centerIn:   parent
                text:               qsTr("TRACKING Active")
                color:              ribbonTextColor
                font.bold:          true
                font.pointSize:     ScreenTools.smallFontPointSize
            }
        }

        // STRATUM: dropdown chevron so the flight-mode label reads as a menu trigger.
        QGCLabel {
            id:                 flightModeChevron
            Layout.alignment:   Qt.AlignVCenter
            Layout.leftMargin:  -ScreenTools.defaultFontPixelWidth * 0.2
            text:               "\u25BE"
            color:              ribbonTextColor
            font.pointSize:     ScreenTools.smallFontPointSize
            opacity:            0.85
        }
    }

    MouseArea {
        anchors.fill:   mainLayout
        onClicked:      mainWindow.showIndicatorDrawer(drawerComponent, control)
    }

    Component {
        id: drawerComponent

        ToolIndicatorPage {
            showExpand:         true
            waitForParameters:                  false
            expandedComponentWaitForParameters: true

            contentComponent:    flightModeContentComponent
            expandedComponent:   flightModeExpandedComponent

            onExpandedChanged: {
                if (!expanded) {
                    editMode = false
                }
            }
        }
    }

    Component {
        id: flightModeContentComponent

        ColumnLayout {
            id:         modeColumn
            spacing:    ScreenTools.defaultFontPixelWidth / 2

            property var    activeVehicle:            QGroundControl.multiVehicleManager.activeVehicle
            property var    flightModeSettings:       QGroundControl.settingsManager.flightModeSettings
            property var    hiddenFlightModesFact:    null
            property var    hiddenFlightModesList:    []

            Component.onCompleted: {
                // Hidden flight modes are classified by firmware and vehicle class
                var hiddenFlightModesPropPrefix
                if (activeVehicle.px4Firmware) {
                    hiddenFlightModesPropPrefix = "px4HiddenFlightModes"
                } else if (activeVehicle.apmFirmware) {
                    hiddenFlightModesPropPrefix = "apmHiddenFlightModes"
                } else {
                    control.allowEditMode = false
                }
                if (control.allowEditMode) {
                    var hiddenFlightModesProp = hiddenFlightModesPropPrefix + activeVehicle.vehicleClassInternalName()
                    if (flightModeSettings.hasOwnProperty(hiddenFlightModesProp)) {
                        hiddenFlightModesFact = flightModeSettings[hiddenFlightModesProp]
                        // Split string into list of flight modes
                        if (hiddenFlightModesFact && hiddenFlightModesFact.value !== "") {
                            hiddenFlightModesList = hiddenFlightModesFact.value.split(",")
                        }
                    } else {
                        control.allowEditMode = false
                    }
                }
                hiddenModesLabel.calcVisible()
            }

            Connections {
                target: control
                function onEditModeChanged() {
                    if (editMode) {
                        for (var i=0; i<modeRepeater.count; i++) {
                            var button      = modeRepeater.itemAt(i).children[0]
                            var checkBox    = modeRepeater.itemAt(i).children[1]

                            checkBox.checked = !hiddenFlightModesList.find(item => { return item === button.text } )
                        }
                    }
                }
            }

            QGCDelayButton {
                id:                 vtolTransitionButton
                Layout.fillWidth:   true
                text:               _vtolInFWDFlight ? qsTr("Transition to Multi-Rotor") : qsTr("Transition to Fixed Wing")
                visible:            _isVTOL && _vehicleInAir

                onActivated: {
                    _activeVehicle.vtolInFwdFlight = !_vtolInFWDFlight
                    mainWindow.closeIndicatorDrawer()
                }
            }

            Repeater {
                id:     modeRepeater
                // STRATUM: operator UX spec limits the mode picker to a whitelist. The
                // firmware plugin still enumerates the full list (so telemetry / mode
                // callbacks are unchanged); we just hide unsupported entries. Empty
                // the array to restore upstream behaviour (show every mode).
                readonly property var _stratumAllowedFlightModes: [
                    qsTr("Takeoff"), qsTr("Land"),
                    qsTr("Safe Recovery"), qsTr("Return"),
                    qsTr("Position"),
                    qsTr("Standoff"), qsTr("Engagement"),
                    qsTr("Hold"), qsTr("Abort")
                ]
                // STRATUM: PX4's "Position" (POSCTL) is what the operator knows as
                // "Manual". Rename the label only; the flight-mode string sent to the
                // vehicle stays "Position" (see modeButton.onActivated below).
                function _stratumDisplayLabel(mode) {
                    if (mode === qsTr("Position")) {
                        return qsTr("Manual")
                    }
                    return mode
                }
                model: activeVehicle
                       ? (_stratumAllowedFlightModes.length === 0
                          ? activeVehicle.flightModes
                          : activeVehicle.flightModes.filter(function(m) {
                                return _stratumAllowedFlightModes.indexOf(m) !== -1
                            }))
                       : []

                RowLayout {
                    spacing: ScreenTools.defaultFontPixelWidth
                    visible: editMode || !hiddenFlightModesList.find(item => { return item === modelData } )

                    QGCDelayButton {
                        id:                 modeButton
                        text:               modeRepeater._stratumDisplayLabel(modelData)
                        delay:              flightModeSettings.requireModeChangeConfirmation.rawValue ? defaultDelay : 0
                        Layout.fillWidth:   true

                        onActivated: {
                            if (editMode) {
                                parent.children[1].toggle()
                                parent.children[1].clicked()
                            } else {
                                //var controller = globals.guidedControllerFlyView
                                //controller.confirmAction(controller.actionSetFlightMode, modelData)
                                activeVehicle.flightMode = modelData
                                mainWindow.closeIndicatorDrawer()
                            }
                        }
                    }

                    QGCCheckBoxSlider {
                        visible: editMode

                        onClicked: {
                            hiddenFlightModesList = []
                            for (var i=0; i<modeRepeater.count; i++) {
                                var checkBox = modeRepeater.itemAt(i).children[1]
                                if (!checkBox.checked) {
                                    hiddenFlightModesList.push(modeRepeater.model[i])
                                }
                            }
                            hiddenFlightModesFact.value = hiddenFlightModesList.join(",")
                            hiddenModesLabel.calcVisible()
                        }
                    }
                }
            }

            QGCLabel {
                id:                     hiddenModesLabel
                text:                   qsTr("Some Modes Hidden")
                Layout.fillWidth:       true
                font.pointSize:         ScreenTools.smallFontPointSize
                horizontalAlignment:    Text.AlignHCenter
                visible:                false

                function calcVisible() {
                    hiddenModesLabel.visible = hiddenFlightModesList.length > 0
                }
            }
        }
    }

    Component {
        id: flightModeExpandedComponent

        ColumnLayout {
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 60
            spacing:                margins / 2

            property var  qgcPal:               QGroundControl.globalPalette
            property real margins:              ScreenTools.defaultFontPixelHeight
            property var  flightModeSettings:   QGroundControl.settingsManager.flightModeSettings

            Loader {
                Layout.fillWidth:   true
                source:             _activeVehicle.expandedToolbarIndicatorSource("FlightMode")
            }

            SettingsGroupLayout {
                Layout.fillWidth:  true

                FactCheckBoxSlider {
                    Layout.fillWidth:   true
                    text:               qsTr("Click and Hold to Confirm Mode Change")
                    fact:               flightModeSettings.requireModeChangeConfirmation
                }

                RowLayout {
                    Layout.fillWidth:   true
                    enabled:            control.allowEditMode

                    QGCLabel {
                        Layout.fillWidth:   true
                        text:               qsTr("Edit Displayed Flight Modes")
                    }

                    QGCCheckBoxSlider {
                        onClicked: control.editMode = checked
                    }
                }

                LabelledButton {
                    Layout.fillWidth:   true
                    label:              qsTr("Flight Modes")
                    buttonText:         qsTr("Configure")
                    visible:            _activeVehicle.autopilotPlugin.knownVehicleComponentAvailable(AutoPilotPlugin.KnownFlightModesVehicleComponent) &&
                                            QGroundControl.corePlugin.showAdvancedUI

                    onClicked: {
                        mainWindow.showKnownVehicleComponentConfigPage(AutoPilotPlugin.KnownFlightModesVehicleComponent)
                        mainWindow.closeIndicatorDrawer()
                    }
                }
            }
        }
    }
}
