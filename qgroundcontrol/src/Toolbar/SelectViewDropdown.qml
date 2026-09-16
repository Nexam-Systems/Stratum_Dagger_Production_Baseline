import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

ToolIndicatorPage {
    id: root

    property real _toolButtonHeight: ScreenTools.defaultFontPixelHeight * 3

    contentComponent: Component {
        GridLayout {
            columns: 2
            columnSpacing: ScreenTools.defaultFontPixelWidth
            rowSpacing: columnSpacing

            SubMenuButton {
                objectName: "toolbar_viewFly"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Fly")
                imageResource: "/res/FlyingPaperPlane.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showFlyView()
                    }
                }
            }

            // STRATUM: Plan view removed. The operator does not "plan" missions;
            // area-of-operations (AOP) is defined in-place on the single Fly view.
            // Button hidden (kept for upstream-merge legibility) rather than deleted.
            SubMenuButton {
                objectName: "toolbar_viewPlan"
                visible: false
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Plan")
                imageResource: "/qmlimages/Plan.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showPlanView()
                    }
                }
            }

            SubMenuButton {
                objectName: "toolbar_viewAnalyze"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Analyze")
                imageResource: "/qmlimages/Analyze.svg"
                // STRATUM: hidden per operator UX spec. Flip to the upstream expression
                // (QGroundControl.corePlugin.showAdvancedUI) to bring it back.
                visible: false
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showAnalyzeTool()
                    }
                }
            }

            SubMenuButton {
                id: setupButton
                objectName: "toolbar_viewConfigure"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Configure Joystick")
                imageResource: "/res/GearWithPaperPlane.svg"
                // STRATUM: operators only need the joystick calibration page. Skip the
                // full Vehicle Configuration tree and open the Joystick component
                // directly (falls back to the summary page if the vehicle / autopilot
                // plugin isn't ready yet).
                visible: true
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        var vehicle = globals.activeVehicle
                        if (vehicle && vehicle.autopilotPlugin &&
                            vehicle.autopilotPlugin.knownVehicleComponentAvailable(AutoPilotPlugin.KnownJoystickVehicleComponent)) {
                            mainWindow.showKnownVehicleComponentConfigPage(AutoPilotPlugin.KnownJoystickVehicleComponent)
                        } else {
                            mainWindow.showVehicleConfig()
                        }
                    }
                }
            }

            SubMenuButton {
                id: settingsButton
                objectName: "toolbar_viewSettings"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Settings")
                imageResource: "/res/QGCLogoWhite.svg"
                visible: !QGroundControl.corePlugin.options.combineSettingsAndSetup
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        mainWindow.showSettingsTool()
                    }
                }
            }

            SubMenuButton {
                id: closeButton
                objectName: "toolbar_viewClose"
                implicitHeight: root._toolButtonHeight
                Layout.fillWidth: true
                text: qsTr("Close")
                imageResource: "/res/OpenDoor.svg"
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        mainWindow.closeIndicatorDrawer()
                        // Route through the window close handler so the unsaved
                        // mission / pending parameter / active connection checks
                        // run, matching the desktop window-close behavior.
                        mainWindow.close()
                    }
                }
            }

            ColumnLayout {
                id: versionColumnLayout
                Layout.fillWidth: true
                Layout.columnSpan: 2
                spacing: 0

                QGCLabel {
                    id: versionLabel
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("%1 Version").arg(QGroundControl.appName)
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: QGCLabel.WordWrap
                }

                QGCLabel {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: QGroundControl.qgcVersion
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: QGCLabel.WrapAnywhere
                }

                QGCLabel {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: QGroundControl.qgcAppDate
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: QGCLabel.WrapAnywhere
                    visible: QGroundControl.qgcDailyBuild

                    QGCMouseArea {
                        anchors.topMargin: -(parent.y - versionLabel.y)
                        anchors.fill: parent

                        onClicked: (mouse) => {
                            if (mouse.modifiers & Qt.ControlModifier) {
                                QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas
                                showTouchAreasNotification.open()
                            } else if (ScreenTools.isMobile || mouse.modifiers & Qt.ShiftModifier) {
                                mainWindow.closeIndicatorDrawer()
                                if (!QGroundControl.corePlugin.showAdvancedUI) {
                                    advancedModeOnConfirmation.open()
                                } else {
                                    advancedModeOffConfirmation.open()
                                }
                            }
                        }

                        // This allows you to change this on mobile
                        onPressAndHold: {
                            QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas
                            showTouchAreasNotification.open()
                        }
                    }
                }
            }
        }
    }
}
