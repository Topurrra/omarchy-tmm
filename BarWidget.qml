import QtQuick
import qs.Ui

// Bar button that opens the manual.
//
// It goes through shell IPC rather than touching the overlay directly, so the
// button, the SUPER+ALT+M binding and the menu entries all share one toggle
// path — and the bar can reload without stranding an open overlay.
BarWidget {
    id: root
    moduleName: "tmm.manual"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar

        // A Nerd Font glyph rather than logo.png: the bar is a dense
        // monochrome strip whose icons take their color from the theme, and a
        // full-colour mark would read as a sticker next to every other widget.
        // The logo still carries the branding inside the overlay itself.
        text: "󰗚"
        tooltipText: "The Missing Manual"

        onPressed: function (mouseButton) {
            if (!root.bar) return;
            root.bar.run("omarchy-shell shell toggle tmm.manual");
        }
    }
}
