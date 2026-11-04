pragma ComponentBehavior: Bound

import QtQuick
import Kaskad.Ipc
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    required property string actionId
    property bool recording: false
    property bool submitting: false
    property bool dirty: false
    property string errorText: ""
    readonly property bool supported: KeybindsService.currentProvider === "kaskad"
        && Kaskad.protocolVersion >= 27 && typeof Kaskad.setLauncherShortcut === "function"
    visible: supported
    spacing: Theme.spacingS

    function currentKey() {
        const keys = KeybindsService.keysForAction(actionId);
        return keys.length ? keys[0] : "";
    }

    function stopRecording() {
        if (!recording)
            return;
        recording = false;
        Kaskad.setShortcutCaptureActive(false);
    }

    function save() {
        stopRecording();
        errorText = "";
        submitting = true;
        KeybindsService.saveBind(currentKey(), {key: shortcutField.text.trim(), action: actionId});
        submitting = false;
    }

    Component.onCompleted: shortcutField.text = currentKey()
    Component.onDestruction: stopRecording()
    onVisibleChanged: if (!visible) stopRecording()

    Connections {
        target: Kaskad
        ignoreUnknownSignals: true
        function onShortcutCaptured(shortcut) {
            if (!root.recording || /(?:^|\+)Mouse(?: |\d)/.test(shortcut))
                return;
            root.stopRecording();
            if (shortcut === "Esc")
                return;
            root.dirty = true;
            shortcutField.text = shortcut;
            root.errorText = "";
        }
    }

    Connections {
        target: KeybindsService
        function onBindsLoaded() {
            if (!root.dirty && !root.recording)
                shortcutField.text = root.currentKey();
        }
        function onBindSaveCompleted(success) {
            if (!root.submitting)
                return;
            if (!success)
                root.errorText = KeybindsService.lastError;
            else
                root.dirty = false;
        }
    }

    KaskadTextField {
        id: shortcutField
        width: parent.width
        placeholderText: "Например, Super+Space"
        enabled: !root.recording
        onTextEdited: root.dirty = true
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingS
        KaskadButton {
            text: root.recording ? "Отменить запись" : "Записать клавиши"
            onClicked: {
                if (root.recording) {
                    root.stopRecording();
                } else {
                    root.errorText = "";
                    root.recording = true;
                    Kaskad.setShortcutCaptureActive(true);
                }
            }
        }
        KaskadButton {
            text: "Сохранить"
            enabled: !root.recording && shortcutField.text.trim().length > 0
            onClicked: root.save()
        }
        KaskadButton {
            text: "Убрать назначение"
            enabled: !root.recording && (KeybindsService._dataVersion >= 0 && root.currentKey().length > 0)
            onClicked: {
                root.dirty = false;
                KeybindsService.removeBind(root.currentKey());
                shortcutField.text = root.currentKey();
            }
        }
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.errorText || (root.recording ? "Нажмите сочетание. Esc — отмена." : "Изменение применяется после сохранения. Одиночный Super пока не поддерживается.")
        color: root.errorText ? Theme.error : Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }
}
