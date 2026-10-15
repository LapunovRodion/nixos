import QtQuick
import qs.services
import qs.modules.bar

// Бар сменил край: снимок старого рассыпается на клетки, они летят к новому
// краю и собираются в новый бар (шейдеры — home/caelestia/shaders). Лежит
// поверх окна шелла на весь экран; кладётся в modules/drawers при сборке,
// запускает его Drawers.qml (bar-position.patch).
ShaderEffect {
    id: root

    // Старый бар: { result — grabToImage, rect — где был, side — край }; null — перелёта нет.
    required property var from
    required property BarWrapper bar

    property real progress
    readonly property rect fromRect: from?.rect ?? Qt.rect(0, 0, 0, 0)
    readonly property rect toRect: {
        const t = bar.contentThickness;
        if (bar.position === "top")
            return Qt.rect(0, 0, width, t);
        if (bar.position === "bottom")
            return Qt.rect(0, height - t, width, t);
        return Qt.rect(0, 0, t, height);
    }
    readonly property point grid: Qt.point(72, 4)
    readonly property real fromSide: sideOf(from?.side)
    readonly property real toSide: sideOf(bar.position)
    // Фон бара рисует рамка окна, в снимках его нет.
    readonly property color background: Colours.tPalette.m3surface
    readonly property Image fromSource: oldBar
    readonly property ShaderEffectSource toSource: newBar

    signal finished

    function start(): void {
        flight.start();
    }

    function sideOf(position: string): real {
        return position === "top" ? 1 : position === "bottom" ? 2 : 0;
    }

    visible: from !== null && progress < 1
    mesh: GridMesh {
        resolution: Qt.size(root.grid.x * 2, root.grid.y * 2)
    }
    vertexShader: Qt.resolvedUrl("bar-shatter.vert.qsb")
    fragmentShader: Qt.resolvedUrl("bar-shatter.frag.qsb")

    Image {
        id: oldBar

        visible: false
        source: root.from?.result.url ?? ""
    }

    ShaderEffectSource {
        id: newBar

        visible: false
        sourceItem: root.bar.barContent
    }

    NumberAnimation {
        id: flight

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 1000
        onFinished: root.finished()
    }
}
