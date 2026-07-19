import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 1440
    height: 1024
    minimumWidth: 960
    minimumHeight: 640
    visible: true
    color: Theme.background
    title: "Android-DEX"

    property int section: 0
    property bool compact: width < 1120
    property int sidebarWidth: compact ? 226 : 302
    property var device: backend.selectedDevice
    property string deviceName: device && device.model ? device.model : "Nenhum aparelho"
    property bool deviceReady: device && device.authorized === true

    function go(index) {
        section = index
        pageStack.currentIndex = index
    }

    Shortcut { sequence: "Ctrl+1"; onActivated: window.go(0) }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.go(1) }
    Shortcut { sequence: "Ctrl+3"; onActivated: window.go(2) }
    Shortcut { sequence: "Ctrl+4"; onActivated: window.go(3) }
    Shortcut { sequence: "Ctrl+5"; onActivated: window.go(4) }
    Shortcut { sequence: "Ctrl+6"; onActivated: window.go(5) }

    Rectangle {
        id: sidebar
        width: window.sidebarWidth
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        color: Theme.sidebar
        border.color: "#172532"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: compact ? 18 : 26
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                spacing: 12
                Rectangle {
                    width: 42; height: 42; radius: 11
                    color: Theme.cyan
                    Text {
                        anchors.centerIn: parent
                        text: "desktop_windows"
                        color: Theme.background
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 26
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Text { text: "Android-DEX"; color: Theme.text; font.family: "Inter"; font.pixelSize: 19; font.weight: Font.Bold }
                    Text { text: "SESSÃO SEGURA"; color: Theme.cyan; font.family: "Inter"; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                }
            }

            Item { Layout.preferredHeight: 20 }
            NavItem { Layout.fillWidth: true; text: "Início"; iconName: "home"; selected: section === 0; onClicked: window.go(0) }
            NavItem { Layout.fillWidth: true; text: "Dispositivos"; iconName: "smartphone"; selected: section === 1; onClicked: window.go(1) }
            NavItem { Layout.fillWidth: true; text: "Conexão Wi‑Fi"; iconName: "wifi"; selected: section === 2; onClicked: window.go(2) }
            NavItem { Layout.fillWidth: true; text: "Sessões"; iconName: "view_in_ar"; selected: section === 3; onClicked: window.go(3) }
            NavItem { Layout.fillWidth: true; text: "Diagnóstico"; iconName: "vital_signs"; selected: section === 4; onClicked: window.go(4) }

            Item { Layout.fillHeight: true }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
            Item { Layout.preferredHeight: 14 }
            NavItem {
                Layout.fillWidth: true
                text: "Manutenção avançada"
                iconName: "build"
                accent: Theme.amber
                selected: section === 5
                onClicked: window.go(5)
            }
            Item { Layout.preferredHeight: 14 }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                radius: 10
                color: Theme.surface
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 11
                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: deviceReady ? "#163c30" : Theme.raised
                        Text {
                            anchors.centerIn: parent
                            text: deviceReady ? "check" : "usb_off"
                            color: deviceReady ? Theme.green : Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 21
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: deviceName; color: Theme.text; elide: Text.ElideRight; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: deviceReady ? ((device.transport || "USB") + " conectado") : "Aguardando conexão"; color: deviceReady ? Theme.green : Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                    }
                }
            }
        }
    }

    Item {
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        StackLayout {
            id: pageStack
            anchors.fill: parent
            currentIndex: window.section

            // Início
            Item {
                ScrollView {
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Item {
                        width: parent.width
                        height: Math.max(920, window.height)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: compact ? 38 : 64
                            anchors.rightMargin: compact ? 38 : 64
                            anchors.topMargin: compact ? 36 : 52
                            anchors.bottomMargin: 34
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: "Sessão em um clique"
                                    color: Theme.text
                                    font.family: "Inter"
                                    font.pixelSize: compact ? 34 : 44
                                    font.weight: Font.Bold
                                }
                                StatusPill { label: deviceReady ? "Pronto para iniciar" : "Aguardando USB"; accent: deviceReady ? Theme.green : Theme.amber }
                            }
                            Item { Layout.preferredHeight: 9 }
                            Text {
                                Layout.fillWidth: true
                                text: "Transforme seu Android em um ambiente desktop confortável, estável e reversível."
                                color: Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 17
                                wrapMode: Text.WordWrap
                            }
                            Item { Layout.preferredHeight: compact ? 38 : 58 }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: compact ? 32 : 58

                                Item {
                                    Layout.preferredWidth: compact ? 245 : 310
                                    Layout.fillHeight: true
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        source: "../assets/images/android-phone-usb.png"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        Accessible.name: "Telefone Android sem marca conectado por cabo USB"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 580
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 16

                                    Text { text: "DISPOSITIVO CONECTADO"; color: Theme.cyan; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.7 }
                                    Text { text: deviceName; color: Theme.text; font.family: "Inter"; font.pixelSize: compact ? 27 : 34; font.weight: Font.Bold }
                                    RowLayout {
                                        spacing: 16
                                        StatusPill { label: deviceReady ? "Conectado" : "Indisponível"; accent: deviceReady ? Theme.green : Theme.red }
                                        Text { text: device && device.android ? "Android " + device.android : "Android"; color: Theme.muted; font.family: "Inter"; font.pixelSize: 13 }
                                        Text { text: device && device.battery !== undefined && device.battery !== null ? device.battery + "% de bateria" : "Bateria —"; color: Theme.muted; font.family: "Inter"; font.pixelSize: 13 }
                                    }
                                    Item { Layout.preferredHeight: 8 }
                                    AppButton {
                                        Layout.fillWidth: true
                                        implicitHeight: 62
                                        text: "Iniciar modo desktop"
                                        iconName: "desktop_windows"
                                        primary: true
                                        enabled: deviceReady && !backend.busy
                                        onClicked: backend.startDesktop("auto")
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12
                                        AppButton { Layout.fillWidth: true; text: "Espelhar tela"; iconName: "cast"; enabled: deviceReady && !backend.busy; onClicked: backend.startDesktop("mirror") }
                                        AppButton { Layout.fillWidth: true; text: "Usar Wi‑Fi"; iconName: "wifi"; onClicked: window.go(2) }
                                    }
                                    Item { Layout.preferredHeight: 12 }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 82
                                        color: Theme.surface
                                        radius: 11
                                        border.color: Theme.border
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 15
                                            spacing: 12
                                            Text { text: "verified_user"; color: Theme.green; font.family: "Material Symbols Rounded"; font.pixelSize: 24 }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                Text { text: "Alterações reversíveis"; color: Theme.text; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                                Text { Layout.fillWidth: true; text: "A sessão restaura os ajustes temporários ao encerrar."; color: Theme.muted; font.family: "Inter"; font.pixelSize: 12; wrapMode: Text.WordWrap }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Dispositivos
            StandardPage {
                title: "Dispositivos"
                subtitle: "Escolha exatamente qual aparelho será usado em cada operação."
                actionText: "Atualizar"
                actionIcon: "refresh"
                onAction: backend.refresh()
                ColumnLayout {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: backend.devices
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 104
                            radius: 12
                            color: backend.selectedSerial === modelData.serial ? Theme.raised : Theme.surface
                            border.width: backend.selectedSerial === modelData.serial ? 2 : 1
                            border.color: backend.selectedSerial === modelData.serial ? Theme.cyan : Theme.border
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 16
                                Text { text: "smartphone"; color: modelData.authorized ? Theme.cyan : Theme.amber; font.family: "Material Symbols Rounded"; font.pixelSize: 32 }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Text { text: modelData.model || modelData.serial; color: Theme.text; font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold }
                                    Text { text: modelData.serial + "  ·  " + (modelData.transport || "USB"); color: Theme.muted; font.family: "Inter"; font.pixelSize: 12 }
                                }
                                StatusPill { label: modelData.authorized ? "Autorizado" : modelData.state; accent: modelData.authorized ? Theme.green : Theme.amber }
                                AppButton { text: backend.selectedSerial === modelData.serial ? "Selecionado" : "Selecionar"; iconName: "check_circle"; enabled: modelData.authorized; onClicked: backend.selectDevice(modelData.serial) }
                            }
                        }
                    }
                    Rectangle {
                        visible: backend.devices.length === 0
                        Layout.fillWidth: true; Layout.preferredHeight: 150; radius: 12; color: Theme.surface; border.color: Theme.border
                        Column { anchors.centerIn: parent; spacing: 8; Text { anchors.horizontalCenter: parent.horizontalCenter; text: "usb_off"; color: Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 34 } Text { text: "Conecte um aparelho e autorize a depuração USB."; color: Theme.muted; font.family: "Inter" } }
                    }
                }
            }

            // Wi-Fi
            StandardPage {
                title: "Conexão Wi‑Fi"
                subtitle: "Pareie pela rede local sem guardar códigos ou credenciais."
                actionText: "Procurar"
                actionIcon: "radar"
                onAction: backend.discoverWifi()
                ColumnLayout {
                    width: parent.width
                    spacing: 18
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 178; radius: 12; color: Theme.surface; border.color: Theme.border
                        GridLayout {
                            anchors.fill: parent; anchors.margins: 20; columns: 2; columnSpacing: 14; rowSpacing: 12
                            Text { text: "Endereço IP e porta"; color: Theme.text; font.family: "Inter"; font.pixelSize: 13 }
                            Text { text: "Código de pareamento"; color: Theme.text; font.family: "Inter"; font.pixelSize: 13 }
                            TextField { id: wifiEndpoint; Layout.fillWidth: true; implicitHeight: 50; placeholderText: "192.168.1.24:37123"; color: Theme.text; placeholderTextColor: Theme.muted; selectByMouse: true; background: Rectangle { radius: 9; color: Theme.raised; border.color: wifiEndpoint.activeFocus ? Theme.cyan : Theme.border; border.width: wifiEndpoint.activeFocus ? 2 : 1 } }
                            TextField { id: wifiCode; Layout.fillWidth: true; implicitHeight: 50; placeholderText: "6 dígitos"; inputMask: "999999"; color: Theme.text; placeholderTextColor: Theme.muted; selectByMouse: true; background: Rectangle { radius: 9; color: Theme.raised; border.color: wifiCode.activeFocus ? Theme.cyan : Theme.border; border.width: wifiCode.activeFocus ? 2 : 1 } }
                            RowLayout { Layout.columnSpan: 2; Layout.alignment: Qt.AlignRight; AppButton { text: "Conectar"; iconName: "link"; onClicked: backend.connectWifi(wifiEndpoint.text) } AppButton { text: "Parear"; iconName: "wifi_tethering"; primary: true; onClicked: backend.pairWifi(wifiEndpoint.text, wifiCode.text) } }
                        }
                    }
                    Text { text: "Encontrados na rede"; color: Theme.text; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Repeater {
                        model: backend.snapshot.wifi ? backend.snapshot.wifi.endpoints : []
                        delegate: Rectangle {
                            required property string modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 72; radius: 11; color: Theme.surface; border.color: Theme.border
                            RowLayout { anchors.fill: parent; anchors.margins: 15; Text { text: "wifi"; color: Theme.cyan; font.family: "Material Symbols Rounded"; font.pixelSize: 23 } Text { Layout.fillWidth: true; text: modelData; color: Theme.text; font.family: "Inter"; font.pixelSize: 14 } AppButton { text: "Usar endereço"; iconName: "arrow_forward"; onClicked: wifiEndpoint.text = modelData } }
                        }
                    }
                }
            }

            // Sessões
            StandardPage {
                title: "Sessões"
                subtitle: "Acompanhe e encerre desktops ativos; o serviço continua mesmo sem a janela."
                actionText: "Atualizar"
                actionIcon: "refresh"
                onAction: backend.refresh()
                ColumnLayout {
                    width: parent.width; spacing: 12
                    Repeater {
                        model: backend.sessions
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 96; radius: 12; color: Theme.surface; border.color: Theme.border
                            RowLayout { anchors.fill: parent; anchors.margins: 18; spacing: 15
                                Text { text: "desktop_windows"; color: modelData.status === "running" ? Theme.green : Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 30 }
                                ColumnLayout { Layout.fillWidth: true; Text { text: modelData.mode === "dex" ? "Modo desktop" : "Espelhamento"; color: Theme.text; font.family: "Inter"; font.pixelSize: 16; font.weight: Font.DemiBold } Text { text: modelData.serial + "  ·  " + modelData.startedAt; color: Theme.muted; font.family: "Inter"; font.pixelSize: 12 } }
                                StatusPill { label: modelData.status === "running" ? "Em execução" : "Encerrada"; accent: modelData.status === "running" ? Theme.green : Theme.muted }
                                AppButton { visible: modelData.status === "running"; text: "Encerrar"; iconName: "stop_circle"; danger: true; onClicked: backend.stopDesktop(modelData.id) }
                            }
                        }
                    }
                    Text { visible: backend.sessions.length === 0; text: "Nenhuma sessão registrada."; color: Theme.muted; font.family: "Inter"; font.pixelSize: 15 }
                }
            }

            // Diagnóstico
            StandardPage {
                title: "Diagnóstico"
                subtitle: "Verifique dependências, autorização USB e recursos do aparelho."
                actionText: "Executar diagnóstico"
                actionIcon: "vital_signs"
                onAction: backend.runDoctor()
                ColumnLayout {
                    width: parent.width; spacing: 16
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 100; radius: 12; color: Theme.surface; border.color: Theme.border
                        RowLayout { anchors.fill: parent; anchors.margins: 18; spacing: 16
                            Text { text: "verified"; color: Theme.green; font.family: "Material Symbols Rounded"; font.pixelSize: 32 }
                            ColumnLayout { Layout.fillWidth: true; Text { text: deviceReady ? "Aparelho autorizado" : "Aparelho não disponível"; color: Theme.text; font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold } Text { text: deviceReady ? deviceName + " está pronto para verificação." : "Conecte e autorize um dispositivo."; color: Theme.muted; font.family: "Inter"; font.pixelSize: 13 } }
                            AppButton { text: "Restaurar ajustes"; iconName: "settings_backup_restore"; enabled: deviceReady; onClicked: backend.restoreTweaks() }
                        }
                    }
                    Text { text: "Resultado"; color: Theme.text; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 300; radius: 12; color: "#050b11"; border.color: Theme.border
                        ScrollView { anchors.fill: parent; anchors.margins: 17; AppTextArea { text: backend.snapshot.doctor ? backend.snapshot.doctor.output : "Execute o diagnóstico para ver o relatório."; color: backend.snapshot.doctor ? Theme.text : Theme.muted; font.family: "monospace"; font.pixelSize: 13; readOnly: true } }
                    }
                }
            }

            // Manutenção avançada
            StandardPage {
                title: "Manutenção avançada"
                subtitle: "Assistente explícito para firmware, bootloader e recuperação. Nada é executado sem prévia."
                warning: true
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 72; radius: 11; color: "#241a0d"; border.color: Theme.amber
                        RowLayout { anchors.fill: parent; anchors.margins: 15; spacing: 12
                            Text { text: "warning"; color: Theme.amber; font.family: "Material Symbols Rounded"; font.pixelSize: 25 }
                            Text { Layout.fillWidth: true; text: "Firmware incompatível pode apagar dados, afetar Knox/Play Integrity ou inutilizar o aparelho. Downgrade e identidade são verificados novamente antes da execução."; color: "#ffd9a1"; font.family: "Inter"; font.pixelSize: 12; wrapMode: Text.WordWrap }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 218; radius: 12; color: Theme.surface; border.color: Theme.border
                        GridLayout { anchors.fill: parent; anchors.margins: 20; columns: 2; columnSpacing: 16; rowSpacing: 10
                            Text { text: "1  Ação"; color: Theme.text; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { text: "2  Artefato local"; color: Theme.text; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            AppComboBox { id: maintenanceAction; Layout.fillWidth: true; model: [{text: "Desbloquear bootloader", value: "unlock"}, {text: "Iniciar recovery temporário", value: "boot-recovery"}, {text: "Aplicar imagem Magisk", value: "root"}, {text: "Restaurar boot", value: "restore-boot"}, {text: "Validar/rotear firmware", value: "flash-firmware"}]; textRole: "text"; valueRole: "value"; accent: Theme.amber }
                            RowLayout { Layout.fillWidth: true; TextField { id: artifactField; Layout.fillWidth: true; implicitHeight: 50; placeholderText: maintenanceAction.currentValue === "unlock" ? "Não necessário para esta ação" : "Selecione um arquivo ou diretório"; enabled: maintenanceAction.currentValue !== "unlock"; color: Theme.text; placeholderTextColor: Theme.muted; selectByMouse: true; background: Rectangle { radius: 9; color: Theme.raised; border.color: artifactField.activeFocus ? Theme.amber : Theme.border; border.width: artifactField.activeFocus ? 2 : 1 } } AppButton { text: "Escolher"; iconName: "folder_open"; enabled: maintenanceAction.currentValue !== "unlock"; onClicked: artifactDialog.open() } }
                            Text { text: "3  Partição"; color: Theme.text; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Item { }
                            AppComboBox { id: partitionBox; Layout.fillWidth: true; model: ["boot", "init_boot"]; accent: Theme.amber }
                            AppButton { Layout.alignment: Qt.AlignRight; text: "Criar prévia segura"; iconName: "fact_check"; primary: true; enabled: deviceReady && !backend.busy; onClicked: backend.planMaintenance(maintenanceAction.currentValue, artifactField.text, partitionBox.currentText) }
                        }
                    }
                    Rectangle {
                        visible: backend.maintenance.planId !== undefined
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                        radius: 12; color: Theme.surface; border.color: backend.maintenance.commitAllowed ? Theme.green : Theme.amber
                        ColumnLayout { anchors.fill: parent; anchors.margins: 19; spacing: 10
                            RowLayout { Layout.fillWidth: true; Text { Layout.fillWidth: true; text: "Prévia vinculada a " + (backend.maintenance.model || deviceName); color: Theme.text; font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold } StatusPill { label: backend.maintenance.commitAllowed ? "Execução disponível" : "Somente roteiro seguro"; accent: backend.maintenance.commitAllowed ? Theme.green : Theme.amber } }
                            ScrollView { Layout.fillWidth: true; Layout.fillHeight: true; AppTextArea { text: backend.maintenance.preview || ""; readOnly: true; color: Theme.muted; font.family: "monospace"; font.pixelSize: 12; accent: Theme.amber } }
                            RowLayout { Layout.fillWidth: true; spacing: 12
                                Text { Layout.fillWidth: true; text: backend.maintenance.commitAllowed ? "A frase obrigatória será solicitada no próximo passo." : "Esta ação permanece em roteiro/dry-run: o driver não aceita commit."; color: backend.maintenance.commitAllowed ? Theme.muted : Theme.amber; font.family: "Inter"; font.pixelSize: 12; wrapMode: Text.WordWrap }
                                AppButton { text: "Revisar e confirmar"; iconName: "security"; danger: true; enabled: backend.maintenance.commitAllowed === true && !backend.busy; onClicked: confirmationDialog.open() }
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: artifactDialog
        title: "Selecione o artefato local"
        fileMode: FileDialog.OpenFile
        onAccepted: artifactField.text = selectedFile.toString()
    }

    SafetyConfirmationDialog {
        id: confirmationDialog
        actionLabel: backend.maintenance.action || "Operação"
        deviceLabel: (backend.maintenance.model || deviceName) + " · " + (backend.maintenance.serial || backend.selectedSerial)
        requiredConfirmation: backend.maintenance.requiredConfirmation || "SIM"
        onConfirmed: backend.applyMaintenance(confirmation)
    }

    Rectangle {
        id: toast
        visible: backend.message.title !== undefined
        width: Math.min(520, window.width - sidebar.width - 60)
        height: toastDetail.visible ? 88 : 62
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        radius: 11
        color: Theme.raised
        border.width: 1
        border.color: backend.message.level === "error" ? Theme.red : backend.message.level === "success" ? Theme.green : Theme.cyan
        z: 20
        RowLayout {
            anchors.fill: parent; anchors.margins: 14; spacing: 12
            Text { text: backend.message.level === "error" ? "error" : backend.message.level === "success" ? "check_circle" : "info"; color: toast.border.color; font.family: "Material Symbols Rounded"; font.pixelSize: 23 }
            ColumnLayout { Layout.fillWidth: true; spacing: 2; Text { text: backend.message.title || ""; color: Theme.text; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold } Text { id: toastDetail; visible: text.length > 0; Layout.fillWidth: true; text: backend.message.detail || ""; color: Theme.muted; font.family: "Inter"; font.pixelSize: 11; elide: Text.ElideRight } }
            Button { text: "close"; flat: true; onClicked: backend.clearMessage(); contentItem: Text { text: parent.text; color: Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 21 } }
        }
    }

    BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 14; running: backend.busy; visible: running; z: 30 }
}
