import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

RowLayout {
    id:         control
    spacing:    ScreenTools.defaultFontPixelWidth * 0.25

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property bool   _armed:             _activeVehicle ? _activeVehicle.armed : false
    property bool   _communicationLost: _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property color  ribbonTextColor:    qgcPal.text
    property real   _margins:           ScreenTools.defaultFontPixelWidth
    property real   _spacing:           ScreenTools.defaultFontPixelWidth / 2
    property bool   _allowForceArm:      false
    property bool   _healthAndArmingChecksSupported: _activeVehicle ? _activeVehicle.healthAndArmingCheckReport.supported : false
    property bool   _vehicleFlies:      _activeVehicle ? _activeVehicle.airShip || _activeVehicle.fixedWing || _activeVehicle.vtol || _activeVehicle.multiRotor : false
    property var    _vehicleInAir:      _activeVehicle ? _activeVehicle.flying || _activeVehicle.landing : false
    property bool   _vtolInFWDFlight:   _activeVehicle ? _activeVehicle.vtolInFwdFlight : false

    // STRATUM: hover + press affordance so the status readout reads as a real button.
    property bool   _hovered:           statusHoverArea.containsMouse

    function dropMainStatusIndicator() {
        let overallStatusComponent = _activeVehicle ? overallStatusIndicatorPage : overallStatusOfflineIndicatorPage
        mainWindow.showIndicatorDrawer(overallStatusComponent, control)
    }

    QGCPalette { id: qgcPal }

    // STRATUM: light hover chip that hugs the status word + chevron. Rounded so it
    // reads as a discrete button on the neutral tactical ribbon. The chip is scoped
    // to just the label + chevron so an adjacent VTOL mode label (when present)
    // keeps its own interactive region.
    Rectangle {
        anchors.left:           mainStatusLabel.left
        anchors.right:          mainStatusChevron.right
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.15
        anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.15
        anchors.leftMargin:     -ScreenTools.defaultFontPixelWidth * 0.35
        anchors.rightMargin:    -ScreenTools.defaultFontPixelWidth * 0.35
        radius:                 ScreenTools.defaultFontPixelHeight * 0.3
        color:                  Qt.rgba(1, 1, 1, _hovered ? 0.12 : 0.06)
        border.color:           Qt.rgba(1, 1, 1, _hovered ? 0.35 : 0.18)
        border.width:           1
        z:                      -1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id:                 statusHoverArea
        anchors.left:       mainStatusLabel.left
        anchors.right:      mainStatusChevron.right
        anchors.top:        parent.top
        anchors.bottom:     parent.bottom
        anchors.leftMargin: -ScreenTools.defaultFontPixelWidth * 0.35
        anchors.rightMargin:-ScreenTools.defaultFontPixelWidth * 0.35
        hoverEnabled:       !ScreenTools.isMobile
        cursorShape:        Qt.PointingHandCursor
        acceptedButtons:    Qt.LeftButton
        onClicked:          dropMainStatusIndicator()
        z:                  10
    }

    QGCLabel {
        id:                 mainStatusLabel
        Layout.fillHeight:  true
        Layout.preferredWidth: contentWidth + (vehicleMessagesIcon.visible ? vehicleMessagesIcon.width + control.spacing : 0)
        verticalAlignment:  Text.AlignVCenter
        font.pointSize:     ScreenTools.largeFontPointSize

        property string _commLostText:      qsTr("Comms Lost")
        property string _readyToFlyText:    qsTr("Ready")
        property string _notReadyToFlyText: qsTr("Not Ready")
        property string _disconnectedText:  qsTr("Disconnected - Click to manually connect")
        property string _armedText:         qsTr("Armed")
        property string _flyingText:        qsTr("Flying")
        property string _landingText:       qsTr("Landing")
        property string _engagingText:      qsTr("Engaging")
        property string _abortText:         qsTr("Abort")

        // STRATUM: ribbon status reflects the live operational state. It is derived from
        // the dynamic armed / flying / landing telemetry -- a disarmed or landed vehicle
        // can never read "Flying". A disarmed vehicle only reads "Ready" when the
        // firmware's pre-arm check + sensor health both pass; otherwise "Not Ready".
        text: {
            if (!_activeVehicle) {
                return _disconnectedText
            }
            if (_communicationLost) {
                return _commLostText
            }
            // Disarmed on the ground: never "Flying" regardless of the last flight mode.
            if (!_armed) {
                if (_activeVehicle.readyToFlyAvailable && !_activeVehicle.readyToFly) {
                    return _notReadyToFlyText
                }
                if (!_activeVehicle.allSensorsHealthy) {
                    return _notReadyToFlyText
                }
                return _readyToFlyText
            }
            var mode = _activeVehicle.flightMode
            if (mode === qsTr("Abort")) {
                return _abortText
            }
            if (mode === qsTr("Engagement") || mode === qsTr("Vision Engagement")) {
                return _engagingText
            }
            if (_activeVehicle.landing) {
                return _landingText
            }
            if (_activeVehicle.flying) {
                return _flyingText
            }
            // Armed but still on the ground (e.g. pre-takeoff).
            return _armedText
        }
        color:              ribbonTextColor

        QGCColoredImage {
            id:                     vehicleMessagesIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.right:          parent.right
            width:                  ScreenTools.defaultFontPixelWidth * 2
            height:                 width
            source:                 "/res/VehicleMessages.png"
            color:                  getIconColor()
            sourceSize.width:       width
            fillMode:               Image.PreserveAspectFit
            visible:                _activeVehicle && _activeVehicle.messageCount > 0

            function getIconColor() {
                let iconColor = ribbonTextColor
                if (_activeVehicle) {
                    if (_activeVehicle.messageTypeWarning) {
                        iconColor = qgcPal.colorOrange
                    } else if (_activeVehicle.messageTypeError) {
                        iconColor = qgcPal.colorRed
                    }
                }
                return iconColor
            }
        }
    }

    // STRATUM: dropdown chevron so the status label reads as a menu trigger, not a
    // passive status word. Rendered in the same ribbon text colour.
    QGCLabel {
        id:                 mainStatusChevron
        Layout.alignment:   Qt.AlignVCenter
        text:               "\u25BE"
        color:              ribbonTextColor
        font.pointSize:     ScreenTools.smallFontPointSize
        opacity:            0.85
    }

    QGCLabel {
        id:                 vtolModeLabel
        Layout.fillHeight:  true
        verticalAlignment:  Text.AlignVCenter
        text:               _vtolInFWDFlight ? qsTr("FW(vtol)") : qsTr("MR(vtol)")
        color:              qgcPal.text
        font.pointSize:     _vehicleInAir ? ScreenTools.largeFontPointSize : ScreenTools.defaultFontPointSize
        visible:            _activeVehicle && _activeVehicle.vtol

        QGCMouseArea {
            anchors.fill: parent
            onClicked: {
                if (_vehicleInAir) {
                    mainWindow.showIndicatorDrawer(vtolTransitionIndicatorPage)
                }
            }
        }
    }

    Component {
        id: overallStatusOfflineIndicatorPage

        MainStatusIndicatorOfflinePage {
            Component.onCompleted:   mainWindow.suppressCriticalVehicleMessages = true
            Component.onDestruction: mainWindow.suppressCriticalVehicleMessages = false
        }
    }

    Component {
        id: overallStatusIndicatorPage

        ToolIndicatorPage {
            showExpand:                         true
            waitForParameters:                  false
            expandedComponentWaitForParameters: true
            contentComponent:                   mainStatusContentComponent
            expandedComponent:                  mainStatusExpandedComponent

            Component.onCompleted:   mainWindow.suppressCriticalVehicleMessages = true
            Component.onDestruction: mainWindow.suppressCriticalVehicleMessages = false
        }
    }

    Component {
        id: mainStatusContentComponent

        ColumnLayout {
            id:         mainLayout
            spacing:    _spacing

            property bool parametersReady: QGroundControl.multiVehicleManager.parameterReadyVehicleAvailable

            RowLayout {
                spacing: ScreenTools.defaultFontPixelWidth
                visible: parametersReady

                QGCDelayButton {
                    enabled:    _armed || !_healthAndArmingChecksSupported || _activeVehicle.healthAndArmingCheckReport.canArm
                    text:       _armed ? qsTr("Disarm") : (control._allowForceArm ? qsTr("Force Arm") : qsTr("Arm"))

                    onActivated: {
                        if (_armed) {
                            _activeVehicle.armed = false
                        } else {
                            if (_allowForceArm) {
                                _allowForceArm = false
                                _activeVehicle.forceArm()
                            } else {
                                _activeVehicle.armed = true
                            }
                        }
                        mainWindow.closeIndicatorDrawer()
                    }
                }

                LabelledComboBox {
                    id:                 primaryLinkCombo
                    Layout.alignment:   Qt.AlignTop
                    label:              qsTr("Primary Link")
                    alternateText:      _primaryLinkName
                    visible:            _activeVehicle && _activeVehicle.vehicleLinkManager.linkNames.length > 1

                    property var    _rgLinkNames:       _activeVehicle ? _activeVehicle.vehicleLinkManager.linkNames : [ ]
                    property var    _rgLinkStatus:      _activeVehicle ? _activeVehicle.vehicleLinkManager.linkStatuses : [ ]
                    property string _primaryLinkName:   _activeVehicle ? _activeVehicle.vehicleLinkManager.primaryLinkName : ""

                    function updateComboModel() {
                        let linkModel = []
                        for (let i = 0; i < _rgLinkNames.length; i++) {
                            let linkStatus = _rgLinkStatus[i]
                            linkModel.push(_rgLinkNames[i] + (linkStatus === "" ? "" : " " + _rgLinkStatus[i]))
                        }
                        primaryLinkCombo.model = linkModel
                        primaryLinkCombo.currentIndex = -1
                    }

                    Component.onCompleted:  updateComboModel()
                    on_RgLinkNamesChanged:  updateComboModel()
                    on_RgLinkStatusChanged: updateComboModel()

                    onActivated:    (index) => {
                        _activeVehicle.vehicleLinkManager.primaryLinkName = _rgLinkNames[index]; currentIndex = -1
                        mainWindow.closeIndicatorDrawer()
                    }
                }
            }

            SettingsGroupLayout {
                //Layout.fillWidth:   true
                heading:            qsTr("Vehicle Messages")

                VehicleMessageList {
                    id: vehicleMessageList
                    visible: !noMessages
                }

                QGCLabel {
                    text: qsTr("No new vehicle messages")
                    visible: vehicleMessageList.noMessages
                }
            }

            SettingsGroupLayout {
                //Layout.fillWidth:   true
                heading:            qsTr("Sensor Status")
                visible:            parametersReady && !_healthAndArmingChecksSupported

                GridLayout {
                    rowSpacing:     _spacing
                    columnSpacing:  _spacing
                    rows:           _activeVehicle.sysStatusSensorInfo.sensorNames.length
                    flow:           GridLayout.TopToBottom

                    Repeater {
                        model: _activeVehicle.sysStatusSensorInfo.sensorNames
                        QGCLabel { text: modelData }
                    }

                    Repeater {
                        model: _activeVehicle.sysStatusSensorInfo.sensorStatus
                        QGCLabel { text: modelData }
                    }
                }
            }

            SettingsGroupLayout {
                //Layout.fillWidth:   true
                heading:            qsTr("Overall Status")
                visible:            parametersReady && _healthAndArmingChecksSupported && _activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode.count > 0

                // List health and arming checks
                Repeater {
                    model:      _activeVehicle ? _activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode : null
                    delegate:   listdelegate
                }
            }

            Component {
                id: listdelegate

                Column {
                    Row {
                        spacing: ScreenTools.defaultFontPixelHeight

                        QGCLabel {
                            id:           message
                            text:         object.message
                            textFormat:   TextEdit.RichText
                            color:        object.severity == 'error' ? qgcPal.colorRed : object.severity == 'warning' ? qgcPal.colorOrange : qgcPal.text
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (object.description != "")
                                        object.expanded = !object.expanded
                                }
                            }
                        }

                        QGCColoredImage {
                            id:                     arrowDownIndicator
                            anchors.verticalCenter: parent.verticalCenter
                            height:                 1.5 * ScreenTools.defaultFontPixelWidth
                            width:                  height
                            source:                 "/qmlimages/arrow-down.png"
                            color:                  qgcPal.text
                            visible:                object.description != ""
                            MouseArea {
                                anchors.fill:       parent
                                onClicked:          object.expanded = !object.expanded
                            }
                        }
                    }

                    QGCLabel {
                        id:                 description
                        text:               object.description
                        textFormat:         TextEdit.RichText
                        clip:               true
                        visible:            object.expanded

                        property var fact:  null

                        onLinkActivated: (link) => {
                            if (link.startsWith('param://')) {
                                var paramName = link.substr(8);
                                fact = controller.getParameterFact(-1, paramName, true)
                                if (fact != null) {
                                    paramEditorDialogFactory.open()
                                }
                            } else {
                                Qt.openUrlExternally(link);
                            }
                        }

                        FactPanelController {
                            id: controller
                        }

                        QGCPopupDialogFactory {
                            id: paramEditorDialogFactory

                            dialogComponent: paramEditorDialogComponent
                        }

                        Component {
                            id: paramEditorDialogComponent

                            ParameterEditorDialog {
                                title:          qsTr("Edit Parameter")
                                fact:           description.fact
                                destroyOnClose: true
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: mainStatusExpandedComponent

        ColumnLayout {
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 60
            spacing:                margins / 2

            property real margins: ScreenTools.defaultFontPixelHeight

            Loader {
                Layout.fillWidth:   true
                source:             _activeVehicle.expandedToolbarIndicatorSource("MainStatus")
            }

            SettingsGroupLayout {
                Layout.fillWidth:   true
                heading:            qsTr("Force Arm")
                headingDescription: qsTr("Force arming bypasses pre-arm checks. Use with caution.")
                visible:            _activeVehicle && !_armed

                QGCCheckBoxSlider {
                    Layout.fillWidth:   true
                    text:               qsTr("Allow Force Arm")
                    checked:            false
                    onClicked:          _allowForceArm = true
                }
            }

            SettingsGroupLayout {
                Layout.fillWidth:   true
                visible:            QGroundControl.corePlugin.showAdvancedUI

                GridLayout {
                    columns:            2
                    rowSpacing:         ScreenTools.defaultFontPixelHeight / 2
                    columnSpacing:      ScreenTools.defaultFontPixelWidth *2
                    Layout.fillWidth:   true

                    QGCLabel { Layout.fillWidth: true; text: qsTr("Vehicle Parameters") }
                    QGCButton {
                        text: qsTr("Configure")
                        onClicked: {
                            mainWindow.showVehicleConfigParametersPage()
                            mainWindow.closeIndicatorDrawer()
                        }
                    }

                    QGCLabel { Layout.fillWidth: true; text: qsTr("Vehicle Configuration") }
                    QGCButton {
                        text: qsTr("Configure")
                        onClicked: {
                            mainWindow.showVehicleConfig()
                            mainWindow.closeIndicatorDrawer()
                        }
                    }
                }
            }
        }
    }
}
