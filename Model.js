.pragma library

// Pure helpers for tmm.manual. No Qt imports, no side effects.
// Imported into QML as: import "Model.js" as Model
// (.pragma library top-levels are shared/exported automatically.)

const API_BASE = "https://themissingmanual.dev";

function searchUrl(q, limit = 8) {
    return API_BASE + "/search.json?q=" + encodeURIComponent(q) + "&limit=" + limit;
}

function guideJsonUrl(slug) {
    return API_BASE + "/api/guides/" + encodeURIComponent(slug);
}

function phaseMarkdownUrl(slug, phase) {
    return API_BASE + "/guides/" + encodeURIComponent(slug) + "/" + phase + ".md";
}

function catalogUrl() {
    return API_BASE + "/guides.json";
}

function cheatSheetUrl() {
    return API_BASE + "/cheat-sheet.json";
}

function offlineCorpusUrl() {
    return API_BASE + "/llms-full.txt";
}

function cacheKeyFor(slug, phase) {
    return slug + "/" + phase;
}

// Remove leading YAML frontmatter: ---\n...---\n
function stripFrontmatter(md) {
    if (!md) return md;
    return md.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
}

// Random element of an array (phases, guides, ...). undefined when empty.
function pickRandom(arr) {
    if (!arr || arr.length === 0) return undefined;
    return arr[Math.floor(Math.random() * arr.length)];
}

// Neighbor phases around currentNo. Returns {prev, next} (phase objs or null).
// Accepts both {no} (guides.json) and {phase_no} (PhaseRef) shapes.
function phaseNav(phases, currentNo) {
    var idx = -1;
    for (var i = 0; i < phases.length; i++) {
        var n = (phases[i].no !== undefined) ? phases[i].no : phases[i].phase_no;
        // eslint-disable-next-line eqeqeq
        if (n == currentNo) { idx = i; break; }
    }
    if (idx === -1) return { prev: null, next: null };
    return {
        prev: idx > 0 ? phases[idx - 1] : null,
        next: idx < phases.length - 1 ? phases[idx + 1] : null
    };
}
