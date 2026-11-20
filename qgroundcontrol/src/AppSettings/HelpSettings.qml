import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM: temporary quick-start guide for field operators. Written in plain language;
// avoid technical/setup terms (no RTSP links, no comm-link setup). Final help content
// TBD -- keep this file as the single source of truth so it is easy to swap out.
Rectangle {
    objectName:     "settingsPage_Help"
    color:          qgcPal.window
    anchors.fill:   parent

    readonly property real _margins:     ScreenTools.defaultFontPixelHeight
    readonly property real _stepIndent:  ScreenTools.defaultFontPixelWidth * 3

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    QGCFlickable {
        anchors.margins:  _margins
        anchors.fill:     parent
        contentWidth:     content.width
        contentHeight:    content.height
        clip:             true

        ColumnLayout {
            id:      content
            width:   parent.width - (_margins * 2)
            spacing: _margins

            QGCLabel {
                text:            qsTr("Quick Start Guide")
                font.pointSize:  ScreenTools.largeFontPointSize * 1.4
                font.bold:       true
            }

            QGCLabel {
                Layout.fillWidth: true
                wrapMode:         Text.WordWrap
                text: qsTr("Welcome to STRATUM. This short guide covers the everyday tasks. " +
                           "For each task, follow the steps in order.")
            }

            // ----- How to define an Area of Operations -------------------
            QGCLabel {
                text:            qsTr("How to define an Area of Operations (AOP)")
                font.pointSize:  ScreenTools.largeFontPointSize
                font.bold:       true
            }
            QGCLabel {
                Layout.fillWidth: true
                Layout.leftMargin: _stepIndent
                wrapMode:         Text.WordWrap
                text: qsTr("The AOP is the boundary the aircraft is allowed to work inside. Targets and Standoff points must sit inside it.\n\n" +
                           "1. On the top ribbon, press \"Define AOP\". A box will appear centred on the map.\n\n" +
                           "2. Drag the corner handles to shape the boundary. Add more corners by dragging the small handles on the edges.\n\n" +
                           "3. Keep every corner inside the allowed range. If a corner sits too far away the app will reject the change when you press Apply.\n\n" +
                           "4. When the shape looks right, press \"Apply changes\". If a red message appears, pull the outermost corner in and press Apply again.\n\n" +
                           "The maximum AOP size can be adjusted in Application Settings → General → STRATUM Operational Limits → \"Max AOP Distance\".")
            }

            // ----- How to set a Standoff point ---------------------------
            QGCLabel {
                text:            qsTr("How to pick a target and set a Standoff point")
                font.pointSize:  ScreenTools.largeFontPointSize
                font.bold:       true
            }
            QGCLabel {
                Layout.fillWidth: true
                Layout.leftMargin: _stepIndent
                wrapMode:         Text.WordWrap
                text: qsTr("The Standoff point is where the aircraft will hold and observe the target from a safe distance.\n\n" +
                           "1. On the top ribbon, press \"Set Standoff\". The Set Standoff panel opens.\n\n" +
                           "2. Choose the target location. Either type the latitude and longitude, or press the crosshair icon and tap on the map where the target is. The target must lie inside the AOP.\n\n" +
                           "3. Fill in the values:\n" +
                           "   • Altitude (AMSL) — the target's altitude above sea level.\n" +
                           "   • Distance — how far the aircraft stays from the target. You can also drag the round handle on the dashed ring on the map.\n" +
                           "   • Height above target — how high above the target the aircraft flies.\n" +
                           "   • Speed — cruise speed to the standoff point.\n" +
                           "   • Direction — the bearing from the target to the standoff point, from 0 up to (not including) 360 degrees (0 = North, 90 = East).\n\n" +
                           "   The panel shows the standoff point (latitude, longitude, altitude, slant range and distance from this ground station) as you type. Distance and height must stay within the allowed limits. A warning appears if the standoff point is beyond the link range limit from this ground station; it does not stop you from continuing.\n\n" +
                           "4. Press \"Set Standoff\". The aircraft will fly to the standoff point and orbit it. You can reopen the panel and re-apply new values while it holds; it will move to the new point.\n\n" +
                           "If the app says the standoff point is too far, either move the target closer to the aircraft or increase Application Settings → General → STRATUM Operational Limits → \"Max Standoff Distance\".")
            }

            // ----- How to change flight modes ----------------------------
            QGCLabel {
                text:            qsTr("How to change flight modes")
                font.pointSize:  ScreenTools.largeFontPointSize
                font.bold:       true
            }
            QGCLabel {
                Layout.fillWidth: true
                Layout.leftMargin: _stepIndent
                wrapMode:         Text.WordWrap
                text: qsTr("1. At the top of the Fly view you will see the current flight mode name (for example, \"Hold\").\n\n" +
                           "2. Tap the flight mode name. A list of available modes will open.\n\n" +
                           "3. Press and hold the mode you want. The button fills up while you hold, then the aircraft switches to that mode.\n\n" +
                           "The everyday modes are:\n" +
                           "   • Takeoff — climb straight up and hover.\n" +
                           "   • Land — descend slowly and land where it is.\n" +
                           "   • Safe Recovery — fly back to the launch point.\n" +
                           "   • Standoff — hold at the standoff point (see above).\n" +
                           "   • Engagement — start the engagement run against the target.\n" +
                           "   • Hold — stop and stay in place.\n" +
                           "   • Abort — safely break off and retreat to a safe point.")
            }

            // ----- How to use the camera view ----------------------------
            QGCLabel {
                text:            qsTr("How to use the camera view")
                font.pointSize:  ScreenTools.largeFontPointSize
                font.bold:       true
            }
            QGCLabel {
                Layout.fillWidth: true
                Layout.leftMargin: _stepIndent
                wrapMode:         Text.WordWrap
                text: qsTr("1. The camera view is the small window in the corner. Tap the swap icon to make it the main view.\n\n" +
                           "2. Tap once on the video where you see the target — a green box will appear and the aircraft will start following that spot.\n\n" +
                           "3. If the target moves and the box no longer sits on it, tap the target again to correct.\n\n" +
                           "4. To draw a box around a wider area, click and drag on the video instead of tapping.")
            }

            // ----- If something goes wrong -------------------------------
            QGCLabel {
                text:            qsTr("If something goes wrong")
                font.pointSize:  ScreenTools.largeFontPointSize
                font.bold:       true
            }
            QGCLabel {
                Layout.fillWidth: true
                Layout.leftMargin: _stepIndent
                wrapMode:         Text.WordWrap
                text: qsTr("• If the aircraft does not respond, first switch to \"Hold\" mode so it stays in place while you check.\n\n" +
                           "• If you need to break off immediately, press \"Abort\". The aircraft will fly to a safe recovery point.\n\n" +
                           "• If the battery gets low, switch to \"Safe Recovery\" to return to the launch point.")
            }
        }
    }
}
