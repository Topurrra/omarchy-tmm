import QtQuick
import qs.Ui
import qs.Commons

// Bar button that opens the manual.
//
// It goes through shell IPC rather than touching the panel directly, so the
// button, the SUPER+ALT+M binding and the menu entries all share one toggle
// path — and the bar can reload without stranding an open panel.
BarWidget {
    id: root
    moduleName: "tmm.manual"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property var hostShell: root.bar && root.bar.shell ? root.bar.shell : null

    function togglePanel() {
        if (!root.bar) return;
        if (hostShell && typeof hostShell.toggle === "function") {
            hostShell.toggle(moduleName, "{}");
        } else {
            root.bar.run("omarchy-shell shell toggle tmm.manual");
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        tooltipText: "The Missing Manual"

        // The Missing Manual mark, redrawn as a single-colour line icon so it
        // takes the bar's own text colour like every other glyph on the strip —
        // the full-colour logo.png would read as a sticker here. It keeps the
        // three things that make the mark recognisable: the book, the terminal
        // prompt inside it, and the ribbon. Built from plain items rather than a
        // Canvas so it paints reliably at the bar's tiny size.
        iconComponent: Component {
            Item {
                id: mark
                anchors.fill: parent
                // Match the bar's own text colour so it themes like every glyph.
                readonly property color ink: (Color.bar && Color.bar.text)
                    ? Color.bar.text : Color.foreground
                // One grid unit; the mark is authored on a 24-unit square.
                readonly property real u: Math.min(width, height) / 24

                // Book cover: a rounded-rectangle outline.
                Rectangle {
                    id: cover
                    anchors.centerIn: parent
                    width: 15 * mark.u
                    height: 18 * mark.u
                    radius: 2.4 * mark.u
                    color: "transparent"
                    border.width: Math.max(1, 1.6 * mark.u)
                    border.color: mark.ink
                }

                // Spine rule, a touch in from the left edge.
                Rectangle {
                    width: Math.max(1, 1.1 * mark.u)
                    height: cover.height - 4 * mark.u
                    radius: width
                    color: mark.ink
                    x: cover.x + 2.4 * mark.u
                    anchors.verticalCenter: cover.verticalCenter
                }

                // The terminal prompt inside the book: a chevron and an
                // underscore. Drawn as a chevron shape plus a bar so it stays
                // crisp and identical whatever fonts the theme ships.
                Canvas {
                    id: promptGlyph
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = mark.ink;
                        ctx.lineWidth = Math.max(1, 1.5 * mark.u);
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        var px = cover.x + 5.2 * mark.u;
                        var py = cover.y + cover.height / 2;
                        ctx.beginPath();                 // the >
                        ctx.moveTo(px, py - 2.4 * mark.u);
                        ctx.lineTo(px + 2.6 * mark.u, py);
                        ctx.lineTo(px, py + 2.4 * mark.u);
                        ctx.stroke();
                        ctx.beginPath();                 // the _
                        ctx.moveTo(px + 3.7 * mark.u, py + 2.4 * mark.u);
                        ctx.lineTo(px + 6.8 * mark.u, py + 2.4 * mark.u);
                        ctx.stroke();
                    }
                    Connections {
                        target: mark
                        function onInkChanged() { promptGlyph.requestPaint() }
                        function onUChanged() { promptGlyph.requestPaint() }
                    }
                }

                // Ribbon: a small tab hanging past the bottom edge.
                Rectangle {
                    width: 3.2 * mark.u
                    height: 4.4 * mark.u
                    color: mark.ink
                    x: cover.x + cover.width / 2 - width / 2 + 1.2 * mark.u
                    y: cover.y + cover.height - 1.4 * mark.u
                }
            }
        }

        onPressed: function (mouseButton) {
            if (mouseButton !== undefined && mouseButton !== null && mouseButton !== Qt.LeftButton) return;
            root.togglePanel();
        }
    }
}
