/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/


import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.FactSystem
import QGroundControl.FactControls
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.MultiVehicleManager
import QGroundControl.Palette
import QGroundControl.Controllers
import QGroundControl.Viewer3D

SettingsPage {
    property var    _settingsManager:                       QGroundControl.settingsManager
    property var    _flyViewSettings:                       _settingsManager.flyViewSettings
    property var    _mavlinkActionsSettings:                _settingsManager.mavlinkActionsSettings
    property Fact   _virtualJoystick:                       _settingsManager.appSettings.virtualJoystick
    property Fact   _virtualJoystickAutoCenterThrottle:     _settingsManager.appSettings.virtualJoystickAutoCenterThrottle
    property Fact   _virtualJoystickLeftHandedMode:         _settingsManager.appSettings.virtualJoystickLeftHandedMode
    property Fact   _enableMultiVehiclePanel:               _settingsManager.appSettings.enableMultiVehiclePanel
    property Fact   _showAdditionalIndicatorsCompass:       _flyViewSettings.showAdditionalIndicatorsCompass
    property Fact   _lockNoseUpCompass:                     _flyViewSettings.lockNoseUpCompass
    property Fact   _guidedMinimumAltitude:                 _flyViewSettings.guidedMinimumAltitude
    property Fact   _guidedMaximumAltitude:                 _flyViewSettings.guidedMaximumAltitude
    property Fact   _maxGoToLocationDistance:               _flyViewSettings.maxGoToLocationDistance
    property Fact   _forwardFlightGoToLocationLoiterRad:    _flyViewSettings.forwardFlightGoToLocationLoiterRad
    property Fact   _goToLocationRequiresConfirmInGuided:   _flyViewSettings.goToLocationRequiresConfirmInGuided
    property var    _viewer3DSettings:                      _settingsManager.viewer3DSettings
    property Fact   _viewer3DEnabled:                       _viewer3DSettings.enabled
    property Fact   _viewer3DOsmFilePath:                   _viewer3DSettings.osmFilePath
    property Fact   _viewer3DBuildingLevelHeight:           _viewer3DSettings.buildingLevelHeight
    property Fact   _viewer3DAltitudeBias:                  _viewer3DSettings.altitudeBias

    QGCFileDialogController { id: fileController }

    function mavlinkActionList() {
        var fileModel = fileController.getFiles(_settingsManager.appSettings.mavlinkActionsSavePath, "*.json")
        fileModel.unshift(qsTr("<None>"))
        return fileModel
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("General")

        FactCheckBoxSlider {
            id:                 useCheckList
            Layout.fillWidth:   true
            text:               qsTr("Use Preflight Checklist")
            fact:               _useChecklist
            visible:            _useChecklist.visible && QGroundControl.corePlugin.options.preFlightChecklistUrl.toString().length
            property Fact _useChecklist:      _settingsManager.appSettings.useChecklist
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Enforce Preflight Checklist")
            fact:               _enforceChecklist
            enabled:            _settingsManager.appSettings.useChecklist.value
            visible:            useCheckList.visible && _enforceChecklist.visible
            property Fact _enforceChecklist: _settingsManager.appSettings.enforceChecklist
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Enable Multi-Vehicle Panel")
            fact:               _enableMultiVehiclePanel
            visible:            _enableMultiVehiclePanel.visible
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Keep Map Centered On Vehicle")
            fact:               _keepMapCenteredOnVehicle
            visible:            _keepMapCenteredOnVehicle.visible
            property Fact _keepMapCenteredOnVehicle: _flyViewSettings.keepMapCenteredOnVehicle
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Show Telemetry Log Replay Status Bar")
            fact:               _showLogReplayStatusBar
            visible:            _showLogReplayStatusBar.visible
            property Fact _showLogReplayStatusBar: _flyViewSettings.showLogReplayStatusBar
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Show simple camera controls (DIGICAM_CONTROL)")
            visible:            _showDumbCameraControl.visible
            fact:               _showDumbCameraControl

            property Fact _showDumbCameraControl: _flyViewSettings.showSimpleCameraControl
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Update return to home position based on device location.")
            fact:               _updateHomePosition
            visible:            _updateHomePosition.visible
            property Fact _updateHomePosition: _flyViewSettings.updateHomePosition
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Vehicle Icon")

        property Fact _vehicleIconSizeScale: _flyViewSettings.vehicleIconSizeScale
        property Fact _vehicleIconColor:     _flyViewSettings.vehicleIconColor

        id: _vehicleIconGroup

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Icon Size Scale (0.4 - 3.0)")
            fact:               _vehicleIconGroup._vehicleIconSizeScale
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth:   true
                text:               qsTr("Icon Color")
            }

            Repeater {
                model: [ "", "#ffffff", "#ff3b30", "#ff9500", "#ffee00", "#2ecc40", "#00e5ff", "#3478f6", "#e040fb", "#000000" ]

                Rectangle {
                    width:          ScreenTools.defaultFontPixelHeight * 1.5
                    height:         width
                    radius:         width / 4
                    color:          modelData === "" ? "transparent" : modelData
                    border.width:   _vehicleIconGroup._vehicleIconColor.rawValue === modelData ? 2 : 1
                    border.color:   _vehicleIconGroup._vehicleIconColor.rawValue === modelData ? qgcPal.colorGreen : qgcPal.text

                    QGCLabel {
                        anchors.centerIn:   parent
                        visible:            modelData === ""
                        text:               qsTr("Std")
                        font.pointSize:     ScreenTools.smallFontPointSize
                    }

                    MouseArea {
                        anchors.fill:   parent
                        onClicked:      _vehicleIconGroup._vehicleIconColor.rawValue = modelData
                    }
                }
            }
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Flight Logs")
        headingDescription: ScreenTools.isMobile ?
                                qsTr("Telemetry logs are saved after each flight. Tap Share to send one to Google Drive, email, etc.") :
                                qsTr("Telemetry logs are saved after each flight. Open Folder shows them on disk.")

        LogExportController { id: logExportController }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Save telemetry log after each flight")
            fact:               _settingsManager.mavlinkSettings.telemetrySave
        }

        QGCLabel {
            Layout.fillWidth:   true
            visible:            logExportController.logFiles.length === 0
            text:               qsTr("No telemetry logs saved yet.")
            color:              qgcPal.colorGrey
        }

        Repeater {
            model: logExportController.logFiles

            RowLayout {
                Layout.fillWidth:   true
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    Layout.fillWidth:   true
                    text:               modelData
                    elide:              Text.ElideMiddle
                }

                QGCLabel {
                    text:   logExportController.logSizeText(modelData)
                    color:  qgcPal.colorGrey
                }

                QGCButton {
                    text:       ScreenTools.isMobile ? qsTr("Share") : qsTr("Open Folder")
                    onClicked:  logExportController.shareLog(modelData)
                }
            }
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth:   true
                visible:            logExportController.logFiles.length >= 30
                text:               qsTr("Showing the 30 most recent logs.")
                color:              qgcPal.colorGrey
            }

            QGCButton {
                text:       qsTr("Refresh")
                onClicked:  logExportController.refresh()
            }
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Live Tracking (Customer Stream)")

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Stream position to tracking server")
            fact:               _flyViewSettings.liveTrackingEnabled
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Tracking Server URL")
            fact:               _flyViewSettings.liveTrackingServerUrl
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 40
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Upload Interval (seconds)")
            fact:               _flyViewSettings.liveTrackingInterval
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Guided Commands")
        visible:            _guidedMinimumAltitude.visible || _guidedMaximumAltitude.visible ||
                            _maxGoToLocationDistance.visible || _forwardFlightGoToLocationLoiterRad.visible ||
                            _goToLocationRequiresConfirmInGuided.visible

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Minimum Altitude")
            fact:               _guidedMinimumAltitude
            visible:            fact.visible
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Maximum Altitude")
            fact:               _guidedMaximumAltitude
            visible:            fact.visible
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Go To Location Max Distance")
            fact:               _maxGoToLocationDistance
            visible:            fact.visible
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Loiter Radius in Forward Flight Guided Mode")
            fact:               _forwardFlightGoToLocationLoiterRad
            visible:            fact.visible
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Require Confirmation for Go To Location in Guided Mode")
            fact:               _goToLocationRequiresConfirmInGuided
            visible:            fact.visible
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:       true
        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 35
        heading:                qsTr("MAVLink Actions")
        headingDescription:     qsTr("Action JSON files should be created in the '%1' folder.").arg(QGroundControl.settingsManager.appSettings.mavlinkActionsSavePath)

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Fly View Actions")
            model:              mavlinkActionList()
            onActivated:        (index) => index == 0 ? _mavlinkActionsSettings.flyViewActionsFile.rawValue = "" : _mavlinkActionsSettings.flyViewActionsFile.rawValue = comboBox.currentText
            enabled:            model.length > 1

            Component.onCompleted: {
                var index = comboBox.find(_mavlinkActionsSettings.flyViewActionsFile.valueString)
                comboBox.currentIndex = index == -1 ? 0 : index
            }
        }

        LabelledComboBox {
            Layout.fillWidth:   true
            label:              qsTr("Joystick Actions")
            model:              mavlinkActionList()
            onActivated:        (index) => index == 0 ? _mavlinkActionsSettings.joystickActionsFile.rawValue = "" : _mavlinkActionsSettings.joystickActionsFile.rawValue = comboBox.currentText
            enabled:            model.length > 1

            Component.onCompleted: {
                var index = comboBox.find(_mavlinkActionsSettings.joystickActionsFile.valueString)
                comboBox.currentIndex = index == -1 ? 0 : index
            }
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Virtual Joystick")
        visible:            _virtualJoystick.visible || _virtualJoystickAutoCenterThrottle.visible || _virtualJoystickLeftHandedMode.visible

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Enabled")
            visible:            _virtualJoystick.visible
            fact:               _virtualJoystick
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Auto-Center Throttle")
            visible:            _virtualJoystickAutoCenterThrottle.visible
            enabled:            _virtualJoystick.rawValue
            fact:               _virtualJoystickAutoCenterThrottle
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Left-Handed Mode (swap sticks)")
            visible:            _virtualJoystickLeftHandedMode.visible
            enabled:            _virtualJoystick.rawValue
            fact:               _virtualJoystickLeftHandedMode
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Instrument Panel")
        visible:            _showAdditionalIndicatorsCompass.visible || _lockNoseUpCompass.visible

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Show additional heading indicators on Compass")
            visible:            _showAdditionalIndicatorsCompass.visible
            fact:               _showAdditionalIndicatorsCompass
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Lock Compass Nose-Up")
            visible:            _lockNoseUpCompass.visible
            fact:               _lockNoseUpCompass
        }
    }

    SettingsGroupLayout {
        id:                 viewer3DGroup
        Layout.fillWidth:   true
        heading:            qsTr("3D View")
        visible:            _viewer3DSettings.visible

        property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
        property string _noneSite:          qsTr("<None>")
        property string _defaultPathText:   "Please select an OSM file"

        function _selectedSiteIndex() {
            var name = sitePreloader.siteNameFromPath(_viewer3DOsmFilePath.rawValue)
            var idx = sitePreloader.availableSites.indexOf(name)
            return idx < 0 ? 0 : idx + 1
        }

        function _siteModel() {
            var list = sitePreloader.availableSites.slice()
            list.unshift(_noneSite)
            return list
        }

        Viewer3DSitePreloader {
            id: sitePreloader
            onPreloadFinished: (ok, filePath) => {
                if (ok) {
                    _viewer3DOsmFilePath.value = filePath
                    siteNameField.text = sitePreloader.defaultSiteName()
                }
            }
        }

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               qsTr("Enabled")
            fact:               _viewer3DEnabled
            visible:            _viewer3DEnabled.visible
        }

        QGCLabel {
            Layout.fillWidth:   true
            wrapMode:           Text.WordWrap
            font.pointSize:     ScreenTools.smallFontPointSize
            text:               qsTr("Preload a site while on Wi-Fi: this downloads building outlines and caches the satellite tiles for the current map type so the 3D View works in the field with no connection. Larger radius = more tiles.")
        }

        // ---- Site chooser (files in the app's Maps3D folder) ----
        LabelledComboBox {
            id:                 siteCombo
            Layout.fillWidth:   true
            label:              qsTr("Site")
            enabled:            _viewer3DEnabled.rawValue && !sitePreloader.busy
            model:              viewer3DGroup._siteModel()
            Component.onCompleted: currentIndex = viewer3DGroup._selectedSiteIndex()
            onActivated: (index) => {
                if (index <= 0) {
                    _viewer3DOsmFilePath.value = viewer3DGroup._defaultPathText
                } else {
                    _viewer3DOsmFilePath.value = sitePreloader.sitePath(model[index])
                }
            }
            Connections {
                target: sitePreloader
                function onAvailableSitesChanged() {
                    siteCombo.model = viewer3DGroup._siteModel()
                    siteCombo.currentIndex = viewer3DGroup._selectedSiteIndex()
                }
            }
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCLabel {
                Layout.fillWidth:   true
                wrapMode:           Text.WordWrap
                font.pointSize:     ScreenTools.smallFontPointSize
                text:               _viewer3DOsmFilePath.rawValue
                elide:              Text.ElideLeft
                maximumLineCount:   2
            }

            QGCButton {
                text:       qsTr("Delete site")
                enabled:    siteCombo.currentIndex > 0 && !sitePreloader.busy
                onClicked: {
                    var name = siteCombo.currentText
                    if (sitePreloader.siteNameFromPath(_viewer3DOsmFilePath.rawValue) === name) {
                        _viewer3DOsmFilePath.value = viewer3DGroup._defaultPathText
                    }
                    sitePreloader.deleteSite(name)
                }
            }

            QGCButton {
                text:       qsTr("Select File...")
                visible:    !ScreenTools.isMobile
                enabled:    _viewer3DEnabled.rawValue && !sitePreloader.busy
                onClicked:  fileDialog.openForLoad()

                QGCFileDialog {
                    id:             fileDialog
                    folder:         sitePreloader.mapsDirectory
                    nameFilters:    [qsTr("OpenStreetMap files (*.osm)")]
                    title:          qsTr("Select map file")
                    onAcceptedForLoad: (file) => { _viewer3DOsmFilePath.value = file }
                }
            }
        }

        // ---- Preload a new site ----
        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth
            enabled:            _viewer3DEnabled.rawValue && !sitePreloader.busy

            QGCLabel { text: qsTr("New site name") }
            QGCTextField {
                id:                 siteNameField
                Layout.fillWidth:   true
                text:               sitePreloader.defaultSiteName()
            }
            QGCLabel { text: qsTr("Radius") }
            QGCTextField {
                id:                 radiusField
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                text:               "1500"
                unitsLabel:         "m"
                showUnits:          true
                numericValuesOnly:  true
            }
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth

            QGCButton {
                text:       qsTr("Preload around map center")
                enabled:    _viewer3DEnabled.rawValue && !sitePreloader.busy
                onClicked:  sitePreloader.preload(siteNameField.text, QGroundControl.flightMapPosition, parseFloat(radiusField.text))
            }

            QGCButton {
                text:       qsTr("Preload around vehicle")
                enabled:    _viewer3DEnabled.rawValue && !sitePreloader.busy && viewer3DGroup._activeVehicle && viewer3DGroup._activeVehicle.coordinate.isValid
                onClicked:  sitePreloader.preload(siteNameField.text, viewer3DGroup._activeVehicle.coordinate, parseFloat(radiusField.text))
            }

            QGCButton {
                text:       qsTr("Cancel")
                visible:    sitePreloader.busy
                onClicked:  sitePreloader.cancel()
            }
        }

        RowLayout {
            Layout.fillWidth:   true
            spacing:            ScreenTools.defaultFontPixelWidth
            visible:            sitePreloader.status.length > 0

            Rectangle {
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 12
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.6
                visible:                sitePreloader.busy
                color:                  qgcPal.windowShade
                border.color:           qgcPal.text
                border.width:           1
                Rectangle {
                    anchors.left:   parent.left
                    anchors.top:    parent.top
                    anchors.bottom: parent.bottom
                    width:          parent.width * sitePreloader.progress / 100
                    color:          qgcPal.colorGreen
                }
            }

            QGCLabel {
                Layout.fillWidth:   true
                wrapMode:           Text.WordWrap
                font.pointSize:     ScreenTools.smallFontPointSize
                text:               sitePreloader.status
            }
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Average Building Level Height")
            fact:               _viewer3DBuildingLevelHeight
            enabled:            _viewer3DEnabled.rawValue
            visible:            _viewer3DBuildingLevelHeight.visible
        }

        LabelledFactTextField {
            Layout.fillWidth:   true
            label:              qsTr("Vehicles Altitude Bias")
            fact:               _viewer3DAltitudeBias
            enabled:            _viewer3DEnabled.rawValue
            visible:            _viewer3DAltitudeBias.visible
        }
    }
}
