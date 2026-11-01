pragma Singleton

import Quickshell
import qs.KaskadCommon.Common as KaskadCommon

Singleton {
    readonly property var rounding: KaskadCommon.Appearance.rounding
    readonly property var spacing: KaskadCommon.Appearance.spacing
    readonly property var fontSize: KaskadCommon.Appearance.fontSize
    readonly property var anim: KaskadCommon.Appearance.anim
}
