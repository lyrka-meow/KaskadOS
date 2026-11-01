pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

FloatingWindow {
    id: root

    property string editorMode: ""
    property string pendingDanger: ""
    property var pendingDangerEntry: null
    property var formatTarget: null
    property bool formatStarting: false
    property string storageAction: ""
    property bool storageActionBusy: false
    property string archivePasswordPath: ""
    property string archivePasswordName: ""
    property string archivePasswordError: ""
    property bool archivePasswordBusy: false
    property bool splitEnabled: false
    property int activePane: 0
    property string secondaryPath: FileManagerService.homePath
    property string secondaryParentPath: ""
    property var secondaryEntries: []
    property var secondarySelectedEntry: null
    property bool secondaryLoading: false
    property string secondaryRefreshedOperation: ""
    property var primaryScrollPositions: ({})

    Shortcut {
        sequence: StandardKey.Copy
        context: Qt.WindowShortcut
        enabled: root.visible && !root.textInputActive()
        onActivated: root.rememberActive(false)
    }
    Shortcut {
        sequence: StandardKey.Cut
        context: Qt.WindowShortcut
        enabled: root.visible && !root.textInputActive()
        onActivated: root.rememberActive(true)
    }
    Shortcut {
        sequence: StandardKey.Paste
        context: Qt.WindowShortcut
        enabled: root.visible && !root.textInputActive()
        onActivated: root.pasteActive()
    }
    Shortcut {
        sequence: StandardKey.Delete
        context: Qt.WindowShortcut
        enabled: root.visible && !root.textInputActive()
        onActivated: {
            if (FileManagerService.viewMode === "trash" && root.activeEntry()) {
                root.pendingDangerEntry = FileManagerService.selectedEntry;
                root.pendingDanger = "delete";
            } else {
                root.trashActive();
            }
        }
    }
    Shortcut {
        sequence: "F3"
        context: Qt.WindowShortcut
        enabled: root.visible && FileManagerService.viewMode === "files" && !root.textInputActive()
        onActivated: root.setSplitEnabled(!root.splitEnabled)
    }

    function textInputActive() {
        return locationField.activeFocus || secondaryLocationField.activeFocus
            || nameEditor.activeFocus || archivePasswordInput.activeFocus;
    }

    function activeEntry() {
        return FileManagerService.viewMode === "files" && splitEnabled && activePane === 1
            ? secondarySelectedEntry : FileManagerService.selectedEntry;
    }

    function activeDirectory() {
        return splitEnabled && activePane === 1 ? secondaryPath : FileManagerService.currentPath;
    }

    function rememberActive(move) {
        FileManagerService.rememberEntry(activeEntry(), move);
    }

    function pasteActive() {
        FileManagerService.pasteTo(activeDirectory());
    }

    function trashActive() {
        const entry = activeEntry();
        if (!entry)
            return;
        FileManagerService.trashEntry(entry, success => {
            if (success && splitEnabled)
                navigateSecondary(secondaryPath);
        });
    }

    function navigateSecondary(path) {
        if (!path || !FileManagerService.available)
            return;
        secondaryLoading = true;
        secondarySelectedEntry = null;
        KaskadService.filesList(path, FileManagerService.showHidden, response => {
            secondaryLoading = false;
            if (response?.result) {
                secondaryPath = response.result.path;
                secondaryParentPath = response.result.parent || "";
                secondaryEntries = response.result.entries || [];
            } else {
                ToastService.showError(response?.error || "Не удалось открыть папку.", "", "", "files");
            }
        });
    }

    function savePrimaryScroll(path) {
        if (!path || !fileList)
            return;
        const updated = Object.assign({}, primaryScrollPositions);
        updated[path] = fileList.contentY;
        primaryScrollPositions = updated;
    }

    function restorePrimaryScroll(path) {
        const saved = primaryScrollPositions[path];
        Qt.callLater(() => {
            if (saved === undefined) {
                fileList.positionViewAtBeginning();
                return;
            }
            fileList.contentY = Number(saved);
            fileList.returnToBounds();
        });
    }

    function setSplitEnabled(enabled) {
        splitEnabled = enabled === true;
        if (splitEnabled) {
            activePane = 1;
            navigateSecondary(secondaryPath || FileManagerService.currentPath);
        } else {
            activePane = 0;
        }
    }

    function commitNameEdit() {
        const value = nameEditor.text.trim();
        if (value.length === 0)
            return;
        if (editorMode === "mkdir")
            FileManagerService.makeDirectoryAt(activeDirectory(), value,
                success => { if (success && splitEnabled) navigateSecondary(secondaryPath); });
        else
            FileManagerService.renameEntry(activeEntry(), value,
                success => { if (success && splitEnabled) navigateSecondary(secondaryPath); });
        nameEditor.text = "";
        editorMode = "";
    }

    function openFormatPanel(device) {
        if (!device || device.readOnly || device.system || device.layered || !device.path)
            return;
        formatTarget = device;
        formatStarting = false;
        formatType.currentValue = "exFAT";
        formatLabel.text = device.label && device.label !== device.name ? device.label : "KASKADOS";
        formatAcknowledgement.checked = false;
    }

    function closeFormatPanel() {
        if (formatStarting)
            return;
        formatTarget = null;
        formatAcknowledgement.checked = false;
    }

    function closeArchivePasswordPanel() {
        if (archivePasswordBusy)
            return;
        archivePasswordInput.text = "";
        archivePasswordPath = "";
        archivePasswordName = "";
        archivePasswordError = "";
    }

    function submitArchivePassword() {
        if (archivePasswordBusy || archivePasswordPath.length === 0)
            return;
        if (archivePasswordInput.text.length === 0) {
            archivePasswordError = "Введите пароль";
            archivePasswordInput.forceActiveFocus();
            return;
        }
        archivePasswordBusy = true;
        archivePasswordError = "";
        FileManagerService.extractWithPassword(archivePasswordPath, archivePasswordName,
                                                archivePasswordInput.text, (success, errorText) => {
            archivePasswordBusy = false;
            if (success) {
                closeArchivePasswordPanel();
                return;
            }
            archivePasswordInput.text = "";
            archivePasswordError = errorText || "Не удалось распаковать архив";
            archivePasswordInput.forceActiveFocus();
        });
    }

    objectName: "kaskadosFileManager"
    title: "Файлы - KaskadOS"
    minimumSize: Qt.size(820, 480)
    implicitWidth: 980
    implicitHeight: 680
    color: Theme.surfaceContainer
    visible: false

    function showAt(path) {
        visible = true;
        if (path)
            FileManagerService.navigate(path);
        Qt.callLater(() => locationField.forceActiveFocus());
    }

    onClosed: {
        if (FileManagerService.viewMode === "files")
            savePrimaryScroll(FileManagerService.currentPath);
        visible = false;
    }

    Column {
        anchors.fill: parent

        Rectangle {
            width: parent.width
            height: 58
            color: Theme.surfaceContainerHigh

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingXS

                KaskadActionButton {
                    buttonSize: 36
                    iconName: "arrow_upward"
                    iconColor: Theme.surfaceText
                    backgroundColor: Theme.surfaceContainerHighest
                    enabled: FileManagerService.viewMode === "files" && FileManagerService.parentPath.length > 0
                    tooltipText: "На уровень выше"
                    onClicked: FileManagerService.navigate(FileManagerService.parentPath)
                }

                KaskadActionButton {
                    buttonSize: 36
                    iconName: "home"
                    iconColor: Theme.surfaceText
                    backgroundColor: Theme.surfaceContainerHighest
                    tooltipText: "Домашняя папка"
                    onClicked: FileManagerService.navigate(FileManagerService.homePath)
                }

                KaskadActionButton {
                    buttonSize: 36
                    iconName: "refresh"
                    iconColor: Theme.surfaceText
                    backgroundColor: Theme.surfaceContainerHighest
                    tooltipText: "Обновить"
                    onClicked: FileManagerService.refresh()
                }

                KaskadTextField {
                    id: locationField
                    width: Math.max(220, parent.width - 284)
                    height: 38
                    text: FileManagerService.viewMode === "trash" ? "Корзина"
                        : FileManagerService.viewMode === "storage" ? "Управление дисками"
                        : FileManagerService.currentPath
                    leftIconName: FileManagerService.viewMode === "trash" ? "delete"
                        : FileManagerService.viewMode === "storage" ? "hard_drive" : "folder"
                    showClearButton: false
                    enabled: FileManagerService.viewMode === "files"
                    onAccepted: if (FileManagerService.viewMode === "files") FileManagerService.navigate(text.trim())
                }

                KaskadActionButton {
                    buttonSize: 36
                    iconName: FileManagerService.showHidden ? "visibility" : "visibility_off"
                    iconColor: FileManagerService.showHidden ? Theme.primary : Theme.surfaceVariantText
                    backgroundColor: Theme.surfaceContainerHighest
                    tooltipText: FileManagerService.showHidden ? "Скрытые файлы показаны" : "Показать скрытые файлы"
                    onClicked: FileManagerService.setShowHidden(!FileManagerService.showHidden)
                }

                KaskadActionButton {
                    buttonSize: 36
                    iconName: "vertical_split"
                    iconColor: root.splitEnabled ? Theme.primary : Theme.surfaceVariantText
                    backgroundColor: Theme.surfaceContainerHighest
                    enabled: FileManagerService.viewMode === "files"
                    tooltipText: root.splitEnabled ? "Закрыть вторую панель (F3)" : "Открыть вторую панель (F3)"
                    onClicked: root.setSplitEnabled(!root.splitEnabled)
                }
            }

        }

        Rectangle {
            width: parent.width
            height: editorRow.visible ? 50 : 0
            visible: root.editorMode.length > 0
            color: Theme.surfaceContainer
            clip: true

            Row {
                id: editorRow
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS

                KaskadTextField {
                    id: nameEditor
                    width: parent.width - saveNameButton.width - cancelNameButton.width - Theme.spacingS * 2
                    height: 36
                    placeholderText: root.editorMode === "mkdir" ? "Название новой папки" : "Новое имя"
                    onAccepted: root.commitNameEdit()
                }

                KaskadActionButton {
                    id: saveNameButton
                    buttonSize: 36
                    iconName: "check"
                    iconColor: Theme.onPrimary
                    backgroundColor: Theme.primary
                    tooltipText: "Сохранить"
                    onClicked: root.commitNameEdit()
                }

                KaskadActionButton {
                    id: cancelNameButton
                    buttonSize: 36
                    iconName: "close"
                    iconColor: Theme.surfaceText
                    backgroundColor: Theme.surfaceContainerHighest
                    tooltipText: "Отмена"
                    onClicked: root.editorMode = ""
                }
            }
        }

        Row {
            id: browserBody
            width: parent.width
            height: parent.height - y

            Rectangle {
                id: placesSidebar
                width: Math.min(230, Math.max(178, browserBody.width * 0.23))
                height: parent.height
                color: Theme.surfaceContainerHigh

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingXS

                    SidebarPlace {
                        width: parent.width
                        text: "Файлы"
                        subtitle: FileManagerService.currentPath
                        iconName: "home"
                        active: FileManagerService.viewMode === "files"
                        onClicked: FileManagerService.navigate(FileManagerService.currentPath || FileManagerService.homePath)
                    }

                    SidebarPlace {
                        width: parent.width
                        text: "Корзина"
                        subtitle: "Восстановление и окончательное удаление"
                        iconName: "delete"
                        active: FileManagerService.viewMode === "trash"
                        onClicked: FileManagerService.openTrash()
                    }

                    SidebarPlace {
                        width: parent.width
                        text: "Диски"
                        subtitle: "Разделы и свободное место"
                        iconName: "hard_drive"
                        active: FileManagerService.viewMode === "storage"
                        onClicked: FileManagerService.openStorage()
                    }

                    StyledText {
                        width: parent.width
                        height: 32
                        verticalAlignment: Text.AlignBottom
                        text: "Накопители"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceVariantText
                    }

                    ListView {
                        id: deviceList
                        width: parent.width
                        height: Math.max(0, parent.height - y)
                        clip: true
                        spacing: 4
                        model: FileManagerService.devices

                        delegate: Rectangle {
                            id: deviceRow
                            required property var modelData
                            required property int index
                            width: deviceList.width
                            height: 68
                            radius: Theme.cornerRadius
                            color: deviceArea.containsMouse ? Theme.primaryHoverLight : "transparent"

                            MouseArea {
                                id: deviceArea
                                anchors.fill: parent
                                anchors.rightMargin: deviceAction.width
                                    + (formatAction.visible ? formatAction.width + Theme.spacingXS : 0)
                                    + Theme.spacingXS
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: FileManagerService.openDevice(deviceRow.modelData)
                            }

                            Item {
                                id: deviceGlyph
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 34

                                Image {
                                    anchors.centerIn: parent
                                    width: deviceRow.modelData.compatibility === "universal" ? 26 : 32
                                    height: width
                                    source: Qt.resolvedUrl("../assets/kaskados-logo.png")
                                    fillMode: Image.PreserveAspectFit
                                    visible: ["kaskados", "universal"].includes(deviceRow.modelData.compatibility)
                                }

                                KaskadIcon {
                                    anchors.centerIn: parent
                                    name: deviceRow.modelData.compatibility === "windows" ? "window" : "hard_drive"
                                    size: 27
                                    color: deviceRow.modelData.compatibility === "windows" ? Theme.info : Theme.surfaceVariantText
                                    visible: ["windows", "other"].includes(deviceRow.modelData.compatibility)
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: Theme.surfaceContainerHigh
                                    border.width: 1
                                    border.color: Theme.outlineVariant
                                    visible: deviceRow.modelData.compatibility === "universal"
                                    KaskadIcon {
                                        anchors.centerIn: parent
                                        name: "window"
                                        size: 14
                                        color: Theme.info
                                    }
                                }
                            }

                            Column {
                                anchors.left: deviceGlyph.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: formatAction.visible ? formatAction.left : deviceAction.left
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    width: parent.width
                                    text: deviceRow.modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    width: parent.width
                                    text: FileManagerService.compatibilityLabel(deviceRow.modelData)
                                        + " · " + root.formatSize(deviceRow.modelData.sizeBytes)
                                    font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2)
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }
                            }

                            KaskadActionButton {
                                id: formatAction
                                anchors.right: deviceAction.left
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                visible: deviceRow.modelData.removable === true
                                enabled: !deviceRow.modelData.readOnly && !FileManagerService.operationActive()
                                buttonSize: 32
                                iconName: "format_paint"
                                iconColor: Theme.error
                                backgroundColor: Theme.withAlpha(Theme.error, 0.09)
                                tooltipText: deviceRow.modelData.readOnly ? "Накопитель защищён от записи" : "Форматировать"
                                onClicked: root.openFormatPanel(deviceRow.modelData)
                            }

                            KaskadActionButton {
                                id: deviceAction
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                buttonSize: 32
                                iconName: deviceRow.modelData.mounted ? "eject" : "mount"
                                iconColor: deviceRow.modelData.mounted ? Theme.primary : Theme.surfaceVariantText
                                backgroundColor: Theme.surfaceContainerHighest
                                enabled: !FileManagerService.operationActive()
                                tooltipText: deviceRow.modelData.mounted
                                    ? (deviceRow.modelData.removable ? "Безопасно извлечь" : "Отключить")
                                    : "Подключить"
                                onClicked: {
                                    if (deviceRow.modelData.mounted)
                                        FileManagerService.safelyRemove(deviceRow.modelData);
                                    else
                                        FileManagerService.openDevice(deviceRow.modelData);
                                }
                            }
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spacingM
                            visible: deviceList.count === 0
                            text: "Накопителей нет"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            Column {
                id: contentColumn
                width: browserBody.width - placesSidebar.width
                height: browserBody.height

                Rectangle {
                    id: dangerBar
                    width: parent.width
                    height: root.pendingDanger.length > 0 ? 72 : 0
                    visible: height > 0
                    color: Theme.withAlpha(Theme.error, 0.09)
                    clip: true

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: dangerButtons.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pendingDanger === "empty"
                            ? "Окончательно удалить всё содержимое корзины?"
                            : "Окончательно удалить «" + (root.pendingDangerEntry?.name || "") + "»?"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.error
                        elide: Text.ElideRight
                    }

                    Row {
                        id: dangerButtons
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS
                        KaskadButton {
                            text: "Отмена"
                            backgroundColor: Theme.surfaceContainerHighest
                            textColor: Theme.surfaceText
                            onClicked: {
                                root.pendingDanger = "";
                                root.pendingDangerEntry = null;
                            }
                        }
                        KaskadButton {
                            text: "Удалить навсегда"
                            iconName: "delete_forever"
                            backgroundColor: Theme.error
                            textColor: Theme.surface
                            onClicked: {
                                if (root.pendingDanger === "empty")
                                    FileManagerService.emptyTrash();
                                else
                                    FileManagerService.deleteTrashEntry(root.pendingDangerEntry);
                                root.pendingDanger = "";
                                root.pendingDangerEntry = null;
                            }
                        }
                    }
                }

                Item {
                    id: fileArea
                    width: parent.width
                    height: parent.height - dangerBar.height - operationPanel.height - actionBar.height
                    visible: FileManagerService.viewMode !== "storage"

                    ListView {
                    id: fileList
                    width: root.splitEnabled && FileManagerService.viewMode === "files"
                        ? Math.floor(parent.width / 2) : parent.width
                    height: parent.height
                    clip: true
                    spacing: 2
                    model: FileManagerService.entries

                    header: Rectangle {
                        width: fileList.width
                        height: 32
                        color: Theme.surfaceContainer

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 72
                            anchors.rightMargin: Theme.spacingL
                            StyledText { width: parent.width * 0.52; anchors.verticalCenter: parent.verticalCenter; text: "Имя"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText {
                                width: parent.width * 0.30
                                anchors.verticalCenter: parent.verticalCenter
                                text: FileManagerService.viewMode === "trash" ? "Было расположено" : "Тип"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText { width: parent.width * 0.18; anchors.verticalCenter: parent.verticalCenter; text: "Размер"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    delegate: Rectangle {
                        id: fileRow
                        required property var modelData
                        required property int index
                        width: fileList.width
                        height: 52
                        radius: Theme.cornerRadius
                        color: rowDropArea.containsDrag && modelData.directory
                            ? Theme.withAlpha(Theme.primary, 0.24)
                            : FileManagerService.selectedEntry?.path === modelData.path
                            ? Theme.primaryPressed : rowArea.containsMouse ? Theme.primaryHoverLight : "transparent"

                        Item {
                            id: rowDragProxy
                            property real pressX: 0
                            property real pressY: 0
                            width: 1
                            height: 1
                            Drag.active: rowArea.drag.active
                            Drag.source: fileRow
                            Drag.keys: ["kaskados-file-entry"]
                            Drag.supportedActions: Qt.MoveAction
                            Drag.proposedAction: Qt.MoveAction
                            Drag.hotSpot.x: pressX
                            Drag.hotSpot.y: pressY
                        }

                        DropArea {
                            id: rowDropArea
                            anchors.fill: parent
                            keys: ["kaskados-file-entry"]
                            enabled: FileManagerService.viewMode === "files" && fileRow.modelData.directory
                                && !FileManagerService.operationActive()
                            onDropped: drop => {
                                const sourceEntry = drop.source?.modelData;
                                if (!sourceEntry || sourceEntry.path === fileRow.modelData.path)
                                    return;
                                FileManagerService.moveEntryTo(sourceEntry, fileRow.modelData.path);
                                drop.acceptProposedAction();
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            drag.target: FileManagerService.viewMode === "files" ? rowDragProxy : null
                            drag.threshold: 8
                            onPressed: mouse => {
                                rowDragProxy.x = 0;
                                rowDragProxy.y = 0;
                                rowDragProxy.pressX = mouse.x;
                                rowDragProxy.pressY = mouse.y;
                            }
                            onReleased: {
                                if (drag.active)
                                    rowDragProxy.Drag.drop();
                            }
                            onClicked: {
                                FileManagerService.selectedEntry = fileRow.modelData;
                                root.activePane = 0;
                                fileList.forceActiveFocus();
                            }
                            onDoubleClicked: if (FileManagerService.viewMode === "files") FileManagerService.activate(fileRow.modelData)
                        }

                        KaskadIcon {
                            id: entryIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingL
                            anchors.verticalCenter: parent.verticalCenter
                            name: {
                                if (fileRow.modelData.directory) return "folder";
                                const lower = fileRow.modelData.name.toLowerCase();
                                if (lower.endsWith(".exe")) return "window";
                                if (lower.includes(".pkg.tar.")) return "package_2";
                                if (FileManagerService.isArchive(lower)) return "folder_zip";
                                return "description";
                            }
                            size: 27
                            color: fileRow.modelData.directory ? Theme.primary : Theme.surfaceVariantText
                        }

                        Row {
                            anchors.left: entryIcon.right
                            anchors.leftMargin: Theme.spacingL
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingL
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText { width: parent.width * 0.52; text: fileRow.modelData.name; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; elide: Text.ElideRight }
                            StyledText {
                                width: parent.width * 0.30
                                text: FileManagerService.viewMode === "trash"
                                    ? (fileRow.modelData.originalPath || "")
                                    : fileRow.modelData.directory ? "Папка" : (fileRow.modelData.mimeType || "Файл")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                            }
                            StyledText { width: parent.width * 0.18; text: fileRow.modelData.directory ? "" : root.formatSize(fileRow.modelData.sizeBytes); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: !FileManagerService.loading && fileList.count === 0
                        text: FileManagerService.viewMode === "trash" ? "Корзина пуста" : "Папка пуста"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                    }
                    }

                    Rectangle {
                        id: secondaryPane
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: fileList.right
                        anchors.right: parent.right
                        visible: root.splitEnabled && FileManagerService.viewMode === "files"
                        color: Theme.surfaceContainer
                        border.width: root.activePane === 1 ? 1 : 0
                        border.color: Theme.primary

                        Column {
                            anchors.fill: parent

                            Rectangle {
                                width: parent.width
                                height: 42
                                color: Theme.surfaceContainerHigh

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 4

                                    KaskadActionButton {
                                        buttonSize: 34
                                        iconName: "arrow_upward"
                                        iconColor: Theme.surfaceText
                                        backgroundColor: Theme.surfaceContainerHighest
                                        enabled: root.secondaryParentPath.length > 0
                                        tooltipText: "На уровень выше"
                                        onClicked: root.navigateSecondary(root.secondaryParentPath)
                                    }

                                    KaskadTextField {
                                        id: secondaryLocationField
                                        width: parent.width - 42
                                        height: 34
                                        text: root.secondaryPath
                                        leftIconName: "folder"
                                        showClearButton: false
                                        onActiveFocusChanged: if (activeFocus) root.activePane = 1
                                        onAccepted: root.navigateSecondary(text.trim())
                                    }
                                }
                            }

                            ListView {
                                id: secondaryFileList
                                width: parent.width
                                height: parent.height - 42
                                clip: true
                                spacing: 2
                                model: root.secondaryEntries

                                header: Rectangle {
                                    width: secondaryFileList.width
                                    height: 32
                                    color: Theme.surfaceContainer
                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingL
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Имя"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                delegate: Rectangle {
                                    id: secondaryFileRow
                                    required property var modelData
                                    required property int index
                                    width: secondaryFileList.width
                                    height: 52
                                    radius: Theme.cornerRadius
                                    color: secondaryDropArea.containsDrag && modelData.directory
                                        ? Theme.withAlpha(Theme.primary, 0.24)
                                        : root.secondarySelectedEntry?.path === modelData.path
                                        ? Theme.primaryPressed
                                        : secondaryRowArea.containsMouse ? Theme.primaryHoverLight : "transparent"

                                    Item {
                                        id: secondaryDragProxy
                                        property real pressX: 0
                                        property real pressY: 0
                                        width: 1
                                        height: 1
                                        Drag.active: secondaryRowArea.drag.active
                                        Drag.source: secondaryFileRow
                                        Drag.keys: ["kaskados-file-entry"]
                                        Drag.supportedActions: Qt.MoveAction
                                        Drag.proposedAction: Qt.MoveAction
                                        Drag.hotSpot.x: pressX
                                        Drag.hotSpot.y: pressY
                                    }

                                    DropArea {
                                        id: secondaryDropArea
                                        anchors.fill: parent
                                        keys: ["kaskados-file-entry"]
                                        enabled: secondaryFileRow.modelData.directory && !FileManagerService.operationActive()
                                        onDropped: drop => {
                                            const sourceEntry = drop.source?.modelData;
                                            if (!sourceEntry || sourceEntry.path === secondaryFileRow.modelData.path)
                                                return;
                                            FileManagerService.moveEntryTo(sourceEntry, secondaryFileRow.modelData.path);
                                            drop.acceptProposedAction();
                                        }
                                    }

                                    MouseArea {
                                        id: secondaryRowArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: secondaryDragProxy
                                        drag.threshold: 8
                                        onPressed: mouse => {
                                            secondaryDragProxy.x = 0;
                                            secondaryDragProxy.y = 0;
                                            secondaryDragProxy.pressX = mouse.x;
                                            secondaryDragProxy.pressY = mouse.y;
                                        }
                                        onReleased: {
                                            if (drag.active)
                                                secondaryDragProxy.Drag.drop();
                                        }
                                        onClicked: {
                                            root.secondarySelectedEntry = secondaryFileRow.modelData;
                                            root.activePane = 1;
                                            secondaryFileList.forceActiveFocus();
                                        }
                                        onDoubleClicked: {
                                            if (secondaryFileRow.modelData.directory)
                                                root.navigateSecondary(secondaryFileRow.modelData.path);
                                            else
                                                FileManagerService.activate(secondaryFileRow.modelData);
                                        }
                                    }

                                    KaskadIcon {
                                        id: secondaryEntryIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingL
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: secondaryFileRow.modelData.directory ? "folder"
                                            : FileManagerService.isArchive(secondaryFileRow.modelData.name.toLowerCase())
                                            ? "folder_zip" : "description"
                                        size: 27
                                        color: secondaryFileRow.modelData.directory ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        anchors.left: secondaryEntryIcon.right
                                        anchors.leftMargin: Theme.spacingM
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingL
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: secondaryFileRow.modelData.name
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: !root.secondaryLoading && secondaryFileList.count === 0
                                    text: "Папка пуста"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }

                Item {
                    id: storageView
                    width: parent.width
                    height: parent.height - dangerBar.height - operationPanel.height
                    visible: FileManagerService.viewMode === "storage"

                    Row {
                        anchors.fill: parent

                        Rectangle {
                            width: Math.min(220, storageView.width * 0.28)
                            height: parent.height
                            color: Theme.surfaceContainer

                            Column {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                StyledText {
                                    width: parent.width
                                    text: "Физические накопители"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }

                                ListView {
                                    id: physicalDiskList
                                    width: parent.width
                                    height: parent.height - y
                                    spacing: Theme.spacingXS
                                    clip: true
                                    model: FileManagerService.storageDisks

                                    delegate: Rectangle {
                                        id: physicalDiskRow
                                        required property var modelData
                                        width: physicalDiskList.width
                                        height: 76
                                        radius: Theme.cornerRadius
                                        color: FileManagerService.selectedDisk?.path === modelData.path
                                            ? Theme.primaryPressed : physicalDiskArea.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh

                                        KaskadIcon {
                                            id: physicalDiskIcon
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: physicalDiskRow.modelData.removable || physicalDiskRow.modelData.hotplug ? "usb" : "hard_drive"
                                            size: 27
                                            color: physicalDiskRow.modelData.system ? Theme.primary : Theme.surfaceVariantText
                                        }
                                        Column {
                                            anchors.left: physicalDiskIcon.right
                                            anchors.leftMargin: Theme.spacingS
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            StyledText {
                                                width: parent.width
                                                text: root.diskTitle(physicalDiskRow.modelData)
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                width: parent.width
                                                text: root.formatSize(physicalDiskRow.modelData.sizeBytes)
                                                    + (physicalDiskRow.modelData.system ? " · Система" : "")
                                                font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2)
                                                color: Theme.surfaceVariantText
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: physicalDiskArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                FileManagerService.selectStorageDisk(physicalDiskRow.modelData);
                                                root.storageAction = "";
                                            }
                                        }
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: physicalDiskList.count === 0 && !FileManagerService.storageLoading
                                        text: "Диски не найдены"
                                        color: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width - Math.min(220, storageView.width * 0.28)
                            height: parent.height
                            color: Theme.surfaceContainerHigh

                            Column {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Row {
                                    width: parent.width
                                    height: 54
                                    spacing: Theme.spacingM

                                    Column {
                                        width: parent.width - diskTableButton.width
                                            - (diskEjectButton.visible ? diskEjectButton.width + parent.spacing : 0)
                                            - parent.spacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        StyledText {
                                            width: parent.width
                                            text: FileManagerService.selectedDisk ? root.diskTitle(FileManagerService.selectedDisk) : "Выберите накопитель"
                                            font.pixelSize: Theme.fontSizeLarge
                                            font.weight: Font.DemiBold
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            width: parent.width
                                            text: FileManagerService.selectedDisk
                                                ? root.diskSubtitle(FileManagerService.selectedDisk) : ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                        }
                                    }

                                    KaskadButton {
                                        id: diskEjectButton
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: FileManagerService.selectedDisk?.removable || FileManagerService.selectedDisk?.hotplug
                                        text: "Извлечь"
                                        iconName: "eject"
                                        backgroundColor: Theme.surfaceContainerHighest
                                        textColor: Theme.surfaceText
                                        enabled: !FileManagerService.operationActive()
                                        onClicked: FileManagerService.safelyRemoveDisk(FileManagerService.selectedDisk)
                                    }

                                    KaskadButton {
                                        id: diskTableButton
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: FileManagerService.selectedDisk?.partitionTable ? "Переразметить" : "Подготовить диск"
                                        iconName: "delete_sweep"
                                        backgroundColor: Theme.withAlpha(Theme.error, 0.1)
                                        textColor: Theme.error
                                        enabled: FileManagerService.selectedDisk !== null
                                            && !FileManagerService.selectedDisk.system
                                            && !FileManagerService.selectedDisk.readOnly
                                            && !(FileManagerService.selectedDisk.regions || []).some(region => region.mounted)
                                            && !FileManagerService.operationActive()
                                        onClicked: root.beginStorageAction("table")
                                    }
                                }

                                Flickable {
                                    id: partitionMap
                                    width: parent.width
                                    height: 82
                                    contentWidth: width
                                    contentHeight: height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    Row {
                                        id: regionStrip
                                        width: partitionMap.width
                                        height: parent.height
                                        spacing: 4

                                        Repeater {
                                            model: FileManagerService.selectedDisk?.regions || []
                                            delegate: Rectangle {
                                                id: mapRegion
                                                required property var modelData
                                                required property int index
                                                width: root.partitionRegionWidth(index)
                                                height: partitionMap.height
                                                radius: Theme.cornerRadius
                                                color: root.regionColor(modelData,
                                                    FileManagerService.selectedRegion === modelData
                                                    || (modelData.path && FileManagerService.selectedRegion?.path === modelData.path)
                                                    || (!modelData.path && Number(FileManagerService.selectedRegion?.offsetBytes) === Number(modelData.offsetBytes)))
                                                border.width: 1
                                                border.color: modelData.system ? Theme.primary : Theme.outlineVariant

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: Theme.spacingS
                                                    spacing: 1
                                                    StyledText {
                                                        width: parent.width
                                                        text: modelData.kind === "free" ? "Свободно" : (modelData.label || modelData.name)
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.Medium
                                                        color: Theme.surfaceText
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        width: parent.width
                                                        text: root.formatSize(modelData.sizeBytes)
                                                            + (modelData.fileSystem ? " · " + modelData.fileSystem.toUpperCase() : "")
                                                        font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2)
                                                        color: Theme.surfaceVariantText
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        FileManagerService.selectStorageRegion(mapRegion.modelData);
                                                        root.storageAction = "";
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: parent.height - y
                                    spacing: Theme.spacingM

                                    ListView {
                                        id: regionList
                                        width: Math.min(300, parent.width * 0.42)
                                        height: parent.height
                                        spacing: Theme.spacingXS
                                        clip: true
                                        model: FileManagerService.selectedDisk?.regions || []

                                        delegate: Rectangle {
                                            id: regionRow
                                            required property var modelData
                                            width: regionList.width
                                            height: 62
                                            radius: Theme.cornerRadius
                                            color: (modelData.path && FileManagerService.selectedRegion?.path === modelData.path)
                                                || (!modelData.path && Number(FileManagerService.selectedRegion?.offsetBytes) === Number(modelData.offsetBytes))
                                                ? Theme.primaryPressed : regionArea.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainer
                                            KaskadIcon {
                                                id: regionIcon
                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: modelData.kind === "free" ? "add_circle" : modelData.system ? "verified_user" : "storage"
                                                size: 24
                                                color: modelData.kind === "free" ? Theme.primary : modelData.system ? Theme.primary : Theme.surfaceVariantText
                                            }
                                            Column {
                                                anchors.left: regionIcon.right
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.right: parent.right
                                                anchors.rightMargin: Theme.spacingS
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1
                                                StyledText { width: parent.width; text: modelData.kind === "free" ? "Свободное место" : (modelData.label || modelData.name); font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText; elide: Text.ElideRight }
                                                StyledText { width: parent.width; text: root.formatSize(modelData.sizeBytes) + (modelData.fileSystem ? " · " + modelData.fileSystem.toUpperCase() : ""); font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2); color: Theme.surfaceVariantText; elide: Text.ElideRight }
                                            }
                                            MouseArea {
                                                id: regionArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    FileManagerService.selectStorageRegion(regionRow.modelData);
                                                    root.storageAction = "";
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width - regionList.width - parent.spacing
                                        height: parent.height
                                        radius: Theme.cornerRadius
                                        color: Theme.surfaceContainer

                                        Flickable {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM
                                            contentWidth: width
                                            contentHeight: storageDetails.implicitHeight
                                            clip: true

                                            Column {
                                                id: storageDetails
                                                width: parent.width
                                                spacing: Theme.spacingM

                                                StyledText {
                                                    width: parent.width
                                                    text: root.regionTitle(FileManagerService.selectedRegion)
                                                    font.pixelSize: Theme.fontSizeLarge
                                                    font.weight: Font.DemiBold
                                                    color: Theme.surfaceText
                                                    wrapMode: Text.WordWrap
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    text: root.regionDetails(FileManagerService.selectedRegion)
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceVariantText
                                                    wrapMode: Text.WordWrap
                                                }

                                                Flow {
                                                    width: parent.width
                                                    spacing: Theme.spacingS
                                                    visible: FileManagerService.selectedRegion !== null && root.storageAction === ""

                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind === "free"
                                                        text: "Создать раздел"
                                                        iconName: "add"
                                                        backgroundColor: Theme.primary
                                                        textColor: Theme.onPrimary
                                                        enabled: !FileManagerService.operationActive()
                                                            && !FileManagerService.selectedDisk?.readOnly
                                                            && ["gpt", "dos"].includes(FileManagerService.selectedDisk?.partitionTable || "")
                                                        onClicked: root.beginStorageAction("create")
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free" && FileManagerService.selectedRegion?.mounted
                                                        text: "Открыть"
                                                        iconName: "folder_open"
                                                        backgroundColor: Theme.primary
                                                        textColor: Theme.onPrimary
                                                        onClicked: FileManagerService.navigate(FileManagerService.selectedRegion.mountPoint)
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free" && FileManagerService.selectedRegion?.fileSystem
                                                        text: FileManagerService.selectedRegion?.mounted ? "Отключить" : "Подключить"
                                                        iconName: FileManagerService.selectedRegion?.mounted ? "eject" : "mount"
                                                        backgroundColor: Theme.surfaceContainerHighest
                                                        textColor: Theme.surfaceText
                                                        enabled: !FileManagerService.selectedRegion?.system && !FileManagerService.operationActive()
                                                        onClicked: FileManagerService.selectedRegion?.mounted
                                                            ? FileManagerService.unmountRegion(FileManagerService.selectedRegion)
                                                            : FileManagerService.mountRegion(FileManagerService.selectedRegion)
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free"
                                                        text: "Форматировать"
                                                        iconName: "format_paint"
                                                        backgroundColor: Theme.withAlpha(Theme.error, 0.1)
                                                        textColor: Theme.error
                                                        enabled: root.regionCanChange(FileManagerService.selectedRegion) && !FileManagerService.operationActive()
                                                        onClicked: root.openFormatPanel(FileManagerService.selectedRegion)
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind === "partition" && FileManagerService.selectedRegion?.fileSystem
                                                        text: "Изменить размер"
                                                        iconName: "width"
                                                        backgroundColor: Theme.surfaceContainerHighest
                                                        textColor: Theme.surfaceText
                                                        enabled: root.regionCanChange(FileManagerService.selectedRegion) && !FileManagerService.operationActive()
                                                        onClicked: root.beginStorageAction("resize")
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free" && FileManagerService.selectedRegion?.fileSystem
                                                        text: "Переименовать"
                                                        iconName: "edit"
                                                        backgroundColor: Theme.surfaceContainerHighest
                                                        textColor: Theme.surfaceText
                                                        enabled: root.regionCanChange(FileManagerService.selectedRegion) && !FileManagerService.operationActive()
                                                        onClicked: root.beginStorageAction("label")
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free" && FileManagerService.selectedRegion?.fileSystem
                                                        text: "Проверить"
                                                        iconName: "fact_check"
                                                        backgroundColor: Theme.surfaceContainerHighest
                                                        textColor: Theme.surfaceText
                                                        enabled: !FileManagerService.selectedRegion?.system
                                                            && !FileManagerService.selectedRegion?.layered
                                                            && !FileManagerService.operationActive()
                                                        onClicked: root.beginStorageAction("check")
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind !== "free" && FileManagerService.selectedRegion?.fileSystem
                                                        text: "Исправить"
                                                        iconName: "build"
                                                        backgroundColor: Theme.surfaceContainerHighest
                                                        textColor: Theme.surfaceText
                                                        enabled: root.regionCanChange(FileManagerService.selectedRegion) && !FileManagerService.operationActive()
                                                        onClicked: root.beginStorageAction("repair")
                                                    }
                                                    KaskadButton {
                                                        visible: FileManagerService.selectedRegion?.kind === "partition"
                                                        text: "Удалить раздел"
                                                        iconName: "delete_forever"
                                                        backgroundColor: Theme.withAlpha(Theme.error, 0.1)
                                                        textColor: Theme.error
                                                        enabled: root.regionCanChange(FileManagerService.selectedRegion) && !FileManagerService.operationActive()
                                                        onClicked: root.beginStorageAction("delete")
                                                    }
                                                }

                                                Column {
                                                    width: parent.width
                                                    spacing: Theme.spacingS
                                                    visible: root.storageAction !== ""

                                                    StyledText {
                                                        width: parent.width
                                                        text: root.storageActionTitle()
                                                        font.pixelSize: Theme.fontSizeMedium
                                                        font.weight: Font.DemiBold
                                                        color: root.storageAction === "delete" || root.storageAction === "table" ? Theme.error : Theme.surfaceText
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    KaskadTextField {
                                                        id: storageLabelField
                                                        width: parent.width
                                                        visible: ["create", "label"].includes(root.storageAction)
                                                        placeholderText: "Имя тома"
                                                        enabled: !root.storageActionBusy
                                                    }

                                                    KaskadDropdown {
                                                        id: storageFormatType
                                                        width: parent.width
                                                        visible: root.storageAction === "create"
                                                        compactMode: true
                                                        options: ["exFAT", "NTFS", "FAT32", "EXT4", "Btrfs"]
                                                        currentValue: "exFAT"
                                                    }

                                                    KaskadTextField {
                                                        id: storageSizeField
                                                        width: parent.width
                                                        visible: ["create", "resize"].includes(root.storageAction)
                                                        placeholderText: "Размер в ГиБ"
                                                        enabled: !root.storageActionBusy
                                                    }

                                                    KaskadDropdown {
                                                        id: storageTableType
                                                        width: parent.width
                                                        visible: root.storageAction === "table"
                                                        compactMode: true
                                                        options: ["GPT", "MBR"]
                                                        currentValue: "GPT"
                                                    }

                                                    StyledText {
                                                        width: parent.width
                                                        text: root.storageActionDescription()
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        color: root.storageActionNeedsConfirmation() ? Theme.error : Theme.surfaceVariantText
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    KaskadToggle {
                                                        id: storageAcknowledgement
                                                        width: parent.width
                                                        visible: root.storageActionNeedsConfirmation()
                                                        checked: false
                                                        enabled: !root.storageActionBusy
                                                        text: "Я понимаю последствия этой операции"
                                                    }

                                                    Row {
                                                        spacing: Theme.spacingS
                                                        KaskadButton {
                                                            text: "Отмена"
                                                            backgroundColor: Theme.surfaceContainerHighest
                                                            textColor: Theme.surfaceText
                                                            enabled: !root.storageActionBusy
                                                            onClicked: root.storageAction = ""
                                                        }
                                                        KaskadButton {
                                                            text: root.storageActionBusy ? "Подготовка…" : root.storageActionButtonText()
                                                            iconName: root.storageActionBusy ? "hourglass_top" : "check"
                                                            backgroundColor: root.storageAction === "delete" || root.storageAction === "table" ? Theme.error : Theme.primary
                                                            textColor: root.storageAction === "delete" || root.storageAction === "table" ? Theme.surface : Theme.onPrimary
                                                            enabled: !root.storageActionBusy
                                                                && (!root.storageActionNeedsConfirmation() || storageAcknowledgement.checked)
                                                            onClicked: root.applyStorageAction()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: operationPanel
                    width: parent.width
                    height: FileManagerService.operation !== null ? 88 : 0
                    visible: height > 0
                    color: Theme.surfaceContainer
                    clip: true

                    Column {
                        anchors.left: parent.left
                        anchors.right: operationButton.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Row {
                            width: parent.width
                            StyledText {
                                width: parent.width * 0.58
                                text: root.operationTitle()
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: FileManagerService.operation?.state === "failed" ? Theme.error : Theme.surfaceText
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width * 0.42
                                text: root.operationDetails()
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 7
                            radius: 4
                            color: Theme.surfaceContainerHighest
                            Rectangle {
                                width: parent.width * root.operationRatio()
                                height: parent.height
                                radius: parent.radius
                                color: FileManagerService.operation?.state === "failed" ? Theme.error : Theme.primary
                                Behavior on width { NumberAnimation { duration: 140 } }
                            }
                        }
                    }

                    KaskadActionButton {
                        id: operationButton
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 36
                        enabled: !(FileManagerService.operationActive()
                            && (FileManagerService.operation?.kind === "format"
                                || (FileManagerService.operation?.kind || "").startsWith("storage-")))
                        iconName: FileManagerService.operationActive()
                            ? (FileManagerService.operation?.kind === "format"
                                || (FileManagerService.operation?.kind || "").startsWith("storage-") ? "hourglass_top" : "close") : "done"
                        iconColor: FileManagerService.operationActive()
                            && FileManagerService.operation?.kind !== "format"
                            && !(FileManagerService.operation?.kind || "").startsWith("storage-")
                            ? Theme.error : Theme.primary
                        backgroundColor: Theme.surfaceContainerHighest
                        tooltipText: FileManagerService.operationActive()
                            ? (FileManagerService.operation?.kind === "format"
                                || (FileManagerService.operation?.kind || "").startsWith("storage-")
                                ? "Операцию с разделами нельзя прерывать" : "Отменить операцию")
                            : "Скрыть"
                        onClicked: {
                            if (FileManagerService.operationActive())
                                FileManagerService.cancelOperation();
                            else
                                FileManagerService.dismissOperation();
                        }
                    }
                }

                Rectangle {
                    id: actionBar
                    width: parent.width
                    height: FileManagerService.viewMode === "storage" ? 0 : 58
                    visible: height > 0
                    color: Theme.surfaceContainerHigh

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        spacing: Theme.spacingS
                        visible: FileManagerService.viewMode === "files"

                        KaskadButton {
                            text: "Новая папка"
                            iconName: "create_new_folder"
                            backgroundColor: Theme.surfaceContainerHighest
                            textColor: Theme.surfaceText
                            onClicked: {
                                root.editorMode = "mkdir";
                                nameEditor.text = "";
                                Qt.callLater(() => nameEditor.forceActiveFocus());
                            }
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "edit"; tooltipText: "Переименовать"
                            iconColor: Theme.surfaceText; backgroundColor: Theme.surfaceContainerHighest
                            enabled: root.activeEntry() !== null
                            onClicked: {
                                root.editorMode = "rename";
                                nameEditor.text = root.activeEntry()?.name || "";
                                Qt.callLater(() => nameEditor.forceActiveFocus());
                            }
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "content_copy"; tooltipText: "Копировать"
                            iconColor: Theme.surfaceText; backgroundColor: Theme.surfaceContainerHighest
                            enabled: root.activeEntry() !== null
                            onClicked: root.rememberActive(false)
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "content_cut"; tooltipText: "Переместить"
                            iconColor: Theme.surfaceText; backgroundColor: Theme.surfaceContainerHighest
                            enabled: root.activeEntry() !== null
                            onClicked: root.rememberActive(true)
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "content_paste"; tooltipText: "Вставить сюда"
                            iconColor: Theme.primary; backgroundColor: Theme.surfaceContainerHighest
                            enabled: FileManagerService.clipboardEntry !== null && !FileManagerService.operationActive()
                            onClicked: root.pasteActive()
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "delete"; tooltipText: "Переместить в корзину"
                            iconColor: Theme.error; backgroundColor: Theme.withAlpha(Theme.error, 0.1)
                            enabled: root.activeEntry() !== null
                            onClicked: root.trashActive()
                        }
                        KaskadDropdown {
                            id: archiveFormat
                            width: 92
                            compactMode: true
                            options: ["zip", "7z", "tar.gz", "tar.zst"]
                            currentValue: "zip"
                        }
                        KaskadActionButton {
                            buttonSize: 38; iconName: "archive"; tooltipText: "Создать архив"
                            iconColor: Theme.surfaceText; backgroundColor: Theme.surfaceContainerHighest
                            enabled: root.activeEntry() !== null
                            onClicked: FileManagerService.archiveEntry(root.activeEntry(), archiveFormat.currentValue)
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        spacing: Theme.spacingS
                        visible: FileManagerService.viewMode === "trash"

                        KaskadButton {
                            text: "Восстановить"
                            iconName: "restore_from_trash"
                            backgroundColor: Theme.primary
                            textColor: Theme.onPrimary
                            enabled: FileManagerService.selectedEntry !== null
                            onClicked: FileManagerService.restoreSelected()
                        }
                        KaskadButton {
                            text: "Удалить навсегда"
                            iconName: "delete_forever"
                            backgroundColor: Theme.withAlpha(Theme.error, 0.1)
                            textColor: Theme.error
                            enabled: FileManagerService.selectedEntry !== null
                            onClicked: {
                                root.pendingDangerEntry = FileManagerService.selectedEntry;
                                root.pendingDanger = "delete";
                            }
                        }
                        KaskadButton {
                            text: "Очистить корзину"
                            iconName: "delete_sweep"
                            backgroundColor: Theme.surfaceContainerHighest
                            textColor: Theme.error
                            enabled: FileManagerService.entries.length > 0
                            onClicked: {
                                root.pendingDangerEntry = null;
                                root.pendingDanger = "empty";
                            }
                        }
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        visible: contentColumn.width >= 760
                        text: FileManagerService.loading ? "Загрузка…" : FileManagerService.entries.length + " объектов"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    Rectangle {
        id: archivePasswordScrim
        anchors.fill: parent
        z: 60
        visible: root.archivePasswordPath.length > 0
        color: Theme.withAlpha("#000000", 0.62)

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(440, root.width - Theme.spacingL * 2)
            height: 300
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineVariant

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    height: 48
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 48
                        height: 48
                        radius: 14
                        color: Theme.withAlpha(Theme.primary, 0.14)
                        KaskadIcon {
                            anchors.centerIn: parent
                            name: "lock"
                            size: 26
                            color: Theme.primary
                        }
                    }

                    Column {
                        width: parent.width - 48 - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        StyledText {
                            width: parent.width
                            text: "Архив защищён паролем"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                        StyledText {
                            width: parent.width
                            text: root.archivePasswordName
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideMiddle
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Введите пароль, чтобы распаковать файлы. Пароль не будет сохранён."
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                KaskadTextField {
                    id: archivePasswordInput
                    width: parent.width
                    height: 44
                    placeholderText: "Пароль архива"
                    leftIconName: "key"
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    enabled: !root.archivePasswordBusy
                    onTextChanged: {
                        if (root.archivePasswordError.length > 0)
                            root.archivePasswordError = "";
                    }
                    Keys.onReturnPressed: root.submitArchivePassword()
                    Keys.onEnterPressed: root.submitArchivePassword()
                    Keys.onEscapePressed: root.closeArchivePasswordPanel()
                }

                StyledText {
                    width: parent.width
                    height: root.archivePasswordError.length > 0 ? implicitHeight : 0
                    visible: root.archivePasswordError.length > 0
                    text: root.archivePasswordError
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                }

                Item { width: 1; height: Math.max(0, parent.height - y - passwordButtons.height) }

                Row {
                    id: passwordButtons
                    width: parent.width
                    height: 44
                    spacing: Theme.spacingM

                    KaskadButton {
                        width: (parent.width - parent.spacing) * 0.38
                        height: parent.height
                        text: "Отмена"
                        backgroundColor: Theme.surfaceContainerHighest
                        textColor: Theme.surfaceText
                        enabled: !root.archivePasswordBusy
                        onClicked: root.closeArchivePasswordPanel()
                    }

                    KaskadButton {
                        width: (parent.width - parent.spacing) * 0.62
                        height: parent.height
                        text: root.archivePasswordBusy ? "Распаковываем…" : "Распаковать"
                        iconName: root.archivePasswordBusy ? "hourglass_top" : "folder_zip"
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        enabled: !root.archivePasswordBusy && archivePasswordInput.text.length > 0
                        onClicked: root.submitArchivePassword()
                    }
                }
            }
        }
    }

    Rectangle {
        id: formatScrim
        anchors.fill: parent
        z: 50
        visible: root.formatTarget !== null
        color: Theme.withAlpha("#000000", 0.62)

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(590, root.width - Theme.spacingL * 2)
            height: Math.min(540, root.height - Theme.spacingM * 2)
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineVariant

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    height: 44
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 14
                        color: Theme.withAlpha(Theme.error, 0.12)
                        KaskadIcon {
                            anchors.centerIn: parent
                            name: "format_paint"
                            size: 25
                            color: Theme.error
                        }
                    }

                    Column {
                        width: parent.width - 44 - closeFormatButton.width - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        StyledText {
                            width: parent.width
                            text: "Форматирование накопителя"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                        StyledText {
                            width: parent.width
                            text: (root.formatTarget?.label || "Накопитель") + " · "
                                + root.formatSize(root.formatTarget?.sizeBytes || 0)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }

                    KaskadActionButton {
                        id: closeFormatButton
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 36
                        iconName: "close"
                        iconColor: Theme.surfaceText
                        backgroundColor: Theme.surfaceContainerHighest
                        enabled: !root.formatStarting
                        tooltipText: "Закрыть"
                        onClicked: root.closeFormatPanel()
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Файловая система"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                KaskadDropdown {
                    id: formatType
                    width: parent.width
                    compactMode: true
                    options: ["exFAT", "NTFS", "FAT32", "EXT4", "Btrfs"]
                    currentValue: "exFAT"
                }

                Rectangle {
                    width: parent.width
                    height: 58
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    StyledText {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        text: root.formatDescription(formatType.currentValue)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Имя накопителя"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                KaskadTextField {
                    id: formatLabel
                    width: parent.width
                    height: 42
                    placeholderText: "Например, KASKADOS"
                    leftIconName: "drive_file_rename_outline"
                    showClearButton: true
                    enabled: !root.formatStarting
                }

                Rectangle {
                    width: parent.width
                    height: 78
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.09)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.error, 0.28)
                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM
                        KaskadIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "warning"
                            size: 25
                            color: Theme.error
                        }
                        StyledText {
                            width: parent.width - 25 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Все файлы на выбранном томе будут удалены. Остальные диски не затрагиваются. Это быстрое форматирование, а не безопасное стирание данных."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                KaskadToggle {
                    id: formatAcknowledgement
                    width: parent.width
                    checked: false
                    enabled: !root.formatStarting
                    text: "Я понимаю, что данные на этом накопителе будут удалены"
                }

                Item { width: 1; height: Math.max(0, parent.height - y - formatButtons.height) }

                Row {
                    id: formatButtons
                    width: parent.width
                    height: 44
                    spacing: Theme.spacingM

                    KaskadButton {
                        width: (parent.width - parent.spacing) * 0.35
                        height: parent.height
                        text: "Отмена"
                        backgroundColor: Theme.surfaceContainerHighest
                        textColor: Theme.surfaceText
                        enabled: !root.formatStarting
                        onClicked: root.closeFormatPanel()
                    }

                    KaskadButton {
                        width: (parent.width - parent.spacing) * 0.65
                        height: parent.height
                        text: root.formatStarting ? "Подготовка…" : "Стереть и создать " + formatType.currentValue
                        iconName: root.formatStarting ? "hourglass_top" : "format_paint"
                        backgroundColor: Theme.error
                        textColor: Theme.surface
                        enabled: formatAcknowledgement.checked && !root.formatStarting
                            && !FileManagerService.operationActive()
                        onClicked: {
                            root.formatStarting = true;
                            FileManagerService.formatDevice(root.formatTarget,
                                                            root.formatBackendName(formatType.currentValue),
                                                            formatLabel.text.trim(), success => {
                                root.formatStarting = false;
                                if (success)
                                    root.closeFormatPanel();
                            });
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: FileManagerService
        function onDirectoryNavigationStarted(path) {
            root.savePrimaryScroll(path);
        }
        function onDirectoryListingReady(path) {
            root.restorePrimaryScroll(path);
        }
        function onArchivePasswordRequested(path, name, incorrect) {
            root.archivePasswordPath = path;
            root.archivePasswordName = name;
            root.archivePasswordError = incorrect ? "Неверный пароль" : "";
            root.archivePasswordBusy = false;
            archivePasswordInput.text = "";
            Qt.callLater(() => archivePasswordInput.forceActiveFocus());
        }
        function onCurrentPathChanged() {
            if (!locationField.activeFocus)
                locationField.text = FileManagerService.currentPath;
        }
        function onViewModeChanged() {
            if (!locationField.activeFocus)
                locationField.text = FileManagerService.viewMode === "trash" ? "Корзина"
                    : FileManagerService.viewMode === "storage" ? "Управление дисками"
                    : FileManagerService.currentPath;
            root.pendingDanger = "";
            root.pendingDangerEntry = null;
            root.storageAction = "";
            if (FileManagerService.viewMode !== "files")
                root.activePane = 0;
        }
        function onShowHiddenChanged() {
            if (root.splitEnabled)
                root.navigateSecondary(root.secondaryPath);
        }
        function onOperationChanged() {
            const item = FileManagerService.operation;
            if (!root.splitEnabled || !item?.id || item.state !== "completed"
                    || root.secondaryRefreshedOperation === item.id)
                return;
            root.secondaryRefreshedOperation = item.id;
            root.navigateSecondary(root.secondaryPath);
        }
    }

    component SidebarPlace: Rectangle {
        id: place
        property string text: ""
        property string subtitle: ""
        property string iconName: "folder"
        property bool active: false
        signal clicked

        height: 58
        radius: Theme.cornerRadius
        color: active ? Theme.primaryPressed : placeArea.containsMouse ? Theme.primaryHoverLight : "transparent"

        KaskadIcon {
            id: placeIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: place.iconName
            size: 25
            color: place.active ? Theme.primary : Theme.surfaceVariantText
        }
        Column {
            anchors.left: placeIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            StyledText { width: parent.width; text: place.text; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText; elide: Text.ElideRight }
            StyledText { width: parent.width; text: place.subtitle; font.pixelSize: Math.max(9, Theme.fontSizeSmall - 2); color: Theme.surfaceVariantText; elide: Text.ElideRight }
        }
        MouseArea {
            id: placeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: place.clicked()
        }
    }

    function diskTitle(disk) {
        if (!disk)
            return "";
        const title = ((disk.vendor || "") + " " + (disk.model || "")).trim();
        return title || disk.name || disk.path || "Накопитель";
    }

    function diskSubtitle(disk) {
        if (!disk)
            return "";
        const parts = [formatSize(disk.sizeBytes), disk.path];
        if (disk.partitionTable)
            parts.push(disk.partitionTable.toUpperCase());
        else
            parts.push("Без таблицы разделов");
        if (disk.transport)
            parts.push(disk.transport.toUpperCase());
        if (disk.readOnly)
            parts.push("Только чтение");
        return parts.join(" · ");
    }

    function regionTitle(region) {
        if (!region)
            return "Выберите раздел или свободную область";
        if (region.kind === "free")
            return "Свободное место — " + formatSize(region.sizeBytes);
        return (region.label || region.name || "Раздел") + " — " + formatSize(region.sizeBytes);
    }

    function regionDetails(region) {
        if (!region)
            return "Выберите область на схеме диска, чтобы открыть действия и подробности.";
        if (region.kind === "free")
            return "Нераспределённая область. Здесь можно создать новый раздел.";
        const parts = [];
        if (region.fileSystem)
            parts.push("Файловая система: " + region.fileSystem.toUpperCase());
        if (region.mountPoint)
            parts.push("Подключён: " + region.mountPoint);
        else
            parts.push("Не подключён");
        if (region.availableBytes > 0)
            parts.push("Свободно: " + formatSize(region.availableBytes));
        if (region.system)
            parts.push("Системный раздел защищён от изменений");
        if (region.layered)
            parts.push("Содержит шифрование или логические тома");
        if (region.uuid)
            parts.push("UUID: " + region.uuid);
        return parts.join("\n");
    }

    function regionCanChange(region) {
        return region !== null && !region.system && !region.readOnly && !region.layered && !!region.path;
    }

    function regionColor(region, selected) {
        if (selected)
            return Theme.primaryPressed;
        if (region?.kind === "free")
            return Theme.surfaceContainerHighest;
        if (region?.system)
            return Theme.withAlpha(Theme.primary, 0.16);
        if (region?.compatibility === "windows")
            return Theme.withAlpha(Theme.info, 0.16);
        if (region?.compatibility === "universal")
            return Theme.withAlpha(Theme.primary, 0.12);
        return Theme.surfaceContainer;
    }

    function beginStorageAction(action) {
        const region = FileManagerService.selectedRegion;
        root.storageAction = action;
        root.storageActionBusy = false;
        storageAcknowledgement.checked = false;
        if (action === "create" && region) {
            storageSizeField.text = (Number(region.sizeBytes || 0) / 1073741824).toFixed(1);
            storageLabelField.text = "Новый том";
            storageFormatType.currentValue = "exFAT";
        } else if (action === "resize" && region) {
            storageSizeField.text = (Number(region.sizeBytes || 0) / 1073741824).toFixed(1);
        } else if (action === "label" && region) {
            storageLabelField.text = region.label || "";
        } else if (action === "table") {
            storageTableType.currentValue = "GPT";
        }
    }

    function storageActionNeedsConfirmation() {
        return ["create", "resize", "repair", "delete", "table"].includes(root.storageAction);
    }

    function storageActionTitle() {
        const titles = {
            "create": "Создание нового раздела",
            "resize": "Изменение размера раздела",
            "label": "Новое имя раздела",
            "check": "Проверка файловой системы",
            "repair": "Исправление файловой системы",
            "delete": "Удаление раздела",
            "table": "Очистка всего накопителя"
        };
        return titles[root.storageAction] || "";
    }

    function storageActionDescription() {
        if (root.storageAction === "create")
            return "Будет создан и отформатирован новый раздел. Размер не может превышать выбранную свободную область.";
        if (root.storageAction === "resize")
            return "Уменьшение может занять много времени. Не отключайте питание до завершения операции.";
        if (root.storageAction === "label")
            return "Изменяется только отображаемое имя тома; файлы останутся на месте.";
        if (root.storageAction === "check")
            return "Раздел временно отключится, будет проверен и затем подключён обратно.";
        if (root.storageAction === "repair")
            return "Раздел временно отключится. Система попытается исправить обнаруженные повреждения.";
        if (root.storageAction === "delete")
            return "Раздел и все находящиеся на нём файлы будут удалены. На его месте появится свободная область.";
        if (root.storageAction === "table")
            return "Все разделы и файлы на выбранном физическом накопителе будут удалены без возможности восстановления.";
        return "";
    }

    function storageActionButtonText() {
        const labels = {
            "create": "Создать раздел",
            "resize": "Изменить размер",
            "label": "Сохранить имя",
            "check": "Проверить",
            "repair": "Исправить",
            "delete": "Удалить раздел",
            "table": "Очистить и создать таблицу"
        };
        return labels[root.storageAction] || "Применить";
    }

    function applyStorageAction() {
        const action = root.storageAction;
        const disk = FileManagerService.selectedDisk;
        const region = FileManagerService.selectedRegion;
        if (!action || !disk)
            return;
        let sizeBytes = 0;
        if (["create", "resize"].includes(action)) {
            const gib = Number(storageSizeField.text.trim().replace(",", "."));
            if (!Number.isFinite(gib) || gib <= 0) {
                ToastService.showError("Укажите корректный размер в ГиБ.", "", "", "files");
                return;
            }
            sizeBytes = Math.floor(gib * 1073741824);
            if (action === "create")
                sizeBytes = Math.min(sizeBytes, Number(region?.sizeBytes || 0));
        }
        root.storageActionBusy = true;
        const done = success => {
            root.storageActionBusy = false;
            if (success)
                root.storageAction = "";
        };
        if (action === "create")
            FileManagerService.createPartition(disk, region, sizeBytes,
                formatBackendName(storageFormatType.currentValue), storageLabelField.text.trim(), done);
        else if (action === "resize")
            FileManagerService.resizePartition(region, sizeBytes, done);
        else if (action === "label")
            FileManagerService.setFilesystemLabel(region, storageLabelField.text.trim(), done);
        else if (action === "check")
            FileManagerService.checkFilesystem(region, false, done);
        else if (action === "repair")
            FileManagerService.checkFilesystem(region, true, done);
        else if (action === "delete")
            FileManagerService.deletePartition(region, done);
        else if (action === "table")
            FileManagerService.createPartitionTable(disk,
                storageTableType.currentValue === "MBR" ? "dos" : "gpt", done);
    }

    function formatBackendName(displayName) {
        if (displayName === "FAT32")
            return "vfat";
        if (displayName === "NTFS")
            return "ntfs";
        if (displayName === "EXT4")
            return "ext4";
        if (displayName === "Btrfs")
            return "btrfs";
        return "exfat";
    }

    function formatDescription(displayName) {
        if (displayName === "FAT32")
            return "Для старых устройств, телевизоров и автомагнитол. Один файл не может быть больше 4 ГиБ.";
        if (displayName === "EXT4")
            return "Лучший вариант для KaskadOS и Linux. Windows без дополнительных программ его не откроет.";
        if (displayName === "Btrfs")
            return "Для KaskadOS и Linux: снимки, контроль целостности и сжатие. Windows обычно его не открывает.";
        if (displayName === "NTFS")
            return "Для накопителей, которые в основном используются в Windows. KaskadOS умеет читать и записывать NTFS.";
        return "Рекомендуется для флешек: работает в KaskadOS, Windows и macOS, поддерживает большие файлы.";
    }

    function partitionRegionWidth(regionIndex) {
        const regions = FileManagerService.selectedDisk?.regions || [];
        const count = regions.length;
        if (count === 0 || regionIndex < 0 || regionIndex >= count)
            return 0;

        const spacing = 4;
        const available = Math.max(0, partitionMap.width - spacing * Math.max(0, count - 1));
        if (available === 0)
            return 0;

        // Small service partitions remain readable, while large partitions
        // share exactly the space left in the strip. Nothing can escape past
        // the right edge, even when one partition occupies almost the disk.
        const minimum = Math.min(82, available / count);
        const sizes = regions.map(region => Math.max(1, Number(region.sizeBytes || 0)));
        const widths = new Array(count).fill(0);
        let active = sizes.map((_, index) => index);
        let remaining = available;

        while (active.length > 0) {
            const activeTotal = active.reduce((sum, index) => sum + sizes[index], 0);
            const pinned = active.filter(index => remaining * sizes[index] / activeTotal < minimum);
            if (pinned.length === 0) {
                active.forEach(index => widths[index] = remaining * sizes[index] / activeTotal);
                break;
            }
            if (pinned.length === active.length) {
                active.forEach(index => widths[index] = remaining / active.length);
                break;
            }
            pinned.forEach(index => {
                widths[index] = minimum;
                remaining -= minimum;
            });
            active = active.filter(index => !pinned.includes(index));
        }
        return widths[regionIndex];
    }

    function operationRatio() {
        const operation = FileManagerService.operation;
        if (!operation)
            return 0;
        if (operation.state === "completed")
            return 1;
        const total = Number(operation.totalBytes || 0);
        return total > 0 ? Math.max(0, Math.min(1, Number(operation.processedBytes || 0) / total)) : 0;
    }

    function operationTitle() {
        const operation = FileManagerService.operation;
        if (!operation)
            return "";
        if (operation.state === "scanning")
            return "Подсчитываем размер «" + operation.name + "»…";
        if (operation.state === "failed")
            return operation.error || "Операция не выполнена";
        if (operation.state === "cancelled")
            return "Операция отменена";
        if (operation.state === "completed")
            return operation.kind === "format" ? "Форматирование завершено"
                : (operation.kind || "").startsWith("storage-") ? "Операция с накопителем завершена"
                : operation.kind === "move" ? "Перемещение завершено" : "Копирование завершено";
        if (operation.kind === "format")
            return "Форматируем «" + operation.name + "»";
        if ((operation.kind || "").startsWith("storage-"))
            return operation.detail || "Выполняется операция с накопителем";
        return (operation.kind === "move" ? "Перемещаем «" : "Копируем «") + operation.name + "»";
    }

    function operationDetails() {
        const operation = FileManagerService.operation;
        if (!operation || operation.state === "scanning")
            return "";
        const total = Number(operation.totalBytes || 0);
        const processed = Number(operation.processedBytes || 0);
        if (operation.kind === "format" || (operation.kind || "").startsWith("storage-")) {
            const progress = total > 0 ? Math.min(100, Math.round(processed * 100 / total)) : 0;
            return progress + "% · " + (operation.detail || "Не отключайте накопитель");
        }
        if (total <= 0)
            return operation.state === "completed" ? "Готово" : "0 Б";
        const percent = Math.min(100, Math.round(processed * 100 / total));
        return percent + "% · осталось " + formatSize(Math.max(0, total - processed));
    }

    function formatSize(bytes) {
        let value = Number(bytes || 0);
        const units = ["Б", "КиБ", "МиБ", "ГиБ", "ТиБ"];
        let index = 0;
        while (value >= 1024 && index < units.length - 1) {
            value /= 1024;
            index++;
        }
        return (index === 0 ? Math.round(value) : value.toFixed(1)) + " " + units[index];
    }
}
