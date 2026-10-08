import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

QGCPopupDialog {
    id:         root
    title:      ""
    buttons:    Dialog.Close

    readonly property var _admin:     QGroundControl.settingsManager.adminSettings
    readonly property bool _unlocked: _admin ? _admin.unlocked : false

    QGCPalette { id: qgcPal }

    onClosed: {
        passwordField.text = ""
        wrongLabel.visible = false
        if (_admin) {
            _admin.relock()
        }
    }

    ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight / 2

        ColumnLayout {
            visible:    !_unlocked
            spacing:    ScreenTools.defaultFontPixelHeight / 2

            QGCLabel {
                Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 44
                wrapMode:               Text.WordWrap
                text:                   qsTr("Enter access code to continue.")
            }

            RowLayout {
                spacing: ScreenTools.defaultFontPixelWidth
                QGCTextField {
                    id:                 passwordField
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                    echoMode:           TextInput.Password
                    enabled:            _admin ? !_admin.lockedOut : false
                    onAccepted:         verifyButton.clicked()
                    Keys.onEscapePressed: root.close()
                }
                QGCButton {
                    id:         verifyButton
                    text:       qsTr("Verify")
                    enabled:    _admin ? !_admin.lockedOut && passwordField.text.length > 0 : false
                    onClicked: {
                        if (!_admin) return
                        if (_admin.verifyPassword(passwordField.text)) {
                            passwordField.text = ""
                            wrongLabel.visible = false
                        } else {
                            wrongLabel.text = _admin.lockedOut
                                ? qsTr("Too many attempts. Restart the application to try again.")
                                : qsTr("Incorrect.")
                            wrongLabel.visible = true
                            passwordField.text = ""
                            passwordField.forceActiveFocus()
                        }
                    }
                }
            }

            QGCLabel {
                id:         wrongLabel
                visible:    false
                color:      qgcPal.warningText
                text:       qsTr("Incorrect.")
            }
        }

        ColumnLayout {
            visible:    _unlocked
            spacing:    ScreenTools.defaultFontPixelHeight / 2

            QGCLabel {
                text:               qsTr("STRATUM admin settings")
                font.bold:          true
                font.pointSize:     ScreenTools.mediumFontPointSize
            }

            QGCLabel {
                Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 58
                wrapMode:               Text.WordWrap
                color:                  qgcPal.warningText
                text:                   qsTr("Changes take effect immediately.")
            }

            GridLayout {
                columns:            3
                columnSpacing:      ScreenTools.defaultFontPixelWidth
                rowSpacing:         ScreenTools.defaultFontPixelHeight / 3

                QGCLabel {
                    Layout.columnSpan: 3
                    text: qsTr("Required autopilot firmware versions")
                    font.bold: true
                }

                QGCLabel { text: qsTr("Major") }
                FactTextField {
                    fact: _admin ? _admin.requiredPx4MajorVersion : null
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
                Item { Layout.fillWidth: true }

                QGCLabel { text: qsTr("Minor") }
                FactTextField {
                    fact: _admin ? _admin.requiredPx4MinorVersion : null
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
                Item { Layout.fillWidth: true }

                QGCLabel { text: qsTr("Patch") }
                FactTextField {
                    fact: _admin ? _admin.requiredPx4PatchVersion : null
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
                Item { Layout.fillWidth: true }

                QGCLabel { text: qsTr("STRATUM schema major") }
                FactTextField {
                    fact: _admin ? _admin.requiredStratumSchemaMajor : null
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
                Item { Layout.fillWidth: true }

                QGCLabel { text: qsTr("STRATUM NX major minimum") }
                FactTextField {
                    fact: _admin ? _admin.requiredStratumNxMajor : null
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                }
                Item { Layout.fillWidth: true }

                QGCLabel { text: qsTr("Show mismatch warning") }
                FactCheckBox {
                    fact: _admin ? _admin.strictCompatibilityGate : null
                    Layout.columnSpan: 2
                }

                QGCLabel {
                    Layout.columnSpan: 3
                    Layout.topMargin: ScreenTools.defaultFontPixelHeight / 3
                    Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 58
                    wrapMode: Text.WordWrap
                    text: qsTr("Incompatible firmware, a missing NX marker, a schema mismatch, or an NX version below minimum disconnects the vehicle. The strict option controls whether a warning is shown. Set base firmware major, minor, and patch all to 0 to disable that version comparison.")
                }

                QGCLabel { text: qsTr("Tracker click box") }
                Slider {
                    id: trackerBoxSlider
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 22
                    from: 32
                    to: 640
                    stepSize: 1
                    value: _admin ? Number(_admin.trackerBoxSizePx.rawValue) : 200
                    onMoved: {
                        if (_admin) {
                            _admin.trackerBoxSizePx.rawValue = Math.round(value)
                        }
                    }
                }
                QGCLabel {
                    text: _admin ? qsTr("%1 px").arg(Number(_admin.trackerBoxSizePx.rawValue)) : "200 px"
                }

                QGCLabel { text: qsTr("C12 max gimbal speed") }
                Slider {
                    id: gimbalSpeedSlider
                    Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 22
                    from: 1
                    to: 127
                    stepSize: 1
                    value: _admin ? Number(_admin.c12GimbalMaxSpeed.rawValue) : 100
                    onMoved: {
                        if (_admin) {
                            _admin.c12GimbalMaxSpeed.rawValue = Math.round(value)
                        }
                    }
                }
                QGCLabel {
                    text: _admin ? qsTr("%1").arg(Number(_admin.c12GimbalMaxSpeed.rawValue)) : "100"
                }
            }

            Rectangle {
                Layout.topMargin:       ScreenTools.defaultFontPixelHeight / 2
                Layout.fillWidth:       true
                implicitHeight:         changePwdSection.implicitHeight + ScreenTools.defaultFontPixelHeight
                color:                  "transparent"
                border.color:           qgcPal.windowShade
                border.width:           1
                radius:                 ScreenTools.defaultFontPixelHeight / 4

                ColumnLayout {
                    id:                 changePwdSection
                    anchors.margins:    ScreenTools.defaultFontPixelHeight / 2
                    anchors.left:       parent.left
                    anchors.right:      parent.right
                    anchors.top:        parent.top
                    spacing:            ScreenTools.defaultFontPixelHeight / 3

                    property bool _expanded: false

                    RowLayout {
                        Layout.fillWidth: true
                        QGCLabel {
                            Layout.fillWidth:   true
                            text:               qsTr("Change admin password")
                            font.bold:          true
                        }
                        QGCButton {
                            text:       changePwdSection._expanded ? qsTr("Hide") : qsTr("Change...")
                            onClicked:  changePwdSection._expanded = !changePwdSection._expanded
                        }
                    }

                    ColumnLayout {
                        visible:    changePwdSection._expanded
                        spacing:    ScreenTools.defaultFontPixelHeight / 3

                        GridLayout {
                            columns:        2
                            columnSpacing:  ScreenTools.defaultFontPixelWidth * 2
                            rowSpacing:     ScreenTools.defaultFontPixelHeight / 3

                            QGCLabel { text: qsTr("Current password") }
                            QGCTextField {
                                id:         currentPwdField
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                                echoMode:   TextInput.Password
                            }
                            QGCLabel { text: qsTr("New password") }
                            QGCTextField {
                                id:         newPwdField
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                                echoMode:   TextInput.Password
                            }
                            QGCLabel { text: qsTr("Confirm new password") }
                            QGCTextField {
                                id:         confirmPwdField
                                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 24
                                echoMode:   TextInput.Password
                            }
                        }

                        QGCLabel {
                            Layout.maximumWidth:    ScreenTools.defaultFontPixelWidth * 56
                            wrapMode:               Text.WordWrap
                            text:                   qsTr("Minimum 8 characters. The new password overrides the build-time default and persists across restarts.")
                        }

                        QGCLabel {
                            id:         changePwdResult
                            visible:    text.length > 0
                            wrapMode:   Text.WordWrap
                            Layout.maximumWidth: ScreenTools.defaultFontPixelWidth * 56
                            property bool success: false
                            color:      success ? qgcPal.text : qgcPal.warningText
                            text:       ""
                        }

                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth
                            QGCButton {
                                text:       qsTr("Apply")
                                enabled:    currentPwdField.text.length > 0 &&
                                            newPwdField.text.length > 0 &&
                                            confirmPwdField.text.length > 0
                                onClicked: {
                                    if (!_admin) return
                                    changePwdResult.success = false
                                    if (newPwdField.text !== confirmPwdField.text) {
                                        changePwdResult.text = qsTr("New password and confirmation do not match.")
                                        return
                                    }
                                    if (newPwdField.text.length < 8) {
                                        changePwdResult.text = qsTr("New password must be at least 8 characters.")
                                        return
                                    }
                                    if (newPwdField.text === currentPwdField.text) {
                                        changePwdResult.text = qsTr("New password must differ from the current one.")
                                        return
                                    }
                                    var ok = _admin.changePassword(currentPwdField.text, newPwdField.text)
                                    if (ok) {
                                        changePwdResult.success = true
                                        changePwdResult.text = qsTr("Password changed. It takes effect on the next unlock.")
                                        currentPwdField.text = ""
                                        newPwdField.text = ""
                                        confirmPwdField.text = ""
                                    } else {
                                        changePwdResult.text = qsTr("Could not change password. Check the current password and try again.")
                                    }
                                }
                            }
                            QGCButton {
                                text: qsTr("Cancel")
                                onClicked: {
                                    currentPwdField.text = ""
                                    newPwdField.text = ""
                                    confirmPwdField.text = ""
                                    changePwdResult.text = ""
                                    changePwdSection._expanded = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
