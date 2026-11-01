pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("CalendarService")
    readonly property string tasksDirectory: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kaskad-shell"

    readonly property string activeBackend: khalBackend.installed ? "khal" : "none"
    readonly property bool calendarAvailable: true // The local planner is always available.
    property bool khalAvailable: true // Local planner remains available without khal.

    property var eventsByDate: ({})
    property var taskEventsByDate: ({})
    property var localTasks: ({})
    property bool isLoading: khalBackend.isLoading
    property string lastError: ""

    property bool _rangeSet: false
    property date lastStartDate
    property date lastEndDate

    onTaskEventsByDateChanged: mergeEvents()
    onActiveBackendChanged: {
        mergeEvents();
        if (_rangeSet)
            loadEvents(lastStartDate, lastEndDate);
    }

    CalendarKhalBackend {
        id: khalBackend
        onEventsByDateChanged: root.mergeEvents()
    }

    function loadEvents(startDate, endDate) {
        root.lastStartDate = startDate;
        root.lastEndDate = endDate;
        root._rangeSet = true;
        if (khalBackend.installed)
            khalBackend.loadEvents(startDate, endDate);
    }

    function getEventsForDate(date) {
        let dateKey = Qt.formatDate(date, "yyyy-MM-dd");
        return root.eventsByDate[dateKey] || [];
    }

    function hasEventsForDate(date) {
        return getEventsForDate(date).length > 0;
    }

    function loadTasks(text) {
        if (!text || text.trim() === "") {
            root.localTasks = {};
            root.taskEventsByDate = {};
            return;
        }
        try {
            root.localTasks = JSON.parse(text);
            updateTaskEvents();
        } catch (error) {
            log.warn("Failed to parse local tasks JSON: " + error.toString());
        }
    }

    function saveTasks() {
        if (!ensureTasksDirectory.running)
            ensureTasksDirectory.running = true;
    }

    function updateTaskEvents() {
        let newTaskEvents = {};
        for (let dateKey in root.localTasks) {
            let taskList = root.localTasks[dateKey] || [];
            newTaskEvents[dateKey] = [];
            for (let task of taskList) {
                let eventId = "task_" + task.id;
                let parts = dateKey.split("-");
                let taskDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));

                newTaskEvents[dateKey].push({
                    "id": eventId,
                    "title": task.text,
                    "completed": !!task.completed,
                    "start": taskDate,
                    "end": taskDate,
                    "location": "",
                    "description": "Task from your Planner",
                    "url": "",
                    "calendar": "Todo Planner",
                    "color": "#10B981",
                    "allDay": true,
                    "isMultiDay": false
                });
            }
        }
        root.taskEventsByDate = newTaskEvents;
    }

    function addTaskForDate(date, text) {
        let dateKey = Qt.formatDate(date, "yyyy-MM-dd");
        let tasks = Object.assign({}, root.localTasks);
        if (!tasks[dateKey])
            tasks[dateKey] = [];
        let taskId = (new Date().getTime()) + "-kaskad-shell";
        tasks[dateKey].push({
            "id": taskId,
            "text": text,
            "completed": false
        });
        root.localTasks = tasks;
        updateTaskEvents();
        saveTasks();
    }

    function toggleTask(taskId) {
        let cleanId = taskId.replace("task_", "");
        let tasks = Object.assign({}, root.localTasks);
        let updated = false;
        for (let dateKey in tasks) {
            let list = tasks[dateKey];
            for (let item of list) {
                if (item.id === cleanId) {
                    item.completed = !item.completed;
                    updated = true;
                    break;
                }
            }
            if (updated)
                break;
        }
        if (updated) {
            root.localTasks = tasks;
            updateTaskEvents();
            saveTasks();
        }
    }

    function removeTask(taskId) {
        let cleanId = taskId.replace("task_", "");
        let tasks = Object.assign({}, root.localTasks);
        let updated = false;
        for (let dateKey in tasks) {
            let list = tasks[dateKey];
            let filtered = list.filter(item => item.id !== cleanId);
            if (filtered.length !== list.length) {
                if (filtered.length === 0)
                    delete tasks[dateKey];
                else
                    tasks[dateKey] = filtered;
                updated = true;
                break;
            }
        }
        if (updated) {
            root.localTasks = tasks;
            updateTaskEvents();
            saveTasks();
        }
    }

    function reorderTasksForDate(date, orderedIds) {
        let dateKey = Qt.formatDate(date, "yyyy-MM-dd");
        let tasks = Object.assign({}, root.localTasks);
        let v = tasks[dateKey] || [];
        let idToItem = {};
        for (let item of v)
            idToItem[item.id] = item;
        let newV = [];
        for (let tid of orderedIds) {
            if (idToItem[tid])
                newV.push(idToItem[tid]);
        }
        let orderedSet = new Set(orderedIds);
        for (let item of v) {
            if (!orderedSet.has(item.id))
                newV.push(item);
        }
        tasks[dateKey] = newV;
        root.localTasks = tasks;
        updateTaskEvents();
        saveTasks();
    }

    function editTask(taskId, newText) {
        let cleanId = taskId.replace("task_", "");
        let tasks = Object.assign({}, root.localTasks);
        let updated = false;
        for (let dateKey in tasks) {
            let list = tasks[dateKey];
            for (let item of list) {
                if (item.id === cleanId) {
                    item.text = newText;
                    updated = true;
                    break;
                }
            }
            if (updated)
                break;
        }
        if (updated) {
            root.localTasks = tasks;
            updateTaskEvents();
            saveTasks();
        }
    }

    function _mergeInto(merged, byDate) {
        for (let dateKey in byDate) {
            if (!merged[dateKey])
                merged[dateKey] = [];
            for (let event of byDate[dateKey]) {
                if (!merged[dateKey].some(e => e.id === event.id))
                    merged[dateKey].push(event);
            }
        }
    }

    function mergeEvents() {
        let merged = {};
        let backendEvents = khalBackend.installed ? khalBackend.eventsByDate : {};

        for (let dateKey in backendEvents)
            merged[dateKey] = [].concat(backendEvents[dateKey]);

        _mergeInto(merged, root.taskEventsByDate);

        for (let dateKey in merged) {
            let list = merged[dateKey];
            for (let idx = 0; idx < list.length; idx++)
                list[idx]._origIdx = idx;
            list.sort((a, b) => {
                let diff = a.start.getTime() - b.start.getTime();
                if (diff !== 0)
                    return diff;
                return a._origIdx - b._origIdx;
            });
        }

        root.eventsByDate = merged;
    }

    Process {
        id: ensureTasksDirectory
        command: ["mkdir", "-p", root.tasksDirectory]
        onExited: exitCode => {
            if (exitCode === 0)
                tasksFileView.setText(JSON.stringify(root.localTasks, null, 2));
            else
                root.log.warn("Failed to create the local tasks directory");
        }
    }

    FileView {
        id: tasksFileView
        path: root.tasksDirectory + "/tasks.json"
        blockLoading: false
        blockWrites: false
        atomicWrites: true
        watchChanges: true
        printErrors: false

        onLoaded: loadTasks(tasksFileView.text())

        onLoadFailed: {
            root.localTasks = {};
            root.taskEventsByDate = {};
        }
    }
}
