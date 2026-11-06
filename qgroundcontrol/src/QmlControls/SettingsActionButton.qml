import QtQuick
import QGroundControl
import QGroundControl.Controls

QGCButton {
    id: control
    implicitHeight: Math.max(40, contentItem.implicitHeight + topPadding + bottomPadding)
    focusPolicy: Qt.StrongFocus
    fontWeight: Font.Medium
    textColor: primary ? theme.accentText : theme.text

    SettingsTheme { id: theme }

    background: Rectangle {
        implicitWidth: ScreenTools.implicitButtonWidth
        radius: 4
        color: control.primary ? theme.accent : (control.hovered || control.down ? theme.input : theme.panel)
        border.color: control.activeFocus || control.primary ? theme.accent : theme.border
        border.width: control.activeFocus || theme.highContrast ? 2 : 1
        opacity: control.enabled ? 1 : 0.5
    }
}
