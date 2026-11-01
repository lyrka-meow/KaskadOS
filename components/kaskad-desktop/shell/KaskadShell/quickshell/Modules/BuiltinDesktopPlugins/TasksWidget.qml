pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property real widgetWidth: 380
    property real widgetHeight: 430
    property real defaultWidth: 380
    property real defaultHeight: 430
    property real minWidth: 300
    property real minHeight: 250
    property string instanceId: ""
    property var instanceData: null
    property string pendingDeleteId: ""
    property bool expanded: false
    property bool acceptsKeyboardFocus: true

    readonly property var cfg: instanceData?.config ?? ({})
    readonly property bool showCompleted: cfg.showCompleted ?? false
    readonly property int maxItems: Math.max(1, cfg.maxItems ?? 8)
    readonly property string todayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var allTasks: {
        const rows = [];
        const source = CalendarService.localTasks || {};
        for (const dateKey of Object.keys(source)) {
            for (const task of source[dateKey] || []) {
                if (!root.showCompleted && task.completed)
                    continue;
                rows.push({
                    id: task.id,
                    eventId: "task_" + task.id,
                    text: task.text || "",
                    completed: !!task.completed,
                    dateKey: dateKey
                });
            }
        }
        rows.sort((a, b) => {
            if (a.completed !== b.completed)
                return a.completed ? 1 : -1;
            if (a.dateKey !== b.dateKey)
                return a.dateKey.localeCompare(b.dateKey);
            return a.id.localeCompare(b.id);
        });
        return rows;
    }
    readonly property var visibleTasks: expanded ? allTasks : allTasks.slice(0, maxItems)
    readonly property int remainingCount: Math.max(0, allTasks.length - maxItems)
    readonly property int openCount: {
        let count = 0;
        const source = CalendarService.localTasks || {};
        for (const dateKey of Object.keys(source)) {
            for (const task of source[dateKey] || []) {
                if (!task.completed)
                    count++;
            }
        }
        return count;
    }

    function addTask() {
        const value = taskInput.text.trim();
        if (!value)
            return;
        CalendarService.addTaskForDate(new Date(), value);
        taskInput.clear();
    }

    function formatDate(dateKey) {
        if (dateKey === todayKey)
            return I18n.tr("Today", "Task due date");
        const parts = dateKey.split("-");
        if (parts.length !== 3)
            return dateKey;
        return Qt.formatDate(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])), "d MMM");
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, root.cfg.transparency ?? 0.94)
        border.color: Theme.outlineMedium
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                KaskadIcon {
                    name: "checklist"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.tr("Tasks", "Desktop tasks widget title")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    implicitWidth: countLabel.implicitWidth + Theme.spacingM
                    implicitHeight: 28
                    radius: 14
                    color: Theme.primaryContainer

                    StyledText {
                        id: countLabel
                        anchors.centerIn: parent
                        text: root.openCount
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                KaskadTextField {
                    id: taskInput
                    Layout.fillWidth: true
                    height: 44
                    placeholderText: I18n.tr("Add a task or note…", "Desktop tasks quick input")
                    leftIconName: "edit_note"
                    showClearButton: true
                    onAccepted: root.addTask()
                }

                KaskadActionButton {
                    buttonSize: 44
                    iconName: "add"
                    iconSize: 20
                    iconColor: Theme.onPrimary
                    backgroundColor: Theme.primary
                    tooltipText: I18n.tr("Add", "Add task button")
                    onClicked: root.addTask()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    visible: root.visibleTasks.length === 0
                    text: root.showCompleted
                          ? I18n.tr("Nothing here yet", "Empty tasks widget")
                          : I18n.tr("All done. Add something when it appears.", "Empty tasks widget")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                ListView {
                    id: taskList
                    anchors.fill: parent
                    visible: root.visibleTasks.length > 0
                    clip: true
                    spacing: Theme.spacingXS
                    model: root.visibleTasks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: taskRow
                        required property var modelData
                        width: ListView.view.width
                        height: root.pendingDeleteId === modelData.id ? 82 : 52
                        radius: Theme.cornerRadius
                        color: taskHover.containsMouse ? Theme.primaryBackground : Theme.nestedSurface
                        border.color: root.pendingDeleteId === modelData.id ? Theme.error : Theme.outlineMedium
                        border.width: 1

                        Behavior on height {
                            NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutCubic }
                        }

                        MouseArea {
                            id: taskHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingXS
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                spacing: Theme.spacingXS

                                KaskadActionButton {
                                    buttonSize: 40
                                    iconSize: 20
                                    iconName: taskRow.modelData.completed ? "check_box" : "check_box_outline_blank"
                                    iconColor: taskRow.modelData.completed ? Theme.primary : Theme.surfaceVariantText
                                    tooltipText: taskRow.modelData.completed ? I18n.tr("Mark active") : I18n.tr("Complete")
                                    onClicked: CalendarService.toggleTask(taskRow.modelData.eventId)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: taskRow.modelData.text
                                        color: taskRow.modelData.completed ? Theme.surfaceVariantText : Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.strikeout: taskRow.modelData.completed
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    StyledText {
                                        visible: taskRow.modelData.dateKey !== root.todayKey
                                        text: root.formatDate(taskRow.modelData.dateKey)
                                        color: taskRow.modelData.dateKey < root.todayKey ? Theme.error : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                KaskadActionButton {
                                    buttonSize: 40
                                    iconSize: 18
                                    iconName: "delete"
                                    iconColor: Theme.error
                                    tooltipText: I18n.tr("Delete")
                                    onClicked: root.pendingDeleteId = taskRow.modelData.id
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                visible: root.pendingDeleteId === taskRow.modelData.id

                                StyledText {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Delete this task?")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                KaskadActionButton {
                                    buttonSize: 28
                                    iconSize: 16
                                    iconName: "close"
                                    tooltipText: I18n.tr("Cancel")
                                    onClicked: root.pendingDeleteId = ""
                                }

                                KaskadActionButton {
                                    buttonSize: 28
                                    iconSize: 16
                                    iconName: "check"
                                    iconColor: Theme.error
                                    tooltipText: I18n.tr("Delete")
                                    onClicked: {
                                        CalendarService.removeTask(taskRow.modelData.eventId);
                                        root.pendingDeleteId = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            KaskadButton {
                Layout.fillWidth: true
                visible: root.remainingCount > 0 || root.expanded
                text: root.expanded
                      ? I18n.tr("Show less")
                      : I18n.tr("Show %1 more").arg(root.remainingCount)
                onClicked: root.expanded = !root.expanded
            }
        }
    }
}
