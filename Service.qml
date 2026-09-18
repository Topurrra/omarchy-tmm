import Quickshell
import Quickshell.Io
import QtQuick
import QtCore
import "Model.js" as Model

// Headless data service for tmm.manual (Omarchy v4 Quattro).
// Host injects `shell` and `manifest`. No UI: data functions only.
Item {
    id: root

    property string apiBase: Quickshell.env("TMM_BASE") || "https://themissingmanual.dev"
    // StandardPaths hands back a file:// URL on current Quickshell, but every
    // consumer here is a shell command or an Image that wants a plain path --
    // left as a URL it writes the whole cache under a literal "file:" folder
    // and the reader's own "file://" prefix doubles up, so diagrams and the
    // offline cache silently break. Strip the scheme once, here.
    property string cacheDir: String(StandardPaths.writableLocation(StandardPaths.CacheLocation))
        .replace(/^file:\/\//, "") + "/tmm"
    property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
    property int searchLimit: 24
    property int recentsLimit: 12

    // Injected by host; optional at runtime.
    property var shell
    property var manifest

    // In-flight counters let the overlay show honest progress instead of a
    // status string that never clears.
    property bool searching: false
    property bool loadingPhase: false
    property bool loadingCatalog: false
    property bool asking: false

    // Cached for the session: /llms.txt is ~400 entries and never changes
    // mid-session, so the catalog opens instantly after the first fetch.
    property var catalogCache: []
    // Diagrams are extracted once per phase per session; the files themselves
    // live in the cache dir and survive restarts.
    property var diagramCache: ({})
    property string diagramDir: cacheDir + "/diagrams"
    property var recents: []

    signal searchDone(var result)
    signal guideDone(var guide)
    signal catalogDone(var catalog)
    signal cheatSheetDone(var sheet)
    // `meta` is { count, next } from the response headers: 0 means unknown.
    // A phase served from an old cache with no sidecar has no bounds.
    signal phaseDone(string slug, int phase, string markdown, bool fromCache, var meta)
    // [{ path, w, h }] in document order, matching the Nth ```mermaid fence.
    signal diagramsDone(string slug, int phase, var diagrams)
    // The /ask.json payload, verbatim. The overlay reads its shape rather than
    // this file flattening it into something lossy.
    signal askDone(string query, var data, bool fromCache)
    signal error(string msg)

    // Pending request context (each proc is single-flight).
    property string _searchQ: ""
    property string _guideSlug: ""
    property string _phaseSlug: ""
    property int _phaseNo: 0

    function _url(path) { return apiBase + path; }

    // Percent-encode for a URL that will be interpolated into a single-quoted
    // shell word. encodeURIComponent leaves ! ' ( ) * alone, and an apostrophe
    // -- "what's a deadlock" -- would end the quoting. Escaping them here means
    // the command never contains a quote character to escape.
    function _urlArg(value) {
        return encodeURIComponent(String(value === undefined || value === null ? "" : value))
            .replace(/[!'()*]/g, function (c) {
                return "%" + c.charCodeAt(0).toString(16).toUpperCase();
            });
    }

    // Restart a proc with a new command (kills any in-flight request).
    function _run(proc, cmd) {
        proc.running = false;
        proc.command = cmd;
        proc.running = true;
    }

    // Public URL of a phase, for "open in browser".
    function webUrl(slug, phase) {
        if (!slug) return apiBase;
        return _url("/guides/" + encodeURIComponent(slug) + (phase > 0 ? "/" + phase : ""));
    }

    function search(query) {
        if (!query) { root.searchDone({ hits: [], suggestion: "" }); return; }
        _searchQ = query;
        searching = true;
        _run(searchProc, ["curl", "-fsSL", "--max-time", "15",
            _url("/search.json?q=" + encodeURIComponent(query) + "&limit=" + searchLimit)]);
    }

    function getGuide(slug) {
        // Full-guide markdown is open; /api/guides/* is not public.
        // Emits guideDone({slug, markdown}).
        _guideSlug = slug;
        _run(guideProc, ["curl", "-fsSL", "--max-time", "20",
            _url("/guides/" + encodeURIComponent(slug) + ".md")]);
    }

    function getCatalog() {
        // /llms.txt is open; /guides.json needs a site key (401).
        // Emits catalogDone([{title, slug, summary: category}]).
        if (catalogCache.length > 0) { root.catalogDone(catalogCache); return; }
        loadingCatalog = true;
        _run(catalogProc, ["curl", "-fsSL", "--max-time", "20", _url("/llms.txt")]);
    }

    function getCheatSheet() {
        _run(cheatProc, ["curl", "-fsSL", _url("/cheat-sheet.json")]);
    }

    // Body and headers come back in one stream, split by a record separator:
    // the phase-bounds headers are the only way to know a guide has ended, and
    // a second Process to read them would race the first.
    readonly property string _rs: "\u001e"

    function _phaseBase(slug, phase) { return cacheDir + "/" + slug + "-" + phase; }

    function getPhase(slug, phase) {
        // The slug reaches a shell both as a URL and as a cache filename, so it
        // is checked once here rather than escaped in three places. Catalog
        // slugs are URL-safe by construction; that is the server's invariant.
        if (!slug || phase < 1 || !/^[A-Za-z0-9._-]+$/.test(slug)) return;
        _phaseSlug = slug;
        _phaseNo = phase;
        loadingPhase = true;
        _phaseSettled = false;
        var url = _url("/guides/" + _urlArg(slug) + "/" + phase + ".md");
        var base = _phaseBase(slug, phase);
        // Drop the old sidecar first: curl leaves it untouched on a failed
        // fetch, and stale bounds are worse than none.
        _run(phaseProc, ["sh", "-c",
            "mkdir -p '" + cacheDir + "' && rm -f '" + base + ".hdr' && "
            + "curl -fsSL -D '" + base + ".hdr' --max-time 20 '" + url + "' | tee '" + base + ".md'"
            + "; printf '\\036'; cat '" + base + ".hdr' 2>/dev/null"]);
    }

    // x-phase-count / x-next-phase, set by the site for exactly this: the
    // absence of x-next-phase is the "no next phase" signal. Later header
    // blocks win, so a redirect reports its final response.
    function _parseMeta(headers) {
        var meta = { "count": 0, "next": 0 };
        var lines = String(headers || "").split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var c = /^x-phase-count:\s*(\d+)/i.exec(lines[i]);
            if (c) { meta.count = Number(c[1]); continue; }
            var n = /^x-next-phase:\s*(\d+)/i.exec(lines[i]);
            if (n) meta.next = Number(n[1]);
            // A fresh header block means a new response: forget the last next.
            else if (/^HTTP\//i.test(lines[i])) meta.next = 0;
        }
        return meta;
    }

    // Split one stream into [body, headers].
    function _splitPhase(text) {
        var raw = String(text || "");
        var at = raw.lastIndexOf(root._rs);
        if (at < 0) return [raw, ""];
        return [raw.substring(0, at), raw.substring(at + 1)];
    }

    // ------------------------------------------------------------ diagrams
    //
    // The site bakes every ```mermaid fence to SVG with sentinel colours its
    // own CSS remaps. bin/tmm-diagrams pulls those figures out of the phase
    // HTML and swaps the sentinels for the theme we hand it, writing one file
    // per diagram -- QML's Image cannot load a data: URI, so a file it is.

    property string _diagSlug: ""
    property int _diagPhase: 0
    property string _diagKey: ""

    function _scriptPath(name) {
        // Resolve a sibling script inside the plugin directory.
        return String(Qt.resolvedUrl("bin/" + name)).replace(/^file:\/\//, "");
    }

    // Short, stable fingerprint of a colour set. Not a checksum -- it only has
    // to change when the theme does, and name a file.
    function _themeKey(colours) {
        var names = Object.keys(colours).sort();
        var flat = "";
        for (var i = 0; i < names.length; i++) flat += names[i] + colours[names[i]];
        var h = 5381;
        for (var c = 0; c < flat.length; c++) h = ((h * 33) ^ flat.charCodeAt(c)) >>> 0;
        return h.toString(36);
    }

    // Phases whose HTML we already pulled this session. A re-theme re-runs the
    // extractor over the cached copy rather than fetching the page again.
    property var _htmlSeen: ({})

    function getDiagrams(slug, phase, colours) {
        // The command goes through `sh -c`, so the slug is interpolated into a
        // quoted string. Catalog slugs are URL-safe by construction, but that
        // is the server's invariant, not ours.
        if (!slug || phase < 1 || !/^[A-Za-z0-9._-]+$/.test(slug)) return;
        var fp = _themeKey(colours || ({}));
        var key = slug + "/" + phase + "/" + fp;
        if (diagramCache[key]) { root.diagramsDone(slug, phase, diagramCache[key]); return; }

        _diagSlug = slug; _diagPhase = phase; _diagKey = key;
        var args = "";
        for (var name in colours) {
            var value = String(colours[name]);
            if (/^#[0-9A-Fa-f]{3,8}$/.test(value)) args += " --colour " + name + "=" + value;
        }
        var stem = slug + "-" + phase;
        var html = cacheDir + "/" + stem + ".html";
        var url = _url("/guides/" + _urlArg(slug) + "/" + phase);
        // Switching themes must not cost a round trip, so the page is teed on
        // the first fetch and read back for every re-theme after it. The -s
        // test matters: a failed first fetch leaves an empty file behind, and
        // re-theming off that would show nothing forever.
        var fetch = "mkdir -p '" + cacheDir + "' && curl -fsSL --max-time 20 '" + url
            + "' | tee '" + html + "'";
        var source = _htmlSeen[stem]
            ? "if [ -s '" + html + "' ]; then cat '" + html + "'; else " + fetch + "; fi"
            : fetch;
        _htmlSeen[stem] = true;
        _run(diagramProc, ["sh", "-c",
            source + " | '" + _scriptPath("tmm-diagrams")
            + "' '" + diagramDir + "' '" + stem + "-" + fp + "'"
            + " --prune '" + stem + "-'" + args]);
    }

    Process {
        id: diagramProc
        stdout: StdioCollector {
            onStreamFinished: {
                var list = [];
                var lines = String(text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    var parts = lines[i].split("\t");
                    if (!parts[0]) continue;
                    list.push({
                        "path": parts[0],
                        "w": Number(parts[1]) || 0,
                        "h": Number(parts[2]) || 0
                    });
                }
                // Only a non-empty result is cached. An empty one is usually
                // transient -- a theme switch fired while the first fetch was
                // still writing the page and single-flight killed it mid-stream,
                // yielding zero figures -- and caching that would strand the
                // diagram on its fallback card for the rest of the session.
                // Re-extracting a genuinely diagram-less phase is cheap (the
                // page is already on disk), so letting it retry costs nothing.
                if (list.length > 0) {
                    var next = ({});
                    for (var k in root.diagramCache) next[k] = root.diagramCache[k];
                    next[root._diagKey] = list;
                    root.diagramCache = next;
                }
                root.diagramsDone(root._diagSlug, root._diagPhase, list);
            }
        }
        stderr: StdioCollector {}
        // A failure here is not worth an error banner: the reader falls back to
        // a card naming the diagram, which is what it shows while loading too.
        onExited: code => {
            if (code !== 0) root.diagramsDone(root._diagSlug, root._diagPhase, []);
        }
    }

    // ---------------------------------------------------------------- ask
    //
    // GET /ask.json?q=... is public: no key, no cookie, which is the only thing
    // curl can do. The site's own rule (aiFallback.js) is that AI is never
    // called from typeahead -- the generated answer is an explicit action, and
    // the zero-hit path uses ?mode=search, which is free. That rule is about a
    // budget this plugin shares, so it is kept here rather than reinvented.
    //
    // Answers are cached on disk as well: asking the same thing twice should
    // not spend the budget twice, and a re-read is instant.

    property string askDir: cacheDir + "/ask"
    property string _askQ: ""
    property string _askFile: ""

    // Names a cache file. Not a checksum -- it only has to not collide, and
    // QML has no crypto.
    function _askKey(query, mode) {
        var flat = String(mode || "") + "\u0000" + String(query || "");
        var h = 5381;
        for (var i = 0; i < flat.length; i++) h = ((h * 33) ^ flat.charCodeAt(i)) >>> 0;
        return h.toString(36);
    }

    function askCacheKey(query, mode) {
        return _askKey(_normaliseAsk(query), mode);
    }

    function _normaliseAsk(query) {
        return String(query || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "").toLowerCase();
    }

    // mode: "" for a generated answer (paid), "search" for retrieval (free).
    function ask(query, mode) {
        var q = String(query || "").replace(/^\s+|\s+$/g, "");
        if (!q) return;
        // The endpoint rejects anything longer; say so before spending a call.
        if (q.length > 300) { root.askDone(q, { "enabled": true, "error": "too_long" }, false); return; }

        _askQ = q;
        _askFile = askDir + "/" + _askKey(_normaliseAsk(q), mode) + ".json";
        asking = true;
        var url = _url("/ask.json?q=" + _urlArg(q) + (mode === "search" ? "&mode=search" : ""));
        // Read the cached answer if we have one, otherwise fetch and keep it.
        // The leading flag says which happened, so the panel can be honest
        // about showing you something it did not just ask for.
        _run(askProc, ["sh", "-c",
            "if [ -s '" + _askFile + "' ]; then printf 'c\\036'; cat '" + _askFile + "'; else "
            + "printf 'n\\036'; mkdir -p '" + askDir + "' && curl -fsSL --max-time 25 '" + url + "'"
            + " | tee '" + _askFile + "'; fi"]);
    }

    function clearAskCache() { Quickshell.execDetached(["sh", "-c", "rm -rf '" + askDir + "'"]); }

    Process {
        id: askProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.asking = false;
                var raw = String(text || "");
                var at = raw.indexOf(root._rs);
                var cached = at >= 0 && raw.substring(0, at) === "c";
                var body = at >= 0 ? raw.substring(at + 1) : raw;
                if (body.length === 0) {
                    root.askDone(root._askQ, { "enabled": true, "error": "network" }, false);
                    return;
                }
                try {
                    root.askDone(root._askQ, JSON.parse(body), cached);
                } catch (e) {
                    // A half-written cache file would poison every later ask.
                    Quickshell.execDetached(["rm", "-f", root._askFile]);
                    root.askDone(root._askQ, { "enabled": true, "error": "network" }, false);
                }
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0 && root.asking) {
                root.asking = false;
                root.askDone(root._askQ, { "enabled": true, "error": "network" }, false);
            }
        }
    }

    // ---------------------------------------------------------- AI chat (BYOK)
    //
    // Bring-your-own-key: generation runs on the USER's own LLM, configured in
    // ~/.config/tmm/ai.json. With no key the Controller degrades to grounded
    // retrieval and never calls this. The request is built as a curl ARGV array
    // -- never `sh -c` -- so the key and the JSON body are literal argv words:
    // nothing is interpolated into a shell string, so there is no injection and
    // no escaping to get wrong.

    // { provider, baseUrl, apiKey, model, maxTokens }
    property var aiConfig: ({})
    property bool chatting: false
    // Remembered across the request so the response is parsed for the right
    // provider even if the config file changes mid-flight.
    property string _chatProvider: ""

    signal chatDone(string text)
    signal chatError(string msg)

    function _parseAiConfig(raw) {
        try {
            var c = JSON.parse(raw || "{}");
            root.aiConfig = (c && typeof c === "object" && !Array.isArray(c)) ? c : ({});
        } catch (e) {
            root.aiConfig = ({});
        }
    }

    function _aiKey() {
        return (root.aiConfig && root.aiConfig.apiKey) || Quickshell.env("TMM_AI_KEY") || "";
    }

    // The CLI providers are subscription-backed (a local agent CLI you already
    // signed into), so they need no API key -- just the binary. Everything else
    // needs a key.
    function _isCliProvider(p) {
        return p === "claude-cli" || p === "codex" || p === "cursor" || p === "opencode";
    }
    readonly property bool aiReady: _isCliProvider(aiConfig.provider)
        ? true : !!(_aiKey() && aiConfig.model && aiConfig.provider)

    FileView {
        id: aiConfigFile
        path: Quickshell.env("HOME") + "/.config/tmm/ai.json"
        watchChanges: true
        printErrors: false
        onLoaded: root._parseAiConfig(text())
        onLoadFailed: root.aiConfig = ({})
        // watchChanges only fires this signal; it does not reload on its own.
        // Reloading here is what makes ai.json hot-reload -- an external edit or
        // a write from the settings form both land in aiConfig without a restart.
        onFileChanged: aiConfigFile.reload()
    }

    readonly property string aiConfigPath: aiConfigFile.path
    signal aiConfigSaved()
    signal aiConfigSaveError(string msg)

    // Write ai.json from the settings form. The JSON is pretty-printed and
    // passed as an argv word ($0) -- never interpolated into the shell -- so a
    // key or a system prompt with any characters in it can never break out.
    // The watching FileView above reloads aiConfig on its own once written.
    function saveAiConfig(obj) {
        var json;
        try { json = JSON.stringify(obj || ({}), null, 2) + "\n"; }
        catch (e) { root.aiConfigSaveError("Could not encode the settings."); return; }
        var cmd = "d=$(dirname \"$1\"); mkdir -p \"$d\" && printf '%s' \"$0\" > \"$1\"";
        _run(aiWriteProc, ["sh", "-c", cmd, json, aiConfigFile.path]);
    }

    Process {
        id: aiWriteProc
        onExited: code => {
            if (code === 0) root.aiConfigSaved();
            else root.aiConfigSaveError("Could not write " + aiConfigFile.path + ".");
        }
    }

    // provider-agnostic. `system` is a string; `messages` a JS array of
    // { role: "user"|"assistant", content: "..." }.
    function chat(system, messages) {
        if (!root.aiReady) { root.chatError("No AI key configured."); return; }
        var cfg = root.aiConfig || ({});
        var key = _aiKey();
        var provider = String(cfg.provider || "");
        var model = String(cfg.model || "");
        var effort = String(cfg.effort || "");
        var maxTokens = Number(cfg.maxTokens) > 0 ? Number(cfg.maxTokens) : 1024;
        var msgs = Array.isArray(messages) ? messages : [];
        var argv, body, url;

        if (_isCliProvider(provider)) {
            // Subscription-backed: pipe the whole conversation to a local agent
            // CLI (Claude Code / OpenAI Codex / Cursor / opencode) in its
            // read-only, no-edit mode, run in an empty scratch dir, so the chat
            // can only ever produce text -- it can't touch the machine. The
            // prompt goes in on stdin as $0 (never interpolated); model is $1
            // and effort $2 (each provider uses whichever flags it supports).
            var bin = String(cfg.bin || (provider === "codex" ? "codex"
                : provider === "cursor" ? "cursor-agent"
                : provider === "opencode" ? "opencode" : "claude"));
            var blob = String(system || "") + "\n\n";
            for (var mi = 0; mi < msgs.length; mi++) {
                blob += (msgs[mi].role === "assistant" ? "ASSISTANT: " : "USER: ")
                    + String(msgs[mi].content || "") + "\n\n";
            }
            blob += "ASSISTANT:";

            var scratch = cacheDir + "/ai-scratch";
            var pre = "mkdir -p '" + scratch + "' 2>/dev/null; cd '" + scratch + "' 2>/dev/null; ";
            var mopt = model ? " " + (provider === "opencode" ? "-m" : "--model") + " \"$1\"" : "";
            var cliCmd;
            if (provider === "codex") {
                // Clean final answer is written to a file, then catted to stdout;
                // the agent's own reasoning/exec chatter goes to /dev/null.
                var eopt = effort ? " -c model_reasoning_effort=\"$2\"" : "";
                cliCmd = pre + "F=\"" + scratch + "/codex.out\"; rm -f \"$F\"; "
                    + "printf '%s' \"$0\" | timeout 150 '" + bin
                    + "' exec --sandbox read-only --skip-git-repo-check" + mopt + eopt
                    + " --output-last-message \"$F\" - >/dev/null 2>&1; "
                    + "cat \"$F\" 2>/dev/null; rm -f \"$F\"";
            } else if (provider === "cursor") {
                cliCmd = pre + "printf '%s' \"$0\" | timeout 150 '" + bin
                    + "' -p --output-format text --mode ask --trust" + mopt + " 2>/dev/null";
            } else if (provider === "opencode") {
                // opencode streams JSONL; a tiny helper pulls out the answer text.
                cliCmd = pre + "printf '%s' \"$0\" | timeout 150 '" + bin
                    + "' run --format json" + mopt + " 2>/dev/null | '"
                    + _scriptPath("tmm-cli-extract") + "'";
            } else { // claude-cli
                cliCmd = pre + "printf '%s' \"$0\" | timeout 150 '" + bin
                    + "' -p --output-format text" + mopt
                    + " --disallowed-tools Bash Read Write Edit MultiEdit NotebookEdit "
                    + "WebFetch WebSearch Glob Grep Task TodoWrite";
            }
            root._chatProvider = "cli";
            root.chatting = true;
            _run(chatProc, ["sh", "-c", cliCmd, blob, model, effort]);
            return;
        }

        if (provider === "anthropic") {
            url = (cfg.baseUrl || "https://api.anthropic.com") + "/v1/messages";
            var abody = {
                "model": model, "max_tokens": maxTokens,
                "system": String(system || ""), "messages": msgs
            };
            if (effort) abody.output_config = { "effort": effort };
            body = JSON.stringify(abody);
            argv = ["curl", "-sS", "--max-time", "90", "-X", "POST", url,
                "-H", "x-api-key: " + key,
                "-H", "anthropic-version: 2023-06-01",
                "-H", "content-type: application/json",
                "-d", body];
            root._chatProvider = "anthropic";
        } else {
            // OpenAI-compatible: OpenAI, OpenRouter, Groq, Ollama, LM Studio, …
            var base = String(cfg.baseUrl || "");
            if (!base) {
                root.chatError("No AI endpoint configured — set baseUrl for an OpenAI-compatible provider.");
                return;
            }
            url = /\/chat\/completions$/.test(base) ? base : base.replace(/\/$/, "") + "/chat/completions";
            var full = [{ "role": "system", "content": String(system || "") }].concat(msgs);
            var obody = { "model": model, "max_tokens": maxTokens, "messages": full };
            if (effort) obody.reasoning_effort = effort;
            body = JSON.stringify(obody);
            argv = ["curl", "-sS", "--max-time", "90", "-X", "POST", url,
                "-H", "Authorization: Bearer " + key,
                "-H", "content-type: application/json",
                "-d", body];
            root._chatProvider = "openai";
        }

        root.chatting = true;
        _run(chatProc, argv);
    }

    Process {
        id: chatProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.chatting = false;
                var raw = String(text || "");
                // The CLI providers return plain text, not JSON.
                if (root._chatProvider === "cli") {
                    var ans = raw.replace(/^\s+|\s+$/g, "");
                    if (!ans) {
                        root.chatError("The AI CLI returned nothing — check that it's installed, on PATH, and signed in.");
                        return;
                    }
                    root.chatDone(ans);
                    return;
                }
                if (raw.length === 0) {
                    root.chatError("Could not read the model's reply — check the config and key.");
                    return;
                }
                var d;
                try { d = JSON.parse(raw); }
                catch (e) {
                    root.chatError("Could not read the model's reply — check the config and key.");
                    return;
                }
                if (!d || typeof d !== "object") {
                    root.chatError("Could not read the model's reply — check the config and key.");
                    return;
                }

                if (root._chatProvider === "anthropic") {
                    if (d.type === "error" || d.error) {
                        var em = d.error && (d.error.message || d.error.type);
                        root.chatError(String(em || "The AI request was rejected."));
                        return;
                    }
                    if (d.stop_reason === "refusal") {
                        root.chatError("The model declined to answer that.");
                        return;
                    }
                    var out = "";
                    var parts = Array.isArray(d.content) ? d.content : [];
                    for (var i = 0; i < parts.length; i++) {
                        if (parts[i] && parts[i].type === "text") out += String(parts[i].text || "");
                    }
                    if (!out) {
                        root.chatError("Could not read the model's reply — check the config and key.");
                        return;
                    }
                    root.chatDone(out);
                } else {
                    if (d.error) { root.chatError(String(d.error.message || d.error)); return; }
                    var choices = Array.isArray(d.choices) ? d.choices : [];
                    var content = (choices.length > 0 && choices[0] && choices[0].message)
                        ? choices[0].message.content : "";
                    var otext = String(content || "");
                    if (!otext) {
                        root.chatError("Could not read the model's reply — check the config and key.");
                        return;
                    }
                    root.chatDone(otext);
                }
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0 && root.chatting) {
                root.chatting = false;
                root.chatError(root._chatProvider === "cli"
                    ? "The AI CLI didn't run — check that it's installed and on PATH, or set \"bin\" to its full path in ai.json."
                    : "The AI request failed — check your connection and endpoint.");
            }
        }
    }

    // ------------------------------------------------------------- recents
    //
    // Reopening what you were last reading is the single most-used path in a
    // manual, so the last few phases are kept in ~/.local/state/omarchy/ and
    // shown on the empty search screen.

    function rememberPhase(slug, phase, title) {
        if (!slug || phase < 1) return;
        var next = [{ slug: slug, phase: phase, title: title || slug, at: Date.now() }];
        for (var i = 0; i < recents.length; i++) {
            var r = recents[i];
            if (r.slug === slug && r.phase === phase) continue;
            next.push(r);
            if (next.length >= recentsLimit) break;
        }
        recents = next;
        recentsFile.setText(JSON.stringify(next));
    }

    function clearRecents() {
        recents = [];
        recentsFile.setText("[]");
    }

    function _loadRecents(raw) {
        try {
            var parsed = JSON.parse(raw || "[]");
            recents = Array.isArray(parsed) ? parsed.slice(0, recentsLimit) : [];
        } catch (e) {
            recents = [];
        }
    }

    // The state dir exists on a normal Omarchy install, but a first write
    // must not be the thing that discovers otherwise.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

    FileView {
        id: recentsFile
        path: root.stateDir + "/tmm-recents.json"
        watchChanges: false
        printErrors: false
        atomicWrites: true
        onLoaded: root._loadRecents(text())
        onLoadFailed: root.recents = []
    }

    // -------------------------------------------------------------- ui state
    //
    // Sidebar widths the user has dragged, kept beside recents so the layout
    // comes back the way they left it. View state, but persisted here with the
    // rest of the state files so the view needs no file machinery of its own.
    property var uiState: ({})

    function saveUiState(obj) {
        root.uiState = (obj && typeof obj === "object" && !Array.isArray(obj)) ? obj : ({});
        uiStateFile.setText(JSON.stringify(root.uiState));
    }

    function _loadUiState(raw) {
        try {
            var p = JSON.parse(raw || "{}");
            root.uiState = (p && typeof p === "object" && !Array.isArray(p)) ? p : ({});
        } catch (e) {
            root.uiState = ({});
        }
    }

    FileView {
        id: uiStateFile
        path: root.stateDir + "/tmm-ui.json"
        watchChanges: false
        printErrors: false
        atomicWrites: true
        onLoaded: root._loadUiState(text())
        onLoadFailed: root.uiState = ({})
    }

    // -- fetchers: one declarative Process per endpoint. --

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                try { root.searchDone(JSON.parse(text)); }
                catch (e) { root.error("Could not read the search response"); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.searching = false;
            if (code !== 0) root.error("Search failed — check your connection");
        }
    }

    Process {
        id: guideProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) root.guideDone({ "slug": root._guideSlug, "markdown": text });
                else root.error("That guide came back empty");
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("Could not load " + root._guideSlug); }
    }

    Process {
        id: catalogProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingCatalog = false;
                try {
                    var parsed = Model.parseLlmsCatalog(text);
                    var mapped = [];
                    for (var i = 0; i < parsed.length; i++) {
                        mapped.push({ "title": parsed[i].title, "slug": parsed[i].slug,
                            "summary": parsed[i].category });
                    }
                    root.catalogCache = mapped;
                    root.catalogDone(mapped);
                } catch (e) { root.error("Could not read the catalog"); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.loadingCatalog = false;
            if (code !== 0) root.error("Could not load the catalog — check your connection");
        }
    }

    Process {
        id: cheatProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.cheatSheetDone(JSON.parse(text)); }
                catch (e) { root.error("Could not read the cheat sheet"); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("The cheat sheet needs a site key; try search instead"); }
    }

    // Read the cached copy of the pending phase. Used when the network call
    // fails outright and when it succeeds with an empty body. Both the stream
    // and the exit code can reach here for the same request, so it is guarded:
    // reading twice would deliver the phase twice.
    property bool _phaseSettled: false

    function _readCachedPhase() {
        if (root._phaseSettled) return;
        root._phaseSettled = true;
        var base = _phaseBase(root._phaseSlug, root._phaseNo);
        cacheReadProc.running = false;
        cacheReadProc.command = ["sh", "-c",
            "cat '" + base + ".md' 2>/dev/null; printf '\\036'; cat '" + base + ".hdr' 2>/dev/null"];
        cacheReadProc.running = true;
    }

    Process {
        id: phaseProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = root._splitPhase(text);
                if (parts[0].length > 0) {
                    root._phaseSettled = true;
                    root.loadingPhase = false;
                    root.phaseDone(root._phaseSlug, root._phaseNo, parts[0], false,
                                   root._parseMeta(parts[1]));
                } else {
                    // Exit code 0 with no body still leaves the reader empty,
                    // so treat it exactly like a failed fetch.
                    root._readCachedPhase();
                }
            }
        }
        stderr: StdioCollector {}
        // Network failed: fall back to cached file.
        onExited: code => { if (code !== 0) root._readCachedPhase(); }
    }

    Process {
        id: cacheReadProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingPhase = false;
                var parts = root._splitPhase(text);
                if (parts[0].length > 0)
                    root.phaseDone(root._phaseSlug, root._phaseNo, parts[0], true,
                                   root._parseMeta(parts[1]));
                else root.error("Phase " + root._phaseNo + " is not available offline");
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.loadingPhase = false;
            if (code !== 0) root.error("Could not load phase " + root._phaseNo + " of " + root._phaseSlug);
        }
    }
}
