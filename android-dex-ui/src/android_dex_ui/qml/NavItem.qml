import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string iconName: "home"
    property bool selected: false
    property color accent: Theme.cyan

    implicitHeight: 52
    leftPadding: 18
    rightPadding: 14
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Keys.onReturnPressed: function(event) { control.clicked(); event.accepted = true }
    Keys.onEnterPressed: function(event) { control.clicked(); event.accepted = true }

    contentItem: Row {
        spacing: 14
        Text {
            text: control.iconName
            color: control.selected ? control.accent : Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 23
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            color: control.selected ? Theme.text : Theme.muted
            font.family: "Inter"
            font.pixelSize: 15
            font.weight: control.selected ? Font.DemiBold : Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    background: Rectangle {
        radius: 9
        color: control.selected ? Theme.raised : (control.hovered ? "#0d1a25" : "transparent")
        border.width: control.activeFocus ? 2 : 0
        border.color: control.accent
        Rectangle {
            visible: control.selected
            width: 3
            height: 26
            radius: 2
            color: control.accent
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
