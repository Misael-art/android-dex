import QtQuick
import QtQuick.Controls

TextField {
    id: control
    property color accent: Theme.cyan

    implicitHeight: 50
    color: Theme.text
    placeholderTextColor: Theme.muted
    font.family: "Inter"
    font.pixelSize: 13
    selectByMouse: true
    activeFocusOnTab: true
    background: Rectangle {
        radius: 9
        color: Theme.raised
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.accent : Theme.border
    }
}
