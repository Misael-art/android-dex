import QtQuick

Rectangle {
    id: root
    property string label: "Conectado"
    property color accent: Theme.green
    implicitWidth: content.implicitWidth + 26
    implicitHeight: 32
    radius: 16
    color: Qt.rgba(accent.r, accent.g, accent.b, 0.12)
    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.42)
    border.width: 1
    Row {
        id: content
        spacing: 8
        anchors.centerIn: parent
        Rectangle { width: 8; height: 8; radius: 4; color: root.accent }
        Text {
            text: root.label
            color: root.accent
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
