pragma Singleton

import QtQuick

QtObject {
    id: root

    property var sessions: []
    property var activeSession: null
    property string dashboardSource: "local"

    readonly property bool hasActiveLocalSession: activeSession !== null && activeSession.hasCurrentTrack

    function registerSession(session) {
        if (!session || sessions.includes(session))
            return;
        sessions = sessions.concat([session]);
    }

    function unregisterSession(session) {
        sessions = sessions.filter(candidate => candidate !== session);
        if (activeSession === session)
            activeSession = sessions.find(candidate => candidate.hasCurrentTrack) || null;
    }

    function activate(session) {
        if (!session)
            return;
        registerSession(session);
        activeSession = session;
    }

    function setDashboardSource(source) {
        if (source === "local" || source === "external")
            dashboardSource = source;
    }

    function play() {
        if (hasActiveLocalSession)
            activeSession.togglePlaying();
    }

    function pause() {
        if (hasActiveLocalSession && activeSession.playing)
            activeSession.togglePlaying();
    }

    function previous() {
        if (hasActiveLocalSession)
            activeSession.previous();
    }

    function next() {
        if (hasActiveLocalSession)
            activeSession.next();
    }

    function stop() {
        if (hasActiveLocalSession)
            activeSession.stop();
    }

    function adjustVolume(delta) {
        if (!hasActiveLocalSession)
            return -1;
        activeSession.setVolume(activeSession.volume + delta);
        return Math.round(activeSession.volume * 100);
    }

    function setVolume(value) {
        if (!hasActiveLocalSession)
            return -1;
        activeSession.setVolume(value);
        return Math.round(activeSession.volume * 100);
    }
}
