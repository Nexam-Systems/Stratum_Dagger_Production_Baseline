import QtQuick
import QGroundControl
import QGroundControl.Controls

QGCButton {
    id: control
    implicitHeight: Math.max(40, contentItem.implicitHeight + topPadding + bottomPadding)
    focusPolicy: Qt.StrongFocus
    fontWeight: Font.Medium
    textColor: theme.lightTheme && !enabled ? actionPalette.buttonText : (primary ? theme.accentText : theme.text)

    SettingsTheme { id: theme }
    QGCPalette { id: actionPalette; colorGroupEnabled: control.enabled }

    background: Rectangle {
        implicitWidth: ScreenTools.implicitButtonWidth
        radius: 4
        color: theme.lightTheme
               ? (!control.enabled ? actionPalette.button
                  : control.primary ? Qt.darker(theme.accent, control.down ? 1.15 : control.hovered ? 1.07 : 1)
                  : control.down ? actionPalette.windowShadeDark : control.hovered ? theme.header : theme.panel)
               : control.primary ? theme.accent : (control.hovered || control.down ? theme.input : theme.panel)
        border.color: theme.lightTheme && !control.enabled ? actionPalette.buttonBorder
                      : control.activeFocus || control.primary ? theme.accent : theme.border
        border.width: control.activeFocus || theme.highContrast ? 2 : 1
        opacity: theme.lightTheme || control.enabled ? 1 : 0.5
    }
}
