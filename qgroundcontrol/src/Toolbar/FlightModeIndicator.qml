import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// STRATUM: read-only flight-mode status display for the fly-view ribbon. The
// interactive mode picker was relocated to the left command strip
// (FlyViewFlightModeAction). This shows the vehicle's current mode plus a
// "TRACKING Active" pill when the companion tracker is running.
Item {
    id:                     control
    Layout.preferredWidth:  mainLayout.width + ScreenTools.defaultFontPixelWidth
    Layout.preferredHeight: mainLayout.height
    height:                 parent ? parent.height : mainLayout.height
    width:                  mainLayout.width + ScreenTools.defaultFontPixelWidth

    property bool   showIndicator:      true
    property bool   waitForParameters:  false
    property color  ribbonTextColor:    qgcPal.text

    property real fontPointSize:    ScreenTools.largeFontPointSize
    property var  activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle

    property bool _isVTOL:          activeVehicle ? activeVehicle.vtol : false
    property bool _vtolInFWDFlight: activeVehicle ? activeVehicle.vtolInFwdFlight : false

    // "TRACKING Active" cue driven by NEXAM_TARGET_TRACK (42004). Dagger-only.
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
            // PX4's "Position" (POSCTL) is presented as "Manual" throughout the UI.
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
            color:                  ribbonTextColor
            visible:                _isVTOL
        }

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
    }
}
