pragma Singleton

import QtQuick

QtObject {
    id: root
    property bool active: false
    property int step: 0
    readonly property int stepCount: 5

    signal finished

    function start() {
        step = 0;
        active = true;
    }

    function next() {
        if (step < stepCount - 1) {
            step++;
            return;
        }
        complete();
    }

    function previous() {
        if (step > 0)
            step--;
    }

    function complete() {
        active = false;
        FirstLaunchService.markFirstLaunchComplete();
        finished();
    }

    function skip() {
        complete();
    }
}
