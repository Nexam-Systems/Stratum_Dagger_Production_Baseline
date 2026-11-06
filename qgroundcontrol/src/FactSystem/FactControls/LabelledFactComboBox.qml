import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

RowLayout {
    id: control
    property alias label:                   label.text
    property alias fact:                    _comboBox.fact
    property alias indexModel:              _comboBox.indexModel
    property var   comboBox:                _comboBox
    property real  comboBoxPreferredWidth:  -1
    property bool  comboBoxFillWidth:       false
    property alias comboBoxOutlined:       _comboBox.outlined

    spacing: ScreenTools.defaultFontPixelWidth * 2

    signal activated(int index)

    QGCLabel {
        id:                 label
        visible:            text !== ""
        Layout.fillWidth:   true
        Layout.minimumWidth: implicitWidth
    }

    FactComboBox {
        id:                     _comboBox
        Layout.preferredWidth:  comboBoxPreferredWidth
        Layout.fillWidth:       control.comboBoxFillWidth
        sizeToContents:         true

        onActivated: (index) => { parent.activated(index) }
    }
}
