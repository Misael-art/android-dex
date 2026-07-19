import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property color accent: Theme.cyan

    implicitHeight: 50
    focusPolicy: Qt.StrongFocus
    Accessible.name: displayText

    contentItem: Text {
        leftPadding: 14
        rightPadding: 42
        text: control.displayText
        color: Theme.text
        font.family: "Inter"
        font.pixelSize: 13
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 14
        y: (control.height - height) / 2
        text: "expand_more"
        color: control.enabled ? Theme.muted : Theme.border
        font.family: "Material Symbols Rounded"
        font.pixelSize: 22
    }
    background: Rectangle {
        radius: 9
        color: Theme.raised
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.accent : Theme.border
    }
    delegate: ItemDelegate {
        required property var modelData
        width: control.width
        height: 44
        contentItem: Text {
            leftPadding: 14
            rightPadding: 14
            text: control.textRole.length > 0 ? modelData[control.textRole] : modelData
            color: Theme.text
            font.family: "Inter"
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        highlighted: control.highlightedIndex === index
        background: Rectangle {
            color: parent.highlighted ? Theme.border : Theme.surface
        }
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: contentItem.implicitHeight
        padding: 1
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator { }
        }
        background: Rectangle {
            radius: 9
            color: Theme.surface
            border.color: Theme.border
        }
    }
}
