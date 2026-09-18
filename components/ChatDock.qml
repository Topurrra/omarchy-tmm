import QtQuick
import Quickshell
import qs.Commons
import "../Markdown.js" as Markdown

// The tutor dock. A self-contained, theme-driven view that pins to the right
// of the reader (or covers the content area when compact). It owns its own
// input focus and keys once open; everything else is injected by the view.
//
// It mirrors the website's TutorChat: a titled header with a close X, a
// mascot empty state with starter chips, block-rendered assistant answers
// (real code cards, headings, lists) and a paper-plane send button.
//
//   header  — "Ask the tutor" + close X
//   body    — the empty state, or the conversation (You / Tutor turns)
//   input   — a growing field; Enter sends, Shift+Enter is a newline, Esc closes
Item {
    id: dock

    // --- injected state ---
    property var messages: []
    property bool busy: false
    property string errorText: ""
    property bool aiReady: false

    // The live AI config (Service.aiConfig) and the built-in Tutor prompt, both
    // read by the settings form the gear button opens.
    property var aiConfig: ({})
    property string defaultSystemPrompt: ""
    // When true the settings form covers the conversation.
    property bool settingsOpen: false

    // --- injected palette ---
    property color background: Color.background
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color muted: Util.alpha(foreground, 0.6)
    property color selectedBackground: Util.alpha(foreground, 0.08)
    property color divider: Util.alpha(foreground, 0.14)
    property color urgent: Color.urgent
    property string fontFamily: Style.font.menuFamily

    // Which palette the fenced-code highlighter should use -- true for a dark
    // card background, false for light. Panel sets this from the active theme.
    property bool codeDark: true

    // A left seam against the reader in wide mode; the view turns it off when
    // the dock covers the whole content area (compact).
    property bool showDivider: true

    // The three website starter prompts; a click sends one immediately.
    readonly property var starters: [
        "Why does this matter?",
        "Show a real example",
        "Explain it more simply"
    ]

    // --- outputs ---
    signal send(string text)
    signal sourceActivated(string slug, int phase)
    signal closeRequested()
    signal clearRequested()
    signal saveSettings(var cfg)

    // The view grabs the input when the dock opens.
    function focusInput() { input.forceActiveFocus(); }
    function scrollToBottom() { Qt.callLater(function () { list.positionViewAtEnd(); }); }

    onMessagesChanged: scrollToBottom()
    onBusyChanged: scrollToBottom()
    onVisibleChanged: if (visible) Qt.callLater(focusInput)
    // Move focus into the settings form when it opens (so it takes the keyboard),
    // and back to the chat input when it closes.
    onSettingsOpenChanged: {
        if (dock.settingsOpen) Qt.callLater(function () { settingsForm.focusForm(); });
        else Qt.callLater(function () { dock.focusInput(); });
    }

    // Click-to-copy confirmation for code cards. One string, matched against a
    // card's own text so only the copied card shows "copied".
    property string copiedText: ""
    Timer { id: copiedReset; interval: 1400; onTriggered: dock.copiedText = "" }
    function copyCode(text) {
        if (!text) return;
        Quickshell.execDetached(["wl-copy", "--", text]);
        dock.copiedText = text;
        copiedReset.restart();
    }

    function _submit() {
        var t = input.text.replace(/^\s+|\s+$/g, "");
        if (!t || dock.busy) return;
        dock.send(t);
        input.text = "";
    }

    function _inputKey(e) {
        if (e.key === Qt.Key_Escape) {
            dock.closeRequested();
            e.accepted = true;
            return;
        }
        // Ctrl+K closes from inside the field too, mirroring the global toggle.
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_K) {
            dock.closeRequested();
            e.accepted = true;
            return;
        }
        // Ctrl+, opens the settings form (the gear's keyboard equivalent).
        if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Comma) {
            dock.settingsOpen = true;
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            if (e.modifiers & Qt.ShiftModifier) return;   // let TextEdit insert a newline
            dock._submit();
            e.accepted = true;
        }
    }

    // Opaque base: in compact mode the dock sits over the reader, so it must
    // cover it rather than let it show through.
    Rectangle {
        anchors.fill: parent
        color: dock.background
    }

    Rectangle {
        id: seam
        visible: dock.showDivider
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: dock.divider
    }

    readonly property int hpad: Style.space(14)

    // ------------------------------------------------------------- header
    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        height: titleText.implicitHeight + Style.space(18)

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Ask the tutor"
            color: dock.foreground
            font.family: dock.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
        }

        // Settings gear: opens the provider editor over the conversation. A
        // Canvas cog rather than a glyph, so it never falls back to tofu in a
        // mono font that lacks the symbol.
        Item {
            id: gearBtn
            anchors.right: closeBtn.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(24)
            height: Style.space(24)

            Canvas {
                id: gearIcon
                anchors.centerIn: parent
                width: Style.space(18)
                height: Style.space(18)
                readonly property color ink: dock.settingsOpen || gearHover.containsMouse
                    ? dock.accent : dock.muted
                readonly property real u: Math.min(width, height) / 24

                onInkChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var u = gearIcon.u;
                    var cx = 12 * u, cy = 12 * u;
                    var teeth = 8, steps = teeth * 2;
                    var rOut = 11 * u, rIn = 8.4 * u, hub = 3.3 * u;
                    ctx.fillStyle = gearIcon.ink;
                    ctx.beginPath();
                    for (var k = 0; k <= steps; k++) {
                        var ang = (k / steps) * 2 * Math.PI - Math.PI / 2;
                        var r = (k % 2 === 0) ? rOut : rIn;
                        var x = cx + Math.cos(ang) * r;
                        var y = cy + Math.sin(ang) * r;
                        if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                    ctx.fill();
                    // Punch the centre hole so it reads as a gear, not a star.
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.beginPath();
                    ctx.arc(cx, cy, hub, 0, 2 * Math.PI);
                    ctx.fill();
                    ctx.globalCompositeOperation = "source-over";
                }
                Connections {
                    target: dock
                    function onAccentChanged() { gearIcon.requestPaint(); }
                    function onMutedChanged() { gearIcon.requestPaint(); }
                }
            }
            MouseArea {
                id: gearHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dock.settingsOpen = !dock.settingsOpen
            }
        }

        // Close X. A glyph rather than a Canvas: it themes with the text and
        // reads crisply at any size.
        Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(24)
            height: Style.space(24)

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "✕"
                color: closeHover.containsMouse ? dock.accent : dock.muted
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
            }
            MouseArea {
                id: closeHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dock.closeRequested()
            }
        }
    }

    Rectangle {
        id: headerRule
        anchors.top: headerRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: dock.divider
    }

    // ------------------------------------------------------------- empty state
    Item {
        id: emptyState
        anchors.top: headerRule.bottom
        anchors.bottom: clearRow.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        visible: dock.messages.length === 0 && !dock.settingsOpen

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(12)

            // The graduation-cap robot, drawn on a 24-grid and scaled to fit.
            Canvas {
                id: mascot
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(56)
                height: Style.space(56)
                readonly property color ink: dock.foreground
                readonly property color eyeWhite: dock.background
                readonly property real u: Math.min(width, height) / 24

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                Component.onCompleted: requestPaint()
                Connections {
                    target: dock
                    function onForegroundChanged() { mascot.requestPaint(); }
                    function onBackgroundChanged() { mascot.requestPaint(); }
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var u = mascot.u;

                    function rr(x, y, w, h, r) {
                        ctx.beginPath();
                        ctx.moveTo(x + r, y);
                        ctx.lineTo(x + w - r, y);
                        ctx.arcTo(x + w, y, x + w, y + r, r);
                        ctx.lineTo(x + w, y + h - r);
                        ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
                        ctx.lineTo(x + r, y + h);
                        ctx.arcTo(x, y + h, x, y + h - r, r);
                        ctx.lineTo(x, y + r);
                        ctx.arcTo(x, y, x + r, y, r);
                        ctx.closePath();
                    }

                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.strokeStyle = mascot.ink;

                    // Mortarboard.
                    ctx.lineWidth = 1.6 * u;
                    ctx.beginPath();
                    ctx.moveTo(12 * u, 4 * u);
                    ctx.lineTo(21 * u, 7.5 * u);
                    ctx.lineTo(12 * u, 9 * u);
                    ctx.lineTo(3 * u, 7.5 * u);
                    ctx.closePath();
                    ctx.stroke();

                    // Tassel string.
                    ctx.lineWidth = 1.5 * u;
                    ctx.beginPath();
                    ctx.moveTo(21 * u, 7.5 * u);
                    ctx.bezierCurveTo(21.8 * u, 8.5 * u, 21.8 * u, 10 * u, 21 * u, 11 * u);
                    ctx.stroke();

                    // Tassel ball.
                    ctx.fillStyle = mascot.ink;
                    ctx.beginPath();
                    ctx.arc(21 * u, 11.4 * u, 0.9 * u, 0, 2 * Math.PI);
                    ctx.fill();

                    // Face.
                    ctx.lineWidth = 1.6 * u;
                    rr(6 * u, 9 * u, 12 * u, 9 * u, 3 * u);
                    ctx.stroke();

                    // Ears.
                    ctx.lineWidth = 1.4 * u;
                    rr(4 * u, 11.5 * u, 2 * u, 3 * u, 0.6 * u);
                    ctx.stroke();
                    rr(18 * u, 11.5 * u, 2 * u, 3 * u, 0.6 * u);
                    ctx.stroke();

                    // Eye whites.
                    ctx.fillStyle = mascot.eyeWhite;
                    ctx.beginPath();
                    ctx.arc(9.5 * u, 13.7 * u, 1.5 * u, 0, 2 * Math.PI);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(14.5 * u, 13.7 * u, 1.5 * u, 0, 2 * Math.PI);
                    ctx.fill();

                    // Pupils.
                    ctx.fillStyle = mascot.ink;
                    ctx.beginPath();
                    ctx.arc(9.5 * u, 13.7 * u, 0.85 * u, 0, 2 * Math.PI);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(14.5 * u, 13.7 * u, 0.85 * u, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: "Ask anything about this phase."
                color: dock.muted
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                visible: !dock.aiReady
                textFormat: Text.PlainText
                text: "retrieval mode — add a key for AI answers"
                color: dock.muted
                opacity: 0.85
                font.family: dock.fontFamily
                font.pixelSize: Style.font.caption
            }

            // Starter chips: pills that wrap and send on click.
            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, Style.space(300))
                spacing: Style.space(8)

                Repeater {
                    model: dock.starters

                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        radius: height / 2
                        height: chipLabel.implicitHeight + Style.space(11)
                        width: chipLabel.implicitWidth + Style.space(22)
                        color: chipHover.containsMouse
                            ? Util.alpha(dock.accent, 0.18)
                            : Util.alpha(dock.foreground, 0.06)
                        border.width: 1
                        border.color: chipHover.containsMouse
                            ? Util.alpha(dock.accent, 0.45)
                            : dock.divider

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: chip.modelData
                            color: chipHover.containsMouse ? dock.accent : dock.foreground
                            font.family: dock.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }
                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dock.send(chip.modelData)
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- messages
    ListView {
        id: list
        anchors.top: headerRule.bottom
        anchors.bottom: clearRow.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        anchors.topMargin: Style.space(12)
        visible: dock.messages.length > 0 && !dock.settingsOpen
        clip: true
        spacing: Style.space(6)
        model: dock.messages
        boundsBehavior: Flickable.StopAtBounds

        footer: Item {
            width: ListView.view ? ListView.view.width : 0
            height: dock.busy ? thinking.implicitHeight + Style.space(16) : 0
            visible: dock.busy
            Text {
                id: thinking
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Thinking…"
                color: dock.muted
                font.family: dock.fontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }

        delegate: Item {
            id: row
            width: ListView.view ? ListView.view.width : 0

            readonly property bool isUser: !!(modelData && modelData.role === "user")
            readonly property var srcs: (modelData && modelData.sources) ? modelData.sources : []
            readonly property string mtext: (modelData && modelData.text) ? String(modelData.text) : ""

            implicitHeight: turn.implicitHeight + Style.space(12)

            Column {
                id: turn
                width: row.width
                spacing: Style.space(5)

                // "You" / "Tutor" label.
                Text {
                    textFormat: Text.PlainText
                    text: row.isUser ? "You" : "Tutor"
                    color: row.isUser ? dock.muted : dock.accent
                    font.family: dock.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

                // The body: a plain tinted bubble for you, block-rendered
                // markdown for the tutor.
                Loader {
                    id: bodyLoader
                    width: turn.width
                    height: item ? item.implicitHeight : 0
                    property string turnText: row.mtext
                    sourceComponent: row.isUser ? userBubble : assistantBody
                }

                // "Referenced:" source chips under a tutor turn.
                Column {
                    width: turn.width
                    spacing: Style.space(6)
                    visible: !row.isUser && row.srcs.length > 0

                    Text {
                        textFormat: Text.PlainText
                        text: "Referenced:"
                        color: dock.muted
                        font.family: dock.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Flow {
                        width: parent.width
                        spacing: Style.space(6)
                        Repeater {
                            model: row.srcs
                            delegate: Rectangle {
                                id: srcChip
                                required property var modelData
                                radius: Style.space(6)
                                color: srcHover.containsMouse
                                    ? Util.alpha(dock.accent, 0.22)
                                    : Util.alpha(dock.accent, 0.12)
                                height: srcText.implicitHeight + Style.space(7)
                                width: Math.min(turn.width, srcText.implicitWidth + Style.space(16))
                                Text {
                                    id: srcText
                                    anchors.centerIn: parent
                                    width: parent.width - Style.space(12)
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: (srcChip.modelData.title || srcChip.modelData.slug || "source")
                                        + (Number(srcChip.modelData.phase) > 0
                                            ? "  ·  phase " + srcChip.modelData.phase : "")
                                    color: dock.accent
                                    font.family: dock.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    id: srcHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dock.sourceActivated(
                                        String(srcChip.modelData.slug || ""),
                                        Number(srcChip.modelData.phase) > 0
                                            ? Number(srcChip.modelData.phase) : 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- turn body types

    // Your own turn: a simple plain-text bubble hugged to its text (capped),
    // right-aligned. `turnText` comes from the loading Loader's context.
    Component {
        id: userBubble
        Item {
            id: ub
            implicitHeight: bubble.height
            readonly property int bpad: Style.space(10)

            TextMetrics {
                id: metrics
                text: turnText
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
            }

            Rectangle {
                id: bubble
                x: ub.width - width
                width: Math.min(ub.width * 0.85,
                    Math.max(Style.space(48), metrics.advanceWidth + ub.bpad * 2))
                height: ubText.implicitHeight + ub.bpad * 2
                radius: Style.space(9)
                color: dock.selectedBackground

                Text {
                    id: ubText
                    x: ub.bpad
                    y: ub.bpad
                    width: bubble.width - ub.bpad * 2
                    textFormat: Text.PlainText
                    text: turnText
                    color: dock.foreground
                    font.family: dock.fontFamily
                    font.pixelSize: Style.font.subtitle
                    wrapMode: Text.Wrap
                    lineHeight: 1.35
                    lineHeightMode: Text.ProportionalHeight
                }
            }
        }
    }

    // The tutor's turn: markdown parsed into typed blocks, each drawn as real
    // QML. `turnText` comes from the loading Loader's context.
    Component {
        id: assistantBody
        Item {
            id: ab
            implicitHeight: blockCol.implicitHeight

            Column {
                id: blockCol
                width: ab.width
                spacing: Style.space(2)

                Repeater {
                    model: Markdown.parseBlocks(turnText)

                    Loader {
                        id: blockLoader
                        required property var modelData
                        readonly property var blk: modelData
                        width: blockCol.width
                        height: item ? item.implicitHeight : 0
                        // Unknown / interactive types fall back to a paragraph.
                        sourceComponent: {
                            var t = (modelData && modelData.type) ? modelData.type : "";
                            return t === "heading" ? mdHeading
                                : t === "code" ? mdCode
                                : t === "bullet" ? mdBullet
                                : t === "quote" ? mdQuote
                                : t === "rule" ? mdRule
                                : t === "table" ? mdTable
                                : mdPara;
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------- block types
    //
    // Each reads `blk` from its Loader's context and the palette from `dock`.

    Component {
        id: mdPara
        Item {
            implicitHeight: para.implicitHeight + Style.space(8)
            Text {
                id: para
                width: parent.width
                textFormat: Text.RichText
                text: Markdown.inline((blk && blk.text) ? String(blk.text) : "",
                    { code: dock.accent, link: dock.accent })
                color: dock.foreground
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                lineHeightMode: Text.ProportionalHeight
                onLinkActivated: url => Qt.openUrlExternally(url)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: para.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }

    Component {
        id: mdHeading
        Item {
            implicitHeight: heading.implicitHeight + Style.space(10)
            Text {
                id: heading
                y: Style.space(4)
                width: parent.width
                textFormat: Text.RichText
                text: Markdown.inline((blk && blk.text) ? String(blk.text) : "",
                    { code: dock.accent, link: dock.accent })
                color: dock.foreground
                font.family: dock.fontFamily
                font.bold: true
                font.pixelSize: (blk && blk.level <= 2) ? Style.font.title : Style.font.subtitle
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: mdBullet
        Item {
            implicitHeight: Math.max(marker.implicitHeight, bulletText.implicitHeight) + Style.space(3)
            readonly property int indent: Style.space(2)
                + ((blk && blk.depth) ? blk.depth : 0) * Style.space(14)

            Text {
                id: marker
                x: parent.indent
                width: Style.space(16)
                textFormat: Text.PlainText
                text: (blk && blk.marker) ? String(blk.marker) : "•"
                color: dock.accent
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
                lineHeight: 1.4
                lineHeightMode: Text.ProportionalHeight
            }
            Text {
                id: bulletText
                x: parent.indent + Style.space(16)
                width: parent.width - x
                textFormat: Text.RichText
                text: Markdown.inline((blk && blk.text) ? String(blk.text) : "",
                    { code: dock.accent, link: dock.accent })
                color: dock.foreground
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                lineHeightMode: Text.ProportionalHeight
                onLinkActivated: url => Qt.openUrlExternally(url)
            }
        }
    }

    Component {
        id: mdQuote
        Item {
            implicitHeight: quoteText.implicitHeight + Style.space(10)
            Rectangle {
                x: 0
                y: Style.space(2)
                width: Math.max(1, Style.space(2))
                height: quoteText.implicitHeight
                color: dock.accent
                opacity: 0.7
            }
            Text {
                id: quoteText
                x: Style.space(12)
                y: Style.space(2)
                width: parent.width - x
                textFormat: Text.RichText
                text: Markdown.inline((blk && blk.text) ? String(blk.text) : "",
                    { code: dock.accent, link: dock.accent })
                color: dock.muted
                font.family: dock.fontFamily
                font.italic: true
                font.pixelSize: Style.font.subtitle
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                lineHeightMode: Text.ProportionalHeight
            }
        }
    }

    Component {
        id: mdRule
        Item {
            implicitHeight: Style.space(18)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: dock.divider
            }
        }
    }

    // A real code card: bordered, hover-lit, click-to-copy with confirmation.
    Component {
        id: mdCode
        Item {
            id: codeRoot
            implicitHeight: card.height + Style.space(10)
            readonly property string ctext: (blk && blk.text) ? String(blk.text) : ""
            readonly property string clang: (blk && blk.lang) ? String(blk.lang) : ""
            readonly property bool copied: dock.copiedText !== "" && dock.copiedText === ctext
            readonly property int labelHeight: clang.length > 0 ? langLabel.implicitHeight : 0

            Rectangle {
                id: card
                width: parent.width
                y: Style.space(3)
                height: codeText.implicitHeight + Style.space(18) + codeRoot.labelHeight
                radius: Style.space(8)
                color: Util.alpha(dock.foreground, 0.05)
                border.width: 1
                border.color: Util.alpha(dock.foreground, codeHover.containsMouse ? 0.22 : 0.12)

                Text {
                    id: langLabel
                    visible: codeRoot.clang.length > 0 || codeHover.containsMouse || codeRoot.copied
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(6)
                    anchors.rightMargin: Style.space(10)
                    textFormat: Text.PlainText
                    text: codeRoot.copied ? "copied"
                        : codeHover.containsMouse
                            ? (codeRoot.clang ? codeRoot.clang + "  ·  click to copy" : "click to copy")
                        : codeRoot.clang
                    color: codeRoot.copied ? dock.accent : dock.muted
                    font.family: dock.fontFamily
                    font.pixelSize: Style.font.caption
                }

                // Long lines wrap rather than scroll; click-to-copy always
                // yields the original text.
                Text {
                    id: codeText
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(9) + codeRoot.labelHeight
                    anchors.leftMargin: Style.space(11)
                    anchors.rightMargin: Style.space(11)
                    textFormat: Text.RichText
                    text: Markdown.highlightCode(codeRoot.ctext, codeRoot.clang, dock.codeDark)
                    color: dock.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    lineHeight: 1.4
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                MouseArea {
                    id: codeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dock.copyCode(codeRoot.ctext)
                }
            }
        }
    }

    Component {
        id: mdTable
        Item {
            id: tableRoot
            implicitHeight: grid.height + Style.space(10)
            readonly property var hdr: (blk && blk.header) ? blk.header : []
            readonly property var rws: (blk && blk.rows) ? blk.rows : []
            readonly property int columnCount: Math.max(1, hdr.length)
            readonly property real cellWidth: width / columnCount

            Column {
                id: grid
                width: parent.width
                spacing: 0

                Row {
                    width: parent.width
                    Repeater {
                        model: tableRoot.hdr
                        Text {
                            required property var modelData
                            width: tableRoot.cellWidth
                            padding: Style.space(5)
                            textFormat: Text.RichText
                            text: Markdown.inline(modelData, { code: dock.accent, link: dock.accent })
                            color: dock.accent
                            font.family: dock.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Util.alpha(dock.foreground, 0.2)
                }

                Repeater {
                    model: tableRoot.rws
                    Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        width: grid.width
                        height: cells.height

                        Rectangle {
                            anchors.fill: parent
                            color: rowItem.index % 2 === 1
                                ? Util.alpha(dock.foreground, 0.04) : "transparent"
                        }

                        Row {
                            id: cells
                            width: parent.width
                            Repeater {
                                model: rowItem.modelData
                                Text {
                                    required property var modelData
                                    width: tableRoot.cellWidth
                                    padding: Style.space(5)
                                    textFormat: Text.RichText
                                    text: Markdown.inline(modelData, { code: dock.accent, link: dock.accent })
                                    color: dock.foreground
                                    font.family: dock.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------- clear history
    Item {
        id: clearRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: errorLine.top
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        visible: dock.messages.length > 0 && !dock.settingsOpen
        height: visible ? clearBtn.implicitHeight + Style.space(12) : 0

        Text {
            id: clearBtn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Clear history"
            color: clearHover.containsMouse ? dock.accent : dock.muted
            font.family: dock.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
                id: clearHover
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dock.clearRequested()
            }
        }
    }

    // --------------------------------------------------------------- error
    Text {
        id: errorLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputWrap.top
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        visible: dock.errorText.length > 0 && !dock.settingsOpen
        height: visible ? implicitHeight + Style.space(8) : 0
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: dock.errorText
        color: dock.urgent
        font.family: dock.fontFamily
        font.pixelSize: Style.font.bodySmall
    }

    // --------------------------------------------------------------- input
    Item {
        id: inputWrap
        visible: !dock.settingsOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        height: field.height + Style.space(16)

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: -dock.hpad
            anchors.rightMargin: -dock.hpad
            height: 1
            color: dock.divider
        }

        readonly property real oneLine: Math.ceil(Style.font.subtitle * 1.5)
        readonly property int fpad: Style.space(9)

        Rectangle {
            id: field
            anchors.left: parent.left
            anchors.right: sendArea.left
            anchors.rightMargin: Style.space(8)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            radius: Style.space(9)
            color: Util.alpha(dock.foreground, 0.05)
            border.width: 1
            border.color: input.activeFocus ? Util.alpha(dock.accent, 0.6) : dock.divider
            // Grows with content between one and four lines.
            height: Math.min(Math.max(input.implicitHeight, inputWrap.oneLine), inputWrap.oneLine * 4)
                + inputWrap.fpad * 2

            TextEdit {
                id: input
                anchors.fill: parent
                anchors.margins: inputWrap.fpad
                clip: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: dock.foreground
                selectByMouse: true
                selectionColor: Util.alpha(dock.accent, 0.35)
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
                Keys.onPressed: e => dock._inputKey(e)

                Text {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    verticalAlignment: Text.AlignTop
                    textFormat: Text.PlainText
                    text: "Ask a question…"
                    color: dock.muted
                    font: input.font
                    elide: Text.ElideRight
                }
            }
        }

        // Send button: a paper-plane rather than the word "Send".
        Rectangle {
            id: sendArea
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            width: Style.space(40)
            height: Style.space(32)
            radius: Style.space(9)
            readonly property bool canSend: input.text.replace(/^\s+|\s+$/g, "").length > 0 && !dock.busy
            color: canSend ? Util.alpha(dock.accent, 0.18) : Util.alpha(dock.foreground, 0.05)

            Canvas {
                id: planeIcon
                anchors.centerIn: parent
                width: Style.space(18)
                height: Style.space(18)
                readonly property color ink: sendArea.canSend ? dock.accent : dock.muted
                readonly property real u: Math.min(width, height) / 24

                onInkChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var u = planeIcon.u;
                    ctx.fillStyle = planeIcon.ink;
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.moveTo(3 * u, 4 * u);
                    ctx.lineTo(21 * u, 12 * u);
                    ctx.lineTo(3 * u, 20 * u);
                    ctx.lineTo(7 * u, 12 * u);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: sendArea.canSend
                cursorShape: Qt.PointingHandCursor
                onClicked: dock._submit()
            }
        }
    }

    // -------------------------------------------------------- settings form
    //
    // Covers the conversation (from under the header to the bottom) when the
    // gear is pressed. Opaque and on top; the body pieces above hide themselves
    // while it is open. Save hands a fresh config object up; the view writes it.
    SettingsForm {
        id: settingsForm
        z: 5
        visible: dock.settingsOpen
        anchors.top: headerRule.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        config: dock.aiConfig
        defaultSystemPrompt: dock.defaultSystemPrompt

        background: dock.background
        foreground: dock.foreground
        accent: dock.accent
        muted: dock.muted
        selectedBackground: dock.selectedBackground
        divider: dock.divider
        urgent: dock.urgent
        fontFamily: dock.fontFamily

        onSave: cfg => { dock.saveSettings(cfg); dock.settingsOpen = false; }
        onCancel: dock.settingsOpen = false
    }
}
