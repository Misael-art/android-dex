import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property string actionText: ""
    property string actionIcon: ""
    property bool warning: false
    default property alias body: bodyColumn.data
    signal action()

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Item {
            width: parent.width
            height: Math.max(childrenRect.height + 90, root.height)
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: window.compact ? 38 : 64
                anchors.rightMargin: window.compact ? 38 : 64
                anchors.topMargin: window.compact ? 36 : 52
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        Text { text: root.title; color: root.warning ? Theme.amber : Theme.text; font.family: "Inter"; font.pixelSize: window.compact ? 31 : 39; font.weight: Font.Bold }
                        Text { Layout.fillWidth: true; text: root.subtitle; color: Theme.muted; font.family: "Inter"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    }
                    AppButton { visible: root.actionText.length > 0; text: root.actionText; iconName: root.actionIcon; primary: true; onClicked: root.action() }
                }
                Item { Layout.preferredHeight: 38 }
                ColumnLayout { id: bodyColumn; Layout.fillWidth: true; spacing: 0 }
                Item { Layout.preferredHeight: 54 }
            }
        }
    }
}
