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
    property string cacheDir: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/tmm"
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
    signal error(string msg)

    // Pending request context (each proc is single-flight).
    property string _searchQ: ""
    property string _guideSlug: ""
    property string _phaseSlug: ""
    property int _phaseNo: 0

    function _url(path) { return apiBase + path; }

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
        if (!slug || phase < 1) return;
        _phaseSlug = slug;
        _phaseNo = phase;
        loadingPhase = true;
        _phaseSettled = false;
        var url = _url("/guides/" + encodeURIComponent(slug) + "/" + phase + ".md");
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
        var url = _url("/guides/" + encodeURIComponent(slug) + "/" + phase);
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
                // Cache even an empty result: a phase whose diagrams the server
                // could not render should not be refetched on every open.
                var next = ({});
                for (var k in root.diagramCache) next[k] = root.diagramCache[k];
                next[root._diagKey] = list;
                root.diagramCache = next;
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
