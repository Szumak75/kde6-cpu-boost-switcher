import QtQuick 2.15
import org.kde.kirigami as Kirigami

MouseArea {
    id: compactRoot

    required property var controller
    property bool wasExpanded: false

    implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
    implicitHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing

    hoverEnabled: true
    onPressed: wasExpanded = compactRoot.controller.expanded
    onClicked: compactRoot.controller.expanded = !wasExpanded

    CpuBoostIcon {
        anchors.centerIn: parent
        iconState: compactRoot.controller.stateIcon
        iconSize: Kirigami.Units.iconSizes.smallMedium
    }

    Rectangle {
        visible: compactRoot.controller.busy
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Kirigami.Units.smallSpacing * 2
        height: width
        radius: width / 2
        color: "#2d9cdb"
    }
}
