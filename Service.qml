import Quickshell
import Quickshell.Io
import QtQuick
import QtCore
import "Model.js" as Model

// Headless data service for tmm.manual (Omarchy v4 Quattro).
// Host injects `shell` and `manifest`. No UI: data functions only.
Item {
    id: root

    property string apiBase: "https://themissingmanual.dev"
    property string cacheDir: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/tmm"
    property int searchLimit: 8

    // Injected by host; optional at runtime.
    property var shell
    property var manifest

    signal searchDone(var result)
    signal guideDone(var guide)
    signal catalogDone(var catalog)
    signal cheatSheetDone(var sheet)
    signal phaseDone(string slug, int phase, string markdown)
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

    function search(query) {
        _searchQ = query;
        _run(searchProc, ["curl", "-fsSL",
            _url("/search.json?q=" + encodeURIComponent(query) + "&limit=" + searchLimit)]);
    }

    function getGuide(slug) {
        // Full-guide markdown is open; /api/guides/* is not public.
        // Emits guideDone({slug, markdown}).
        _guideSlug = slug;
        _run(guideProc, ["curl", "-fsSL",
            _url("/guides/" + encodeURIComponent(slug) + ".md")]);
    }

    function getCatalog() {
        // /llms.txt is open; /guides.json needs a site key (401).
        // Emits catalogDone([{title, slug, summary: category}]).
        _run(catalogProc, ["curl", "-fsSL", _url("/llms.txt")]);
    }

    function getCheatSheet() {
        _run(cheatProc, ["curl", "-fsSL", _url("/cheat-sheet.json")]);
    }

    function getPhase(slug, phase) {
        _phaseSlug = slug;
        _phaseNo = phase;
        var url = _url("/guides/" + encodeURIComponent(slug) + "/" + phase + ".md");
        var out = cacheDir + "/" + slug + "-" + phase + ".md";
        // Fetch while teeing raw markdown into the cache file.
        _run(phaseProc, ["sh", "-c",
            "mkdir -p '" + cacheDir + "' && curl -fsSL '" + url + "' | tee '" + out + "'"]);
    }

    // -- fetchers: one declarative Process per endpoint. --

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.searchDone(JSON.parse(text)); }
                catch (e) { root.error("search parse failed: " + e); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("search failed: " + root._searchQ); }
    }

    Process {
        id: guideProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) root.guideDone({ "slug": root._guideSlug, "markdown": text });
                else root.error("guide empty: " + root._guideSlug);
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("guide fetch failed: " + root._guideSlug); }
    }

    Process {
        id: catalogProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = Model.parseLlmsCatalog(text);
                    var mapped = [];
                    for (var i = 0; i < parsed.length; i++) {
                        mapped.push({ "title": parsed[i].title, "slug": parsed[i].slug,
                            "summary": parsed[i].category });
                    }
                    root.catalogDone(mapped);
                } catch (e) { root.error("catalog parse failed: " + e); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("catalog fetch failed"); }
    }

    Process {
        id: cheatProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.cheatSheetDone(JSON.parse(text)); }
                catch (e) { root.error("cheat-sheet parse failed: " + e); }
            }
        }
        stderr: StdioCollector {}
        onExited: code => { if (code !== 0) root.error("cheat sheet needs a site key; use search instead"); }
    }

    Process {
        id: phaseProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) root.phaseDone(root._phaseSlug, root._phaseNo, text);
            }
        }
        stderr: StdioCollector {}
        // Network failed: fall back to cached file.
        onExited: code => {
            if (code !== 0) {
                cacheReadProc.running = false;
                cacheReadProc.command = ["cat", root.cacheDir + "/" + root._phaseSlug + "-" + root._phaseNo + ".md"];
                cacheReadProc.running = true;
            }
        }
    }

    Process {
        id: cacheReadProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) root.phaseDone(root._phaseSlug, root._phaseNo, text);
                else root.error("phase not cached: " + root._phaseSlug + " " + root._phaseNo);
            }
        }
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0) root.error("phase fetch failed: " + root._phaseSlug + " " + root._phaseNo);
        }
    }
}
