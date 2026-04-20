import QtQml 2.15
import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents3
import "../code/I18n.js" as I18n

Item {
    id: fullRoot

    required property var controller

    implicitWidth: 380
    implicitHeight: 420
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            CpuBoostIcon {
                iconState: fullRoot.controller.stateIcon
                iconSize: Kirigami.Units.iconSizes.large
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: tr("CPU Boost Switcher")
                    font.bold: true
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label {
                    text: fullRoot.controller.statusSummary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Label {
                    text: fullRoot.controller.busy && fullRoot.controller.operationSummary !== ""
                        ? fullRoot.controller.operationSummary
                        : fullRoot.controller.statusDetails
                    wrapMode: Text.WordWrap
                    opacity: 0.8
                    Layout.fillWidth: true
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label { text: tr("Supported:") }
            PlasmaComponents3.Label { text: fullRoot.controller.commandAvailable ? (fullRoot.controller.boostSupported ? tr("Yes") : tr("No")) : tr("No data") }

            PlasmaComponents3.Label { text: tr("Active:") }
            PlasmaComponents3.Label { text: fullRoot.controller.boostSupported ? (fullRoot.controller.boostActive ? tr("Yes") : tr("No")) : "—" }

            PlasmaComponents3.Label { text: tr("Driver:") }
            PlasmaComponents3.Label {
                text: fullRoot.controller.driver !== "" ? fullRoot.controller.driver : "—"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label { text: tr("Governors:") }
            PlasmaComponents3.Label {
                text: fullRoot.controller.availableGovernors !== "" ? fullRoot.controller.availableGovernors : "—"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label { text: tr("Governor:") }
            QQC2.ComboBox {
                id: governorComboBox
                Layout.fillWidth: true
                model: fullRoot.controller.availableGovernorsModel
                enabled: fullRoot.controller.canChangeGovernor
                currentIndex: fullRoot.controller.availableGovernorsModel.length > 0
                    ? Math.max(0, fullRoot.controller.availableGovernorsModel.indexOf(fullRoot.controller.currentGovernor))
                    : -1

                onActivated: function(index) {
                    const governor = governorComboBox.textAt(index)
                    if (governor && governor !== fullRoot.controller.currentGovernor) {
                        fullRoot.controller.requestGovernorChange(governor)
                    }
                }
            }

            PlasmaComponents3.Label { text: tr("Limits:") }
            PlasmaComponents3.Label {
                text: fullRoot.controller.hardwareLimits !== "" ? fullRoot.controller.hardwareLimits : "—"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label { text: tr("Refresh interval:") }
            QQC2.SpinBox {
                id: refreshIntervalSpinBox
                from: 1
                to: 60
                stepSize: 1
                editable: true
                value: fullRoot.controller.refreshIntervalSeconds
                onValueChanged: {
                    if (value !== fullRoot.controller.refreshIntervalSeconds) {
                        fullRoot.controller.setRefreshIntervalSeconds(value)
                    }
                }
            }

            PlasmaComponents3.Label { text: tr("Last refresh:") }
            PlasmaComponents3.Label { text: fullRoot.controller.lastUpdatedText !== "" ? fullRoot.controller.lastUpdatedText : tr("Not yet") }
        }

        QQC2.Switch {
            id: boostSwitch

            text: !fullRoot.controller.commandAvailable
                ? tr("No CPU Boost data available")
                : (!fullRoot.controller.boostSupported
                    ? tr("CPU Boost unsupported")
                    : (fullRoot.controller.boostActive
                        ? tr("CPU Boost enabled")
                        : tr("CPU Boost disabled")))
            enabled: fullRoot.controller.canToggle

            onClicked: {
                fullRoot.controller.requestToggle(!fullRoot.controller.boostActive)
            }
        }

        Binding {
            target: boostSwitch
            property: "checked"
            value: fullRoot.controller.boostActive
        }

        RowLayout {
            Layout.fillWidth: true

            QQC2.Button {
                text: tr("Refresh")
                enabled: !fullRoot.controller.busy
                onClicked: fullRoot.controller.refreshStatus(true)
            }

            QQC2.Button {
                text: tr("Show diagnostics")
                enabled: fullRoot.controller.diagnosticTitle !== ""
                onClicked: diagnosticsDialog.open()
            }

            Item {
                Layout.fillWidth: true
            }

            QQC2.BusyIndicator {
                running: fullRoot.controller.busy
                visible: running
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    QQC2.Dialog {
        id: diagnosticsDialog

        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(fullRoot.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 26)
        modal: true
        title: fullRoot.controller.diagnosticTitle !== "" ? fullRoot.controller.diagnosticTitle : tr("Diagnostics")
        standardButtons: QQC2.Dialog.Ok

        contentItem: ColumnLayout {
            width: diagnosticsDialog.width - diagnosticsDialog.leftPadding - diagnosticsDialog.rightPadding
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: fullRoot.controller.diagnosticMessage !== "" ? fullRoot.controller.diagnosticMessage : fullRoot.controller.statusSummary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label {
                text: tr("Recommendation")
                font.bold: true
                visible: fullRoot.controller.diagnosticRecommendation !== ""
            }

            PlasmaComponents3.Label {
                text: fullRoot.controller.diagnosticRecommendation
                visible: text !== ""
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PlasmaComponents3.Label {
                text: tr("Details")
                font.bold: true
                visible: fullRoot.controller.diagnosticDetails !== ""
            }

            QQC2.ScrollView {
                visible: fullRoot.controller.diagnosticDetails !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8

                QQC2.TextArea {
                    readOnly: true
                    text: fullRoot.controller.diagnosticDetails
                    wrapMode: TextEdit.WrapAnywhere
                }
            }
        }
    }

    Connections {
        target: fullRoot.controller

        function onDiagnosticSerialChanged() {
            if (fullRoot.controller.pendingDiagnosticOpen) {
                diagnosticsDialog.open()
                fullRoot.controller.pendingDiagnosticOpen = false
            }
        }
    }

    function tr(text) {
        return I18n.tr(fullRoot.controller.localeName, text)
    }
}
