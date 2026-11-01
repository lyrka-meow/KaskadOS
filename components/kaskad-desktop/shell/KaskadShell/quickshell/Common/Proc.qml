pragma Singleton

import Quickshell
import qs.KaskadCommon.Common as KaskadCommon

Singleton {
    readonly property int noTimeout: KaskadCommon.Proc.noTimeout
    readonly property string kaskadShellBin: KaskadCommon.Proc.kaskadShellBin

    function runCommand(id, command, callback, debounceMs, timeoutMs) {
        KaskadCommon.Proc.runCommand(id, command, callback, debounceMs, timeoutMs);
    }
}
