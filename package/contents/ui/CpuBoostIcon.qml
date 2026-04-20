import QtQuick 2.15

Item {
    id: iconRoot

    property string iconState: "inactive"
    property int iconSize: 24

    readonly property color chipColor: iconState === "active" ? "#34c759" : "#8b929c"
    readonly property bool struckOut: iconState === "unsupported"

    implicitWidth: iconSize
    implicitHeight: iconSize

    Rectangle {
        id: chip

        anchors.centerIn: parent
        width: Math.round(iconRoot.iconSize * 0.62)
        height: width
        radius: Math.max(2, Math.round(width * 0.08))
        color: iconRoot.chipColor
        border.color: "#4b5563"
        border.width: 1
    }

    Rectangle {
        anchors.centerIn: chip
        width: Math.round(chip.width * 0.46)
        height: width
        radius: Math.max(1, Math.round(width * 0.08))
        color: Qt.lighter(iconRoot.chipColor, 1.12)
        border.color: "#4b5563"
        border.width: 1
    }

    Repeater {
        model: 4

        Rectangle {
            width: Math.max(2, Math.round(iconRoot.iconSize * 0.07))
            height: Math.max(3, Math.round(iconRoot.iconSize * 0.14))
            radius: 1
            color: "#69707d"
            x: chip.x + Math.round((index + 0.5) * chip.width / 4 - width / 2)
            y: chip.y - height
        }
    }

    Repeater {
        model: 4

        Rectangle {
            width: Math.max(2, Math.round(iconRoot.iconSize * 0.07))
            height: Math.max(3, Math.round(iconRoot.iconSize * 0.14))
            radius: 1
            color: "#69707d"
            x: chip.x + Math.round((index + 0.5) * chip.width / 4 - width / 2)
            y: chip.y + chip.height
        }
    }

    Repeater {
        model: 4

        Rectangle {
            width: Math.max(3, Math.round(iconRoot.iconSize * 0.14))
            height: Math.max(2, Math.round(iconRoot.iconSize * 0.07))
            radius: 1
            color: "#69707d"
            x: chip.x - width
            y: chip.y + Math.round((index + 0.5) * chip.height / 4 - height / 2)
        }
    }

    Repeater {
        model: 4

        Rectangle {
            width: Math.max(3, Math.round(iconRoot.iconSize * 0.14))
            height: Math.max(2, Math.round(iconRoot.iconSize * 0.07))
            radius: 1
            color: "#69707d"
            x: chip.x + chip.width
            y: chip.y + Math.round((index + 0.5) * chip.height / 4 - height / 2)
        }
    }

    Rectangle {
        visible: iconRoot.struckOut
        anchors.centerIn: parent
        width: Math.round(iconRoot.iconSize * 1.1)
        height: Math.max(3, Math.round(iconRoot.iconSize * 0.09))
        radius: height / 2
        color: "#d92d20"
        rotation: -35
    }
}
