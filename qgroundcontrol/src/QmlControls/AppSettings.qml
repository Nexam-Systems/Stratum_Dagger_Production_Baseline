import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings

Rectangle {
    id:     settingsView
    color:  qgcPal.window
    z:      QGroundControl.zOrderTopMost

    readonly property real _defaultTextHeight:  ScreenTools.defaultFontPixelHeight
    readonly property real _defaultTextWidth:   ScreenTools.defaultFontPixelWidth
    readonly property real _horizontalMargin:   _defaultTextWidth / 2
    readonly property real _verticalMargin:     _defaultTextHeight / 2

    property bool _first: true
    property bool _commingFromRIDSettings: false
    property int  _selectedPageIndex: -1
    property int  _selectedSectionIndex: -1
    property var  _expandedPages: ({})  // pageIndex -> bool
    property int  _expandedRevision: 0  // bumped to trigger re-evaluation
    property string _searchQuery: ""

    // STRATUM: settings top-row connection state.
    readonly property var  _activeVehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _vehicleConnected: _activeVehicle && _activeVehicle.vehicleLinkManager
                                              && !_activeVehicle.vehicleLinkManager.communicationLost

    function _setExpanded(pageIndex, value) {
        _expandedPages[pageIndex] = value
        _expandedRevision++
    }

    function _isExpanded(pageIndex) {
        void _expandedRevision  // create binding dependency
        return !!_expandedPages[pageIndex]
    }

    // Search: returns array of matching section indices for a page, or empty if no match
    function _matchingSections(pageIndex) {
        var query = _searchQuery.toLowerCase().trim()
        if (query === "") return []  // empty = no filtering

        var entry = settingsPagesModel.get(pageIndex)
        if (!entry) return []

        // Check English search terms
        var termsStr = entry.searchTerms
        var matches = []
        var matched = {}
        if (termsStr && termsStr !== "") {
            try {
                var terms = JSON.parse(termsStr)
                for (var i = 0; i < terms.length; i++) {
                    if (terms[i].terms.indexOf(query) !== -1) {
                        matched[terms[i].section] = true
                        matches.push(terms[i].section)
                    }
                }
            } catch(e) { console.warn("AppSettings: JSON parse error in searchTerms:", e) }
        }

        // Check translatable terms (translated at runtime)
        var trStr = entry.translatableTerms
        if (trStr && trStr !== "") {
            try {
                var trTerms = JSON.parse(trStr)
                for (var j = 0; j < trTerms.length; j++) {
                    if (matched[trTerms[j].section]) continue
                    var ctx = trTerms[j].context
                    var tList = trTerms[j].terms
                    for (var k = 0; k < tList.length; k++) {
                        if (qsTranslate(ctx, tList[k]).toLowerCase().indexOf(query) !== -1) {
                            matched[trTerms[j].section] = true
                            matches.push(trTerms[j].section)
                            break
                        }
                    }
                }
            } catch(e) { console.warn("AppSettings: JSON parse error in translatableTerms:", e) }
        }

        return matches
    }

    // Does this page have any search matches? (or is search empty = show all)
    function _pageMatchesSearch(pageIndex) {
        if (_searchQuery.trim() === "") return true
        return _matchingSections(pageIndex).length > 0
    }

    function _navigateTo(pageIndex, sectionIndex) {
        var entry = settingsPagesModel.get(pageIndex)
        if (!entry || entry.name === "Divider") return

        var url = entry.url
        _selectedSectionIndex = sectionIndex

        if (_selectedPageIndex !== pageIndex) {
            _selectedPageIndex = pageIndex
            rightPanel.source = url
        }

        // Apply section filter after the page is loaded
        if (rightPanel.item && typeof rightPanel.item.sectionFilter !== "undefined") {
            rightPanel.item.sectionFilter = sectionIndex
        }
    }

    function showSettingsPage(settingsPage) {
        for (var i = 0; i < settingsPagesModel.count; i++) {
            var entry = settingsPagesModel.get(i)
            if (entry && entry.name === settingsPage) {
                _navigateTo(i, -1)
                break
            }
        }
    }

    // This need to block click event leakage to underlying map.
    DeadMouseArea {
        anchors.fill: parent
    }

    QGCPalette { id: qgcPal }

    Component.onCompleted: {
        // Find and select the default page
        var targetUrl = globals.commingFromRIDIndicator
            ? "qrc:/qml/QGroundControl/AppSettings/RemoteIDSettings.qml"
            : "qrc:/qml/QGroundControl/AppSettings/GeneralSettings.qml"
        globals.commingFromRIDIndicator = false

        for (var i = 0; i < settingsPagesModel.count; i++) {
            var entry = settingsPagesModel.get(i)
            if (entry && entry.url === targetUrl) {
                _navigateTo(i, -1)
                break
            }
        }
    }

    Connections {
        target: rightPanel
        function onLoaded() {
            if (rightPanel.item && typeof rightPanel.item.sectionFilter !== "undefined") {
                rightPanel.item.sectionFilter = _selectedSectionIndex
            }
        }
    }

    SettingsPagesModel { id: settingsPagesModel }

    ColumnLayout {
        id:                 leftPanel
        anchors.topMargin:  _verticalMargin
        anchors.top:        parent.top
        anchors.leftMargin: _horizontalMargin
        anchors.rightMargin:_horizontalMargin
        anchors.left:       parent.left
        anchors.right:      parent.right
        spacing:            _verticalMargin / 2

        // STRATUM #64: settings top row — branding/version, connection status, actions.
        RowLayout {
            Layout.fillWidth: true
            spacing:          _defaultTextWidth

            QGCColoredImage {
                source:                 "qrc:/res/QGCLogoWhite.svg"
                fillMode:               Image.PreserveAspectFit
                color:                  qgcPal.text
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 1.5
                Layout.preferredWidth:  ScreenTools.defaultFontPixelHeight * 1.5
            }
            QGCLabel {
                text:           QGroundControl.appName + "  " + QGroundControl.stratumVersion
                font.bold:      true
                font.pointSize: ScreenTools.mediumFontPointSize
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredWidth:  ScreenTools.defaultFontPixelHeight * 0.6
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.6
                radius:                 width / 2
                Layout.alignment:       Qt.AlignVCenter
                color: !settingsView._activeVehicle ? "#808080"
                       : (settingsView._vehicleConnected ? qgcPal.colorGreen : qgcPal.colorOrange)
            }
            QGCLabel {
                Layout.alignment: Qt.AlignVCenter
                text: !settingsView._activeVehicle ? qsTr("No vehicle")
                      : (settingsView._vehicleConnected ? qsTr("Connected") : qsTr("Comm lost"))
            }
            QGCButton {
                text: qsTr("Reset to Defaults")
                onClicked: QGroundControl.showMessageDialog(settingsView, qsTr("Reset to Defaults"),
                    qsTr("All settings will be reset to defaults the next time %1 is started. Continue?").arg(QGroundControl.appName),
                    Dialog.Yes | Dialog.No,
                    function() { QGroundControl.settingsManager.appSettings.clearSettingsNextBoot.rawValue = true })
            }
            QGCButton {
                text:    qsTr("Save Settings")
                primary: true
                onClicked: {
                    if (QGroundControl.videoManager) QGroundControl.videoManager.syncSettings()
                    QGroundControl.showMessageDialog(settingsView, qsTr("Save Settings"), qsTr("All settings saved."))
                }
            }
        }

        QGCTextField {
            id:                 searchField
            Layout.fillWidth:   true
            placeholderText:    qsTr("Search settings...")

            onTextChanged: {
                settingsView._searchQuery = text
            }
        }

        QGCFlickable {
            id:                 buttonList
            objectName:         "settings_buttonList"
            Layout.fillWidth:   true
            Layout.preferredHeight: tabRow.implicitHeight
            contentWidth:       tabRow.implicitWidth
            contentHeight:      tabRow.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            clip:               true

            Row {
                id:         tabRow
                spacing:    _defaultTextWidth / 2

                Repeater {
                    id:     buttonRepeater
                    model:  settingsPagesModel

                    Button {
                        id:     tabButton

                        required property int index
                        required property var model

                        property string pageName:    model.name ?? ""
                        property var    pageVisible: model.pageVisible ?? function() { return true }
                        property bool   isSelected:  settingsView._selectedPageIndex === index

                        visible: pageName !== "Divider" && pageVisible()
                               && (settingsView._searchQuery.trim() === "" || settingsView._pageMatchesSearch(index))
                        height:       ScreenTools.defaultFontPixelHeight * 2.2
                        leftPadding:  ScreenTools.defaultFontPixelWidth * 1.5
                        rightPadding: ScreenTools.defaultFontPixelWidth * 1.5
                        hoverEnabled: !ScreenTools.isMobile

                        background: Rectangle {
                            color: tabButton.isSelected ? qgcPal.windowShade
                                   : (tabButton.hovered ? qgcPal.windowShadeDark : "transparent")
                            Rectangle {
                                anchors.left:   parent.left
                                anchors.right:  parent.right
                                anchors.bottom: parent.bottom
                                height:         ScreenTools.defaultFontPixelHeight * 0.18
                                visible:        tabButton.isSelected
                                color:          qgcPal.brandingPurple
                            }
                        }
                        contentItem: QGCLabel {
                            text:                tabButton.pageName.toUpperCase()
                            color:               tabButton.isSelected ? qgcPal.text : qgcPal.buttonText
                            font.bold:           tabButton.isSelected
                            verticalAlignment:   Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: {
                            if (mainWindow.allowViewSwitch()) {
                                settingsView._navigateTo(index, -1)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id:                     divider
        anchors.topMargin:      _verticalMargin / 2
        anchors.leftMargin:     _horizontalMargin
        anchors.rightMargin:    _horizontalMargin
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.top:            leftPanel.bottom
        height:                 1
        color:                  qgcPal.windowShade
    }

    //-- Panel Contents
    Loader {
        id:                     rightPanel
        objectName:             "settings_rightPanel"
        anchors.leftMargin:     _horizontalMargin
        anchors.rightMargin:    _horizontalMargin
        anchors.topMargin:      _verticalMargin
        anchors.bottomMargin:   _verticalMargin
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.top:            divider.bottom
        anchors.bottom:         parent.bottom
    }
}
