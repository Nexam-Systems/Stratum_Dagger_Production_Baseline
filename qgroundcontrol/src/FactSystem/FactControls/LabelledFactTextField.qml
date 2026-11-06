import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls

RowLayout {
    id: control
    property string label:                   fact ? fact.shortDescription : ""
    property alias  fact:                    _factTextField.fact
    property real   textFieldPreferredWidth: -1
    property bool   textFieldFillWidth:      false
    property alias  textFieldOutlined:       _factTextField.outlined
    property alias  textFieldUnitsLabel:     _factTextField.unitsLabel
    property alias  textFieldShowUnits:      _factTextField.showUnits
    property alias  textFieldShowHelp:       _factTextField.showHelp
    property alias  textField:               _factTextField

    spacing: ScreenTools.defaultFontPixelWidth * 2

    QGCLabel {
        Layout.fillWidth:    true
        Layout.minimumWidth: implicitWidth
        text:                label
        visible:             label !== ""
    }

    FactTextField {
        id:                     _factTextField
        Layout.preferredWidth:  textFieldPreferredWidth
        Layout.fillWidth:       control.textFieldFillWidth
    }
}
