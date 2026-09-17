import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Markdown.js" as Markdown

// tmm.manual overlay — search, browse and read The Missing Manual without
// leaving the desktop.
//
// Follows the Omarchy overlay idiom used by the menu, clipboard and emoji
// pickers: its own layer-shell window with exclusive keyboard focus, a
// key catcher instead of a focused text field, and every color, size and
// radius taken from the active theme so it restyles with the desktop.
Item {
    id: root

    // Injected by the Omarchy host when available.
    property var shell
    property var manifest
    property var pluginRegistry
    property var service

    // Standalone fallback (sibling Service.qml) so the overlay still works
    // when it is loaded without the service kind mounted.
    Service { id: tmmService }

    property bool opened: false
    property string mode: "search"   // search | reader | catalog
    property string query: ""
    property string catalogFilter: ""
    // Catalog is two levels: the category list, then the guides inside one.
    // "" means we are at the top level.
    property string catalogCategory: ""
    property string suggestion: ""
    property string statusMsg: ""
    property string errorMsg: ""

    property string currentSlug: ""
    property int currentPhase: 1
    property string guideTitle: ""
    property string phaseBody: ""
    property bool phaseFromCache: false
    // Bounds from the response headers; 0 means we do not know yet (an old
    // cached phase has no sidecar). Never guess -- an unknown bound lets the
    // request through, which is how this behaved before the headers existed.
    property int phaseCount: 0
    property int nextPhaseNo: 0
    property string returnMode: "search"

    // ------------------------------------------------------------- theming
    //
    // Shares the [menu] surface tokens, like the other summoned overlays:
    // a theme that styles the Omarchy menu styles this too.
    readonly property color background: Color.menu.background
    readonly property color foreground: Color.menu.text
    readonly property color borderColor: Color.menu.border
    readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
    readonly property color scrim: Color.menu.scrim
    readonly property color selectedBackground: Color.menu.selectedBackground
    readonly property color selectedText: Color.menu.selectedText
    readonly property color mutedColor: Util.alpha(foreground, 0.6)
    readonly property color dividerColor: Util.alpha(foreground, 0.14)
    readonly property int cornerRadius: Style.cornerRadius
    readonly property string fontFamily: Style.font.menuFamily
    readonly property int contentMargin: Style.spacing.panelPadding
    readonly property int headerHeight: Math.max(Style.space(38), Style.font.heading + Style.spacing.controlPaddingY * 2)
    readonly property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.spacing.controlPaddingY)
    readonly property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
    readonly property int cardHeight: Math.min(Style.space(660), panel.height - Style.gapsOut * 2)

    ListModel { id: resultsModel }
    ListModel { id: catalogModel }

    // --------------------------------------------------------- service glue

    function svc() { return (service !== undefined && service) ? service : tmmService; }

    function safeCall(fn) {
        var s = svc();
        if (!s || typeof s[fn] !== "function") {
            root.errorMsg = "The manual service is not available";
            return null;
        }
        return s;
    }

    // ------------------------------------------------------------ lifecycle

    function open(payloadJson) {
        root.opened = true;
        root.errorMsg = "";
        var q = "", slug = "", phase = 0, wantCatalog = false, wantRandom = false;
        if (payloadJson) {
            try {
                var p = typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson;
                q = p.query || p.q || "";
                slug = p.slug || p.guide_slug || "";
                phase = p.phase || p.phase_no || 0;
                wantCatalog = p.catalog === true || p.mode === "catalog";
                wantRandom = p.random === true || p.mode === "random";
            } catch (e) {
                root.errorMsg = "That payload was not valid JSON";
            }
        }
        if (wantRandom) {
            // The catalog may still be in flight; pick as soon as it lands.
            root.pendingRandom = true;
            root.mode = "search";
            root.pickRandom();
        } else if (wantCatalog) {
            root.showCatalog();
        } else if (slug) {
            root.openPhase(slug, phase > 0 ? phase : 1, "");
        } else if (q) {
            root.mode = "search";
            root.setQuery(q);
        } else {
            root.mode = "search";
            root.query = "";
            resultsModel.clear();
            root.suggestion = "";
            root.showRecents();
        }
        // Warm the catalog so Tab is instant and the placeholder can be honest
        // about how many guides there are.
        var s = safeCall("getCatalog");
        if (s) s.getCatalog();
        Qt.callLater(function () { keyCatcher.forceActiveFocus(); });
    }

    function close() { root.opened = false; }

    // Tell the host we are down, so a later summon re-shows us.
    function dismiss() {
        root.opened = false;
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "tmm.manual");
    }

    function toggle() {
        if (root.opened) root.dismiss();
        else root.open("{}");
    }

    // ---------------------------------------------------------- search flow

    function setQuery(next) {
        root.query = next;
        root.mode = "search";
        root.suggestion = "";
        root.errorMsg = "";
        if (next.replace(/^\s+|\s+$/g, "").length === 0) {
            resultsModel.clear();
            root.showRecents();
            searchDebounce.stop();
        } else {
            searchDebounce.restart();
        }
    }

    function runSearch() {
        var q = root.query.replace(/^\s+|\s+$/g, "");
        if (!q) return;
        root.showingRecents = false;
        var s = safeCall("search");
        if (s) s.search(q);
    }

    // Recents stand in for results on the empty search screen: the manual is
    // something you come back to, so "where was I" is the first question.
    property bool showingRecents: false

    function showRecents() {
        var s = svc();
        var list = (s && s.recents) || [];
        resultsModel.clear();
        for (var i = 0; i < list.length; i++) {
            resultsModel.append({
                "title": list[i].title || list[i].slug,
                "summary": "",
                "badge": "phase " + list[i].phase,
                "guide_slug": list[i].slug,
                "phase_no": 0
            });
        }
        root.showingRecents = resultsModel.count > 0;
        resultList.cursorIndex = 0;
        resultList.cursorActive = resultsModel.count > 0;
    }

    // --------------------------------------------------------- reader flow

    function openPhase(slug, phase, title) {
        if (!slug) return;
        if (root.mode !== "reader") root.returnMode = root.mode;
        root.currentSlug = slug;
        root.currentPhase = phase;
        if (title) root.guideTitle = title;
        root.mode = "reader";
        root.errorMsg = "";
        var s = safeCall("getPhase");
        if (s) s.getPhase(slug, phase);
    }

    function activateResult(index) {
        if (index < 0 || index >= resultsModel.count) return;
        var hit = resultsModel.get(index);
        root.openPhase(hit.guide_slug, hit.phase_no > 0 ? hit.phase_no : 1, hit.title);
    }

    function activateCatalog(index) {
        if (index < 0 || index >= catalogModel.count) return;
        var entry = catalogModel.get(index);
        if (entry.kind === "category") {
            root.catalogCategory = entry.title;
            root.catalogFilter = "";
            root.rebuildCatalog();
            return;
        }
        root.openPhase(entry.guide_slug, 1, entry.title);
    }

    function prevPhase() {
        if (root.mode === "reader" && root.currentPhase > 1)
            root.openPhase(root.currentSlug, root.currentPhase - 1, root.guideTitle);
    }

    function nextPhase() {
        if (root.mode !== "reader") return;
        if (root.nextPhaseNo > 0) {
            root.openPhase(root.currentSlug, root.nextPhaseNo, root.guideTitle);
            return;
        }
        // The site omits x-next-phase on the last phase, and that absence is
        // the signal. Walking off the end used to 404 into an error banner.
        if (root.phaseCount > 0) { root.statusMsg = "That was the last phase"; return; }
        root.openPhase(root.currentSlug, root.currentPhase + 1, root.guideTitle);
    }

    function openInBrowser() {
        if (!root.currentSlug) return;
        var s = svc();
        if (s && typeof s.webUrl === "function")
            Quickshell.execDetached(["xdg-open", s.webUrl(root.currentSlug, root.currentPhase)]);
    }

    function firstUnanswered() {
        for (var i = 0; i < reader.quizCount; i++)
            if (reader.quizChosen(i) < 0) return i;
        return 0;
    }

    function backFromReader() {
        root.mode = root.returnMode === "catalog" ? "catalog" : "search";
    }

    // --------------------------------------------------------- catalog flow

    function showCatalog() {
        root.mode = "catalog";
        root.errorMsg = "";
        root.catalogCategory = "";
        root.catalogFilter = "";
        var s = safeCall("getCatalog");
        if (s) s.getCatalog();
        root.rebuildCatalog();
    }

    function setCatalogFilter(next) {
        root.catalogFilter = next;
        root.rebuildCatalog();
    }

    function rebuildCatalog() {
        var s = svc();
        var all = (s && s.catalogCache) || [];
        var needle = root.catalogFilter.toLowerCase().replace(/^\s+|\s+$/g, "");
        catalogModel.clear();

        if (!root.catalogCategory) {
            // Top level: one row per category, with how many guides it holds.
            var names = [], counts = ({});
            for (var i = 0; i < all.length; i++) {
                var c = String(all[i].summary || "Uncategorised");
                if (counts[c] === undefined) { counts[c] = 0; names.push(c); }
                counts[c] += 1;
            }
            names.sort();
            for (var j = 0; j < names.length; j++) {
                var name = names[j];
                if (needle && name.toLowerCase().indexOf(needle) < 0) continue;
                catalogModel.append({
                    "kind": "category",
                    "title": name,
                    "summary": "",
                    "badge": counts[name] + (counts[name] === 1 ? " guide" : " guides"),
                    "guide_slug": "",
                    "phase_no": 0
                });
            }
        } else {
            for (var k = 0; k < all.length; k++) {
                var entry = all[k];
                if (String(entry.summary || "") !== root.catalogCategory) continue;
                if (needle && (String(entry.title) + " " + String(entry.slug))
                        .toLowerCase().indexOf(needle) < 0) continue;
                catalogModel.append({
                    "kind": "guide",
                    "title": entry.title,
                    "summary": "",
                    "badge": "",
                    "guide_slug": entry.slug,
                    "phase_no": 0
                });
            }
        }
        catalogList.cursorIndex = 0;
        catalogList.cursorActive = catalogModel.count > 0;
    }

    // Up one level; returns false when already at the top.
    function catalogBack() {
        if (root.catalogFilter) { root.setCatalogFilter(""); return true; }
        if (root.catalogCategory) {
            root.catalogCategory = "";
            root.rebuildCatalog();
            return true;
        }
        return false;
    }

    // Set when a random pick was asked for before the catalog had arrived.
    property bool pendingRandom: false

    function pickRandom() {
        var s = svc();
        var all = (s && s.catalogCache) || [];
        if (all.length === 0) {
            root.pendingRandom = true;
            if (s && typeof s.getCatalog === "function") s.getCatalog();
            return;
        }
        root.pendingRandom = false;
        var entry = all[Math.floor(Math.random() * all.length)];
        root.returnMode = root.mode === "reader" ? root.returnMode : root.mode;
        root.openPhase(entry.slug, 1, entry.title);
    }

    // A status line says what just happened; it should not still be there when
    // you look back at the panel.
    onStatusMsgChanged: if (statusMsg) statusReset.restart()

    Timer {
        id: statusReset
        interval: 2600
        onTriggered: root.statusMsg = ""
    }

    Timer {
        id: searchDebounce
        interval: 240
        onTriggered: root.runSearch()
    }

    // ------------------------------------------------------------ diagrams
    //
    // The baked SVGs carry sentinel colours that the site's CSS remaps; we do
    // the same substitution against the active theme. SVG Tiny has no alpha
    // channel in its colour grammar and Qt prints an alpha colour as
    // #aarrggbb, which an SVG parser reads as #rrggbbaa -- so every token is
    // flattened to an opaque #rrggbb over the panel background first.
    function opaqueHex(c) {
        var a = c.a === undefined ? 1 : c.a;
        var bg = root.background;
        function part(x, y) {
            var v = Math.round(255 * (x * a + y * (1 - a)));
            v = Math.max(0, Math.min(255, v));
            return (v < 16 ? "0" : "") + v.toString(16);
        }
        return "#" + part(c.r, bg.r) + part(c.g, bg.g) + part(c.b, bg.b);
    }

    function diagramColours() {
        return {
            "fill": opaqueHex(Util.alpha(root.foreground, 0.06)),
            "stroke": opaqueHex(Color.accent),
            "text": opaqueHex(root.foreground),
            "edge": opaqueHex(root.mutedColor),
            "subfill": opaqueHex(Util.alpha(root.foreground, 0.03)),
            "substroke": opaqueHex(root.dividerColor),
            "note": opaqueHex(Util.alpha(Color.accent, 0.18)),
            "ink": opaqueHex(root.foreground),
            "line": opaqueHex(root.dividerColor)
        };
    }

    function fetchDiagrams(slug, phase, body) {
        reader.diagrams = [];
        var blocks = Markdown.parseBlocks(body);
        var wanted = 0;
        for (var i = 0; i < blocks.length; i++)
            if (blocks[i].type === "diagram") wanted++;
        if (wanted === 0) return;
        var s = svc();
        if (s && typeof s.getDiagrams === "function")
            s.getDiagrams(slug, phase, diagramColours());
    }

    // ---------------------------------------------------------- service bus

    Connections {
        target: root.svc()

        function onSearchDone(result) {
            var list = Array.isArray(result) ? result : (result && result.hits) || [];
            resultsModel.clear();
            for (var i = 0; i < list.length; ++i) {
                var h = list[i];
                resultsModel.append({
                    "title": Markdown.plain(h.title || h.guide_title || h.slug || "Untitled"),
                    "summary": Markdown.plain(h.summary || h.description || h.snippet || h.excerpt || ""),
                    "badge": h.category || h.guide_title || "",
                    "guide_slug": h.guide_slug || h.slug || "",
                    "phase_no": h.phase_no || h.phase || 1
                });
            }
            root.showingRecents = false;
            root.suggestion = (result && result.suggestion) || "";
            resultList.cursorIndex = 0;
            resultList.cursorActive = resultsModel.count > 0;
        }

        function onPhaseDone(slug, phase, markdown, fromCache, meta) {
            root.currentSlug = slug;
            root.currentPhase = phase;
            root.statusMsg = "";
            root.phaseCount = (meta && meta.count) || 0;
            root.nextPhaseNo = (meta && meta.next) || 0;
            root.phaseBody = root.stripFrontmatter(markdown);
            root.phaseFromCache = fromCache === true;
            var heading = Markdown.firstHeading(root.phaseBody);
            if (heading) root.guideTitle = heading;
            root.mode = "reader";
            root.errorMsg = "";
            reader.quizActive = false;
            reader.quizAnswers = [];
            reader.quizCursor = 0;
            var s = root.svc();
            if (s && typeof s.rememberPhase === "function")
                s.rememberPhase(slug, phase, root.guideTitle);
            root.fetchDiagrams(slug, phase, root.phaseBody);
        }

        function onDiagramsDone(slug, phase, diagrams) {
            // A phase the user has already paged away from must not repaint
            // the one they are reading now.
            if (slug !== root.currentSlug || phase !== root.currentPhase) return;
            reader.diagrams = diagrams || [];
        }

        function onCatalogDone(catalog) {
            if (root.pendingRandom) { root.pickRandom(); return; }
            if (root.mode === "catalog") root.rebuildCatalog();
        }

        function onError(msg) { root.errorMsg = msg; }
    }

    function stripFrontmatter(md) {
        return String(md || "").replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
    }

    // ------------------------------------------------------------ chrome

    // The welcome screen is the one state that is about identity rather than
    // about what you are doing, so it gets the real logo.
    readonly property bool welcomeState: {
        var s = svc();
        return mode === "search" && !errorMsg && !query
            && !(searchDebounce.running || (s && s.searching));
    }

    readonly property string headline: {
        if (mode === "reader") return guideTitle || currentSlug;
        if (mode === "catalog") {
            if (catalogFilter) return catalogFilter;
            return catalogCategory ? catalogCategory : "Browse by category…";
        }
        if (query) return query;
        return showingRecents ? "Pick up where you left off…" : "Search the manual…";
    }

    readonly property bool headlineIsPlaceholder:
        (mode === "search" && !query)
        || (mode === "catalog" && !catalogFilter && !catalogCategory)

    readonly property string headerStatus: {
        var s = svc();
        if (mode === "reader") {
            if (s && s.loadingPhase) return "loading…";
            var mins = phaseBody ? Markdown.readingMinutes(phaseBody) : 0;
            return "phase " + currentPhase + (phaseCount > 0 ? " of " + phaseCount : "")
                + (mins ? "  ·  " + mins + " min" : "")
                + (phaseFromCache ? "  ·  offline" : "");
        }
        if (mode === "catalog") {
            if (s && s.loadingCatalog && catalogModel.count === 0) return "loading…";
            var n = catalogModel.count;
            if (!catalogCategory) return n + (n === 1 ? " category" : " categories");
            return n + (n === 1 ? " guide" : " guides");
        }
        if (searchDebounce.running || (s && s.searching)) return "searching…";
        if (showingRecents) return "recent";
        if (!query) return "";
        return resultsModel.count + (resultsModel.count === 1 ? " result" : " results");
    }

    readonly property string keyHints: {
        if (mode === "reader" && reader.quizActive)
            return "a-d answer  ·  ↑↓ question  ·  r start over  ·  m retry missed  ·  ⎋ done";
        if (mode === "reader")
            return (reader.quizCount > 0 ? "q quiz  ·  " : "")
                + "↑↓ scroll  ·  n/p phase  ·  y copy  ·  o browser  ·  ⎋ back";
        if (mode === "catalog")
            return catalogCategory
                ? "type to filter  ·  ↑↓ move  ·  ⏎ read  ·  ⎋ categories  ·  ⇥ search"
                : "type to filter  ·  ↑↓ move  ·  ⏎ open category  ·  ⇥ search  ·  ⎋ close";
        return "type to search  ·  ↑↓ move  ·  ⏎ open  ·  ⇥ catalog  ·  ^r random  ·  ⎋ close";
    }

    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "tmm-manual"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            color: root.scrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        BorderSurface {
            id: card
            width: root.cardWidth
            height: root.cardHeight
            radius: root.cornerRadius
            anchors.centerIn: parent
            color: root.background
            borderSpec: root.borderSpec
            padding: root.contentMargin

            // Clicks inside the card must not reach the dismiss layer.
            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => root.handleKey(event)
            }

            // Anchored rather than stacked in a Column: the notice line
            // collapses to zero height when there is nothing to say, and a
            // Column's spacing would silently change the content height with it.
            Item {
                id: body
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset

                // ------------------------------------------------- header
                Item {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.headerHeight

                    Image {
                        id: icon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl("logo.png")
                        width: Style.space(20)
                        height: width
                        sourceSize.width: 64
                        sourceSize.height: 64
                        smooth: true
                        mipmap: true
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        id: status
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.headerStatus
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    Text {
                        anchors.left: icon.right
                        anchors.leftMargin: Style.space(10)
                        anchors.right: status.left
                        anchors.rightMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.headline
                        color: root.foreground
                        opacity: root.headlineIsPlaceholder ? 0.58 : 1
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: headerRule
                    anchors.top: header.bottom
                    anchors.topMargin: Style.spacing.md
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: root.dividerColor
                }

                // "Did you mean" and errors share one slim notice line so the
                // layout never jumps between states.
                Item {
                    id: notice
                    anchors.top: headerRule.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: root.errorMsg.length > 0 || root.statusMsg.length > 0
                        || (root.mode === "search" && root.suggestion.length > 0)
                    height: visible ? noticeText.implicitHeight + Style.spacing.md * 2 : 0

                    Text {
                        id: noticeText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.errorMsg ? root.errorMsg
                            : root.statusMsg ? root.statusMsg
                            : "Did you mean “" + root.suggestion + "”?  Press ⇧⏎"
                        // A status line is not a failure and not an offer:
                        // it says what just happened and gets out of the way.
                        color: root.errorMsg ? Color.urgent
                            : root.statusMsg ? root.mutedColor : Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.mode === "search" && root.suggestion.length > 0
                            && root.errorMsg.length === 0 && root.statusMsg.length === 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setQuery(root.suggestion)
                    }
                }

                // ------------------------------------------------ content
                Item {
                    id: content
                    anchors.top: notice.bottom
                    anchors.topMargin: notice.visible ? 0 : Style.spacing.md
                    anchors.bottom: progressRule.top
                    anchors.bottomMargin: Style.spacing.md
                    anchors.left: parent.left
                    anchors.right: parent.right

                    ResultList {
                        id: resultList
                        anchors.fill: parent
                        visible: root.mode === "search" && resultsModel.count > 0
                        model: resultsModel
                        foreground: root.foreground
                        accentColor: Color.accent
                        mutedColor: root.mutedColor
                        selectedBackground: root.selectedBackground
                        selectedText: root.selectedText
                        fontFamily: root.fontFamily
                        onActivated: index => root.activateResult(index)
                    }

                    ResultList {
                        id: catalogList
                        anchors.fill: parent
                        visible: root.mode === "catalog" && catalogModel.count > 0
                        compact: true
                        model: catalogModel
                        foreground: root.foreground
                        mutedColor: root.mutedColor
                        selectedBackground: root.selectedBackground
                        selectedText: root.selectedText
                        fontFamily: root.fontFamily
                        onActivated: index => root.activateCatalog(index)
                    }

                    Reader {
                        id: reader
                        anchors.fill: parent
                        visible: root.mode === "reader" && root.phaseBody.length > 0
                        markdown: root.phaseBody
                        foreground: root.foreground
                        mutedColor: root.mutedColor
                        fontFamily: root.fontFamily
                        onLinkActivated: url => Quickshell.execDetached(["xdg-open", url])
                    }

                    // Empty and loading states. A blank panel is the least
                    // helpful thing a manual can show, so every one of these
                    // says what to do next.
                    Column {
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        spacing: Style.space(10)
                        visible: !resultList.visible && !catalogList.visible && !reader.visible

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.welcomeState
                            source: Qt.resolvedUrl("logo.png")
                            width: Style.space(72)
                            height: width
                            sourceSize.width: 256
                            sourceSize.height: 256
                            smooth: true
                            mipmap: true
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            width: parent.width
                            visible: !root.welcomeState
                            horizontalAlignment: Text.AlignHCenter
                            textFormat: Text.PlainText
                            text: root.emptyGlyph
                            color: Color.accent
                            opacity: 0.75
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.displayLarge
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: root.emptyTitle
                            color: root.foreground
                            opacity: 0.85
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: root.emptyHint
                            color: root.mutedColor
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            lineHeight: 1.5
                            lineHeightMode: Text.ProportionalHeight
                        }
                    }
                }

                // Reading progress: a hairline that only fills in the reader.
                Rectangle {
                    id: progressRule
                    anchors.bottom: footer.top
                    anchors.bottomMargin: Style.spacing.md
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: root.dividerColor

                    Rectangle {
                        width: parent.width * (root.mode === "reader" ? reader.progress : 0)
                        height: parent.height
                        color: Color.accent
                        visible: root.mode === "reader"
                    }
                }

                // ------------------------------------------------- footer
                Item {
                    id: footer
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.footerHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.keyHints
                        color: Util.alpha(root.foreground, 0.45)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- empty states

    readonly property string emptyGlyph: {
        var s = svc();
        if (root.errorMsg) return "";                       // warning
        if (mode === "reader") return "";                   // book
        if (mode === "catalog") return "";                  // list
        if (s && s.searching) return "";                    // magnifier
        if (query) return "";
        return "";
    }

    readonly property string emptyTitle: {
        var s = svc();
        if (errorMsg) return "That didn’t work";
        if (mode === "reader") return (s && s.loadingPhase) ? "Opening the phase…" : "Nothing loaded yet";
        if (mode === "catalog")
            return (s && s.loadingCatalog) ? "Loading the catalog…"
                : catalogFilter ? "Nothing matches “" + catalogFilter + "”"
                : catalogCategory ? "No guides in " + catalogCategory
                : "The catalog is empty";
        if (searchDebounce.running || (s && s.searching)) return "Searching…";
        if (query) return "No matches for “" + query + "”";
        return "The Missing Manual";
    }

    readonly property string emptyHint: {
        var s = svc();
        if (errorMsg) return "The details are above. Try another search, or ⎋ to go back.";
        if (mode === "reader") return "Press ⎋ to go back to your results.";
        if (mode === "catalog") return catalogFilter
            ? "Backspace to widen the filter, or ⇥ to search instead."
            : catalogCategory ? "Press ⎋ to go back to the categories."
            : "Press ⇥ to go back to search.";
        if (searchDebounce.running || (s && s.searching)) return "";
        if (query) return root.suggestion
            ? "Try the suggestion above, or a broader word."
            : "Try a broader word — search tolerates typos, so “rebse” finds “rebase”.";
        var n = (s && s.catalogCache) ? s.catalogCache.length : 0;
        return (n > 0 ? n + " guides ready. " : "")
            + "Start typing to search, press ⇥ to browse the catalog,\n"
            + "or ^r to open something at random.";
    }

    // ---------------------------------------------------------- key handling

    function handleKey(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        // Escape unwinds one layer at a time rather than dropping everything.
        if (event.key === Qt.Key_Escape) {
            if (root.errorMsg) root.errorMsg = "";
            else if (root.mode === "reader" && reader.quizActive) reader.quizActive = false;
            else if (root.mode === "reader") root.backFromReader();
            else if (root.mode === "catalog" && root.catalogBack()) { /* went up a level */ }
            else if (root.mode === "catalog") root.mode = "search";
            else if (root.query) root.setQuery("");
            else root.dismiss();
            event.accepted = true;
            return;
        }

        if (root.mode === "reader") {
            // Quiz mode is a short-lived layer over the reader: it takes the
            // keys it needs and lets everything else fall through, so n/p/y/o
            // keep working while you answer.
            if (reader.quizActive && root.handleQuizKey(event)) return;
            root.handleReaderKey(event, ctrl, shift);
            return;
        }
        root.handleListKey(event, ctrl, shift);
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
        case Qt.Key_N: case Qt.Key_Right: root.nextPhase(); break;
        case Qt.Key_P: case Qt.Key_Left:  root.prevPhase(); break;
        case Qt.Key_Y: reader.copy(root.phaseBody); break;
        case Qt.Key_O: root.openInBrowser(); break;
        case Qt.Key_Backspace: root.backFromReader(); break;
        case Qt.Key_Slash: root.mode = "search"; root.setQuery(""); break;
        case Qt.Key_Tab: root.showCatalog(); break;
        case Qt.Key_Q:
            if (shift || reader.quizCount === 0) root.dismiss();
            else { reader.quizActive = true; reader.quizCursor = root.firstUnanswered(); }
            break;
        case Qt.Key_R: if (ctrl) root.pickRandom(); else return; break;
        default: return;
        }
        event.accepted = true;
    }

    function handleListKey(event, ctrl, shift) {
        var isCatalog = root.mode === "catalog";
        var list = isCatalog ? catalogList : resultList;
        var text = isCatalog ? root.catalogFilter : root.query;
        var apply = isCatalog ? root.setCatalogFilter : root.setQuery;

        if (ctrl && event.key === Qt.Key_R) { root.pickRandom(); event.accepted = true; return; }

        switch (event.key) {
        case Qt.Key_Tab:
            if (isCatalog) root.mode = "search"; else root.showCatalog();
            event.accepted = true; return;
        case Qt.Key_Down: list.moveCursor(1); event.accepted = true; return;
        case Qt.Key_Up:   list.moveCursor(-1); event.accepted = true; return;
        case Qt.Key_PageDown: list.movePage(1); event.accepted = true; return;
        case Qt.Key_PageUp:   list.movePage(-1); event.accepted = true; return;
        case Qt.Key_Home: list.moveToEdge(-1); event.accepted = true; return;
        case Qt.Key_End:  list.moveToEdge(1); event.accepted = true; return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (shift && root.suggestion) root.setQuery(root.suggestion);
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
            root.catalogBack();
            event.accepted = true; return;
        }

        if (!ctrl && event.text && event.text.length === 1
                && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            apply(text + event.text);
            event.accepted = true;
        }
    }
}
