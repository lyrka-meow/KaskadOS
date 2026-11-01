import QtQuick
import Quickshell.Services.Mpris
import qs.Services

// Open, three-sided Cava visualizer. There is deliberately no ring or frame:
// the live strokes grow from the left, right and bottom edges toward the centre.
Item {
    id: root

    property var activePlayer
    property bool playingOverride: false
    property bool usePlayingOverride: false
    property color color: MediaAccentService.accent
    property real edgeInset: 13
    property real maxLength: Math.min(width, height) * 0.28
    readonly property bool playing: usePlayingOverride ? playingOverride
                                                       : activePlayer?.playbackState === MprisPlaybackState.Playing

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        function strokeFromEdge(ctx, originX, originY, value) {
            const raw = Math.max(0, Math.min(100, value || 0));
            if (!root.playing || raw < 1)
                return;

            const level = Math.sqrt(raw / 100);
            const length = 4 + level * root.maxLength;
            const dx = width / 2 - originX;
            const dy = height / 2 - originY;
            const distance = Math.max(1, Math.sqrt(dx * dx + dy * dy));
            const endX = originX + dx / distance * length;
            const endY = originY + dy / distance * length;

            ctx.beginPath();
            ctx.moveTo(originX, originY);
            ctx.lineTo(endX, endY);
            ctx.stroke();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = root.color;
            ctx.lineCap = "round";
            ctx.lineWidth = Math.max(2, Math.min(width, height) * 0.014);

            const values = CavaService.values;
            const count = 16;
            const inset = root.edgeInset;
            const sideTop = height * 0.12;
            const sideBottom = height - inset;
            const horizontalSpan = width - inset * 2;
            const verticalSpan = sideBottom - sideTop;

            for (let i = 0; i < count; i++) {
                const sideY = sideTop + verticalSpan * i / (count - 1);
                const bottomX = inset + horizontalSpan * i / (count - 1);
                strokeFromEdge(ctx, inset, sideY, values[i]);
                strokeFromEdge(ctx, bottomX, height - inset, values[count + i]);
                strokeFromEdge(ctx, width - inset, sideY, values[count * 2 + i]);
            }
        }

        Connections {
            target: CavaService
            function onValuesChanged() { canvas.requestPaint(); }
        }

        Connections {
            target: MediaAccentService
            function onAccentChanged() { canvas.requestPaint(); }
        }
    }

    onPlayingChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
