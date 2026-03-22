import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactControls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.PlanView
import QGroundControl.Toolbar

ApplicationWindow {
    id: mainWindow
    visible: true
    flags: Qt.Window | (ScreenTools.isAndroid ? Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint : 0)

    Component.onCompleted: {
        firstRunPromptManager.nextPrompt()
    }

    MainWindowSavedState {
        window: mainWindow
    }

    QtObject {
        id: firstRunPromptManager

        property var currentDialog: null
        property var rgPromptIds: QGroundControl.corePlugin.firstRunPromptsToShow()
        property int nextPromptIdIndex: 0

        function clearNextPromptSignal() {
            if (currentDialog) {
                currentDialog.closed.disconnect(nextPrompt)
            }
        }

        function nextPrompt() {
            if (nextPromptIdIndex < rgPromptIds.length) {
                var component = Qt.createComponent(QGroundControl.corePlugin.firstRunPromptResource(rgPromptIds[nextPromptIdIndex]))
                currentDialog = component.createObject(mainWindow)
                currentDialog.closed.connect(nextPrompt)
                currentDialog.open()
                nextPromptIdIndex++
            } else {
                currentDialog = null
                showPreFlightChecklistIfNeeded()
            }
        }
    }

    readonly property real _topBottomMargins: ScreenTools.defaultFontPixelHeight * 0.5
    property bool dashboardMode: false
    property bool missionConsoleMode: false
    property string standardView: "fly"
    property string focusedPanel: ""
    property string missionConsoleFocusedPanel: ""

    QtObject {
        id: globals

        readonly property var activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
        readonly property real defaultTextHeight: ScreenTools.defaultFontPixelHeight
        readonly property real defaultTextWidth: ScreenTools.defaultFontPixelWidth
        readonly property var planMasterControllerFlyView: flyView.planController
        readonly property var guidedControllerFlyView: flyView.guidedController

        property int validationErrorCount: 0
        property bool commingFromRIDIndicator: false
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    signal armVehicleRequest
    signal forceArmVehicleRequest
    signal disarmVehicleRequest
    signal vtolTransitionToFwdFlightRequest
    signal vtolTransitionToMRFlightRequest
    signal showPreFlightChecklistIfNeeded

    function allowViewSwitch(previousValidationErrorCount = 0) {
        if (mainWindow.activeFocusControl instanceof FactTextField) {
            mainWindow.activeFocusControl._onEditingFinished()
        }
        return globals.validationErrorCount <= previousValidationErrorCount
    }

    function showPlanView() {
        dashboardMode = false
        standardView = "plan"
        focusedPanel = ""
        toolDrawer.visible = false
    }
    function showStandardView() {
        dashboardMode = false
        missionConsoleMode = false
        focusedPanel = ""
        missionConsoleFocusedPanel = ""
        standardView = "fly"
        toolDrawer.visible = false
    }

    function showMissionConsoleView() {
        dashboardMode = false
        missionConsoleMode = true
        focusedPanel = ""
        missionConsoleFocusedPanel = ""
        toolDrawer.visible = false
    }

    function closeFocusedView() {
        if (missionConsoleMode && missionConsoleFocusedPanel !== "") {
            missionConsoleFocusedPanel = ""
        } else if (dashboardMode && focusedPanel !== "") {
            focusedPanel = ""
        } else {
            focusedPanel = ""
            missionConsoleFocusedPanel = ""
        }
    }

    function showFlyView() {
        dashboardMode = false
        standardView = "fly"
        focusedPanel = ""
        toolDrawer.visible = false
    }

    function showTool(toolTitle, toolSource, toolIcon) {
        toolDrawer.backIcon = flyView.visible ? "/qmlimages/PaperPlane.svg" : "/qmlimages/Plan.svg"
        toolDrawer.toolTitle = toolTitle
        toolDrawer.toolSource = toolSource
        toolDrawer.toolIcon = toolIcon
        toolDrawer.visible = true
    }

    function showAnalyzeTool() {
        showTool(qsTr("Analyze Tools"), "qrc:/qml/QGroundControl/AnalyzeView/AnalyzeView.qml", "/qmlimages/Analyze.svg")
    }

    function showVehicleConfig() {
        showTool(qsTr("Vehicle Configuration"), "qrc:/qml/QGroundControl/VehicleSetup/SetupView.qml", "/qmlimages/Gears.svg")
    }

    function showVehicleConfigParametersPage() {
        showVehicleConfig()
        toolDrawerLoader.item.showParametersPanel()
    }

    function showKnownVehicleComponentConfigPage(knownVehicleComponent) {
        showVehicleConfig()
        let vehicleComponent = globals.activeVehicle.autopilotPlugin.findKnownVehicleComponent(knownVehicleComponent)
        if (vehicleComponent) {
            toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
        }
    }

    function showSettingsTool(settingsPage = "") {
        showTool(qsTr("Application Settings"), "qrc:/qml/QGroundControl/Controls/AppSettings.qml", "/res/QGCLogoWhite")
        if (settingsPage !== "") {
            toolDrawerLoader.item.showSettingsPage(settingsPage)
        }
    }

    function _showMessageDialogWorker(owner, dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null) {
        let dialog = simpleMessageDialogComponent.createObject(owner, {
            title: dialogTitle,
            text: dialogText,
            buttons: buttons,
            acceptFunction: acceptFunction,
            closeFunction: closeFunction
        })
        dialog.open()
    }

    function _showMessageDialog(dialogTitle, dialogText) {
        _showMessageDialogWorker(mainWindow, dialogTitle, dialogText)
    }

    Connections {
        target: QGroundControl
        function onShowMessageDialogRequested(owner, title, text, buttons, acceptFunction, closeFunction) {
            _showMessageDialogWorker(owner, title, text, buttons, acceptFunction, closeFunction)
        }
    }

    Component {
        id: simpleMessageDialogComponent
        QGCSimpleMessageDialog { }
    }

    property bool _forceClose: false
    readonly property int _skipUnsavedMissionCheckMask: 0x01
    readonly property int _skipPendingParameterWritesCheckMask: 0x02
    readonly property int _skipActiveConnectionsCheckMask: 0x04
    property int _closeChecksToSkip: 0
    property string closeDialogTitle: qsTr("Close %1").arg(QGroundControl.appName)

    function finishCloseProcess() {
        _forceClose = true
        firstRunPromptManager.clearNextPromptSignal()
        QGroundControl.linkManager.shutdown()
        QGroundControl.videoManager.stopVideo()
        mainWindow.close()
    }

    function checkForUnsavedMission() {
        if (planView._planMasterController.dirtyForSave || planView._planMasterController.dirtyForUpload) {
            QGroundControl.showMessageDialog(mainWindow, closeDialogTitle,
                qsTr("You have a mission edit in progress which has not been saved/uploaded. If you close you will lose changes. Are you sure you want to close?"),
                Dialog.Yes | Dialog.No,
                function() { _closeChecksToSkip |= _skipUnsavedMissionCheckMask; performCloseChecks() })
            return false
        }
        return true
    }

    function checkForPendingParameterWrites() {
        for (var index = 0; index < QGroundControl.multiVehicleManager.vehicles.count; index++) {
            if (QGroundControl.multiVehicleManager.vehicles.get(index).parameterManager.pendingWrites) {
                QGroundControl.showMessageDialog(mainWindow, closeDialogTitle,
                    qsTr("You have pending parameter updates to a vehicle. If you close you will lose changes. Are you sure you want to close?"),
                    Dialog.Yes | Dialog.No,
                    function() { _closeChecksToSkip |= _skipPendingParameterWritesCheckMask; performCloseChecks() })
                return false
            }
        }
        return true
    }

    function checkForActiveConnections() {
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            QGroundControl.showMessageDialog(mainWindow, closeDialogTitle,
                qsTr("There are still active connections to vehicles. Are you sure you want to exit?"),
                Dialog.Yes | Dialog.No,
                function() { _closeChecksToSkip |= _skipActiveConnectionsCheckMask; performCloseChecks() })
            return false
        }
        return true
    }

    function performCloseChecks() {
        if (!(_closeChecksToSkip & _skipUnsavedMissionCheckMask) && !checkForUnsavedMission()) return false
        if (!(_closeChecksToSkip & _skipPendingParameterWritesCheckMask) && !checkForPendingParameterWrites()) return false
        if (!(_closeChecksToSkip & _skipActiveConnectionsCheckMask) && !checkForActiveConnections()) return false
        finishCloseProcess()
        return true
    }

    onClosing: (close) => {
        if (!_forceClose) {
            _closeChecksToSkip = 0
            close.accepted = performCloseChecks()
        }
    }

    background: Rectangle {
        anchors.fill: parent
        color: QGroundControl.globalPalette.window
    }



    Loader {
        id: mainViewLoader
        anchors.fill: parent

        sourceComponent: missionConsoleMode
                         ? (missionConsoleFocusedPanel === "" ? missionConsoleDashboardComponent
                                                            : missionConsoleFocusedPanel === "fly" ? missionConsoleFlyComponent
                                                            : missionConsoleFocusedPanel === "plan" ? missionConsolePlanComponent
                                                            : missionConsoleFocusedPanel === "telemetry" ? missionConsoleTelemetryComponent
                                                            : missionConsoleFocusedPanel === "camera" ? missionConsoleCameraComponent
                                                            : missionConsoleDashboardComponent)
                         : dashboardMode
                           ? (focusedPanel === "" ? dashboardComponent
                                                  : focusedPanel === "fly" ? focusedFlyComponent
                                                  : focusedPanel === "plan" ? focusedPlanComponent
                                                  : focusedPanel === "telemetry" ? focusedTelemetryComponent
                                                  : focusedPanel === "camera" ? focusedCameraComponent
                                                  : dashboardComponent)
                           : null
    }
    Rectangle {
        id: floatingBackButton
        z: 999999
        width: 38
        height: 38
        radius: 19
        color: "#123C73"
        border.color: "#4FA3FF"
        border.width: 1

        visible: (dashboardMode && focusedPanel !== "") || (missionConsoleMode && missionConsoleFocusedPanel !== "")

        x: mainWindow.width - width - 16
        y: 12

        Text {
            anchors.centerIn: parent
            text: "<"
            color: "white"
            font.pixelSize: 20
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: mainWindow.closeFocusedView()
        }
    }

    Component {
        id: dashboardComponent

        GridLayout {
            anchors.fill: parent
            columns: 2
            rows: 2
            rowSpacing: 6
            columnSpacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#123C73"
                radius: 6
                clip: true

                FlyView {
                    anchors.fill: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.focusedPanel = "fly"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#123C73"
                radius: 6
                clip: true

                PlanView {
                    anchors.fill: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.focusedPanel = "plan"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#123C73"
                radius: 6

                Text {
                    anchors.centerIn: parent
                    text: "Telemetry / Status"
                    color: "white"
                    font.pixelSize: 20
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.focusedPanel = "telemetry"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#123C73"
                radius: 6
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }

                FlightDisplayViewVideo {
                    anchors.fill: parent
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 220
                    height: 46
                    radius: 8
                    color: "#66000000"
                    visible: !QGroundControl.videoManager.fullScreen

                    Text {
                        anchors.centerIn: parent
                        text: "Camera / Video"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.focusedPanel = "camera"
                }
            }
        }
    }

    Component {
        id: focusedFlyComponent

        Item {
            anchors.fill: parent

            FlyView {
                anchors.fill: parent
            }
        }
    }

    Component {
        id: focusedPlanComponent

        Item {
            anchors.fill: parent

            PlanView {
                anchors.fill: parent
            }
        }
    }

    Component {
        id: focusedTelemetryComponent

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#123C73"
            }

            Text {
                anchors.centerIn: parent
                text: "Telemetry / Status Full Screen"
                color: "white"
                font.pixelSize: 28
                font.bold: true
            }
        }
    }

    Component {
        id: focusedCameraComponent

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            FlightDisplayViewVideo {
                anchors.fill: parent
            }

            Rectangle {
                anchors.centerIn: parent
                width: 260
                height: 50
                radius: 8
                color: "#66000000"
                visible: !QGroundControl.videoManager.fullScreen

                Text {
                    anchors.centerIn: parent
                    text: "Waiting for video stream..."
                    color: "white"
                    font.pixelSize: 16
                }
            }
        }
    }
    Component {
        id: missionConsoleDashboardComponent

        GridLayout {
            anchors.fill: parent
            columns: 2
            rows: 2
            rowSpacing: 6
            columnSpacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#142B45"
                radius: 6
                clip: true

                PlanView {
                    anchors.fill: parent
                }

                Image {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 10
                    anchors.leftMargin: 10
                    width: 110
                    height: 32
                    fillMode: Image.PreserveAspectFit
                    source: mainWindow.kristellarLogoSource
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.missionConsoleFocusedPanel = "plan"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "black"
                radius: 6
                clip: true

                FlightDisplayViewVideo {
                    anchors.fill: parent
                }

                Image {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 10
                    anchors.leftMargin: 10
                    width: 110
                    height: 32
                    fillMode: Image.PreserveAspectFit
                    source: mainWindow.kristellarLogoSource
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.missionConsoleFocusedPanel = "camera"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#101820"
                radius: 6
                clip: true

                FlyView {
                    anchors.fill: parent
                }

                Image {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 10
                    anchors.leftMargin: 10
                    width: 110
                    height: 32
                    fillMode: Image.PreserveAspectFit
                    source: mainWindow.kristellarLogoSource
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.missionConsoleFocusedPanel = "fly"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0E2238"
                radius: 6

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "Telemetry"
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        text: "GPS / Attitude / Status"
                        color: "#CCCCCC"
                        font.pixelSize: 16
                    }
                }



                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.missionConsoleFocusedPanel = "telemetry"
                }
            }
        }
    }
    Component {
        id: missionConsolePlanComponent

        Item {
            anchors.fill: parent

            PlanView {
                anchors.fill: parent
            }

            Image {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 12
                anchors.leftMargin: 12
                width: 120
                height: 36
                fillMode: Image.PreserveAspectFit
                source: mainWindow.kristellarLogoSource
                z: 99999
            }
        }
    }
    Component {
        id: missionConsoleCameraComponent

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            FlightDisplayViewVideo {
                anchors.fill: parent
            }

            Image {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 12
                anchors.leftMargin: 12
                width: 120
                height: 36
                fillMode: Image.PreserveAspectFit
                source: mainWindow.kristellarLogoSource
                z: 99999
            }

            Rectangle {
                anchors.centerIn: parent
                width: 240
                height: 48
                radius: 8
                color: "#66000000"
                visible: !QGroundControl.videoManager.fullScreen

                Text {
                    anchors.centerIn: parent
                    text: "Waiting for video stream..."
                    color: "white"
                    font.pixelSize: 16
                }
            }
        }
    }
    Component {
        id: missionConsoleFlyComponent

        Item {
            anchors.fill: parent

            FlyView {
                anchors.fill: parent
            }


        }
    }
    Component {
        id: missionConsoleTelemetryComponent

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#0B1622"
            }

            Image {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 12
                anchors.leftMargin: 12
                width: 120
                height: 36
                fillMode: Image.PreserveAspectFit
                source: mainWindow.kristellarLogoSource
                z: 99999
            }

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "Telemetry Console"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }

                Text {
                    text: "GPS / Attitude / Battery / Altitude / Speed"
                    color: "#CCCCCC"
                    font.pixelSize: 16
                }
            }
        }
    }



    FlyView {
        id: flyView
        anchors.fill: parent
        visible: !dashboardMode && !missionConsoleMode && standardView === "fly"
    }

    PlanView {
        id: planView
        anchors.fill: parent
        visible: !dashboardMode && !missionConsoleMode && standardView === "plan"
    }

    footer: LogReplayStatusBar {
        visible: QGroundControl.settingsManager.flyViewSettings.showLogReplayStatusBar.rawValue
    }

    MessageDialog {
        id: showTouchAreasNotification
        title: qsTr("Debug Touch Areas")
        text: qsTr("Touch Area display toggled")
        buttons: MessageDialog.Ok
    }

    MessageDialog {
        id: advancedModeOnConfirmation
        title: qsTr("Advanced Mode")
        text: QGroundControl.corePlugin.showAdvancedUIMessage
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true
            }
        }
    }

    MessageDialog {
        id: advancedModeOffConfirmation
        title: qsTr("Advanced Mode")
        text: qsTr("Turn off Advanced Mode?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = false
            }
        }
    }

    function showToolSelectDialog() {
        if (mainWindow.allowViewSwitch()) {
            mainWindow.showIndicatorDrawer(toolSelectComponent, null)
        }
    }

    Component {
        id: toolSelectComponent
        SelectViewDropdown { }
    }

    Rectangle {
        id: toolDrawer
        anchors.fill: parent
        visible: false
        color: qgcPal.window

        property var backIcon
        property string toolTitle
        property alias toolSource: toolDrawerLoader.source
        property var toolIcon

        onVisibleChanged: {
            if (!toolDrawer.visible) {
                toolDrawerLoader.source = ""
            }
        }

        DeadMouseArea {
            anchors.fill: parent
        }

        Rectangle {
            id: toolDrawerToolbar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: ScreenTools.toolbarHeight
            color: qgcPal.toolbarBackground

            RowLayout {
                id: toolDrawerToolbarLayout
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: ScreenTools.defaultFontPixelWidth

                QGCToolBarButton {
                    id: qgcButton
                    height: parent.height
                    icon.source: "/res/QGCLogoFull.svg"
                    logo: true
                    onClicked: mainWindow.showToolSelectDialog()
                }

                QGCLabel {
                    id: toolbarDrawerText
                    text: toolDrawer.toolTitle
                    font.pointSize: ScreenTools.largeFontPointSize
                }
            }
        }

        Loader {
            id: toolDrawerLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolDrawerToolbar.bottom
            anchors.bottom: parent.bottom

            Connections {
                target: toolDrawerLoader.item
                ignoreUnknownSignals: true
                function onPopout() { toolDrawer.visible = false }
            }
        }
    }

    function showCriticalVehicleMessage(message) {
        closeIndicatorDrawer()
        if (criticalVehicleMessagePopup.visible || QGroundControl.videoManager.fullScreen) {
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = true
        } else {
            criticalVehicleMessagePopup.criticalVehicleMessage = message
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
            criticalVehicleMessagePopup.open()
        }
    }

    Popup {
        id: criticalVehicleMessagePopup
        y: ScreenTools.toolbarHeight + ScreenTools.defaultFontPixelHeight
        x: Math.round((mainWindow.width - width) * 0.5)
        width: mainWindow.width * 0.55
        height: criticalVehicleMessageText.contentHeight + ScreenTools.defaultFontPixelHeight * 2
        modal: false
        focus: true

        property alias criticalVehicleMessage: criticalVehicleMessageText.text
        property bool additionalCriticalMessagesReceived: false

        background: Rectangle {
            anchors.fill: parent
            color: qgcPal.alertBackground
            radius: ScreenTools.defaultFontPixelHeight * 0.5
            border.color: qgcPal.alertBorder
            border.width: 2

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -(height / 2)
                color: qgcPal.alertBackground
                radius: ScreenTools.defaultFontPixelHeight * 0.25
                border.color: qgcPal.alertBorder
                border.width: 1
                width: vehicleWarningLabel.contentWidth + _margins
                height: vehicleWarningLabel.contentHeight + _margins

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id: vehicleWarningLabel
                    anchors.centerIn: parent
                    text: qsTr("Vehicle Error")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color: qgcPal.alertText
                }
            }

            Rectangle {
                id: additionalErrorsIndicator
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -(height / 2)
                color: qgcPal.alertBackground
                radius: ScreenTools.defaultFontPixelHeight * 0.25
                border.color: qgcPal.alertBorder
                border.width: 1
                width: additionalErrorsLabel.contentWidth + _margins
                height: additionalErrorsLabel.contentHeight + _margins
                visible: criticalVehicleMessagePopup.additionalCriticalMessagesReceived

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id: additionalErrorsLabel
                    anchors.centerIn: parent
                    text: qsTr("Additional errors received")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color: qgcPal.alertText
                }
            }
        }

        QGCLabel {
            id: criticalVehicleMessageText
            width: criticalVehicleMessagePopup.width - ScreenTools.defaultFontPixelHeight
            anchors.centerIn: parent
            wrapMode: Text.WordWrap
            color: qgcPal.alertText
            textFormat: TextEdit.RichText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                criticalVehicleMessagePopup.close()
                if (criticalVehicleMessagePopup.additionalCriticalMessagesReceived) {
                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
                    flyView.dropMainStatusIndicatorTool()
                } else if (QGroundControl.multiVehicleManager.activeVehicle) {
                    QGroundControl.multiVehicleManager.activeVehicle.resetErrorLevelMessages()
                }
            }
        }
    }

    function showIndicatorDrawer(drawerComponent, indicatorItem) {
        indicatorDrawer.sourceComponent = drawerComponent
        indicatorDrawer.indicatorItem = indicatorItem
        indicatorDrawer.open()
    }

    function closeIndicatorDrawer() {
        indicatorDrawer.close()
    }

    Popup {
        id: indicatorDrawer
        x: calcXPosition()
        y: ScreenTools.toolbarHeight + _margins
        leftInset: 0
        rightInset: 0
        topInset: 0
        bottomInset: 0
        padding: _margins * 2
        visible: false
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var sourceComponent
        property var indicatorItem
        property bool _expanded: false
        property real _margins: ScreenTools.defaultFontPixelHeight / 4


        function calcXPosition() {
            if (indicatorItem) {
                var xCenter = indicatorItem.mapToItem(mainWindow.contentItem, indicatorItem.width / 2, 0).x
                return Math.max(_margins,
                                Math.min(xCenter - (contentItem.implicitWidth / 2),
                                         mainWindow.contentItem.width - contentItem.implicitWidth - _margins - (indicatorDrawer.padding * 2) - (ScreenTools.defaultFontPixelHeight / 2)))
            } else {
                return _margins
            }
        }

        onOpened: {
            _expanded = false
            indicatorDrawerLoader.sourceComponent = indicatorDrawer.sourceComponent
        }

        onClosed: {
            _expanded = false
            indicatorItem = undefined
            indicatorDrawerLoader.sourceComponent = undefined
        }

        background: Item {
            Rectangle {
                id: backgroundRect
                anchors.fill: parent
                color: QGroundControl.globalPalette.window
                radius: indicatorDrawer._margins
                opacity: 0.85
            }

            Rectangle {
                anchors.horizontalCenter: backgroundRect.right
                anchors.verticalCenter: backgroundRect.top
                width: ScreenTools.largeFontPixelHeight
                height: width
                radius: width / 2
                color: QGroundControl.globalPalette.button
                border.color: QGroundControl.globalPalette.buttonText
                visible: indicatorDrawerLoader.item && indicatorDrawerLoader.item._showExpand && !indicatorDrawer._expanded

                QGCLabel {
                    anchors.centerIn: parent
                    text: ">"
                    color: QGroundControl.globalPalette.buttonText
                }

                QGCMouseArea {
                    fillItem: parent
                    onClicked: indicatorDrawer._expanded = true
                }
            }
        }

        contentItem: QGCFlickable {
            id: indicatorDrawerLoaderFlickable
            implicitWidth: Math.min(mainWindow.contentItem.width - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.width)
            implicitHeight: Math.min(mainWindow.contentItem.height - ScreenTools.toolbarHeight - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.height)
            contentWidth: indicatorDrawerLoader.width
            contentHeight: indicatorDrawerLoader.height

            Loader {
                id: indicatorDrawerLoader

                Binding {
                    target: indicatorDrawerLoader.item
                    property: "expanded"
                    value: indicatorDrawer._expanded
                }

                Binding {
                    target: indicatorDrawerLoader.item
                    property: "drawer"
                    value: indicatorDrawer
                }
            }
        }
    }

    function createrWindowedAnalyzePage(title, source) {
        var windowedPage = windowedAnalyzePage.createObject(mainWindow)
        windowedPage.title = title
        windowedPage.source = source
    }

    Component {
        id: windowedAnalyzePage

        Window {
            width: ScreenTools.defaultFontPixelWidth * 100
            height: ScreenTools.defaultFontPixelHeight * 40
            visible: true

            property alias source: loader.source

            Rectangle {
                color: QGroundControl.globalPalette.window
                anchors.fill: parent

                Loader {
                    id: loader
                    anchors.fill: parent
                    onLoaded: item.popped = true
                }
            }
        }
    }
}