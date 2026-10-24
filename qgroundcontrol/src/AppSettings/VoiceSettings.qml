import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM #52 (TEMPORARY): live tuning page for the event-announcement voice. Adjust the
// voice / pitch / rate, note the values that sound best, then they get hard-coded in
// AudioOutput and THIS PAGE (plus the QGroundControlQmlGlobal/AudioOutput tuning API and
// the SettingsPages.json entry) is removed. Changes apply live but are not persisted.
Rectangle {
    id:           root
    objectName:   "settingsPage_Voice"
    color:        qgcPal.window
    anchors.fill: parent

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    readonly property real _margins: ScreenTools.defaultFontPixelHeight

    Component.onCompleted: {
        pitchSlider.value = QGroundControl.voicePitch()
        rateSlider.value  = QGroundControl.voiceRate()
        voiceCombo.model  = QGroundControl.availableVoiceNames()
        var idx = voiceCombo.find(QGroundControl.voiceName())
        if (idx >= 0) {
            voiceCombo.currentIndex = idx
        }
    }

    QGCFlickable {
        anchors.fill:     parent
        anchors.margins:  _margins
        contentWidth:     col.width
        contentHeight:    col.height
        clip:             true

        ColumnLayout {
            id:      col
            width:   root.width - (_margins * 2)
            spacing: _margins

            QGCLabel {
                text:           qsTr("Voice Tuning (temporary)")
                font.pointSize: ScreenTools.largeFontPointSize
                font.bold:      true
            }
            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                text:             qsTr("Adjust the event-announcement voice and note the values you like. These controls are temporary — once the voice is finalized they will be hard-coded and this page removed. Changes apply immediately but are not saved across restarts.")
            }

            QGCLabel { text: qsTr("Voice") }
            QGCComboBox {
                id:               voiceCombo
                Layout.fillWidth: true
                onActivated:      QGroundControl.setVoiceName(currentText)
            }

            QGCLabel { text: qsTr("Pitch (lower = deeper): %1").arg(pitchSlider.value.toFixed(2)) }
            Slider {
                id:               pitchSlider
                Layout.fillWidth: true
                from:             -1.0
                to:               1.0
                stepSize:         0.05
                onMoved:          QGroundControl.setVoicePitch(value)
            }

            QGCLabel { text: qsTr("Rate / speed (lower = slower): %1").arg(rateSlider.value.toFixed(2)) }
            Slider {
                id:               rateSlider
                Layout.fillWidth: true
                from:             -1.0
                to:               1.0
                stepSize:         0.05
                onMoved:          QGroundControl.setVoiceRate(value)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing:          _margins / 2

                QGCTextField {
                    id:               testField
                    Layout.fillWidth: true
                    text:             qsTr("Engagement mode active. Return to home in thirty seconds.")
                }
                QGCButton {
                    text:      qsTr("Speak")
                    onClicked: QGroundControl.sayVoiceTest(testField.text)
                }
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                color:            qgcPal.colorOrange
                text:             qsTr("Current → voice: \"%1\"   pitch: %2   rate: %3")
                                     .arg(voiceCombo.currentText)
                                     .arg(pitchSlider.value.toFixed(2))
                                     .arg(rateSlider.value.toFixed(2))
            }
        }
    }
}
