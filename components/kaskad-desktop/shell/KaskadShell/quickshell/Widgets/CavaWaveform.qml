import QtQuick
import qs.Common
import qs.Services

Item {
    id: root

    property bool playing: false
    property color waveColor: Theme.primary
    readonly property bool live: visible && (Window.window?.visible ?? false) && playing

    Loader {
        active: root.live
        sourceComponent: Component {
            Ref { service: CavaService }
        }
    }

    Connections {
        target: CavaService
        enabled: root.live
        function onValuesChanged() { wave.requestPaint(); }
    }

    Canvas {
        id: wave
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = root.waveColor;
            ctx.lineWidth = Math.max(1.6, height * 0.11);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            const values = CavaService.compactValues;
            const points = 13;
            const center = height / 2;
            const step = width / (points - 1);
            ctx.beginPath();
            ctx.moveTo(0, center);
            for (let i = 1; i < points; i++) {
                const band = Math.min(5, Math.floor(i * 6 / points));
                const level = root.live ? Math.sqrt(Math.max(0, Math.min(100, values[band] || 0)) / 100) : 0;
                const direction = i % 2 === 0 ? -1 : 1;
                const y = center + direction * level * height * 0.38;
                const previousX = (i - 1) * step;
                const x = i * step;
                ctx.quadraticCurveTo(previousX + step * 0.55, y, x, y);
            }
            ctx.stroke();
        }
    }

    onPlayingChanged: wave.requestPaint()
    onWidthChanged: wave.requestPaint()
    onHeightChanged: wave.requestPaint()
}
