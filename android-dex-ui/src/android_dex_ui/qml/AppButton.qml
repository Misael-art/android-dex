import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string iconName: ""
    property bool primary: false
    property bool danger: false

    implicitHeight: 52
    implicitWidth: 180
    padding: 16
    leftPadding: 18
    rightPadding: 18
    activeFocusOnTab: true
    Keys.onReturnPressed: function(event) { control.clicked(); event.accepted = true }
    Keys.onEnterPressed: function(event) { control.clicked(); event.accepted = true }

    contentItem: Row {
        spacing: 10
        anchors.centerIn: parent
        Text {
            visible: control.iconName.length > 0
            text: control.iconName
            color: control.primary ? Theme.background : (control.danger ? Theme.red : Theme.text)
            font.family: "Material Symbols Rounded"
            font.pixelSize: 22
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            color: control.primary ? Theme.background : Theme.text
            font.family: "Inter"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    background: Rectangle {
        radius: 10
        color: !control.enabled ? Theme.border
            : control.primary ? (control.down ? "#0ca7d6" : Theme.cyan)
            : control.down ? Theme.border : Theme.raised
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.cyan
            : control.danger ? Theme.red : (control.primary ? Theme.cyan : Theme.border)
    }
}
