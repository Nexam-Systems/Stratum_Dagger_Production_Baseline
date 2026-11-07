import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.AppSettings

Rectangle {
    id:     settingsView
    color:  settingsTheme.background
    z:      QGroundControl.zOrderTopMost

    readonly property real _defaultTextHeight:  ScreenTools.defaultFontPixelHeight
    readonly property real _defaultTextWidth:   ScreenTools.defaultFontPixelWidth
    readonly property real _horizontalMargin:   _defaultTextWidth * 4
    readonly property real _verticalMargin:     _defaultTextHeight / 2

    property bool _first: true
    property bool _commingFromRIDSettings: false
    property int  _selectedPageIndex: -1
    property int  _selectedSectionIndex: -1
    property var  _expandedPages: ({})  // pageIndex -> bool
    property int  _expandedRevision: 0  // bumped to trigger re-evaluation
    property string _searchQuery: ""

    // The internal applicationName carries a " Daily" suffix on daily builds to isolate the
    // settings space; strip it so the settings header shows the clean product name.
    readonly property string headerTitle: {
        var n = QGroundControl.appName
        return n.endsWith(" Daily") ? n.slice(0, n.length - 6) : n
    }

    property Component headerActions: RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth

        SettingsActionButton {
            objectName: "settings_reset"
            text: (settingsView.width < ScreenTools.defaultFontPixelWidth * 100 ? qsTr("Reset") : qsTr("Reset to Defaults")).toUpperCase()
            iconSource: "/InstrumentValueIcons/reload.svg"
            onClicked: QGroundControl.showMessageDialog(settingsView, qsTr("Reset to Defaults"),
                qsTr("All settings will be reset to defaults the next time %1 is started. Continue?").arg(QGroundControl.appName),
                Dialog.Yes | Dialog.No,
                function() { QGroundControl.settingsManager.appSettings.clearSettingsNextBoot.rawValue = true })
        }
        SettingsActionButton {
            objectName: "settings_save"
            text: (settingsView.width < ScreenTools.defaultFontPixelWidth * 100 ? qsTr("Save") : qsTr("Save Settings")).toUpperCase()
            iconSource: "/InstrumentValueIcons/save-disk.svg"
            primary: true
            onClicked: {
                settingsView.forceActiveFocus()
                if (QGroundControl.videoManager) QGroundControl.videoManager.syncSettings()
                QGroundControl.showMessageDialog(settingsView, qsTr("Save Settings"), qsTr("All settings saved."))
            }
        }
    }

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
    SettingsTheme { id: settingsTheme }

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

        ToolTabBar {
            id:                 buttonList
            objectName:         "settings_buttonList"
            Layout.fillWidth:   true
            Layout.preferredHeight: implicitHeight
            equalWidthTabs: true

            Repeater {
                id:     buttonRepeater
                model:  settingsPagesModel

                ToolTabButton {
                    id:     tabButton
                    tabBar: buttonList
                    objectName: "settingsButton_" + pageName

                    required property int index
                    required property var model

                    property string pageName:    model.name ?? ""
                    property var    pageVisible: model.pageVisible ?? function() { return true }
                    property bool   isSelected:  settingsView._selectedPageIndex === index

                    visible: pageName !== "Divider" && pageVisible()
                           && (settingsView._searchQuery.trim() === "" || settingsView._pageMatchesSearch(index))
                    text: pageName
                    icon.source: model.nameKey === "General" ? "/InstrumentValueIcons/cog.svg" : (model.iconUrl ?? "")
                    checked: isSelected
                    onClicked: {
                        if (mainWindow.allowViewSwitch()) {
                            settingsView._navigateTo(index, -1)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 2
            color: settingsTheme.accent
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: _verticalMargin
            Layout.bottomMargin: _verticalMargin
            spacing: _defaultTextWidth * 2

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: _verticalMargin / 2

                QGCLabel {
                    Layout.fillWidth: true
                    text: rightPanel.item && rightPanel.item.pageTitle
                          ? rightPanel.item.pageTitle
                          : (_selectedPageIndex >= 0 ? settingsPagesModel.get(_selectedPageIndex).name : "")
                    color: settingsTheme.text
                    font.pointSize: ScreenTools.largeFontPointSize
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                QGCLabel {
                    Layout.fillWidth: true
                    text: rightPanel.item && rightPanel.item.pageDescription ? rightPanel.item.pageDescription : ""
                    visible: text !== ""
                    color: settingsTheme.secondaryText
                    wrapMode: Text.WordWrap
                }
            }

            QGCTextField {
                id: searchField
                Layout.preferredWidth: Math.min(settingsView.width * 0.3, _defaultTextWidth * 25)
                Layout.minimumWidth: 0
                placeholderText: qsTr("Search settings...")
                onTextChanged: settingsView._searchQuery = text
            }
        }
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
        anchors.top:            leftPanel.bottom
        anchors.bottom:         parent.bottom
    }
}
