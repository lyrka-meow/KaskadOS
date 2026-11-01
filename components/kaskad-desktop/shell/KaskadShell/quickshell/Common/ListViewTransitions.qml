pragma Singleton

import QtQuick
import Quickshell
import qs.KaskadCommon.Common as KaskadCommon

Singleton {
    readonly property bool enabled: KaskadCommon.ListViewTransitions.enabled
    readonly property Transition add: KaskadCommon.ListViewTransitions.add
    readonly property Transition remove: KaskadCommon.ListViewTransitions.remove
    readonly property Transition displaced: KaskadCommon.ListViewTransitions.displaced
    readonly property Transition move: KaskadCommon.ListViewTransitions.move
}
