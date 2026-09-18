import Quickshell
import QtQuick
import qs.Commons
import "Markdown.js" as Markdown
import "components"

// The Missing Manual — a single responsive floating window that searches,
// browses and reads the manual without leaving the desktop.
//
// The window is the whole user surface: the host injects shell/manifest/
// service here and drives it with open/close/toggle. All the state and the
// service orchestration live in the Controller; this file is the view — the
// window palette, the chrome strings, the two layouts (compact and wide), and
// the keyboard, all wired to that one controller.
Item {
    id: root

    // Injected by the Omarchy host when available.
    property var shell
    property var manifest
    property var service
    property var omarchyPath
    property var pluginRegistry
    property var barWidgetRegistry

    // ------------------------------------------------------------- palette
    //
    // The window's own base palette, from the base theme tokens (NOT the
    // [menu] surface the old overlay borrowed). Everything drawn here — and
    // every colour handed to the reader, the lists and the components — comes
    // from these, so the window restyles with the desktop.
    // The window can follow the desktop theme (auto) or be pinned to a light
    // or dark reading palette regardless of it — ^t cycles the three. The
    // controller themes diagrams off these same colours (surface*), so a
    // switch re-bakes the diagrams to match without any extra wiring.
    property string themeMode: "auto"   // auto | light | dark

    readonly property color background: themeMode === "light" ? "#f5f4ef"
        : themeMode === "dark" ? "#14171a" : Color.background
    readonly property color foreground: themeMode === "light" ? "#1c1e21"
        : themeMode === "dark" ? "#e7e8e9" : Color.foreground
    // The desktop accent is tuned for the desktop background; a pinned light
    // page needs an accent that reads on white, so light mode brings its own.
    readonly property color accent: themeMode === "light" ? "#1f6feb" : Color.accent
    readonly property color urgent: themeMode === "light" ? "#c0392b"
        : themeMode === "dark" ? "#e06c6c" : Color.urgent
    readonly property color muted: Util.alpha(foreground, 0.6)
    readonly property color selectedBackground: Util.alpha(foreground, 0.08)
    readonly property color selectedText: accent
    readonly property color divider: Util.alpha(foreground, 0.14)
    readonly property string fontFamily: Style.font.menuFamily

    // Which code-highlight palette the reader should use. Pinned modes are
    // obvious; in auto we read the luminance of the actual desktop background.
    readonly property bool isDark: themeMode === "light" ? false
        : themeMode === "dark" ? true
        : (0.299 * background.r + 0.587 * background.g + 0.114 * background.b) < 0.5

    readonly property int pad: Style.spacing.panelPadding
    readonly property int gap: Style.spacing.md
    // The gutter between the two wide-mode columns (and their divider).
    readonly property int colGap: Style.space(16)

    // One breakpoint is enough for v1: below it, the classic single-column
    // overlay body; at or above it, list on the left, reader on the right.
    readonly property bool wide: win.width >= 900
    readonly property bool readingMode: app.mode === "reader" || app.mode === "ask"

    // The left list can be tucked away while reading in wide mode (press s) for
    // a full-width reading column; browsing always shows it. In compact mode
    // there is only ever one column, so the toggle does nothing there.
    property bool sidebarHidden: false
    readonly property bool showLeft: root.wide
        && (!root.readingMode || !root.sidebarHidden)
    // True whenever the left column occupies space: the single column when
    // compact, the left pane when wide-and-shown.
    readonly property bool leftColumnVisible: !root.wide || root.showLeft

    // Width of the left column in wide mode: two-fifths of the body, but never
    // so narrow the results stop being readable.
    readonly property real leftWidth: Math.max(Style.space(320),
        (win.width - root.pad * 2) * 0.4)

    // In wide mode the left column keeps showing the list you came from while
    // you read on the right, so its contents follow the *browsing* context,
    // not the literal mode: reading a catalog guide still shows the catalog.
    readonly property bool leftIsCatalog: app.mode === "catalog"
        || (root.readingMode && app.returnMode === "catalog")

    // Wide mode only: when the left column already has a list to pick from and
    // nothing is open on the right, the right column invites you to choose
    // rather than reusing the single-view empty text (which would read as "no
    // matches" even though the matches are sitting right there on the left).
    readonly property bool leftHasItems: resultList.visible || catalogList.visible
    readonly property bool rightPickPrompt: root.showLeft && leftHasItems
        && (app.mode === "search" || app.mode === "catalog")

    // ^t cycles the reading palette; the diagrams re-theme themselves off it.
    function cycleTheme() {
        root.themeMode = root.themeMode === "auto" ? "light"
            : root.themeMode === "light" ? "dark" : "auto";
    }

    // ------------------------------------------------------ host lifecycle

    function open(payloadJson) {
        win.visible = true;
        app.open(payloadJson);
    }

    function close() { win.visible = false; }

    function toggle() {
        if (win.visible) root.close();
        else root.open("{}");
    }

    readonly property bool opened: win.visible

    // ------------------------------------------------------ the controller

    Controller {
        id: app
        service: root.service
        // Diagrams are flattened against the window background, so the surface
        // colours the controller themes them with are this window's.
        surfaceBackground: root.background
        surfaceForeground: root.foreground
        surfaceMuted: root.muted
        surfaceDivider: root.divider
    }

    // The view owns the pieces the controller can no longer touch: focus, the
    // reader's quiz reset, and each list's cursor.
    Connections {
        target: app

        function onFocusRequested() {
            Qt.callLater(function () { keyCatcher.forceActiveFocus(); });
        }
        function onPhaseReady() {
            reader.quizActive = false;
            reader.quizAnswers = [];
            reader.quizCursor = 0;
        }
        function onResultsReplaced() {
            resultList.cursorIndex = 0;
            resultList.cursorActive = app.resultsModel.count > 0;
        }
        function onCatalogReplaced() {
            catalogList.cursorIndex = 0;
            catalogList.cursorActive = app.catalogModel.count > 0;
        }
    }

    // -------------------------------------------------------- chrome strings
    //
    // Presentation derived from controller state. Lifted from the old overlay;
    // the only change is that the state now lives on `app`.

    readonly property bool welcomeState: {
        var s = app.svc();
        return app.mode === "search" && !app.errorMsg && !app.query
            && !(app.searchPending || (s && s.searching));
    }

    readonly property string headline: {
        if (app.mode === "ask") return app.askQuery;
        if (app.mode === "reader") return app.guideTitle || app.currentSlug;
        if (app.mode === "catalog") {
            if (app.catalogFilter) return app.catalogFilter;
            return app.catalogCategory ? app.catalogCategory : "Browse by category…";
        }
        if (app.query) return app.query;
        return app.showingRecents ? "Pick up where you left off…" : "Search the manual…";
    }

    readonly property bool headlineIsPlaceholder:
        (app.mode === "search" && !app.query)
        || (app.mode === "catalog" && !app.catalogFilter && !app.catalogCategory)

    readonly property string headerStatus: {
        var s = app.svc();
        if (app.mode === "ask") {
            if (s && s.asking) return "thinking…";
            if (app.askNotice) return "";
            var n = app.askSources.length;
            return (app.askCached ? "cached" : "answer")
                + (n ? "  ·  " + n + (n === 1 ? " source" : " sources") : "");
        }
        if (app.mode === "reader") {
            if (s && s.loadingPhase) return "loading…";
            var mins = app.phaseBody ? Markdown.readingMinutes(app.phaseBody) : 0;
            return "phase " + app.currentPhase + (app.phaseCount > 0 ? " of " + app.phaseCount : "")
                + (mins ? "  ·  " + mins + " min" : "")
                + (app.phaseFromCache ? "  ·  offline" : "");
        }
        if (app.mode === "catalog") {
            if (s && s.loadingCatalog && app.catalogModel.count === 0) return "loading…";
            var c = app.catalogModel.count;
            if (!app.catalogCategory) return c + (c === 1 ? " category" : " categories");
            return c + (c === 1 ? " guide" : " guides");
        }
        if (app.searchPending || (s && s.searching)) return "searching…";
        if (app.showingRecents) return "recent";
        if (!app.query) return "";
        return app.resultsModel.count + (app.resultsModel.count === 1 ? " result" : " results");
    }

    readonly property string keyHints: {
        if (app.mode === "ask")
            return (app.askSources.length ? "1-9 open a source  ·  " : "")
                + "↑↓ scroll  ·  o browser"
                + (root.wide ? "  ·  s sidebar" : "")
                + "  ·  ^t theme  ·  ⎋ back";
        if (app.mode === "reader" && reader.quizActive)
            return "a-d answer  ·  ↑↓ question  ·  r start over  ·  m retry missed  ·  ⎋ done";
        if (app.mode === "reader")
            return (reader.quizCount > 0 ? "q quiz  ·  " : "")
                + "↑↓ scroll  ·  n/p phase  ·  y copy  ·  o browser"
                + (root.wide ? "  ·  s sidebar" : "")
                + "  ·  ^t theme  ·  ⎋ back";
        if (app.mode === "catalog")
            return app.catalogCategory
                ? "type to filter  ·  ↑↓ move  ·  ⏎ read  ·  ⎋ categories  ·  ⇥ search"
                : "type to filter  ·  ↑↓ move  ·  ⏎ open category  ·  ⇥ search  ·  ⎋ search";
        return "type to search  ·  ↑↓ move  ·  ⏎ open"
            + (app.canAsk() ? "  ·  ? ask" : "")
            + "  ·  ⇥ catalog  ·  ^r random  ·  ⎋ close";
    }

    // ------------------------------------------------------- empty states

    readonly property string emptyGlyph: {
        var s = app.svc();
        if (app.errorMsg) return "";                       // warning
        if (app.mode === "reader") return "";              // book
        if (app.mode === "catalog") return "";             // list
        if (app.mode === "ask") return "";                 // lightbulb
        if (s && s.searching) return "";                   // magnifier
        if (app.query) return "";
        return "";
    }

    readonly property string emptyTitle: {
        var s = app.svc();
        if (app.errorMsg) return "That didn’t work";
        if (app.mode === "ask")
            return (s && s.asking) ? "Asking the guides…"
                : app.askNotice ? "No answer this time" : "Nothing to show";
        if (app.mode === "reader") return (s && s.loadingPhase) ? "Opening the phase…" : "Nothing loaded yet";
        if (app.mode === "catalog")
            return (s && s.loadingCatalog) ? "Loading the catalog…"
                : app.catalogFilter ? "Nothing matches “" + app.catalogFilter + "”"
                : app.catalogCategory ? "No guides in " + app.catalogCategory
                : "The catalog is empty";
        if (app.searchPending || (s && s.searching)) return "Searching…";
        if (app.query) return "No matches for “" + app.query + "”";
        return "The Missing Manual";
    }

    readonly property string emptyHint: {
        var s = app.svc();
        if (app.errorMsg) return "The details are above. Try another search, or ⎋ to go back.";
        if (app.mode === "ask")
            return (s && s.asking) ? "Answers are written from the guides themselves."
                : app.askNotice ? app.askNotice : "Press ⎋ to go back.";
        if (app.mode === "reader") return "Press ⎋ to go back to your results.";
        if (app.mode === "catalog") return app.catalogFilter
            ? "Backspace to widen the filter, or ⇥ to search instead."
            : app.catalogCategory ? "Press ⎋ to go back to the categories."
            : "Pick a category, type to filter it, or ⇥ to search instead.";
        if (app.searchPending || (s && s.searching)) return "";
        if (app.query) {
            if (app.suggestion) return "Try the suggestion above, or a broader word.";
            // When keyword search has nothing, asking beats rewording.
            return (app.canAsk() ? "Press ? to ask the guides about it, or try a " : "Try a ")
                + "broader word — search tolerates typos, so “rebse” finds “rebase”.";
        }
        var count = (s && s.catalogCache) ? s.catalogCache.length : 0;
        return (count > 0 ? count + " guides ready. " : "")
            + "Start typing to search, press ⇥ to browse the catalog,\n"
            + (app.canAsk() ? "? to ask the guides a question, " : "")
            + "or ^r to open something at random.";
    }

    // ---------------------------------------------------------- the window

    FloatingWindow {
        id: win
        visible: false
        title: "The Missing Manual"
        color: root.background
        implicitWidth: Math.max(640, 1000)
        implicitHeight: Math.max(560, 720)
        minimumSize: Qt.size(640, 560)

        // A key catcher, not a focused text field: typing goes to the filter,
        // ↑↓ move the cursor, and the lists/reader keep their own selection.
        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => root.handleKey(event)
        }

        // Everything lives in one padded body. Anchors, not a Column: the
        // notice line collapses to zero height, and in wide mode the reader
        // fills its own column top to bottom regardless of the left header.
        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.pad

            // The column divider, only in wide mode.
            Rectangle {
                id: vdiv
                visible: root.showLeft
                width: 1
                x: root.leftWidth
                anchors.top: parent.top
                anchors.bottom: footer.top
                anchors.bottomMargin: root.gap
                color: root.divider
            }

            // ------------------------------------------------- left / header
            HeaderBar {
                id: header
                visible: root.leftColumnVisible
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: root.wide ? vdiv.left : parent.right
                anchors.rightMargin: root.wide ? root.colGap : 0
                logoSource: Qt.resolvedUrl("logo.png")
                headline: root.headline
                placeholder: root.headlineIsPlaceholder
                status: root.headerStatus
                foreground: root.foreground
                muted: root.muted
                fontFamily: root.fontFamily
            }

            Rectangle {
                id: headerRule
                visible: root.leftColumnVisible
                anchors.top: header.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.right: root.wide ? vdiv.left : parent.right
                anchors.rightMargin: root.wide ? root.colGap : 0
                height: 1
                color: root.divider
            }

            NoticeLine {
                id: notice
                gate: root.leftColumnVisible
                anchors.top: headerRule.bottom
                anchors.left: parent.left
                anchors.right: root.wide ? vdiv.left : parent.right
                anchors.rightMargin: root.wide ? root.colGap : 0
                errorMsg: app.errorMsg
                statusMsg: app.statusMsg
                suggestion: app.suggestion
                canSuggest: app.mode === "search"
                muted: root.muted
                accent: root.accent
                urgent: root.urgent
                fontFamily: root.fontFamily
                onSuggestionClicked: app.setQuery(app.suggestion)
            }

            // ------------------------------------------------- left / list
            //
            // In compact mode the list shares the single content area, visible
            // only in its own mode. In wide mode it lives in the left column
            // and stays visible while you read on the right.
            ResultList {
                id: resultList
                anchors.top: notice.bottom
                anchors.topMargin: notice.visible ? 0 : root.gap
                anchors.left: parent.left
                anchors.right: root.wide ? vdiv.left : parent.right
                anchors.rightMargin: root.wide ? root.colGap : 0
                anchors.bottom: root.wide ? footer.top : progressRule.top
                anchors.bottomMargin: root.gap
                visible: root.leftColumnVisible && (root.wide
                    ? (!root.leftIsCatalog && app.resultsModel.count > 0)
                    : (app.mode === "search" && app.resultsModel.count > 0))
                model: app.resultsModel
                foreground: root.foreground
                mutedColor: root.muted
                selectedBackground: root.selectedBackground
                selectedText: root.selectedText
                accentColor: root.accent
                fontFamily: root.fontFamily
                onActivated: index => app.activateResult(index)
            }

            ResultList {
                id: catalogList
                anchors.top: notice.bottom
                anchors.topMargin: notice.visible ? 0 : root.gap
                anchors.left: parent.left
                anchors.right: root.wide ? vdiv.left : parent.right
                anchors.rightMargin: root.wide ? root.colGap : 0
                anchors.bottom: root.wide ? footer.top : progressRule.top
                anchors.bottomMargin: root.gap
                visible: root.leftColumnVisible && (root.wide
                    ? (root.leftIsCatalog && app.catalogModel.count > 0)
                    : (app.mode === "catalog" && app.catalogModel.count > 0))
                compact: true
                model: app.catalogModel
                foreground: root.foreground
                mutedColor: root.muted
                selectedBackground: root.selectedBackground
                selectedText: root.selectedText
                accentColor: root.accent
                fontFamily: root.fontFamily
                onActivated: index => app.activateCatalog(index)
            }

            // -------------------------------------------- right / reader
            //
            // Compact: fills the single content area. Wide: fills the right
            // column, top to bottom, while the list stays on the left.
            Reader {
                id: reader
                anchors.top: root.wide ? parent.top : notice.bottom
                anchors.topMargin: root.wide ? 0 : (notice.visible ? 0 : root.gap)
                anchors.left: root.showLeft ? vdiv.right : parent.left
                anchors.leftMargin: root.showLeft ? root.colGap : 0
                anchors.right: parent.right
                anchors.bottom: progressRule.top
                anchors.bottomMargin: root.gap
                visible: app.mode === "reader" && app.phaseBody.length > 0
                markdown: app.phaseBody
                diagrams: app.diagrams
                foreground: root.foreground
                mutedColor: root.muted
                accentColor: root.accent
                fontFamily: root.fontFamily
                codeDark: root.isDark
                // Centre the column only when the reader has the whole window
                // to itself (wide layout with the sidebar folded away).
                centered: root.wide && root.sidebarHidden
                onLinkActivated: url => Quickshell.execDetached(["xdg-open", url])
            }

            // The answer is markdown, and the reader draws markdown -- there is
            // nothing here that wants a second renderer.
            Reader {
                id: askReader
                anchors.top: root.wide ? parent.top : notice.bottom
                anchors.topMargin: root.wide ? 0 : (notice.visible ? 0 : root.gap)
                anchors.left: root.showLeft ? vdiv.right : parent.left
                anchors.leftMargin: root.showLeft ? root.colGap : 0
                anchors.right: parent.right
                anchors.bottom: progressRule.top
                anchors.bottomMargin: root.gap
                visible: app.mode === "ask" && app.askBody.length > 0
                markdown: app.askBody
                foreground: root.foreground
                mutedColor: root.muted
                accentColor: root.accent
                fontFamily: root.fontFamily
                codeDark: root.isDark
                // Centre the column only when the reader has the whole window
                // to itself (wide layout with the sidebar folded away).
                centered: root.wide && root.sidebarHidden
                onLinkActivated: url => Quickshell.execDetached(["xdg-open", url])
            }

            // Empty / loading / welcome. Compact: the whole content area when
            // no view is showing. Wide: the right column whenever the reader
            // is not — so "pick a guide to start reading" greets you there.
            EmptyState {
                id: emptyState
                anchors.top: root.wide ? parent.top : notice.bottom
                anchors.topMargin: root.wide ? 0 : (notice.visible ? 0 : root.gap)
                anchors.left: root.showLeft ? vdiv.right : parent.left
                anchors.leftMargin: root.showLeft ? root.colGap : 0
                anchors.right: parent.right
                anchors.bottom: progressRule.top
                anchors.bottomMargin: root.gap
                visible: root.wide
                    ? (!reader.visible && !askReader.visible)
                    : (!resultList.visible && !catalogList.visible
                        && !reader.visible && !askReader.visible)
                // In compact mode rightPickPrompt is always false, so these
                // fall back to the exact overlay empty-state strings.
                welcome: root.rightPickPrompt ? false : root.welcomeState
                logoSource: Qt.resolvedUrl("logo.png")
                glyph: root.rightPickPrompt ? "" : root.emptyGlyph
                title: root.rightPickPrompt ? "Pick a guide to start reading" : root.emptyTitle
                hint: root.rightPickPrompt
                    ? "Move the list on the left with ↑↓, then press ⏎ to open it here."
                    : root.emptyHint
                foreground: root.foreground
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
            }

            // Reading progress, under the reader's column (full width when
            // compact, the right column when wide).
            ProgressHairline {
                id: progressRule
                anchors.bottom: footer.top
                anchors.bottomMargin: root.gap
                anchors.left: root.showLeft ? vdiv.right : parent.left
                anchors.leftMargin: root.showLeft ? root.colGap : 0
                anchors.right: parent.right
                active: app.mode === "reader" || app.mode === "ask"
                progress: app.mode === "reader" ? reader.progress
                    : app.mode === "ask" ? askReader.progress : 0
                divider: root.divider
                accent: root.accent
            }

            // ------------------------------------------------- footer
            FooterHints {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                text: root.keyHints
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
        }
    }

    // ---------------------------------------------------------- key handling
    //
    // The same dispatch the overlay used: it routes by mode, so both panes
    // being mounted in wide mode changes nothing — list keys still move the
    // left list, reader keys still scroll the reader. State calls go to `app`;
    // the reader/list calls stay on the view items.

    function handleKey(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        // Escape unwinds one layer at a time rather than dropping everything.
        if (event.key === Qt.Key_Escape) {
            if (app.errorMsg) app.errorMsg = "";
            else if (app.mode === "ask") app.leaveAsk();
            else if (app.mode === "reader" && reader.quizActive) reader.quizActive = false;
            else if (app.mode === "reader") app.backFromReader();
            else if (app.mode === "catalog" && app.catalogBack()) { /* went up a level */ }
            else if (app.mode === "catalog") app.backToSearch();
            else if (app.query) app.setQuery("");
            else root.close();
            event.accepted = true;
            return;
        }

        // ^t cycles the reading palette (auto → light → dark) from any mode.
        // Ctrl-guarded so it never collides with typing a filter.
        if (ctrl && event.key === Qt.Key_T) {
            root.cycleTheme();
            event.accepted = true;
            return;
        }

        if (app.mode === "ask") { root.handleAskKey(event, ctrl, shift); return; }

        if (app.mode === "reader") {
            // Quiz mode is a short-lived layer over the reader: it takes the
            // keys it needs and lets everything else fall through, so n/p/y/o
            // keep working while you answer.
            if (reader.quizActive && root.handleQuizKey(event)) return;
            root.handleReaderKey(event, ctrl, shift);
            return;
        }
        root.handleListKey(event, ctrl, shift);
    }

    function handleAskKey(event, ctrl, shift) {
        var step = Style.space(60);

        // 1-9 open the Nth source. The answer names them in that order, so the
        // numbers on screen are the numbers you press.
        var text = event.text || "";
        if (!ctrl && text.length === 1) {
            var n = text.charCodeAt(0) - 49;                 // "1" -> 0
            if (n >= 0 && n < 9 && n < app.askSources.length) {
                app.openAskSource(n);
                event.accepted = true;
                return;
            }
        }

        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_J: askReader.scrollBy(step); break;
        case Qt.Key_Up:   case Qt.Key_K: askReader.scrollBy(-step); break;
        case Qt.Key_PageDown: case Qt.Key_Space: askReader.scrollPage(1); break;
        case Qt.Key_PageUp: askReader.scrollPage(-1); break;
        case Qt.Key_Home: askReader.toTop(); break;
        case Qt.Key_End:  askReader.toBottom(); break;
        case Qt.Key_G: if (shift) askReader.toBottom(); else askReader.toTop(); break;
        case Qt.Key_Y: askReader.copy(app.askBody); break;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (app.askSources.length > 0) app.openAskSource(0);
            break;
        case Qt.Key_O: app.openAskInBrowser(); break;
        case Qt.Key_Backspace: app.leaveAsk(); break;
        case Qt.Key_Slash: app.leaveAsk(); app.setQuery(""); break;
        case Qt.Key_S: if (root.wide) root.sidebarHidden = !root.sidebarHidden; else return; break;
        case Qt.Key_Q: root.close(); break;
        default: return;
        }
        event.accepted = true;
    }

    // Returns true when the quiz consumed the key.
    function handleQuizKey(event) {
        var text = (event.text || "").toLowerCase();

        // a-d and 1-4 both answer; the card labels choices A-D like the site.
        var choice = -1;
        if (text.length === 1) {
            var code = text.charCodeAt(0);
            if (code >= 97 && code <= 106) choice = code - 97;        // a..j
            else if (code >= 49 && code <= 57) choice = code - 49;    // 1..9
        }
        if (choice >= 0 && !(event.modifiers & Qt.ControlModifier)) {
            reader.answerQuiz(reader.quizCursor, choice);
            event.accepted = true;
            return true;
        }

        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_J: reader.quizMove(1); break;
        case Qt.Key_Up:   case Qt.Key_K: reader.quizMove(-1); break;
        case Qt.Key_R: reader.quizStartOver(); break;
        case Qt.Key_M: reader.quizRetryMissed(); break;
        default: return false;
        }
        event.accepted = true;
        return true;
    }

    function handleReaderKey(event, ctrl, shift) {
        var step = Style.space(60);
        switch (event.key) {
        case Qt.Key_Down:  case Qt.Key_J: reader.scrollBy(step); break;
        case Qt.Key_Up:    case Qt.Key_K: reader.scrollBy(-step); break;
        case Qt.Key_PageDown: case Qt.Key_Space: reader.scrollPage(1); break;
        case Qt.Key_PageUp: reader.scrollPage(-1); break;
        case Qt.Key_Home: reader.toTop(); break;
        case Qt.Key_End:  reader.toBottom(); break;
        case Qt.Key_G: if (event.modifiers & Qt.ShiftModifier) reader.toBottom(); else reader.toTop(); break;
        case Qt.Key_N: case Qt.Key_Right: app.nextPhase(); break;
        case Qt.Key_P: case Qt.Key_Left:  app.prevPhase(); break;
        case Qt.Key_Y: reader.copy(app.phaseBody); break;
        case Qt.Key_O: app.openInBrowser(); break;
        case Qt.Key_Backspace: app.backFromReader(); break;
        case Qt.Key_Slash: app.mode = "search"; app.setQuery(""); break;
        case Qt.Key_Tab: app.showCatalog(); break;
        // s tucks the left list away for a full-width column (wide mode only).
        case Qt.Key_S: if (root.wide) root.sidebarHidden = !root.sidebarHidden; else return; break;
        case Qt.Key_Q:
            if (shift || reader.quizCount === 0) root.close();
            else { reader.quizActive = true; reader.quizCursor = root.firstUnanswered(); }
            break;
        case Qt.Key_R: if (ctrl) app.pickRandom(); else return; break;
        default: return;
        }
        event.accepted = true;
    }

    // Stays in the view: it reads the reader's quiz answers.
    function firstUnanswered() {
        for (var i = 0; i < reader.quizCount; i++)
            if (reader.quizChosen(i) < 0) return i;
        return 0;
    }

    function handleListKey(event, ctrl, shift) {
        var isCatalog = app.mode === "catalog";
        var list = isCatalog ? catalogList : resultList;
        var text = isCatalog ? app.catalogFilter : app.query;
        var apply = isCatalog ? app.setCatalogFilter : app.setQuery;

        if (ctrl && event.key === Qt.Key_R) { app.pickRandom(); event.accepted = true; return; }

        // "?" asks the guides. Only from search, only with something to ask,
        // and only as a keypress -- this is the path that costs money, so it
        // never happens while you are typing.
        if (!isCatalog && !ctrl && event.text === "?" && text.replace(/^\s+|\s+$/g, "")) {
            app.enterAsk(text);
            event.accepted = true; return;
        }

        switch (event.key) {
        case Qt.Key_Tab:
            if (isCatalog) app.backToSearch(); else app.showCatalog();
            event.accepted = true; return;
        case Qt.Key_Down: list.moveCursor(1); event.accepted = true; return;
        case Qt.Key_Up:   list.moveCursor(-1); event.accepted = true; return;
        case Qt.Key_PageDown: list.movePage(1); event.accepted = true; return;
        case Qt.Key_PageUp:   list.movePage(-1); event.accepted = true; return;
        case Qt.Key_Home: list.moveToEdge(-1); event.accepted = true; return;
        case Qt.Key_End:  list.moveToEdge(1); event.accepted = true; return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (shift && app.suggestion) app.setQuery(app.suggestion);
            else list.activateCursor();
            event.accepted = true; return;
        }

        // Ctrl+N / Ctrl+P move the cursor, matching the rest of the desktop.
        if (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_P)) {
            list.moveCursor(event.key === Qt.Key_N ? 1 : -1);
            event.accepted = true; return;
        }

        if (Util.editsFilter(event, text)) {
            apply(Util.editedFilter(event, text));
            event.accepted = true; return;
        }

        // Backspace with nothing left to delete climbs out of a category.
        if (isCatalog && !text && event.key === Qt.Key_Backspace) {
            app.catalogBack();
            event.accepted = true; return;
        }

        if (!ctrl && event.text && event.text.length === 1
                && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            apply(text + event.text);
            event.accepted = true;
        }
    }
}
