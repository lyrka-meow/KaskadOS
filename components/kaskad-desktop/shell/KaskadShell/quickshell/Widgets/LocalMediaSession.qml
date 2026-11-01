import QtQuick
import QtMultimedia
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    property string instanceId: ""
    property string folderPath: ""
    property bool recursive: false
    property string repeatMode: "none" // none, all, one
    property bool shuffle: false
    property real volume: 0.8
    property var tracks: []
    property int currentIndex: -1
    property bool scanning: false
    property string scanError: ""
    property bool lyricsLoading: false
    property string lyricsText: ""
    property string lyricsError: ""
    property var lyricsLines: []
    property int lyricsRequestId: 0
    property string artworkUrl: ""
    property int artworkRequestId: 0

    readonly property bool hasCurrentTrack: currentIndex >= 0 && currentIndex < tracks.length
    readonly property string currentTrackPath: hasCurrentTrack ? tracks[currentIndex] : ""
    readonly property string currentFileName: {
        if (!currentTrackPath)
            return "";
        const slash = currentTrackPath.lastIndexOf("/");
        return currentTrackPath.substring(slash + 1);
    }
    readonly property string fallbackTitle: currentFileName.replace(/\.[^.]+$/, "")
    readonly property string title: metadataString(MediaMetaData.Title) || fallbackTitle
    readonly property string artist: metadataString(MediaMetaData.ContributingArtist)
                                      || metadataString(MediaMetaData.AlbumArtist)
    readonly property string album: metadataString(MediaMetaData.AlbumTitle)
    readonly property real duration: player.duration > 0 ? player.duration / 1000 : 0
    readonly property real position: player.position > 0 ? player.position / 1000 : 0
    readonly property int lyricIndex: indexForTime(position)
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property bool paused: player.playbackState === MediaPlayer.PausedState
    readonly property bool canGoPrevious: tracks.length > 1 || position > 3
    readonly property bool canGoNext: tracks.length > 1
    readonly property int playbackState: player.playbackState
    readonly property int mediaStatus: player.mediaStatus
    readonly property string errorString: player.errorString || scanError

    signal configurationChanged(var updates)
    signal trackChanged(string path, int index)

    implicitWidth: 0
    implicitHeight: 0
    visible: false

    function metadataString(key) {
        try {
            const value = player.metaData.value(key);
            if (Array.isArray(value))
                return value.join(", ");
            return value ? value.toString() : "";
        } catch (error) {
            return "";
        }
    }

    function stableHash(value) {
        let hash = 2166136261;
        for (let index = 0; index < value.length; index++) {
            hash ^= value.charCodeAt(index);
            hash = Math.imul(hash, 16777619);
        }
        return (hash >>> 0).toString(16);
    }

    function loadArtwork() {
        artExtractor.running = false;
        artworkRequestId++;
        artworkUrl = "";
        if (!currentTrackPath)
            return;
        const cacheDirectory = Paths.strip(Paths.cache) + "/media-art";
        Paths.mkdir(Paths.toFileUrl(cacheDirectory));
        const outputPath = cacheDirectory + "/" + stableHash(instanceId + "\n" + currentTrackPath) + ".jpg";
        artExtractor.requestId = artworkRequestId;
        artExtractor.outputPath = outputPath;
        artExtractor.command = ["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", currentTrackPath,
                                "-map", "0:v:0", "-frames:v", "1", "-q:v", "2", outputPath];
        artExtractor.running = true;
    }

    function folderArtworkFallback() {
        if (!currentTrackPath)
            return "";
        const slash = currentTrackPath.lastIndexOf("/");
        return Paths.toFileUrl(currentTrackPath.substring(0, slash + 1) + "cover.jpg");
    }

    function loadLyrics() {
        lyricsFetcher.running = false;
        lyricsRequestId++;
        lyricsText = "";
        lyricsError = "";
        lyricsLines = [];
        if (!hasCurrentTrack || !title) {
            lyricsLoading = false;
            return;
        }
        const query = "track_name=" + encodeURIComponent(title)
                    + "&artist_name=" + encodeURIComponent(artist || "");
        lyricsFetcher.requestId = lyricsRequestId;
        lyricsFetcher.command = ["curl", "-fsSL", "--connect-timeout", "4", "--max-time", "10",
                                 "-H", "User-Agent: KaskadOS/0.1",
                                 "https://lrclib.net/api/search?" + query];
        lyricsLoading = true;
        lyricsFetcher.running = true;
    }

    function plainSyncedLyrics(value) {
        return (value || "").split(/\r?\n/).map(line => line.replace(/\[[0-9]+:[0-9.]+\]/g, "").trim())
                             .filter(line => line.length > 0).join("\n");
    }

    function parseLrc(text) {
        const parsed = [];
        const rows = (text || "").split(/\r?\n/);
        const stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
        for (let i = 0; i < rows.length; i++) {
            const value = rows[i].replace(stamp, "").trim();
            stamp.lastIndex = 0;
            let match;
            while ((match = stamp.exec(rows[i])) !== null) {
                parsed.push({
                    time: Number(match[1]) * 60 + Number(match[2]),
                    text: value || "♪"
                });
            }
        }
        parsed.sort((left, right) => left.time - right.time);
        return parsed;
    }

    function indexForTime(seconds) {
        let low = 0;
        let high = lyricsLines.length - 1;
        let result = -1;
        while (low <= high) {
            const middle = (low + high) >> 1;
            if (lyricsLines[middle].time <= seconds + 0.08) {
                result = middle;
                low = middle + 1;
            } else {
                high = middle - 1;
            }
        }
        return result;
    }

    function setFolder(path) {
        const normalized = Paths.strip(path || "");
        if (folderPath === normalized) {
            scan();
            return;
        }
        stop();
        currentIndex = -1;
        folderPath = normalized;
        configurationChanged({ localMusicFolder: normalized });
        scan();
    }

    function setRecursive(value) {
        if (recursive === value)
            return;
        recursive = value;
        configurationChanged({ localMusicRecursive: value });
        scan();
    }

    function setRepeatMode(value) {
        if (!["none", "all", "one"].includes(value))
            return;
        repeatMode = value;
        configurationChanged({ localMusicRepeatMode: value });
    }

    function setShuffle(value) {
        shuffle = value;
        configurationChanged({ localMusicShuffle: value });
    }

    function setVolume(value) {
        volume = Math.max(0, Math.min(1, value));
        configurationChanged({ localMusicVolume: volume });
    }

    function scan() {
        scanner.running = false;
        tracks = [];
        scanError = "";
        if (!folderPath) {
            scanning = false;
            return;
        }

        const command = ["find", folderPath];
        if (!recursive)
            command.push("-maxdepth", "1");
        command.push("-regextype", "posix-extended", "-type", "f", "-iregex",
                     ".*\\.(mp3|flac|ogg|opus|wav|m4a|aac|wma)", "-print0");
        scanner.command = command;
        scanning = true;
        scanner.running = true;
    }

    function acceptScan(text) {
        const previousPath = currentTrackPath;
        const found = (text || "").split("\u0000").filter(path => path.length > 0);
        found.sort((left, right) => left.localeCompare(right, undefined, {
            numeric: true,
            sensitivity: "base"
        }));
        tracks = found;
        currentIndex = previousPath ? found.indexOf(previousPath) : -1;
        if (currentIndex < 0)
            player.stop();
    }

    function playIndex(index) {
        if (index < 0 || index >= tracks.length)
            return;
        currentIndex = index;
        player.source = Paths.toFileUrl(tracks[index]);
        player.play();
        LocalMediaCoordinator.activate(root);
        trackChanged(tracks[index], index);
    }

    function togglePlaying() {
        if (!hasCurrentTrack) {
            if (tracks.length > 0)
                playIndex(0);
            return;
        }
        if (playing)
            player.pause();
        else {
            player.play();
            LocalMediaCoordinator.activate(root);
        }
    }

    function stop() {
        player.stop();
    }

    function seek(seconds) {
        if (!hasCurrentTrack || !player.seekable)
            return;
        player.position = Math.max(0, Math.min(player.duration, seconds * 1000));
    }

    function next() {
        if (tracks.length === 0)
            return;
        if (shuffle && tracks.length > 1) {
            let nextIndex = currentIndex;
            while (nextIndex === currentIndex)
                nextIndex = Math.floor(Math.random() * tracks.length);
            playIndex(nextIndex);
            return;
        }
        const candidate = currentIndex + 1;
        if (candidate < tracks.length) {
            playIndex(candidate);
        } else if (repeatMode === "all") {
            playIndex(0);
        } else {
            stop();
        }
    }

    function previous() {
        if (position > 3) {
            seek(0);
            return;
        }
        if (tracks.length === 0)
            return;
        const candidate = currentIndex - 1;
        if (candidate >= 0) {
            playIndex(candidate);
        } else if (repeatMode === "all") {
            playIndex(tracks.length - 1);
        } else {
            seek(0);
        }
    }

    onFolderPathChanged: {
        if (!scanning && !scanner.running)
            scanDebounce.restart();
    }
    onRecursiveChanged: scanDebounce.restart()
    onVolumeChanged: audioSink.volume = Math.max(0, Math.min(1, volume))
    onTitleChanged: lyricsDebounce.restart()
    onArtistChanged: lyricsDebounce.restart()
    onCurrentTrackPathChanged: artworkDebounce.restart()

    Component.onCompleted: {
        LocalMediaCoordinator.registerSession(root);
        scanDebounce.restart();
    }
    Component.onDestruction: LocalMediaCoordinator.unregisterSession(root)

    Timer {
        id: scanDebounce
        interval: 50
        repeat: false
        onTriggered: root.scan()
    }

    Timer {
        id: lyricsDebounce
        interval: 500
        repeat: false
        onTriggered: root.loadLyrics()
    }

    Timer {
        id: artworkDebounce
        interval: 100
        repeat: false
        onTriggered: root.loadArtwork()
    }

    MediaDevices {
        id: mediaDevices
    }

    function selectedAudioDevice() {
        const sinkName = AudioService.sink?.name ?? "";
        const outputs = mediaDevices.audioOutputs ?? [];
        for (let index = 0; index < outputs.length; index++) {
            if (outputs[index].id === sinkName)
                return outputs[index];
        }
        return mediaDevices.defaultAudioOutput;
    }

    AudioOutput {
        id: audioSink
        device: root.selectedAudioDevice()
        volume: Math.max(0, Math.min(1, root.volume))
    }

    MediaPlayer {
        id: player
        audioOutput: audioSink

        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.EndOfMedia)
                return;
            if (root.repeatMode === "one") {
                position = 0;
                play();
            } else {
                root.next();
            }
        }
    }

    Process {
        id: scanner
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.acceptScan(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.scanError = text.trim();
            }
        }

        onExited: exitCode => {
            root.scanning = false;
            if (exitCode !== 0 && !root.scanError)
                root.scanError = I18n.tr("Unable to read the music folder");
        }
    }


    Process {
        id: lyricsFetcher
        property int requestId: 0
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if (lyricsFetcher.requestId !== root.lyricsRequestId)
                    return;
                try {
                    const candidates = JSON.parse(text || "[]");
                    const selected = candidates.find(item => item && item.syncedLyrics)
                                  || candidates.find(item => item && item.plainLyrics)
                                  || null;
                    if (!selected) {
                        root.lyricsError = I18n.tr("Lyrics not found");
                        return;
                    }
                    root.lyricsLines = root.parseLrc(selected.syncedLyrics || "");
                    root.lyricsText = selected.plainLyrics || root.plainSyncedLyrics(selected.syncedLyrics);
                    if (!root.lyricsText)
                        root.lyricsError = I18n.tr("Lyrics not found");
                    else if (root.lyricsLines.length === 0)
                        root.lyricsError = I18n.tr("Lyrics are available, but not synchronized");
                } catch (error) {
                    root.lyricsError = I18n.tr("Lyrics not found");
                }
            }
        }

        onExited: exitCode => {
            if (requestId !== root.lyricsRequestId)
                return;
            root.lyricsLoading = false;
            if (exitCode !== 0 && !root.lyricsText)
                root.lyricsError = I18n.tr("Lyrics are unavailable offline");
        }
    }


    Process {
        id: artExtractor
        property int requestId: 0
        property string outputPath: ""
        running: false

        onExited: exitCode => {
            if (requestId !== root.artworkRequestId)
                return;
            root.artworkUrl = exitCode === 0 ? Paths.toFileUrl(outputPath) : root.folderArtworkFallback();
        }
    }
}
