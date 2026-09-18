import QtQuick
import qs.Commons

// The AI settings form. A self-contained, theme-driven editor for
// ~/.config/tmm/ai.json, so a provider can be set up without hand-editing the
// file. The dock shows it in place of the conversation when the gear is
// pressed; it reads the current config in, and emits `save` with a fresh
// config object (only the fields that matter for the chosen provider).
//
// It owns no persistence: it hands a plain object up and the service writes it.
Item {
    id: form

    // --- injected ---
    // The live config object (Service.aiConfig). Snapshotted into the fields
    // when the form appears; never bound directly, so typing is never clobbered.
    property var config: ({})
    property string defaultSystemPrompt: ""

    // --- injected palette ---
    property color background: Color.background
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color muted: Util.alpha(foreground, 0.6)
    property color selectedBackground: Util.alpha(foreground, 0.08)
    property color divider: Util.alpha(foreground, 0.14)
    property color urgent: Color.urgent
    property string fontFamily: Style.font.menuFamily

    // --- outputs ---
    signal save(var cfg)
    signal cancel()

    // Keyboard: Esc cancels, Ctrl+S / Ctrl+Enter saves. Text fields ignore
    // these, so they bubble up here even while one has focus.
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape) { form.cancel(); e.accepted = true; return; }
        if ((e.modifiers & Qt.ControlModifier)
                && (e.key === Qt.Key_S || e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
            form.save(form.collect());
            e.accepted = true;
        }
    }

    // The dock calls this when the form opens: put the cursor in the first
    // field so it can be driven from the keyboard right away.
    function focusForm() {
        if (hasProvider) modelField.focusField();
        else form.forceActiveFocus();
    }

    // Chip selections live as state; text fields keep their value in the field
    // itself (read back at save time) so there is never a binding loop.
    property string pProvider: ""
    property string pEffort: ""

    readonly property var providers: [
        { v: "", l: "None" },
        { v: "claude-cli", l: "Claude Code" },
        { v: "codex", l: "Codex" },
        { v: "cursor", l: "Cursor" },
        { v: "opencode", l: "OpenCode" },
        { v: "openai", l: "OpenAI-compatible API" },
        { v: "anthropic", l: "Anthropic API" }
    ]
    readonly property var efforts: [
        { v: "", l: "Default" },
        { v: "minimal", l: "Minimal" },
        { v: "low", l: "Low" },
        { v: "medium", l: "Medium" },
        { v: "high", l: "High" }
    ]

    readonly property bool isCli: pProvider === "claude-cli" || pProvider === "codex"
        || pProvider === "cursor" || pProvider === "opencode"
    readonly property bool isApi: pProvider === "openai" || pProvider === "anthropic"
    readonly property bool isOpenai: pProvider === "openai"
    readonly property bool hasProvider: pProvider !== ""

    function _providerLabel(v) {
        for (var i = 0; i < providers.length; i++)
            if (providers[i].v === String(v || "")) return providers[i].l;
        return String(v);
    }
    function _binDefault(p) {
        return p === "codex" ? "codex" : p === "cursor" ? "cursor-agent"
            : p === "opencode" ? "opencode" : "claude";
    }
    function _modelHint(p) {
        return p === "codex" ? "e.g. gpt-5-codex — blank uses the CLI default"
            : p === "cursor" ? "e.g. sonnet-4.5 — blank uses the CLI default"
            : p === "opencode" ? "e.g. anthropic/claude-sonnet-5 — blank uses the default"
            : p === "claude-cli" ? "e.g. claude-sonnet-5 — blank uses the CLI default"
            : p === "anthropic" ? "e.g. claude-sonnet-5"
            : "e.g. gpt-5";
    }

    // Snapshot the live config into the editable fields. Only when the form
    // becomes visible, so an external reload never overwrites a half-typed edit.
    function load() {
        var c = form.config || ({});
        pProvider = String(c.provider || "");
        pEffort = String(c.effort || "");
        modelField.value = String(c.model || "");
        apiKeyField.value = String(c.apiKey || "");
        baseUrlField.value = String(c.baseUrl || "");
        binField.value = String(c.bin || "");
        maxTokensField.value = (Number(c.maxTokens) > 0) ? String(Number(c.maxTokens)) : "";
        systemField.value = String(c.systemPrompt || "");
    }
    onVisibleChanged: if (visible) load()
    Component.onCompleted: load()

    // Assemble the config object: only the keys the chosen provider uses, and
    // only when they carry a value, so the file stays as small as what was set.
    function collect() {
        var o = ({});
        if (!pProvider) return o;                 // None -> {} (retrieval mode)
        o.provider = pProvider;
        var model = modelField.value.replace(/^\s+|\s+$/g, "");
        if (model) o.model = model;
        if (pEffort) o.effort = pEffort;
        if (isCli) {
            var bin = binField.value.replace(/^\s+|\s+$/g, "");
            if (bin) o.bin = bin;
        }
        if (isApi) {
            var key = apiKeyField.value.replace(/^\s+|\s+$/g, "");
            if (key) o.apiKey = key;
            var base = baseUrlField.value.replace(/^\s+|\s+$/g, "");
            if (base) o.baseUrl = base;
            var mt = Number(maxTokensField.value.replace(/^\s+|\s+$/g, ""));
            if (mt > 0) o.maxTokens = mt;
        }
        var sys = systemField.value.replace(/^\s+$/g, "");
        if (sys.replace(/^\s+|\s+$/g, "")) o.systemPrompt = sys;
        return o;
    }

    // ------------------------------------------------------- reusable field
    //
    // A labelled, theme-driven text box. `value` reads/writes the text; the
    // palette is passed in so the field matches the dock's (possibly pinned)
    // reading theme rather than the desktop one.
    component TextRow: Column {
        id: tr
        property string label: ""
        property string placeholder: ""
        property bool multiline: false
        property color fg: form.foreground
        property color mut: form.muted
        property color acc: form.accent
        property color div: form.divider
        property string fnt: form.fontFamily
        property alias value: te.text
        function focusField() { te.forceActiveFocus(); }

        width: parent ? parent.width : 0
        spacing: Style.space(5)

        Text {
            text: tr.label
            color: tr.mut
            font.family: tr.fnt
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
        }

        Rectangle {
            width: parent.width
            height: tr.multiline ? Style.space(132)
                : Math.max(te.implicitHeight + Style.space(16), Style.space(38))
            radius: Style.space(9)
            color: Util.alpha(tr.fg, 0.05)
            border.width: 1
            border.color: te.activeFocus ? Util.alpha(tr.acc, 0.6) : tr.div

            TextEdit {
                id: te
                anchors.fill: parent
                anchors.margins: Style.space(9)
                clip: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: tr.fg
                selectByMouse: true
                selectionColor: Util.alpha(tr.acc, 0.35)
                font.family: tr.fnt
                font.pixelSize: Style.font.subtitle

                Text {
                    anchors.fill: parent
                    visible: te.text.length === 0
                    verticalAlignment: Text.AlignTop
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: tr.placeholder
                    color: tr.mut
                    font: te.font
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Opaque base: the form sits over the conversation, so it must cover it.
    Rectangle { anchors.fill: parent; color: form.background }

    readonly property int hpad: Style.space(14)

    // ---------------------------------------------------------- scroll body
    Flickable {
        id: scroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: buttonBar.top
        anchors.leftMargin: form.hpad
        anchors.rightMargin: form.hpad
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + Style.space(16)
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: scroll.width
            y: Style.space(4)
            spacing: Style.space(14)

            Text {
                text: "AI settings"
                color: form.foreground
                font.family: form.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: "Choose how the tutor answers. Saved to ~/.config/tmm/ai.json — "
                    + "no key is sent anywhere but your own provider."
                color: form.muted
                font.family: form.fontFamily
                font.pixelSize: Style.font.bodySmall
            }

            // ---- provider ----
            Text {
                text: "Provider"
                color: form.muted
                font.family: form.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
            }
            Flow {
                width: parent.width
                spacing: Style.space(7)
                Repeater {
                    model: form.providers
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: form.pProvider === modelData.v
                        radius: Style.space(8)
                        height: chipLabel.implicitHeight + Style.space(11)
                        width: chipLabel.implicitWidth + Style.space(20)
                        color: sel ? Util.alpha(form.accent, 0.18)
                            : chipHover.containsMouse ? Util.alpha(form.foreground, 0.08)
                            : Util.alpha(form.foreground, 0.04)
                        border.width: 1
                        border.color: sel ? Util.alpha(form.accent, 0.6) : form.divider
                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData.l
                            color: parent.sel ? form.accent : form.foreground
                            font.family: form.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            textFormat: Text.PlainText
                        }
                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: form.pProvider = modelData.v
                        }
                    }
                }
            }

            // ---- retrieval-mode note (None) ----
            Text {
                visible: !form.hasProvider
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: "No provider set. The tutor still answers in retrieval mode — "
                    + "it pulls the most relevant manual sections and links their sources. "
                    + "Pick a provider above for written, conversational answers."
                color: form.muted
                font.family: form.fontFamily
                font.pixelSize: Style.font.bodySmall
            }

            // ---- subscription CLI hint ----
            Text {
                visible: form.isCli
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: "Runs answers on your local " + form._providerLabel(form.pProvider)
                    + " CLI — your subscription, no API key. The tutor runs it read-only "
                    + "in a scratch folder, so it can only ever produce text."
                color: form.muted
                font.family: form.fontFamily
                font.pixelSize: Style.font.bodySmall
            }

            // ---- model ----
            TextRow {
                id: modelField
                visible: form.hasProvider
                label: "Model"
                placeholder: form._modelHint(form.pProvider)
            }

            // ---- effort ----
            Column {
                visible: form.hasProvider
                width: parent.width
                spacing: Style.space(5)
                Text {
                    text: "Effort"
                    color: form.muted
                    font.family: form.fontFamily
                    font.pixelSize: Style.font.caption
                    textFormat: Text.PlainText
                }
                Flow {
                    width: parent.width
                    spacing: Style.space(7)
                    Repeater {
                        model: form.efforts
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: form.pEffort === modelData.v
                            radius: Style.space(8)
                            height: eLabel.implicitHeight + Style.space(11)
                            width: eLabel.implicitWidth + Style.space(20)
                            color: sel ? Util.alpha(form.accent, 0.18)
                                : eHover.containsMouse ? Util.alpha(form.foreground, 0.08)
                                : Util.alpha(form.foreground, 0.04)
                            border.width: 1
                            border.color: sel ? Util.alpha(form.accent, 0.6) : form.divider
                            Text {
                                id: eLabel
                                anchors.centerIn: parent
                                text: modelData.l
                                color: parent.sel ? form.accent : form.foreground
                                font.family: form.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                textFormat: Text.PlainText
                            }
                            MouseArea {
                                id: eHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: form.pEffort = modelData.v
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: "Lower effort studies cheaper and faster; Default lets the model decide."
                    color: form.muted
                    font.family: form.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }

            // ---- CLI: command override ----
            TextRow {
                id: binField
                visible: form.isCli
                label: "Command (optional)"
                placeholder: form._binDefault(form.pProvider) + " — the binary, or a full path to it"
            }

            // ---- API: base URL ----
            TextRow {
                id: baseUrlField
                visible: form.isApi
                label: form.isOpenai ? "Base URL" : "Base URL (optional)"
                placeholder: form.isOpenai
                    ? "https://api.openai.com/v1 — or any OpenAI-compatible endpoint"
                    : "https://api.anthropic.com — blank uses the default"
            }

            // ---- API: key ----
            TextRow {
                id: apiKeyField
                visible: form.isApi
                label: "API key"
                placeholder: "stored locally in ai.json — or leave blank to use $TMM_AI_KEY"
            }

            // ---- API: max tokens ----
            TextRow {
                id: maxTokensField
                visible: form.isApi
                label: "Max tokens (optional)"
                placeholder: "1024"
            }

            // ---- system prompt ----
            Column {
                visible: form.hasProvider
                width: parent.width
                spacing: Style.space(5)
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - resetBtn.implicitWidth
                        text: "System prompt (optional)"
                        color: form.muted
                        font.family: form.fontFamily
                        font.pixelSize: Style.font.caption
                        textFormat: Text.PlainText
                    }
                    Text {
                        id: resetBtn
                        text: "Reset"
                        color: resetHover.containsMouse ? form.accent : form.muted
                        font.family: form.fontFamily
                        font.pixelSize: Style.font.caption
                        textFormat: Text.PlainText
                        MouseArea {
                            id: resetHover
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: systemField.value = ""
                        }
                    }
                }
                TextRow {
                    id: systemField
                    width: parent.width
                    multiline: true
                    placeholder: "Blank uses the built-in Tutor prompt."
                }
            }
        }
    }

    // ---------------------------------------------------------- button bar
    Item {
        id: buttonBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: form.hpad
        anchors.rightMargin: form.hpad
        height: saveBtn.height + Style.space(16)

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: -form.hpad
            anchors.rightMargin: -form.hpad
            height: 1
            color: form.divider
        }

        // Live indicator of what is actually active right now.
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: saveBtn.verticalCenter
            width: parent.width - saveBtn.width - cancelBtn.width - Style.space(20)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "Active: " + (form.config && form.config.provider
                ? form._providerLabel(form.config.provider) : "Retrieval mode")
            color: form.muted
            font.family: form.fontFamily
            font.pixelSize: Style.font.caption
        }

        Rectangle {
            id: cancelBtn
            anchors.right: saveBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            radius: Style.space(9)
            width: cancelLabel.implicitWidth + Style.space(24)
            height: cancelLabel.implicitHeight + Style.space(16)
            color: cancelHover.containsMouse ? Util.alpha(form.foreground, 0.08) : "transparent"
            border.width: 1
            border.color: form.divider
            Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: form.foreground
                font.family: form.fontFamily
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
            }
            MouseArea {
                id: cancelHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: form.cancel()
            }
        }

        Rectangle {
            id: saveBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            radius: Style.space(9)
            width: saveLabel.implicitWidth + Style.space(28)
            height: saveLabel.implicitHeight + Style.space(16)
            color: saveHover.containsMouse ? Util.alpha(form.accent, 0.28) : Util.alpha(form.accent, 0.18)
            border.width: 1
            border.color: Util.alpha(form.accent, 0.6)
            Text {
                id: saveLabel
                anchors.centerIn: parent
                text: "Save"
                color: form.accent
                font.family: form.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                textFormat: Text.PlainText
            }
            MouseArea {
                id: saveHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: form.save(form.collect())
            }
        }
    }
}
