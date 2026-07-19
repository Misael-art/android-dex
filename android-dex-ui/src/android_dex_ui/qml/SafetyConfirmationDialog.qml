import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: control
    property string actionLabel: ""
    property string deviceLabel: ""
    property string requiredConfirmation: "SIM"
    property string riskText: "Esta operação pode apagar dados, afetar integridade do sistema ou inutilizar o aparelho."
    property alias confirmation: confirmationInput.text
    signal confirmed(string confirmation)

    width: 560
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: 0
    Accessible.name: "Confirmação de operação crítica"

    background: Rectangle {
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: Theme.amber
    }
    contentItem: ColumnLayout {
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 78
            color: "#241a0d"
            radius: 14
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "warning"
                color: Theme.amber
                font.family: "Material Symbols Rounded"
                font.pixelSize: 28
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 62
                anchors.verticalCenter: parent.verticalCenter
                text: "Confirmar operação crítica"
                color: "#ffd9a1"
                font.family: "Inter"
                font.pixelSize: 18
                font.weight: Font.Bold
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 22
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: "Ação: " + control.actionLabel + "\nAparelho: " + control.deviceLabel
                color: Theme.text
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: control.riskText
                color: Theme.muted
                font.family: "Inter"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Text {
                text: "Digite “" + control.requiredConfirmation + "” para continuar"
                color: Theme.amber
                font.family: "Inter"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            AppTextField {
                id: confirmationInput
                Layout.fillWidth: true
                accent: Theme.amber
                placeholderText: control.requiredConfirmation
                Accessible.name: "Frase de confirmação obrigatória"
                onVisibleChanged: if (visible) forceActiveFocus()
            }
        }
    }
    footer: Rectangle {
        implicitHeight: 84
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Item { Layout.fillWidth: true }
            AppButton { text: "Cancelar"; iconName: "close"; onClicked: control.close() }
            AppButton {
                text: "Executar agora"
                iconName: "security"
                danger: true
                enabled: confirmationInput.text === control.requiredConfirmation
                onClicked: {
                    control.confirmed(confirmationInput.text)
                    control.close()
                }
            }
        }
    }
    onOpened: {
        confirmationInput.text = ""
        confirmationInput.forceActiveFocus()
    }
}
