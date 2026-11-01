import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool loading: false
    property var lines: []
    property string error: ""
    property string trackKey: ""
    property int requestId: 0
    property string pendingArtist: ""
    property string pendingTitle: ""
    property real pendingDuration: 0

    function encoded(value) {
        return encodeURIComponent((value || "").trim());
    }

    function loadTrack(artist, title, album, duration) {
        const cleanArtist = (artist || "").trim();
        const cleanTitle = (title || "").trim();
        const key = cleanArtist + "\n" + cleanTitle + "\n" + (album || "") + "\n" + Math.round(duration || 0);
        if (key === trackKey)
            return;
        trackKey = key;
        requestId++;
        pendingArtist = cleanArtist;
        pendingTitle = cleanTitle;
        pendingDuration = duration || 0;
        lines = [];
        error = "";
        directFetcher.running = false;
        searchFetcher.running = false;
        if (!cleanTitle) {
            loading = false;
            return;
        }
        const query = "track_name=" + encoded(cleanTitle)
                    + "&artist_name=" + encoded(cleanArtist)
                    + ((album || "") ? "&album_name=" + encoded(album) : "")
                    + ((duration || 0) > 0 ? "&duration=" + Math.round(duration) : "");
        directFetcher.reqId = requestId;
        directFetcher.command = ["curl", "-fsSL", "--connect-timeout", "4", "--max-time", "10",
                                 "-H", "User-Agent: KaskadOS/0.1",
                                 "https://lrclib.net/api/get?" + query];
        loading = true;
        directFetcher.running = true;
    }

    function parseLrc(text) {
        const parsed = [];
        const rows = (text || "").split(/\r?\n/);
        const stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
        for (let index = 0; index < rows.length; index++) {
            const value = rows[index].replace(stamp, "").trim();
            stamp.lastIndex = 0;
            let match;
            while ((match = stamp.exec(rows[index])) !== null) {
                parsed.push({ time: Number(match[1]) * 60 + Number(match[2]), text: value || "♪" });
            }
        }
        parsed.sort((left, right) => left.time - right.time);
        return parsed;
    }

    function accept(result) {
        lines = parseLrc(result?.syncedLyrics || "");
        error = lines.length > 0 ? "" : qsTr("Lyrics not found");
    }

    function search() {
        searchFetcher.reqId = requestId;
        searchFetcher.command = ["curl", "-fsSL", "--connect-timeout", "4", "--max-time", "10",
                                 "-H", "User-Agent: KaskadOS/0.1",
                                 "https://lrclib.net/api/search?track_name=" + encoded(pendingTitle)
                                 + "&artist_name=" + encoded(pendingArtist)];
        searchFetcher.running = true;
    }

    property Process directFetcher: Process {
        property int reqId: 0
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (directFetcher.reqId !== root.requestId)
                    return;
                try { root.accept(JSON.parse(text)); } catch (exception) { root.lines = []; }
            }
        }
        onExited: {
            if (reqId !== root.requestId)
                return;
            if (root.lines.length === 0) root.search();
            else root.loading = false;
        }
    }

    property Process searchFetcher: Process {
        property int reqId: 0
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (searchFetcher.reqId !== root.requestId)
                    return;
                try {
                    const candidates = JSON.parse(text);
                    let best = null;
                    let bestScore = -100000;
                    for (let index = 0; index < candidates.length; index++) {
                        const candidate = candidates[index];
                        if (!candidate.syncedLyrics)
                            continue;
                        const delta = root.pendingDuration > 0 ? Math.abs((candidate.duration || 0) - root.pendingDuration) : 0;
                        const score = ((candidate.trackName || "").toLowerCase() === root.pendingTitle.toLowerCase() ? 100 : 0)
                                    + ((candidate.artistName || "").toLowerCase().includes(root.pendingArtist.toLowerCase()) ? 40 : 0)
                                    - delta;
                        if (score > bestScore) { best = candidate; bestScore = score; }
                    }
                    root.accept(best || candidates[0] || {});
                } catch (exception) {
                    root.error = qsTr("Lyrics not found");
                    root.lines = [];
                }
            }
        }
        onExited: {
            if (reqId !== root.requestId)
                return;
            root.loading = false;
            if (root.lines.length === 0 && !root.error)
                root.error = qsTr("Lyrics not found");
        }
    }
}
