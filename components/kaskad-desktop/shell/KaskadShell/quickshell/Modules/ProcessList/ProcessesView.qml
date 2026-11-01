import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property string searchText: ""
    property string expandedPid: ""
    property var contextMenu: null
    property string processFilter: "all"
    property var expandedTreePids: ({})

    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property int forceRefreshCount: 0

    readonly property bool pauseUpdates: (contextMenu?.visible ?? false) || expandedPid.length > 0
    readonly property bool shouldUpdate: !pauseUpdates || forceRefreshCount > 0
    property var cachedProcesses: []

    signal openContextMenuRequested(int index, real x, real y, bool fromKeyboard)

    onFilteredProcessesChanged: {
        if (!shouldUpdate)
            return;
        cachedProcesses = filteredProcesses;
        if (forceRefreshCount > 0)
            forceRefreshCount--;
    }

    onShouldUpdateChanged: {
        if (shouldUpdate)
            cachedProcesses = filteredProcesses;
    }

    function processMatchesFilter(process) {
        return processFilter === "all" || process.category === processFilter;
    }

    function compareProcesses(a, b) {
        let valueA, valueB, result;
        switch (DgopService.currentSort) {
        case "cpu":
            result = (b.cpu || 0) - (a.cpu || 0);
            break;
        case "memory":
            result = (b.memoryKB || 0) - (a.memoryKB || 0);
            break;
        case "name":
            valueA = (a.command || "").toLowerCase();
            valueB = (b.command || "").toLowerCase();
            result = valueA.localeCompare(valueB);
            break;
        case "pid":
            result = (a.pid || 0) - (b.pid || 0);
            break;
        default:
            result = 0;
        }
        return DgopService.sortAscending ? -result : result;
    }

    function toggleTree(pid) {
        const next = Object.assign({}, expandedTreePids);
        if (next[pid])
            delete next[pid];
        else
            next[pid] = true;
        expandedTreePids = next;
    }

    readonly property var filteredProcesses: {
        if (!DgopService.allProcesses || DgopService.allProcesses.length === 0)
            return [];

        let procs = DgopService.allProcesses.filter(p => processMatchesFilter(p));

        if (searchText.length > 0) {
            const search = searchText.toLowerCase();
            procs = procs.filter(p => {
                const cmd = (p.command || "").toLowerCase();
                const fullCmd = (p.fullCommand || "").toLowerCase();
                const category = (p.categoryLabel || "").toLowerCase();
                const unit = ((p.systemUnit || "") + " " + (p.userUnit || "")).toLowerCase();
                const pid = p.pid.toString();
                return cmd.includes(search) || fullCmd.includes(search) || category.includes(search)
                    || unit.includes(search) || pid.includes(search);
            });
            procs.sort(compareProcesses);
            return procs.map(p => Object.assign({}, p, {"treeDepth": 0, "visibleChildCount": 0}));
        }

        const byPid = {};
        const children = {};
        for (const proc of procs) {
            byPid[proc.pid] = proc;
            if (!children[proc.ppid])
                children[proc.ppid] = [];
            children[proc.ppid].push(proc);
        }
        const roots = procs.filter(p => !byPid[p.ppid]);
        roots.sort(compareProcesses);
        for (const parentPid in children)
            children[parentPid].sort(compareProcesses);

        const visible = [];
        function appendProcess(proc, depth) {
            const directChildren = children[proc.pid] || [];
            visible.push(Object.assign({}, proc, {"treeDepth": depth, "visibleChildCount": directChildren.length}));
            if (!expandedTreePids[proc.pid])
                return;
            for (const child of directChildren)
                appendProcess(child, depth + 1);
        }
        for (const rootProcess of roots)
            appendProcess(rootProcess, 0);
        return visible;
    }

    function selectNext() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = Math.min(selectedIndex + 1, cachedProcesses.length - 1);
        ensureVisible();
    }

    function selectPrevious() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        if (selectedIndex <= 0) {
            selectedIndex = -1;
            keyboardNavigationActive = false;
            return;
        }
        selectedIndex = selectedIndex - 1;
        ensureVisible();
    }

    function selectFirst() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = 0;
        ensureVisible();
    }

    function selectLast() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = cachedProcesses.length - 1;
        ensureVisible();
    }

    function toggleExpand() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const process = cachedProcesses[selectedIndex];
        const pidStr = (process?.pid ?? -1).toString();
        expandedPid = (expandedPid === pidStr) ? "" : pidStr;
    }

    function openContextMenu() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const delegate = processListView.itemAtIndex(selectedIndex);
        if (!delegate)
            return;
        const process = cachedProcesses[selectedIndex];
        if (!process || !contextMenu)
            return;
        contextMenu.processData = process;
        const itemPos = delegate.mapToItem(contextMenu.parent, delegate.width / 2, delegate.height / 2);
        contextMenu.parentFocusItem = root;
        contextMenu.show(itemPos.x, itemPos.y, true);
    }

    function reset() {
        selectedIndex = -1;
        keyboardNavigationActive = false;
        expandedPid = "";
    }

    function forceRefresh(count) {
        forceRefreshCount = count || 3;
    }

    function ensureVisible() {
        if (selectedIndex < 0)
            return;
        processListView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down:
            selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                selectNext();
                event.accepted = true;
            }
            return;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                selectPrevious();
                event.accepted = true;
            }
            return;
        case Qt.Key_Home:
            selectFirst();
            event.accepted = true;
            return;
        case Qt.Key_End:
            selectLast();
            event.accepted = true;
            return;
        case Qt.Key_Space:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Menu:
        case Qt.Key_F10:
            if (keyboardNavigationActive && selectedIndex >= 0) {
                openContextMenu();
                event.accepted = true;
            }
            return;
        }
    }

    Component.onCompleted: {
        DgopService.addRef(["processes", "cpu", "memory", "system"]);
        cachedProcesses = filteredProcesses;
    }

    Component.onDestruction: {
        DgopService.removeRef(["processes", "cpu", "memory", "system"]);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingS
                anchors.rightMargin: Theme.spacingS
                spacing: 0

                SortableHeader {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 200
                    text: I18n.tr("Name")
                    sortKey: "name"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: DgopService.toggleSort("name")
                    alignment: Text.AlignLeft
                }

                SortableHeader {
                    Layout.preferredWidth: 100
                    text: "CPU"
                    sortKey: "cpu"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: DgopService.toggleSort("cpu")
                }

                SortableHeader {
                    Layout.preferredWidth: 100
                    text: I18n.tr("Memory")
                    sortKey: "memory"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: DgopService.toggleSort("memory")
                }

                SortableHeader {
                    Layout.preferredWidth: 80
                    text: "PID"
                    sortKey: "pid"
                    currentSort: DgopService.currentSort
                    sortAscending: DgopService.sortAscending
                    onClicked: DgopService.toggleSort("pid")
                }

                Item {
                    Layout.preferredWidth: 40
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.outlineLight
        }

        KaskadListView {
            id: processListView

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingXXS

            model: ScriptModel {
                values: root.cachedProcesses
                objectProp: "pid"
            }

            delegate: ProcessItem {
                required property var modelData
                required property int index

                width: processListView.width
                process: modelData
                isExpanded: root.expandedPid === (modelData?.pid ?? -1).toString()
                isSelected: root.keyboardNavigationActive && root.selectedIndex === index
                contextMenu: root.contextMenu
                treeExpanded: root.expandedTreePids[modelData?.pid ?? -1] === true
                onToggleTree: root.toggleTree(modelData?.pid ?? -1)
                onToggleExpand: {
                    const pidStr = (modelData?.pid ?? -1).toString();
                    root.expandedPid = (root.expandedPid === pidStr) ? "" : pidStr;
                }
                onClicked: {
                    root.keyboardNavigationActive = true;
                    root.selectedIndex = index;
                }
                onContextMenuRequested: (mouseX, mouseY) => {
                    if (root.contextMenu) {
                        root.contextMenu.processData = modelData;
                        root.contextMenu.parentFocusItem = root;
                        const globalPos = mapToItem(root.contextMenu.parent, mouseX, mouseY);
                        root.contextMenu.show(globalPos.x, globalPos.y, false);
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 100
                radius: Theme.cornerRadius
                color: "transparent"
                visible: root.cachedProcesses.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingM

                    KaskadIcon {
                        name: root.searchText.length > 0 ? "search_off" : "hourglass_empty"
                        size: 32
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: I18n.tr("No matching processes", "empty state in process list")
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.searchText.length > 0
                    }
                }
            }
        }
    }

    component SortableHeader: Item {
        id: headerItem

        property string text: ""
        property string sortKey: ""
        property string currentSort: ""
        property bool sortAscending: false
        property int alignment: Text.AlignHCenter

        signal clicked

        readonly property bool isActive: sortKey === currentSort

        height: 36

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Theme.cornerRadius
            color: headerItem.isActive ? Theme.primaryHover : (headerMouseArea.containsMouse ? Theme.surfaceTextLight : Theme.withAlpha(Theme.surfaceTextLight, 0))

            Behavior on color {
                ColorAnimation {
                    duration: Theme.shortDuration
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            spacing: Theme.spacingXS

            Item {
                Layout.fillWidth: headerItem.alignment === Text.AlignLeft
                visible: headerItem.alignment !== Text.AlignLeft
            }

            StyledText {
                text: headerItem.text
                font.pixelSize: Theme.fontSizeSmall
                font.family: SettingsData.monoFontFamily
                font.weight: headerItem.isActive ? Font.Bold : Font.Medium
                color: headerItem.isActive ? Theme.primary : Theme.surfaceText
                opacity: headerItem.isActive ? 1 : 0.8
            }

            KaskadIcon {
                name: headerItem.sortAscending ? "arrow_upward" : "arrow_downward"
                size: Theme.fontSizeSmall
                color: Theme.primary
                visible: headerItem.isActive
            }

            Item {
                Layout.fillWidth: headerItem.alignment !== Text.AlignLeft
                visible: headerItem.alignment === Text.AlignLeft
            }
        }

        MouseArea {
            id: headerMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: headerItem.clicked()
        }
    }

    component ProcessItem: Rectangle {
        id: processItemRoot

        property var process: null
        property bool isExpanded: false
        property bool isSelected: false
        property bool treeExpanded: false
        property var contextMenu: null

        signal toggleExpand
        signal toggleTree
        signal clicked
        signal contextMenuRequested(real mouseX, real mouseY)

        readonly property int processPid: process?.pid ?? 0
        readonly property real processCpu: process?.cpu ?? 0
        readonly property int processMemKB: process?.memoryKB ?? 0
        readonly property string processCmd: process?.command ?? ""
        readonly property string processFullCmd: process?.fullCommand ?? processCmd

        readonly property int rowHeight: 52
        height: isExpanded ? (rowHeight + expandedRect.height + Theme.spacingXS) : rowHeight
        radius: Theme.cornerRadius
        color: {
            if (isSelected)
                return Theme.primaryPressed;
            return processMouseArea.containsMouse ? Theme.primaryBackground : Theme.withAlpha(Theme.primaryBackground, 0);
        }
        border.color: {
            if (isSelected)
                return Theme.primarySelected;
            return processMouseArea.containsMouse ? Theme.primaryHover : Theme.withAlpha(Theme.primaryHover, 0);
        }
        border.width: 1
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.shortDuration
            }
        }

        MouseArea {
            id: processMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    processItemRoot.contextMenuRequested(mouse.x, mouse.y);
                    return;
                }
                processItemRoot.clicked();
                processItemRoot.toggleExpand();
            }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: processItemRoot.rowHeight

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 200
                        height: parent.height

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            Item {
                                width: Math.min(48, (processItemRoot.process?.treeDepth ?? 0) * 14)
                                height: 1
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: Theme.cornerRadius - 2
                                color: treeMouseArea.containsMouse ? Theme.primaryHover : "transparent"
                                visible: (processItemRoot.process?.visibleChildCount ?? 0) > 0

                                KaskadIcon {
                                    anchors.centerIn: parent
                                    name: processItemRoot.treeExpanded ? "expand_more" : "chevron_right"
                                    size: 17
                                    color: Theme.surfaceVariantText
                                }

                                MouseArea {
                                    id: treeMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        processItemRoot.toggleTree();
                                    }
                                }
                            }

                            Item {
                                width: 24
                                height: 1
                                visible: (processItemRoot.process?.visibleChildCount ?? 0) === 0
                            }

                            KaskadIcon {
                                name: DgopService.getProcessIcon(processItemRoot.processCmd)
                                size: Theme.iconSize - 4
                                color: {
                                    if (processItemRoot.processCpu > 80)
                                        return Theme.error;
                                    if (processItemRoot.processCpu > 50)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                                opacity: 0.8
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                StyledText {
                                    text: processItemRoot.processCmd
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: SettingsData.monoFontFamily
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 230)
                                }

                                Row {
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: processItemRoot.process?.categoryLabel ?? ""
                                        font.pixelSize: Theme.fontSizeSmall - 3
                                        color: Theme.primary
                                    }

                                    StyledText {
                                        text: "•"
                                        font.pixelSize: Theme.fontSizeSmall - 3
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: processItemRoot.process?.statusLabel ?? ""
                                        font.pixelSize: Theme.fontSizeSmall - 3
                                        color: {
                                            const severity = processItemRoot.process?.statusSeverity ?? "idle";
                                            if (severity === "error") return Theme.error;
                                            if (severity === "warning") return Theme.warning;
                                            if (severity === "active") return Theme.success;
                                            return Theme.surfaceVariantText;
                                        }
                                    }

                                    StyledText {
                                        text: (processItemRoot.process?.childCount ?? 0) > 0
                                            ? ("• " + processItemRoot.process.childCount + " " + I18n.tr("children", "process child count")) : ""
                                        visible: text.length > 0
                                        font.pixelSize: Theme.fontSizeSmall - 3
                                        color: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 100
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 70
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processCpu > 80)
                                    return Theme.errorPressed;
                                if (processItemRoot.processCpu > 50)
                                    return Theme.warningHover;
                                return Theme.surfaceTextLight;
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatCpuUsage(processItemRoot.processCpu)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processCpu > 80)
                                        return Theme.error;
                                    if (processItemRoot.processCpu > 50)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 100
                        height: parent.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 70
                            height: 24
                            radius: Theme.cornerRadius
                            color: {
                                if (processItemRoot.processMemKB > 2 * 1024 * 1024)
                                    return Theme.errorPressed;
                                if (processItemRoot.processMemKB > 1024 * 1024)
                                    return Theme.warningHover;
                                return Theme.surfaceTextLight;
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: DgopService.formatMemoryUsage(processItemRoot.processMemKB)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: SettingsData.monoFontFamily
                                font.weight: Font.Bold
                                color: {
                                    if (processItemRoot.processMemKB > 2 * 1024 * 1024)
                                        return Theme.error;
                                    if (processItemRoot.processMemKB > 1024 * 1024)
                                        return Theme.warning;
                                    return Theme.surfaceText;
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 80
                        height: parent.height

                        StyledText {
                            anchors.centerIn: parent
                            text: processItemRoot.processPid > 0 ? processItemRoot.processPid.toString() : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: SettingsData.monoFontFamily
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item {
                        Layout.preferredWidth: 40
                        height: parent.height

                        KaskadIcon {
                            anchors.centerIn: parent
                            name: processItemRoot.isExpanded ? "expand_less" : "expand_more"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }

            Rectangle {
                id: expandedRect
                width: parent.width - Theme.spacingM * 2
                height: processItemRoot.isExpanded ? (expandedContent.implicitHeight + Theme.spacingS * 2) : 0
                anchors.horizontalCenter: parent.horizontalCenter
                radius: Theme.cornerRadius - 2
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.6)
                clip: true
                visible: processItemRoot.isExpanded

                Behavior on height {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Column {
                    id: expandedContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingXS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            id: cmdLabel
                            text: I18n.tr("Full Command:", "process detail label")
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.weight: Font.Bold
                            color: Theme.surfaceVariantText
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            id: cmdText
                            text: processItemRoot.processFullCmd
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.family: SettingsData.monoFontFamily
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideMiddle
                        }

                        Rectangle {
                            id: copyBtn
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: Theme.cornerRadius - 2
                            color: copyMouseArea.containsMouse ? Theme.primaryPressed : Theme.withAlpha(Theme.primaryPressed, 0)

                            KaskadIcon {
                                anchors.centerIn: parent
                                name: "content_copy"
                                size: 14
                                color: copyMouseArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: copyMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["kaskad-shell", "cl", "copy", processItemRoot.processFullCmd]);
                                }
                            }
                        }
                    }

                    Row {
                        spacing: Theme.spacingL

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: I18n.tr("Parent", "process detail label") + ":"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: (processItemRoot.process?.ppid ?? 0) > 0
                                    ? (((processItemRoot.process?.parentName ?? "") || "PID") + " (" + processItemRoot.process.ppid + ")") : "--"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Mem:"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.weight: Font.Bold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: (processItemRoot.process?.memoryPercent ?? 0).toFixed(1) + "%"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                font.family: SettingsData.monoFontFamily
                                color: Theme.surfaceText
                            }
                        }
                    }

                    Row {
                        spacing: Theme.spacingL

                        StyledText {
                            text: (processItemRoot.process?.statusLabel ?? "") + " — " + (processItemRoot.process?.statusDetail ?? "")
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: processItemRoot.process?.userUnit
                                || processItemRoot.process?.systemUnit
                                || (processItemRoot.process?.username ?? "")
                            font.pixelSize: Theme.fontSizeSmall - 2
                            font.family: SettingsData.monoFontFamily
                            color: Theme.surfaceVariantText
                        }
                    }

                    Row {
                        spacing: Theme.spacingL

                        StyledText {
                            text: I18n.tr("Started", "process detail label") + ": "
                                + DgopService.formatElapsed(processItemRoot.process?.elapsedSeconds ?? 0)
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: (processItemRoot.process?.processor ?? -1) >= 0
                                ? (I18n.tr("Last CPU core", "process detail label") + ": " + processItemRoot.process.processor) : ""
                            visible: text.length > 0
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: I18n.tr("Owner", "process detail label") + ": " + (processItemRoot.process?.username ?? "--")
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }
                    }

                    StyledText {
                        text: processItemRoot.process?.description ?? ""
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
