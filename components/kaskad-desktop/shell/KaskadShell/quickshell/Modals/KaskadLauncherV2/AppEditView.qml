import QtQuick
import "../../Common/ApplicationCommand.js" as ApplicationCommand
import qs.Modals.FileBrowser
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: root

    property var editingApp: null
    property string editAppId: ""

    property string validationError: ""
    property var originalOverride: ({})

    signal closeRequested

    function loadOverride() {
        var existing = SessionData.getAppOverride(editAppId);
        originalOverride = Object.assign({}, existing || {});
        validationError = "";
        editCommandField.text = ApplicationCommand.format(existing?.command || editingApp?.command || []);
        editDirectoryField.text = existing?.workingDirectory || editingApp?.workingDirectory || "";
        terminalToggle.checked = existing?.runInTerminal !== undefined ? existing.runInTerminal : !!editingApp?.runInTerminal;
        editNameField.text = existing?.name || "";
        editIconField.text = existing?.icon || "";
        editCommentField.text = existing?.comment || "";
        editEnvVarsField.text = existing?.envVars || "";
        editExtraFlagsField.text = existing?.extraFlags || "";
        Qt.callLater(() => editNameField.forceActiveFocus());
    }

    function saveAppOverride() {
        var override = Object.assign({}, originalOverride);
        for (const key of ["name", "icon", "comment", "envVars", "extraFlags", "command", "workingDirectory", "runInTerminal"])
            delete override[key];
        try {
            const command = ApplicationCommand.parse(editCommandField.text);
            if (JSON.stringify(command) !== JSON.stringify(editingApp?.command || []))
                override.command = command;
            if (editDirectoryField.text.trim() !== (editingApp?.workingDirectory || ""))
                override.workingDirectory = editDirectoryField.text.trim();
            if (terminalToggle.checked !== !!editingApp?.runInTerminal)
                override.runInTerminal = terminalToggle.checked;
            ApplicationCommand.prepare(editingApp, Object.assign({}, override, {
                envVars: editEnvVarsField.text,
                extraFlags: editExtraFlagsField.text
            }), null);
        } catch (error) {
            validationError = String(error.message || error);
            Qt.callLater(() => editFlickable.contentY = Math.max(0, validationMessage.y - Theme.spacingM));
            return;
        }
        validationError = "";
        if (editNameField.text.trim())
            override.name = editNameField.text.trim();
        if (editIconField.text.trim())
            override.icon = editIconField.text.trim();
        if (editCommentField.text.trim())
            override.comment = editCommentField.text.trim();
        if (editEnvVarsField.text.trim())
            override.envVars = editEnvVarsField.text.trim();
        if (editExtraFlagsField.text.trim())
            override.extraFlags = editExtraFlagsField.text.trim();
        if (!SessionData.setAppOverride(editAppId, override)) {
            validationError = "Не удалось сохранить настройки ярлыка. Проверьте доступ к файлу настроек. Изменения остались в форме.";
            Qt.callLater(() => editFlickable.contentY = Math.max(0, validationMessage.y - Theme.spacingM));
            return;
        }
        closeRequested();
    }

    function resetAppOverride() {
        if (!SessionData.clearAppOverride(editAppId)) {
            validationError = "Не удалось сбросить настройки ярлыка. Проверьте доступ к файлу настроек.";
            Qt.callLater(() => editFlickable.contentY = Math.max(0, validationMessage.y - Theme.spacingM));
            return;
        }
        closeRequested();
    }

    FileBrowserModal {
        id: iconBrowser
        browserTitle: "Выбрать значок"
        browserType: "generic"
        filterExtensions: ["*.svg", "*.png", "*.jpg", "*.webp"]
        onFileSelected: path => { editIconField.text = path; close(); }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier) {
                saveAppOverride();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_S && event.modifiers & Qt.ControlModifier) {
            saveAppOverride();
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                width: 40
                height: 40
                radius: Theme.cornerRadius
                color: backButtonArea.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surfaceHover, 0)

                KaskadIcon {
                    anchors.centerIn: parent
                    name: "arrow_back"
                    size: 20
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: backButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }

            Image {
                width: 40
                height: 40
                source: Paths.resolveIconUrl(root.editingApp?.icon || "application-x-executable")
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    text: "Настроить ярлык"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                }

                StyledText {
                    text: root.editingApp?.name || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineMedium
        }

        Flickable {
            id: editFlickable
            width: parent.width
            height: parent.height - y - buttonsRow.height - Theme.spacingM
            contentHeight: editFieldsColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: editFieldsColumn
                width: parent.width
                spacing: Theme.spacingS

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Name")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                    }

                    KaskadTextField {
                        id: editNameField
                        width: parent.width
                        placeholderText: root.editingApp?.name || ""
                        keyNavigationTab: editIconField
                        keyNavigationBacktab: editExtraFlagsField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Icon")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                    }

                    KaskadTextField {
                        id: editIconField
                        width: parent.width
                        placeholderText: root.editingApp?.icon || ""
                        keyNavigationTab: editCommentField
                        keyNavigationBacktab: editNameField
                    }
                    KaskadButton {
                        text: "Выбрать изображение…"
                        onClicked: iconBrowser.open()
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Description")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                    }

                    KaskadTextField {
                        id: editCommentField
                        width: parent.width
                        placeholderText: root.editingApp?.comment || ""
                        keyNavigationTab: editCommandField
                        keyNavigationBacktab: editIconField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    StyledText { text: "Команда запуска"; color: Theme.surfaceText }
                    StyledText {
                        width: parent.width
                        text: "Программа и аргументы. Например: prime-run \"/путь/к программе\". Это команда запуска в Kaskad DE, не исходная строка Exec: коды %U и %F сюда добавлять не нужно."
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    KaskadTextField {
                        id: editCommandField
                        width: parent.width
                        keyNavigationTab: editDirectoryField
                        keyNavigationBacktab: editCommentField
                    }
                    StyledText {
                        width: parent.width
                        text: "Изменения применятся при новом запуске. Уже открытое приложение продолжит работать с прежними параметрами."
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    StyledText { text: "Рабочая папка"; color: Theme.surfaceText }
                    KaskadTextField {
                        id: editDirectoryField
                        width: parent.width
                        placeholderText: "Пусто — папка приложения или домашняя папка"
                        keyNavigationTab: editEnvVarsField
                        keyNavigationBacktab: editCommandField
                    }
                }
                KaskadToggle {
                    id: terminalToggle
                    width: parent.width
                    text: "Запускать в терминале"
                    onToggled: checked => terminalToggle.checked = checked
                }
                StyledText {
                    id: validationMessage
                    width: parent.width
                    visible: root.validationError.length > 0
                    text: root.validationError
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Environment Variables")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: "KEY=value KEY2=value2"
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }

                    KaskadTextField {
                        id: editEnvVarsField
                        width: parent.width
                        placeholderText: "VAR=value"
                        keyNavigationTab: editExtraFlagsField
                        keyNavigationBacktab: editDirectoryField
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: I18n.tr("Extra Arguments")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        font.weight: Font.Medium
                    }

                    KaskadTextField {
                        id: editExtraFlagsField
                        width: parent.width
                        placeholderText: "--flag --option=value"
                        keyNavigationTab: editNameField
                        keyNavigationBacktab: editEnvVarsField
                    }
                }
            }
        }

        Row {
            id: buttonsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS
            KaskadButton {
                text: "Сбросить"
                visible: SessionData.getAppOverride(root.editAppId) !== null
                onClicked: root.resetAppOverride()
            }
            KaskadButton { text: "Отмена"; onClicked: root.closeRequested() }
            KaskadButton { text: "Сохранить"; onClicked: root.saveAppOverride() }
        }
    }
}
