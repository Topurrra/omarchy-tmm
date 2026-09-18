import QtQuick
import qs.Commons
import "../Markdown.js" as Markdown

// The study-chat dock. A self-contained, theme-driven view that pins to the
// right of the reader (or covers the content area when compact). It owns its
// own input focus and keys once open; everything else is injected by the view.
//
//   header  — title + a hint about which mode (AI vs retrieval)
//   list    — the conversation, user turns right, assistant turns left
//   input   — a growing field; Enter sends, Shift+Enter is a newline, Esc closes
Item {
    id: dock

    // --- injected state ---
    property var messages: []
    property bool busy: false
    property string errorText: ""
    property bool aiReady: false

    // --- injected palette ---
    property color background: Color.background
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color muted: Util.alpha(foreground, 0.6)
    property color selectedBackground: Util.alpha(foreground, 0.08)
    property color divider: Util.alpha(foreground, 0.14)
    property color urgent: Color.urgent
    property string fontFamily: Style.font.menuFamily

    // A left seam against the reader in wide mode; the view turns it off when
    // the dock covers the whole content area (compact).
    property bool showDivider: true

    // --- outputs ---
    signal send(string text)
    signal sourceActivated(string slug, int phase)
    signal closeRequested()
    signal clearRequested()

    // The view grabs the input when the dock opens.
    function focusInput() { input.forceActiveFocus(); }
    function scrollToBottom() { Qt.callLater(function () { list.positionViewAtEnd(); }); }

    onMessagesChanged: scrollToBottom()
    onBusyChanged: scrollToBottom()
    onVisibleChanged: if (visible) Qt.callLater(focusInput)

    // Split an assistant message into paragraphs so each renders as its own
    // rich-text block (blank lines separate them). Inline markdown only.
    function _paras(t) {
        var s = String(t || "").replace(/^\s+|\s+$/g, "");
        if (!s) return [""];
        return s.split(/\n{2,}/);
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
            text: dock.aiReady ? "Study chat" : "Ask the guides"
            color: dock.foreground
            font.family: dock.fontFamily
            font.pixelSize: Style.font.title
        }

        Text {
            id: clearAction
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: dock.messages.length > 0
            textFormat: Text.PlainText
            text: "clear"
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

        Text {
            anchors.right: clearAction.visible ? clearAction.left : parent.right
            anchors.rightMargin: clearAction.visible ? Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: titleText.right
            anchors.leftMargin: Style.space(10)
            visible: !dock.aiReady
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: "retrieval mode — add a key for AI answers"
            color: dock.muted
            opacity: 0.85
            font.family: dock.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
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

    // ------------------------------------------------------------- messages
    ListView {
        id: list
        anchors.top: headerRule.bottom
        anchors.bottom: errorLine.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: dock.hpad
        anchors.rightMargin: dock.hpad
        anchors.topMargin: Style.space(12)
        clip: true
        spacing: Style.space(4)
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
                text: "thinking…"
                color: dock.muted
                font.family: dock.fontFamily
                font.pixelSize: Style.font.bodySmall
            }
        }

        delegate: Item {
            id: row
            width: ListView.view ? ListView.view.width : 0
            implicitHeight: bubble.height + Style.space(10)

            readonly property bool isUser: !!(modelData && modelData.role === "user")
            readonly property var srcs: (modelData && modelData.sources) ? modelData.sources : []
            readonly property int bpad: Style.space(10)

            // Measures the user turn to hug the bubble to its text (capped).
            TextMetrics {
                id: metrics
                text: (modelData && modelData.text) ? String(modelData.text) : ""
                font.family: dock.fontFamily
                font.pixelSize: Style.font.subtitle
            }

            Rectangle {
                id: bubble
                y: Style.space(2)
                width: row.isUser
                    ? Math.min(row.width * 0.85,
                        Math.max(Style.space(48), metrics.advanceWidth + row.bpad * 2))
                    : row.width
                x: row.isUser ? row.width - width : 0
                height: content.implicitHeight + row.bpad * 2
                radius: Style.space(9)
                color: row.isUser ? dock.selectedBackground : "transparent"

                Column {
                    id: content
                    x: row.bpad
                    y: row.bpad
                    width: bubble.width - row.bpad * 2
                    spacing: Style.space(6)

                    Repeater {
                        model: row.isUser
                            ? [ (modelData && modelData.text) ? String(modelData.text) : "" ]
                            : dock._paras((modelData && modelData.text) ? String(modelData.text) : "")
                        delegate: Text {
                            width: content.width
                            wrapMode: Text.Wrap
                            textFormat: row.isUser ? Text.PlainText : Text.RichText
                            text: row.isUser
                                ? modelData
                                : Markdown.inline(modelData, { code: dock.accent, link: dock.accent })
                            color: dock.foreground
                            font.family: dock.fontFamily
                            font.pixelSize: Style.font.subtitle
                            lineHeight: 1.35
                            lineHeightMode: Text.ProportionalHeight
                            onLinkActivated: url => Qt.openUrlExternally(url)
                        }
                    }

                    // Source chips under a retrieval reply.
                    Flow {
                        width: content.width
                        spacing: Style.space(6)
                        visible: row.srcs.length > 0
                        Repeater {
                            model: row.srcs
                            delegate: Rectangle {
                                radius: Style.space(6)
                                color: chipHover.containsMouse
                                    ? Util.alpha(dock.accent, 0.22)
                                    : Util.alpha(dock.accent, 0.12)
                                height: chipText.implicitHeight + Style.space(7)
                                width: Math.min(content.width, chipText.implicitWidth + Style.space(16))
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    width: parent.width - Style.space(12)
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: (modelData.title || modelData.slug || "source")
                                        + (Number(modelData.phase) > 0 ? "  ·  phase " + modelData.phase : "")
                                    color: dock.accent
                                    font.family: dock.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    id: chipHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dock.sourceActivated(
                                        String(modelData.slug || ""),
                                        Number(modelData.phase) > 0 ? Number(modelData.phase) : 1)
                                }
                            }
                        }
                    }
                }
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
        visible: dock.errorText.length > 0
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
                    text: "Ask about what you're reading…"
                    color: dock.muted
                    font: input.font
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            id: sendArea
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            width: sendLabel.implicitWidth + Style.space(22)
            height: Style.space(32)
            radius: Style.space(9)
            readonly property bool canSend: input.text.replace(/^\s+|\s+$/g, "").length > 0 && !dock.busy
            color: canSend ? Util.alpha(dock.accent, 0.18) : Util.alpha(dock.foreground, 0.05)

            Text {
                id: sendLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Send"
                color: sendArea.canSend ? dock.accent : dock.muted
                font.family: dock.fontFamily
                font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
                anchors.fill: parent
                enabled: sendArea.canSend
                cursorShape: Qt.PointingHandCursor
                onClicked: dock._submit()
            }
        }
    }
}
