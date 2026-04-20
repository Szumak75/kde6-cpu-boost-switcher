import QtQuick 2.15
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "../code/I18n.js" as I18n

KCM.SimpleKCM {
    id: root

    property alias cfg_refreshIntervalSeconds: refreshInterval.value
    readonly property string localeName: Qt.locale().name

    implicitWidth: Kirigami.Units.gridUnit * 18
    implicitHeight: Kirigami.Units.gridUnit * 10

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.SpinBox {
            id: refreshInterval
            from: 1
            to: 60
            stepSize: 1
            editable: true
            Kirigami.FormData.label: I18n.tr(root.localeName, "Refresh interval (s):")
        }
    }
}
