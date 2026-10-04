import Quickshell
import QtQuick
import qs.Commons
import "Markdown.js" as Markdown

// tmm.manual controller — the app state machine, lifted out of the surface.
//
// This is a headless, view-agnostic Item: it owns the modes, the search /
// reader / catalog / ask flows, the service bus and the diagram theming, and
// it talks to whatever view renders it only through plain properties and a
// handful of signals. It never reaches into a list, a reader or a window, so
// the same machine can drive the floating panel, a test harness, or anything
// else that wires the same properties up.
Item {
    id: root

    // Injected by the Omarchy host when available. The view passes `service`
    // down; `shell`/`manifest` are only read by dismiss(), which the view now
    // wraps, so they can stay undefined in the panel.
    property var shell
    property var manifest
    property var service

    // Standalone fallback (sibling Service.qml) so the controller still works
    // when it is loaded without the service kind mounted.
    Service { id: tmmService }

    property bool opened: false
    property string mode: "search"   // search | reader | catalog | ask
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
    property string _diagramsFor: ""
    property int phaseCount: 0
    property int nextPhaseNo: 0
    property string returnMode: "search"

    // ------------------------------------------------------------------ ask
    //
    // The site's rule (aiFallback.js) is that AI is never called from
    // typeahead: the written answer is an explicit action, and the zero-hit
    // path uses the free retrieval mode after a pause. Both are its budget,
    // so both rules hold here.
    property string askQuery: ""
    property string askBody: ""
    property string askNotice: ""
    property bool askCached: false
    property var askSources: []
    // Which call is in flight: "" for the written answer, "search" for the
    // free retrieval used as a zero-hit fallback.
    property string _askMode: ""
    // Set once the host says the feature is off, so we stop offering it.
    property bool askDisabled: false

    // ------------------------------------------------------------ AI chat
    //
    // A persistent study assistant alongside the reader. Generation runs on the
    // user's own LLM (BYOK) via the service; with no key it degrades to grounded
    // retrieval over the same /ask.json search endpoint. Grounding uses whatever
    // guide the reader is on.
    //
    // Each turn is { role: "user"|"assistant", text: "", sources: [] }; sources
    // are only carried on the retrieval-fallback replies.
    property var chatMessages: []
    property string chatError: ""
    // The retrieval fallback is in flight (no-key path). Combined with the
    // service's `chatting` to tell the dock the assistant is working.
    property bool _chatRetrieving: false
    property string _chatFallbackQ: ""

    readonly property bool aiReady: { var s = svc(); return !!(s && s.aiReady); }
    readonly property bool chatBusy: { var s = svc(); return (!!(s && s.chatting)) || root._chatRetrieving; }

    // The live AI config, surfaced for the settings form (read) and written back
    // through the service (which owns the file and reloads it on change).
    readonly property var aiConfig: { var s = svc(); return (s && s.aiConfig) ? s.aiConfig : ({}); }
    function saveAiConfig(obj) {
        var s = svc();
        if (s && typeof s.saveAiConfig === "function") s.saveAiConfig(obj);
    }

    // Persisted layout (sidebar widths). The view reads it once on open and
    // writes it back when a divider is dragged.
    readonly property var uiState: { var s = svc(); return (s && s.uiState) ? s.uiState : ({}); }
    function saveUiState(obj) {
        var s = svc();
        if (s && typeof s.saveUiState === "function") s.saveUiState(obj);
    }

    // Emitted whenever chatMessages is replaced, so the view can scroll to the
    // newest turn. chatMessages is reassigned wholesale (never mutated) so the
    // dock's bindings actually update.
    signal chatChanged()

    // Recents stand in for results on the empty search screen: the manual is
    // something you come back to, so "where was I" is the first question.
    property bool showingRecents: false

    // Set when a random pick was asked for before the catalog had arrived.
    property bool pendingRandom: false

    // ------------------------------------------------------------- view glue
    //
    // The diagrams the reader is currently showing. This used to live on the
    // reader itself; the controller owns it now and the view binds to it, so
    // fetching and theming stay here where the service bus is.
    property var diagrams: []

    // Surface colours the view feeds in. The overlay took these from the
    // [menu] tokens it borrowed; the panel has its own window palette, and
    // diagrams must be flattened against THAT window background (opaqueHex),
    // so the four inputs come from whoever draws the window.
    property color surfaceBackground
    property color surfaceForeground
    property color surfaceMuted
    property color surfaceDivider

    // The view shows "searching…" off this instead of reaching into the timer.
    readonly property bool searchPending: searchDebounce.running

    // View-owned reactions. The controller no longer knows which item holds
    // focus, which list carries the cursor, or which reader shows the quiz, so
    // it announces the moments the view has to respond to and lets the view do
    // the item-level work.
    signal focusRequested()
    signal phaseReady()
    signal resultsReplaced()
    signal catalogReplaced()

    // The ask row lives in resultsModel so it is navigable like any other, and
    // is told apart by a slug no guide can have.
    readonly property string askRowSlug: "\u0000ask"

    // The two navigable models. Aliased so the view can bind to
    // controller.resultsModel / controller.catalogModel — an inner id alone is
    // private to this component and would not resolve from the outside.
    readonly property alias resultsModel: _resultsModel
    readonly property alias catalogModel: _catalogModel
    ListModel { id: _resultsModel }
    ListModel { id: _catalogModel }

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
            // Home is the catalog: 27 categories, no network needed beyond
            // the one fetch. Clearing a search still shows recents, so
            // "where was I" stays one keystroke away.
            root.query = "";
            resultsModel.clear();
            root.suggestion = "";
            root.showCatalog();
        }
        // Warm the catalog so Tab is instant and the placeholder can be honest
        // about how many guides there are.
        var s = safeCall("getCatalog");
        if (s) s.getCatalog();
        // The view owns focus now; tell it we are up so it can grab the keys.
        Qt.callLater(function () { root.focusRequested(); });
    }

    function close() { root.opened = false; }

    // Tell the host we are down, so a later summon re-shows us. The panel view
    // wraps this with a plain window close; kept here so a layer-shell host
    // that still calls the controller directly keeps working.
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

    function showRecents() {
        var s = svc();
        var list = (s && s.recents) || [];
        resultsModel.clear();
        for (var i = 0; i < list.length; i++) {
            // The row opens at phase_no, so it must carry the saved phase;
            // the list already prints "· phase N" from it, so no badge.
            var ph = Number(list[i].phase);
            resultsModel.append({
                "title": list[i].title || list[i].slug,
                "summary": "",
                "badge": "",
                "guide_slug": list[i].slug,
                "phase_no": ph > 0 ? ph : 1
            });
        }
        root.showingRecents = resultsModel.count > 0;
        root.resultsReplaced();
    }

    // ------------------------------------------------------------ ask flow

    function canAsk() {
        var s = svc();
        return !root.askDisabled && s && typeof s.ask === "function";
    }

    function enterAsk(question) {
        var q = String(question || "").replace(/^\s+|\s+$/g, "");
        if (!q || !canAsk()) return;
        if (root.mode !== "ask") root.returnMode = root.mode;
        root.mode = "ask";
        root.errorMsg = "";
        root.askQuery = q;
        root.askBody = "";
        root.askNotice = "";
        root.askCached = false;
        root.askSources = [];
        root._askMode = "";
        aiFallback.stop();
        svc().ask(q, "");
    }

    function leaveAsk() {
        root.mode = root.returnMode === "ask" ? "search" : root.returnMode;
        if (root.mode === "search" && !root.query) root.showRecents();
    }

    // Sources come back as {slug, phase, url, title}; phase is a string or null.
    function _askSource(src) {
        if (!src || !src.slug) return null;
        var phase = Number(src.phase);
        return {
            "title": Markdown.plain(src.title || src.slug),
            "slug": String(src.slug),
            "phase": phase > 0 ? phase : 1,
            "url": String(src.url || "")
        };
    }

    function openAskSource(index) {
        var list = root.askSources;
        if (index < 0 || index >= list.length) return;
        root.returnMode = "search";
        root.openPhase(list[index].slug, list[index].phase, list[index].title);
    }

    // The answer, and its sources, as one markdown document: the reader already
    // draws markdown, and the answer arrives as markdown with its links
    // rewritten, so there is nothing here worth a second renderer.
    function _askDocument(answer, sources) {
        var out = String(answer || "");
        if (sources.length > 0) {
            out += "\n\n---\n\n### Sources\n\n";
            for (var i = 0; i < sources.length; i++) {
                out += (i + 1) + ". " + sources[i].title
                    + "  —  phase " + sources[i].phase + "\n";
            }
        }
        return out;
    }

    // Every shape /ask.json can return gets its own line. A spent budget is
    // not a failure, and a disabled feature is not an error to show someone.
    function applyAsk(query, data, fromCache) {
        var d = data || ({});
        if (d.enabled === false) {
            root.askDisabled = true;
            root.askNotice = "AI answers are not enabled on this host.";
            root.askBody = "";
            root.askSources = [];
            return;
        }
        root.askCached = fromCache === true || d.cached === true;
        if (d.capReached) {
            root.askNotice = "AI answers have hit this month’s limit — search still works.";
            root.askBody = "";
            root.askSources = [];
            return;
        }
        if (d.error) {
            root.askNotice = d.error === "too_long"
                ? "That question is too long — 300 characters is the limit."
                : "The answer service is unavailable right now — try search instead.";
            root.askBody = "";
            root.askSources = [];
            return;
        }

        var sources = [];
        var raw = Array.isArray(d.sources) ? d.sources : [];
        for (var i = 0; i < raw.length; i++) {
            var one = root._askSource(raw[i]);
            if (one) sources.push(one);
        }

        var body = String(d.answer || "");
        if (!body && Array.isArray(d.results)) {
            // Retrieval, not a written answer: show the passages themselves.
            for (var r = 0; r < d.results.length; r++) {
                var hit = d.results[r];
                body += "**" + Markdown.plain(hit.title || hit.slug) + "**\n\n"
                    + String(hit.text || "") + "\n\n";
            }
        }
        if (!body && sources.length === 0) {
            root.askNotice = "Nothing came back for that. Try wording it differently.";
            root.askBody = "";
            root.askSources = [];
            return;
        }
        root.askNotice = "";
        root.askSources = sources;
        root.askBody = root._askDocument(body, sources);
    }

    function openAskInBrowser() {
        var s = svc();
        var base = (s && s.apiBase) || "";
        if (!base || !root.askQuery) return;
        Quickshell.execDetached(["xdg-open", base + "/search?q=" + encodeURIComponent(root.askQuery)]);
    }

    // ------------------------------------------------------------ chat flow

    // The assistant's persona and instructions, used for EVERY provider. This
    // is the one place to edit the voice of the chat. A user can override it
    // per-machine with a "systemPrompt" string in ~/.config/tmm/ai.json; the
    // guide the reader is on is appended after it either way (see sendChat).
    readonly property string defaultSystemPrompt: `You are **Tutor**, the official AI learning companion for The Missing Manual (themissingmanual.dev).

Your purpose is to help developers deeply understand how software actually works — from fundamental concepts to advanced topics — by filling in the gaps that official documentation, tutorials, and courses often leave out.

### Core Identity & Personality
- You are a patient, encouraging, and highly competent technical tutor.
- You explain things clearly and precisely without oversimplifying or being condescending.
- You are humble: if you're unsure about something, you say so and suggest how to verify it.
- You are enthusiastic about helping people build real understanding rather than just memorizing syntax or commands.

### Teaching Philosophy (Very Important)
- Focus on **understanding**, not just answers. Always explain the "why" behind concepts.
- Prioritize fundamentals and mental models before diving into implementation details.
- Connect new concepts to things the user already knows when possible.
- Encourage active learning: ask thoughtful questions, suggest small experiments, and help users think through problems.
- Adapt your depth based on the user's apparent level (beginner → intermediate → advanced).

### Response Guidelines
- **Structure** your answers clearly using markdown:
  - Start with a short, direct answer when appropriate.
  - Use headings, bullet points, and numbered steps.
  - Include code examples when relevant (with explanations).
  - Use analogies to make abstract concepts concrete.
- Keep responses focused and reasonably concise, but thorough enough to be genuinely helpful.
- When explaining code or technical concepts, show both the "how" and the "why".
- If the topic relates to existing guides on the site, you may reference concepts from The Missing Manual naturally (without forcing it).
- End responses with a gentle prompt for the next step when it makes sense (e.g., "Would you like me to explain this with an example?" or "Do you want to go deeper into X?").

### What You Should Do
- Break down complex topics into understandable parts.
- Help users debug their mental models.
- Suggest better ways to think about problems.
- Recommend related concepts the user might be missing.
- Be supportive when users are confused or frustrated.
- Use simple diagrams (ASCII or mermaid) when they would help understanding.

### What You Must NOT Do
- Do not give overly long walls of text without structure.
- Do not assume the user knows something unless they've demonstrated it.
- Do not promote specific tools, frameworks, or products unless directly relevant to understanding a concept.
- Do not be sarcastic or overly casual in a way that could be misinterpreted.
- Do not hallucinate technical details. If something is uncertain, acknowledge it.

### Tone & Language
- Friendly but professional.
- Clear and direct.
- Use "we" when guiding ("Let's break this down...").
- Avoid corporate or overly flowery language.

You are here to help people become better, more thoughtful developers by building strong mental models of how things actually work under the hood.`

    // A non-empty "systemPrompt" in the config wins over the default.
    function _systemPrompt() {
        var s = svc();
        var override = s && s.aiConfig ? s.aiConfig.systemPrompt : "";
        return (typeof override === "string" && override.replace(/^\s+|\s+$/g, ""))
            ? override : root.defaultSystemPrompt;
    }

    function sendChat(text) {
        var q = String(text || "").replace(/^\s+|\s+$/g, "");
        if (!q || root.chatBusy) return;

        root.chatMessages = root.chatMessages.concat([{ "role": "user", "text": q, "sources": [] }]);
        root.chatError = "";
        root.chatChanged();

        // Ground the assistant in the guide the reader is on, if any.
        var ctx = "";
        if (root.mode === "reader" && root.phaseBody) {
            ctx = "GUIDE THE READER IS ON: "
                + (root.guideTitle || root.currentSlug) + " (phase " + root.currentPhase + ")\n\n"
                + String(root.phaseBody).slice(0, 6000);
        }
        // One system prompt for every provider (config override or the default),
        // with the current guide appended as context.
        var system = root._systemPrompt() + (ctx ? "\n\n---\n" + ctx : "");

        var msgs = root.chatMessages.map(function (m) {
            return { "role": m.role, "content": m.text };
        });

        if (root.aiReady) {
            var s = svc();
            if (s && typeof s.chat === "function") s.chat(system, msgs);
            else root.chatError = "The manual service is not available";
        } else {
            // No key: grounded retrieval over the free search endpoint.
            root._chatRetrieving = true;
            root._chatFallbackQ = q;
            var sr = svc();
            if (sr && typeof sr.ask === "function") sr.ask(q, "search");
            else { root._chatRetrieving = false; root.chatError = "The manual service is not available"; }
        }
    }

    // Turn a retrieval payload into an assistant message: the passages, plus
    // clickable source chips.
    function _applyChatRetrieval(query, data) {
        var d = data || ({});
        var results = Array.isArray(d.results) ? d.results : [];
        var sources = [];
        var body = "";
        if (results.length === 0) {
            body = "I couldn't find anything in the guides for that. Try wording it "
                + "differently — or add an AI key for written answers.";
        } else {
            body = "Here are the most relevant sections:\n\n";
            for (var i = 0; i < results.length && i < 4; i++) {
                var hit = results[i];
                if (!hit) continue;
                var title = Markdown.plain(hit.title || hit.slug || "Untitled");
                body += "**" + title + "**\n\n";
                var snippet = Markdown.plain(hit.text || hit.snippet || hit.excerpt || "");
                if (snippet.length > 260) snippet = snippet.slice(0, 260) + "…";
                if (snippet) body += snippet + "\n\n";
                var phase = Number(hit.phase);
                sources.push({
                    "title": title,
                    "slug": String(hit.slug || ""),
                    "phase": phase > 0 ? phase : 1
                });
            }
        }
        root.chatMessages = root.chatMessages.concat([
            { "role": "assistant", "text": body, "sources": sources }
        ]);
        root.chatChanged();
    }

    function openChatSource(slug, phase) {
        if (!slug) return;
        root.openPhase(slug, phase > 0 ? phase : 1, "");
    }

    function clearChat() {
        root.chatMessages = [];
        root.chatError = "";
        root.chatChanged();
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
        if (hit.guide_slug === root.askRowSlug) { root.enterAsk(root.query); return; }
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
        root.catalogReplaced();
    }

    // Back to search from the catalog (Tab, Esc). An empty query shows
    // recents, so the history from the old home screen is still here.
    function backToSearch() {
        root.mode = "search";
        if (!root.query) root.showRecents();
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

    // The zero-hit fallback, mirroring the site's: never per keystroke, only
    // after a pause, only when keyword search already came back empty, and
    // always on the free retrieval path.
    Timer {
        id: aiFallback
        interval: 550
        onTriggered: {
            var q = root.query.replace(/^\s+|\s+$/g, "");
            if (q.length < 3 || root.mode !== "search" || !root.canAsk()) return;
            root._askMode = "search";
            svc().ask(q, "search");
        }
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
        var bg = root.surfaceBackground;
        function part(x, y) {
            var v = Math.round(255 * (x * a + y * (1 - a)));
            v = Math.max(0, Math.min(255, v));
            return (v < 16 ? "0" : "") + v.toString(16);
        }
        return "#" + part(c.r, bg.r) + part(c.g, bg.g) + part(c.b, bg.b);
    }

    function diagramColours() {
        return {
            "fill": opaqueHex(Util.alpha(root.surfaceForeground, 0.06)),
            "stroke": opaqueHex(Color.accent),
            "text": opaqueHex(root.surfaceForeground),
            "edge": opaqueHex(root.surfaceMuted),
            "subfill": opaqueHex(Util.alpha(root.surfaceForeground, 0.03)),
            "substroke": opaqueHex(root.surfaceDivider),
            "note": opaqueHex(Util.alpha(Color.accent, 0.18)),
            "ink": opaqueHex(root.surfaceForeground),
            "line": opaqueHex(root.surfaceDivider)
        };
    }

    // A binding, not a snapshot: it reads the same theme properties
    // diagramColours() does, so switching Omarchy themes changes it by itself.
    // Diagrams left in the old palette next to a repainted panel look broken.
    readonly property string diagramTheme: JSON.stringify(diagramColours())

    onDiagramThemeChanged: {
        if (root.mode === "reader" && root.currentSlug && root.phaseBody)
            root.fetchDiagrams(root.currentSlug, root.currentPhase, root.phaseBody);
    }

    function fetchDiagrams(slug, phase, body) {
        // Keep what is on screen when only the theme changed: blanking the
        // diagrams and redrawing them a moment later reads as a glitch.
        var here = slug + "/" + phase;
        if (here !== root._diagramsFor) root.diagrams = [];
        root._diagramsFor = here;
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
            root.resultsReplaced();
            if (resultsModel.count === 0) aiFallback.restart();
            else aiFallback.stop();
        }

        function onChatDone(text) {
            root.chatMessages = root.chatMessages.concat([
                { "role": "assistant", "text": String(text || ""), "sources": [] }
            ]);
            root.chatChanged();
        }

        function onChatError(msg) {
            root.chatError = String(msg || "Something went wrong.");
        }

        function onAskDone(query, data, fromCache) {
            // The no-key chat fallback rides the same ask endpoint; claim its
            // reply here before the normal ask handling runs.
            if (root._chatRetrieving) {
                root._chatRetrieving = false;
                root._applyChatRetrieval(query, data);
                return;
            }
            if (root._askMode === "search") {
                root._askMode = "";
                root.addAskSuggestions(query, data);
                return;
            }
            if (root.mode !== "ask" || query !== root.askQuery) return;
            root.applyAsk(query, data, fromCache);
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
            // The reader's quiz state is view-owned now; the view resets it.
            root.phaseReady();
            var s = root.svc();
            if (s && typeof s.rememberPhase === "function")
                s.rememberPhase(slug, phase, root.guideTitle);
            root.fetchDiagrams(slug, phase, root.phaseBody);
        }

        function onDiagramsDone(slug, phase, diagrams) {
            // A phase the user has already paged away from must not repaint
            // the one they are reading now.
            if (slug !== root.currentSlug || phase !== root.currentPhase) return;
            root.diagrams = diagrams || [];
        }

        function onCatalogDone(catalog) {
            if (root.pendingRandom) { root.pickRandom(); return; }
            if (root.mode === "catalog") root.rebuildCatalog();
        }

        function onError(msg) { root.errorMsg = msg; }
    }

    // Retrieval rows appended under an empty keyword search. Dropped outright
    // if the query moved on while the call was in flight.
    function addAskSuggestions(query, data) {
        if (root.mode !== "search") return;
        if (query !== root.query.replace(/^\s+|\s+$/g, "")) return;
        if (resultsModel.count > 0) return;
        var d = data || ({});
        if (d.enabled === false) { root.askDisabled = true; return; }
        var rows = Array.isArray(d.results) ? d.results : [];
        if (root.canAsk()) {
            resultsModel.append({
                "title": "Ask the guides about “" + query + "”",
                "summary": "Written from the manual, with the phases it came from",
                "badge": "ask",
                "guide_slug": root.askRowSlug,
                "phase_no": 0
            });
        }
        for (var i = 0; i < rows.length && i < 3; i++) {
            var hit = rows[i];
            if (!hit || !hit.slug) continue;
            var phase = Number(hit.phase);
            resultsModel.append({
                "title": Markdown.plain(hit.title || hit.slug),
                "summary": Markdown.plain(hit.text || ""),
                "badge": "related",
                "guide_slug": String(hit.slug),
                "phase_no": phase > 0 ? phase : 1
            });
        }
        root.resultsReplaced();
    }

    function stripFrontmatter(md) {
        return String(md || "").replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
    }
}
