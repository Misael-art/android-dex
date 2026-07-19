import QtQuick
import QtQuick.Controls
import QtTest 1.3
import "../src/android_dex_ui/qml" as AndroidDex

TestCase {
    id: testCase
    name: "AndroidDexInteraction"
    when: windowShown

    Component {
        id: buttonComponent
        AndroidDex.AppButton {
            text: "Iniciar modo desktop"
            iconName: "desktop_windows"
            primary: true
        }
    }
    Component {
        id: navigationComponent
        AndroidDex.NavItem {
            width: 260
            text: "Dispositivos"
            iconName: "smartphone"
        }
    }
    Component {
        id: comboComponent
        AndroidDex.AppComboBox {
            width: 260
            model: ["boot", "init_boot"]
        }
    }
    Component {
        id: dialogComponent
        AndroidDex.SafetyConfirmationDialog {
            actionLabel: "Iniciar recovery temporário"
            deviceLabel: "Pixel 8 Pro · TESTE"
            requiredConfirmation: "SIM"
        }
    }

    function test_primary_button_is_keyboard_activatable() {
        const button = createTemporaryObject(buttonComponent, testCase)
        verify(button !== null)
        let activations = 0
        button.clicked.connect(function() { activations += 1 })
        button.forceActiveFocus()
        verify(button.activeFocus)
        keyClick(Qt.Key_Space)
        compare(activations, 1)
    }

    function test_navigation_exposes_name_and_keyboard_activation() {
        const nav = createTemporaryObject(navigationComponent, testCase)
        verify(nav !== null)
        compare(nav.Accessible.name, "Dispositivos")
        let activations = 0
        nav.clicked.connect(function() { activations += 1 })
        nav.forceActiveFocus()
        verify(nav.activeFocus)
        keyClick(Qt.Key_Return)
        compare(activations, 1)
    }

    function test_combo_can_open_and_close_from_keyboard() {
        const combo = createTemporaryObject(comboComponent, testCase)
        verify(combo !== null)
        combo.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryVerify(function() { return combo.popup.visible })
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !combo.popup.visible })
    }

    function test_critical_dialog_requires_explicit_phrase_and_closes_on_escape() {
        const dialog = createTemporaryObject(dialogComponent, testCase)
        verify(dialog !== null)
        compare(dialog.Accessible.name, "Confirmação de operação crítica")
        dialog.open()
        tryVerify(function() { return dialog.visible })
        compare(dialog.confirmation, "")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !dialog.visible })
    }
}
