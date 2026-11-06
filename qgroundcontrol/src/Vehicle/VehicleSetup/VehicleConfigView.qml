import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

Rectangle {
    id:             vehicleConfigView
    objectName:     "vehicleConfig_root"
    color:          qgcPal.window
    z:      QGroundControl.zOrderTopMost

    // This need to block click event leakage to underlying map.
    DeadMouseArea {
        anchors.fill: parent
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    readonly property real      _defaultTextHeight: ScreenTools.defaultFontPixelHeight
    readonly property real      _defaultTextWidth:  ScreenTools.defaultFontPixelWidth
    readonly property real      _horizontalMargin:  _defaultTextWidth / 2
    readonly property real      _verticalMargin:    _defaultTextHeight / 2
    readonly property real      _buttonWidth:       _defaultTextWidth * 18
    readonly property string    _armedVehicleText:  qsTr("This operation cannot be performed while the vehicle is armed.")

    property var    _activeVehicle:                 QGroundControl.multiVehicleManager.activeVehicle
    property bool   _vehicleArmed:                  _activeVehicle ? _activeVehicle.armed : false
    property string _messagePanelText:              qsTr("missing message panel text")
    property bool   _fullParameterVehicleAvailable: _activeVehicle && QGroundControl.multiVehicleManager.parameterReadyVehicleAvailable && !_activeVehicle.parameterManager.missingParameters
    property var    _corePlugin:                    QGroundControl.corePlugin

    // Navigation state
    property int    _selectedComponentIndex: -1     // -1 = summary or special button
    property int    _selectedSectionIndex:   -1
    property string _selectedSpecial:        ""     // "summary", "parameters", "firmware", "opticalflow"
    property bool   _showingPrereqMessage:   false  // Panel area shows prerequisite message instead of selected component
    property string _searchQuery:            ""
    // STRATUM: focus one component (e.g. Joystick) and hide navigation so the drawer
    // only exposes that one page. Set by showFocusedVehicleComponentPanel() and cleared
    // by the summary/parameters/panel entry points.
    property bool   _focusedMode:            false

    /// Translate a section name using the component's JSON filename as context.
    /// Falls back to the raw name when no vehicleConfigJson is set.
    function _translateSection(component, name) {
        var context = _translationContext(component)
        if (!context) return name
        return qsTranslate(context, name)
    }

    /// Get the section name for a sidebar entry.
    function _sectionName(compIndex, sectionIndex) {
        if (sectionIndex < 0 || !_fullParameterVehicleAvailable) return ""
        var components = _activeVehicle.autopilotPlugin.vehicleComponents
        if (compIndex < 0 || compIndex >= components.length) return ""
        var secs = components[compIndex].sections
        if (sectionIndex < secs.length) return secs[sectionIndex]
        return ""
    }

    /// Extract the translation context (JSON filename) from a component.
    function _translationContext(component) {
        if (!component || !component.vehicleConfigJson) return ""
        var path = component.vehicleConfigJson.toString()
        var slash = path.lastIndexOf("/")
        return slash >= 0 ? path.substring(slash + 1) : path
    }

    function _componentMatchesSearch(component) {
        if (_searchQuery.trim() === "") return true
        var query = _searchQuery.toLowerCase().trim()
        if (component.name.toLowerCase().indexOf(query) !== -1) return true
        var context = _translationContext(component)
        var secs = component.sections
        if (secs) {
            for (var i = 0; i < secs.length; i++) {
                if (secs[i].toLowerCase().indexOf(query) !== -1) return true
                if (context && qsTranslate(context, secs[i]).toLowerCase().indexOf(query) !== -1) return true
            }
        }
        var keywords = component.sectionKeywords
        if (keywords) {
            for (var key in keywords) {
                var terms = keywords[key]
                for (var j = 0; j < terms.length; j++) {
                    if (terms[j].toLowerCase().indexOf(query) !== -1) return true
                    if (context && qsTranslate(context, terms[j]).toLowerCase().indexOf(query) !== -1) return true
                }
            }
        }
        return false
    }

    function _sectionMatchesSearch(component, sectionName) {
        if (_searchQuery.trim() === "") return true
        var query = _searchQuery.toLowerCase().trim()
        if (sectionName.toLowerCase().indexOf(query) !== -1) return true
        var context = _translationContext(component)
        if (context && qsTranslate(context, sectionName).toLowerCase().indexOf(query) !== -1) return true
        var keywords = component.sectionKeywords
        if (keywords && keywords[sectionName]) {
            var terms = keywords[sectionName]
            for (var i = 0; i < terms.length; i++) {
                if (terms[i].toLowerCase().indexOf(query) !== -1) return true
                if (context && qsTranslate(context, terms[i]).toLowerCase().indexOf(query) !== -1) return true
            }
        }
        return false
    }

    function showSummaryPanel() {
        if (mainWindow.allowViewSwitch()) {
            _showSummaryPanel()
        }
    }

    function _showSummaryPanel() {
        _selectedSpecial = "summary"
        _selectedComponentIndex = -1
        _selectedSectionIndex = -1
        _focusedMode = false
        if (_fullParameterVehicleAvailable) {
            if (_activeVehicle.autopilotPlugin.vehicleComponents.length === 0) {
                panelLoader.setSourceComponent(noComponentsVehicleSummaryComponent)
            } else {
                panelLoader.setSource("qrc:/qml/QGroundControl/VehicleSetup/VehicleSummary.qml")
            }
        } else if (QGroundControl.multiVehicleManager.parameterReadyVehicleAvailable) {
            panelLoader.setSourceComponent(missingParametersVehicleSummaryComponent)
        } else {
            panelLoader.setSourceComponent(disconnectedVehicleAndParamsSummaryComponent)
        }
    }

    function showPanel(specialName, qmlSource) {
        if (mainWindow.allowViewSwitch()) {
            _selectedSpecial = specialName
            _selectedComponentIndex = -1
            _selectedSectionIndex = -1
            _focusedMode = false
            panelLoader.setSource(qmlSource)
        }
    }

    function _navigateToComponent(compIndex, sectionIndex) {
        if (!mainWindow.allowViewSwitch()) return
        if (!_fullParameterVehicleAvailable) return

        var components = _activeVehicle.autopilotPlugin.vehicleComponents
        if (compIndex < 0 || compIndex >= components.length) return
        var vehicleComponent = components[compIndex]

        _selectedSpecial = ""

        // If component opts in and root was clicked, auto-select first section
        if (sectionIndex < 0 && vehicleComponent.showFirstSectionOnRootClick && vehicleComponent.sections.length > 0) {
            sectionIndex = 0
        }
        _selectedSectionIndex = sectionIndex

        var autopilotPlugin = _activeVehicle.autopilotPlugin
        var prereq = autopilotPlugin.prerequisiteSetup(vehicleComponent)
        if (prereq !== "") {
            // Selection state still updates so the tree expands and highlights
            // normally; only the panel area shows the prerequisite message
            _selectedComponentIndex = compIndex
            _showingPrereqMessage = true
            _messagePanelText = qsTr("%1 setup must be completed prior to %2 setup.").arg(prereq).arg(vehicleComponent.name)
            panelLoader.setSourceComponent(messagePanelComponent)
            return
        }

        if (_selectedComponentIndex !== compIndex || _showingPrereqMessage) {
            _selectedComponentIndex = compIndex
            _showingPrereqMessage = false
            panelLoader.setSource(vehicleComponent.setupSource, vehicleComponent)
        }

        // Apply section filter
        if (panelLoader.item && typeof panelLoader.item.sectionNameFilter !== "undefined") {
            panelLoader.item.sectionNameFilter = _sectionName(compIndex, sectionIndex)
        }
    }

    function showParametersPanel() {
        showPanel("parameters", "qrc:/qml/QGroundControl/VehicleSetup/SetupParameterEditor.qml")
    }

    function showVehicleComponentPanel(vehicleComponent) {
        if (!mainWindow.allowViewSwitch()) return
        if (!_fullParameterVehicleAvailable) return

        var components = _activeVehicle.autopilotPlugin.vehicleComponents
        for (var i = 0; i < components.length; i++) {
            if (components[i] === vehicleComponent) {
                _navigateToComponent(i, -1)
                return
            }
        }
    }

    // STRATUM: opens a single vehicle-component page and hides the sidebar so the
    // drawer only exposes that one page (e.g. "Configure Joystick" from the NX menu).
    function showFocusedVehicleComponentPanel(vehicleComponent) {
        _focusedMode = true
        showVehicleComponentPanel(vehicleComponent)
    }

    Component.onCompleted: _showSummaryPanel()

    Connections {
        target: QGroundControl.corePlugin
        function onShowAdvancedUIChanged(showAdvancedUI) {
            if (!showAdvancedUI) {
                _showSummaryPanel()
            }
        }
    }

    Connections {
        target: QGroundControl.multiVehicleManager
        function onParameterReadyVehicleAvailableChanged(parametersReady) {
            if (parametersReady || _selectedSpecial === "summary" || _selectedSpecial !== "firmware") {
                _showSummaryPanel()
            }
        }
    }

    Connections {
        target: panelLoader
        function onLoaded() {
            if (panelLoader.item && typeof panelLoader.item.sectionNameFilter !== "undefined") {
                panelLoader.item.sectionNameFilter = _sectionName(_selectedComponentIndex, _selectedSectionIndex)
            }
        }
    }

    Component {
        id: noComponentsVehicleSummaryComponent
        Rectangle {
            color: qgcPal.windowShade
            QGCLabel {
                anchors.margins:        _defaultTextWidth * 2
                anchors.fill:           parent
                verticalAlignment:      Text.AlignVCenter
                horizontalAlignment:    Text.AlignHCenter
                wrapMode:               Text.WordWrap
                font.pointSize:         ScreenTools.mediumFontPointSize
                text:                   qsTr("%1 does not currently support configuration of your vehicle. ").arg(QGroundControl.appName) +
                                        "If your vehicle is already configured you can still Fly."
            }
        }
    }

    Component {
        id: disconnectedVehicleAndParamsSummaryComponent
        Rectangle {
            id: disconnectedRect
            color: qgcPal.windowShade
            Column {
                anchors.centerIn:   parent
                spacing:            ScreenTools.defaultFontPixelHeight
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:              disconnectedRect.width - _defaultTextWidth * 4
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode:           Text.WordWrap
                    font.pointSize:     ScreenTools.largeFontPointSize
                    text:               !_activeVehicle
                                            ? qsTr("Vehicle configuration pages will display after you connect your vehicle and parameters have been downloaded.")
                                            : (_activeVehicle.parameterManager.parameterDownloadSkipped
                                                ? qsTr("Parameter download was skipped because the vehicle is flying. Configuration pages will be available after parameters are downloaded.")
                                                : qsTr("Waiting for vehicle parameters to download…"))
                }
                QGCButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:       qsTr("Download Parameters")
                    visible:    _activeVehicle && _activeVehicle.parameterManager.parameterDownloadSkipped
                    enabled:    _activeVehicle && _activeVehicle.parameterManager.parameterDownloadSkipped && _activeVehicle.parameterManager.loadProgress === 0
                    onClicked:  _activeVehicle.parameterManager.refreshAllParameters()
                }
            }
        }
    }

    Component {
        id: missingParametersVehicleSummaryComponent

        Rectangle {
            color: qgcPal.windowShade

            QGCLabel {
                anchors.margins:        _defaultTextWidth * 2
                anchors.fill:           parent
                verticalAlignment:      Text.AlignVCenter
                horizontalAlignment:    Text.AlignHCenter
                wrapMode:               Text.WordWrap
                font.pointSize:         ScreenTools.mediumFontPointSize
                text:                   qsTr("Vehicle did not return the full parameter list. ") +
                                        qsTr("As a result, the configuration pages are not available.")
            }
        }
    }

    Component {
        id: messagePanelComponent

        Item {
            objectName: "vehicleConfig_messagePanel"

            QGCLabel {
                anchors.margins:        _defaultTextWidth * 2
                anchors.fill:           parent
                verticalAlignment:      Text.AlignVCenter
                horizontalAlignment:    Text.AlignHCenter
                wrapMode:               Text.WordWrap
                font.pointSize:         ScreenTools.mediumFontPointSize
                text:                   _messagePanelText
            }
        }
    }

    ColumnLayout {
        id:                 navigationPanel
        visible:            !_focusedMode
        anchors.topMargin:  _verticalMargin
        anchors.top:        parent.top
        anchors.leftMargin: _horizontalMargin
        anchors.rightMargin: _horizontalMargin
        anchors.left:       parent.left
        anchors.right:      parent.right
        spacing:            _verticalMargin / 2

        QGCTextField {
            id:                 searchField
            Layout.fillWidth:   true
            placeholderText:    qsTr("Search configuration...")
            visible:            _fullParameterVehicleAvailable

            onTextChanged: {
                vehicleConfigView._searchQuery = text
            }
        }

        ToolTabBar {
            id:                 componentTabs
            objectName:         "vehicleConfig_sidebarFlickable"
            Layout.fillWidth:   true
            Layout.preferredHeight: implicitHeight

            // Summary button
            ToolTabButton {
                tabBar:             componentTabs
                id:                 summaryButton
                objectName:         "vehicleConfig_summary"
                checked:            vehicleConfigView._selectedSpecial === "summary"
                text:               qsTr("Summary")
                visible:            vehicleConfigView._searchQuery.trim() === ""

                onClicked: showSummaryPanel()
            }

            Repeater {
                id:     componentRepeater
                model:  _fullParameterVehicleAvailable ? _activeVehicle.autopilotPlugin.vehicleComponents : 0

                ToolTabButton {
                    id:             componentTab
                    tabBar:         componentTabs

                    required property int index
                    required property var modelData

                    property var    comp:           modelData
                    property string compName:       comp ? comp.name : ""
                    objectName: "vehicleConfig_comp_" + compName.replace(/ /g, "")
                    text: compName
                    checked: vehicleConfigView._selectedComponentIndex === index && vehicleConfigView._selectedSpecial === ""
                    setupComplete: comp ? comp.setupComplete : true
                    visible: comp && comp.setupSource.toString() !== "" && vehicleConfigView._componentMatchesSearch(comp)
                    onClicked: vehicleConfigView._navigateToComponent(index, -1)
                }
            }

            // Optical Flow (special)
            ToolTabButton {
                tabBar:             componentTabs
                visible:            _activeVehicle ? _activeVehicle.flowImageIndex > 0 : false
                text:               qsTr("Optical Flow")
                checked:            vehicleConfigView._selectedSpecial === "opticalflow"
                onClicked:          showPanel("opticalflow", "qrc:/qml/QGroundControl/VehicleSetup/OpticalFlowSensor.qml")
            }

            ToolTabButton {
                tabBar:             componentTabs
                id:                 parametersButton
                visible:            QGroundControl.multiVehicleManager.parameterReadyVehicleAvailable &&
                                    _activeVehicle && !_activeVehicle.usingHighLatencyLink &&
                                    _corePlugin.showAdvancedUI &&
                                    vehicleConfigView._searchQuery.trim() === ""
                text:               qsTr("Parameters")
                checked:            vehicleConfigView._selectedSpecial === "parameters"
                onClicked:          showPanel("parameters", "qrc:/qml/QGroundControl/VehicleSetup/SetupParameterEditor.qml")
            }

            ToolTabButton {
                tabBar:             componentTabs
                id:                 firmwareButton
                visible:            !ScreenTools.isMobile && _corePlugin.options.showFirmwareUpgrade &&
                                    vehicleConfigView._searchQuery.trim() === ""
                text:               qsTr("Firmware")
                checked:            vehicleConfigView._selectedSpecial === "firmware"

                onClicked: showPanel("firmware", "qrc:/qml/QGroundControl/VehicleSetup/FirmwareUpgrade.qml")
            }
        }

        ToolTabBar {
            id: sectionTabs
            objectName: "vehicleConfig_sectionTabs"
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            visible: component && component.sections.length > 1

            readonly property var component: _fullParameterVehicleAvailable && _selectedComponentIndex >= 0
                                             ? _activeVehicle.autopilotPlugin.vehicleComponents[_selectedComponentIndex] : null

            Repeater {
                model: sectionTabs.component ? sectionTabs.component.sections : []

                ToolTabButton {
                    id: sectionButton
                    required property int index
                    required property string modelData
                    tabBar: sectionTabs
                    objectName: "vehicleConfig_section_" + modelData.replace(/ /g, "")
                    text: vehicleConfigView._translateSection(sectionTabs.component, modelData)
                    checked: vehicleConfigView._selectedSectionIndex === index
                    setupComplete: {
                        var comp = sectionTabs.component
                        if (!comp) return true
                        // This function reads Facts internally; setupComplete provides the change notification.
                        void comp.setupComplete
                        return typeof comp.sectionSetupComplete === "function" ? comp.sectionSetupComplete(modelData) : true
                    }
                    visible: sectionTabs.component
                             && vehicleConfigView._sectionMatchesSearch(sectionTabs.component, modelData)
                             && (!panelLoader.item || typeof panelLoader.item.sectionVisible !== "function"
                                 || panelLoader.item.sectionVisible(modelData))
                    onClicked: vehicleConfigView._navigateToComponent(vehicleConfigView._selectedComponentIndex, index)
                }
            }
        }
    }

    Rectangle {
        id:                     divider
        anchors.topMargin:      _verticalMargin
        anchors.leftMargin:     _horizontalMargin
        anchors.rightMargin:    _horizontalMargin
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.top:            navigationPanel.bottom
        height:                 1
        visible:                !_focusedMode
        color:                  qgcPal.windowShade
    }

    Loader {
        id:                     panelLoader
        objectName:             "vehicleConfig_panelLoader"
        anchors.topMargin:      _verticalMargin
        anchors.bottomMargin:   _verticalMargin
        anchors.leftMargin:     _horizontalMargin
        anchors.rightMargin:    _horizontalMargin
        anchors.left:           parent.left
        anchors.right:          parent.right
        anchors.top:            _focusedMode ? parent.top : divider.bottom
        anchors.bottom:         parent.bottom

        function setSource(source, vehicleComponent) {
            panelLoader.source = ""
            panelLoader.vehicleComponent = vehicleComponent
            panelLoader.source = source
        }

        function setSourceComponent(sourceComponent, vehicleComponent) {
            panelLoader.sourceComponent = undefined
            panelLoader.vehicleComponent = vehicleComponent
            panelLoader.sourceComponent = sourceComponent
        }

        property var vehicleComponent
    }
}
