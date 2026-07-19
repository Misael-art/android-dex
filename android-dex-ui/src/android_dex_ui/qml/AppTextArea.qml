import QtQuick
import QtQuick.Controls

TextArea {
    id: control
    property color accent: Theme.cyan

    color: Theme.text
    placeholderTextColor: Theme.muted
    font.family: "Inter"
    font.pixelSize: 13
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    background: Rectangle {
        radius: 8
        color: "#050b11"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.accent : Theme.border
    }
}
