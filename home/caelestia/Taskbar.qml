pragma ComponentBehavior: Bound

// Окна стола кнопками, как панель задач Windows: пункт `taskbar` в
// bar.entries (home/hyprland.nix), показывается только в нижнем баре —
// на float-столах (home/hyprland/modes.lua). Свёрнутые (special:minimized)
// видны бледными. Клик — фокус и наверх, по активному — свернуть, по
// свёрнутому — вернуть на этот стол; средняя кнопка — закрыть.
// Кладётся в исходник шелла рядом с ActiveWindow.qml (home/hyprland.nix).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen

    readonly property int wsId: Hypr.monitorFor(screen)?.activeWorkspace?.id ?? -1
    // ponytail: special:minimized не помнит, с какого стола окно, —
    // свёрнутые видны на панели любого стола.
    readonly property var windows: Hypr.toplevels.values.filter(t => t.workspace && !Hypr.isToplevelIgnored(t) && (t.workspace.id === wsId || t.workspace.name === "special:minimized"))
    readonly property real buttonWidth: Math.min(200, screen.width * 0.5 / Math.max(1, windows.length))

    // Скрытый (не нижний бар) — без ширины: ActiveWindow считает свою
    // по ширине соседей.
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: 32

    function act(t: HyprlandToplevel, button: int): void {
        const w = `"address:${t.lastIpcObject.address}"`;
        let ds;
        if (button === Qt.MiddleButton)
            ds = [`hl.dsp.window.close({ window = ${w} })`];
        else if (t.workspace?.name === "special:minimized")
            ds = [`hl.dsp.window.move({ window = ${w}, workspace = "${wsId}" })`, `hl.dsp.focus({ window = ${w} })`, `hl.dsp.window.alter_zorder({ window = ${w}, mode = "top" })`];
        else if (t.activated)
            ds = [`hl.dsp.window.move({ window = ${w}, workspace = "special:minimized", follow = false })`];
        else
            ds = [`hl.dsp.focus({ window = ${w} })`, `hl.dsp.window.alter_zorder({ window = ${w}, mode = "top" })`];
        Hypr.dispatch(`(function() ${ds.map(d => `hl.dispatch(${d})`).join(" ")} return hl.dsp.no_op() end)()`);
    }

    RowLayout {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.small

        Repeater {
            model: root.windows

            StyledRect {
                id: button

                required property HyprlandToplevel modelData
                readonly property bool minimized: modelData.workspace?.name === "special:minimized"

                implicitWidth: root.buttonWidth
                implicitHeight: root.implicitHeight
                radius: Tokens.rounding.full
                opacity: minimized ? 0.5 : 1
                color: modelData.activated ? Colours.palette.m3primaryContainer : "transparent"

                StateLayer {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: e => root.act(button.modelData, e.button)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.normal
                    anchors.rightMargin: Tokens.padding.normal
                    spacing: Tokens.spacing.small

                    IconImage {
                        implicitSize: 18
                        source: Icons.getAppIcon(button.modelData.lastIpcObject.class ?? "", "application-x-executable")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: button.modelData.title
                        elide: Text.ElideRight
                        font: Tokens.font.body.builders.small.build()
                        color: button.modelData.activated ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                    }
                }
            }
        }
    }
}
