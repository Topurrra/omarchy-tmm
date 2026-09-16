.pragma library

// Markdown -> renderable blocks for the tmm.manual reader.
//
// The reader does not dump raw markdown into a TextArea: it parses the
// document into typed blocks and lets QML draw each one (real headings,
// real code cards, real rules). Inline spans still go through Qt rich
// text, so this file produces two things:
//
//   parseBlocks(md) -> [{type, ...}]   block structure
//   inline(text, opts) -> "<html>"     inline spans for one block
//
// No Qt imports here; everything stays a pure function so it can be
// unit-checked with plain JS.

// ----------------------------------------------------------------- inline

// Placeholder used to park code spans while the rest of the inline syntax is
// parsed. A private-use codepoint, so it cannot collide with guide text.
const SENTINEL = "\uE000";
const SENTINEL_RE = /\uE000(\d+)\uE000/g;

function escapeHtml(s) {
    return String(s === undefined || s === null ? "" : s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

// Convert inline markdown to the HTML subset Qt's rich text engine draws.
// `opts` supplies theme colors so the caller stays in charge of the palette:
//   { code: "#rrggbb", link: "#rrggbb", muted: "#rrggbb" }
function inline(text, opts) {
    var o = opts || {};
    var codeColor = o.code || "#c8a882";
    var linkColor = o.link || "#7aa6da";

    var src = String(text === undefined || text === null ? "" : text);

    // Pull code spans out first so their contents never get re-parsed as
    // emphasis. `a * b` inside backticks has to survive verbatim.
    var spans = [];
    src = src.replace(/`([^`]+)`/g, function (_, code) {
        spans.push(code);
        return SENTINEL + (spans.length - 1) + SENTINEL;
    });

    var out = escapeHtml(src);

    // Links before emphasis: URLs are full of underscores.
    out = out.replace(/\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
        function (_, label, href) {
            return '<a href="' + href + '" style="color:' + linkColor +
                '; text-decoration:none">' + label + "</a>";
        });
    // Bare autolinks: <https://...> survives escaping as &lt;https://...&gt;
    out = out.replace(/&lt;(https?:\/\/[^\s&]+)&gt;/g, function (_, href) {
        return '<a href="' + href + '" style="color:' + linkColor + '">' + href + "</a>";
    });

    out = out.replace(/~~([^~]+)~~/g, "<s>$1</s>");
    out = out.replace(/\*\*\*([^*]+)\*\*\*/g, "<b><i>$1</i></b>");
    out = out.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
    out = out.replace(/(^|[\s(])\*([^*\n]+)\*(?=$|[\s.,;:)!?])/g, "$1<i>$2</i>");
    out = out.replace(/(^|[\s(])__([^_\n]+)__(?=$|[\s.,;:)!?])/g, "$1<b>$2</b>");
    out = out.replace(/(^|[\s(])_([^_\n]+)_(?=$|[\s.,;:)!?])/g, "$1<i>$2</i>");

    // Restore code spans, now escaped and tinted.
    out = out.replace(SENTINEL_RE, function (_, i) {
        return '<font color="' + codeColor + '">' + escapeHtml(spans[Number(i)]) + "</font>";
    });

    return out;
}

// Inline markdown reduced to plain text: used for list/result summaries and
// anywhere rich text would be noise.
function plain(text) {
    return String(text === undefined || text === null ? "" : text)
        .replace(/`([^`]+)`/g, "$1")
        .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/[*_~]{1,3}/g, "")
        .replace(/\s+/g, " ")
        .replace(/^\s+|\s+$/g, "");
}

// ----------------------------------------------------------------- blocks

function _isRule(line) {
    return /^\s{0,3}(?:([-*_])\s*)(?:\1\s*){2,}$/.test(line);
}

function _tableCells(line) {
    var body = line.replace(/^\s*\|/, "").replace(/\|\s*$/, "");
    var cells = body.split("|");
    for (var i = 0; i < cells.length; i++) {
        cells[i] = cells[i].replace(/^\s+|\s+$/g, "");
    }
    return cells;
}

function _isTableDivider(line) {
    return /^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/.test(line) && line.indexOf("-") >= 0 &&
        (line.indexOf("|") >= 0);
}

// Parse a phase document into blocks the reader can draw.
//
// Block shapes:
//   {type:"heading", level, text}
//   {type:"para",    text}
//   {type:"code",    lang, text}
//   {type:"bullet",  text, ordered, marker, depth}
//   {type:"quote",   text}
//   {type:"rule"}
//   {type:"table",   header:[...], rows:[[...], ...]}
function parseBlocks(md) {
    var lines = String(md || "").replace(/\r\n?/g, "\n").split("\n");
    var blocks = [];
    var para = [];

    function flushPara() {
        if (para.length === 0) return;
        blocks.push({ type: "para", text: para.join(" ") });
        para = [];
    }

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var trimmed = line.replace(/^\s+|\s+$/g, "");

        if (trimmed === "") { flushPara(); continue; }

        // Fenced code: ``` or ~~~, closed by a matching fence or EOF.
        var fence = /^\s*(`{3,}|~{3,})\s*([A-Za-z0-9_+.#-]*)/.exec(line);
        if (fence) {
            flushPara();
            var marker = fence[1].charAt(0);
            var body = [];
            i++;
            for (; i < lines.length; i++) {
                if (new RegExp("^\\s*" + marker + "{3,}\\s*$").test(lines[i])) break;
                body.push(lines[i]);
            }
            blocks.push({
                type: "code",
                lang: fence[2] || "",
                text: body.join("\n").replace(/\s+$/, "")
            });
            continue;
        }

        if (_isRule(trimmed)) { flushPara(); blocks.push({ type: "rule" }); continue; }

        var heading = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line);
        if (heading) {
            flushPara();
            blocks.push({ type: "heading", level: heading[1].length, text: heading[2] });
            continue;
        }

        // Table: a header row followed by a |---|---| divider.
        if (trimmed.indexOf("|") >= 0 && i + 1 < lines.length && _isTableDivider(lines[i + 1])) {
            flushPara();
            var header = _tableCells(trimmed);
            var rows = [];
            i += 2;
            for (; i < lines.length; i++) {
                var rowLine = lines[i].replace(/^\s+|\s+$/g, "");
                if (rowLine === "" || rowLine.indexOf("|") < 0) { i--; break; }
                rows.push(_tableCells(rowLine));
            }
            blocks.push({ type: "table", header: header, rows: rows });
            continue;
        }

        var quote = /^\s{0,3}>\s?(.*)$/.exec(line);
        if (quote) {
            flushPara();
            var quoted = [quote[1]];
            while (i + 1 < lines.length && /^\s{0,3}>\s?/.test(lines[i + 1])) {
                quoted.push(lines[++i].replace(/^\s{0,3}>\s?/, ""));
            }
            blocks.push({ type: "quote", text: quoted.join(" ").replace(/^\s+|\s+$/g, "") });
            continue;
        }

        var bullet = /^(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$/.exec(line);
        if (bullet) {
            flushPara();
            var ordered = /\d/.test(bullet[2]);
            blocks.push({
                type: "bullet",
                ordered: ordered,
                marker: ordered ? bullet[2].replace(/[.)]$/, ".") : "•",
                depth: Math.min(2, Math.floor(bullet[1].replace(/\t/g, "  ").length / 2)),
                text: bullet[3]
            });
            continue;
        }

        para.push(trimmed);
    }

    flushPara();
    return blocks;
}

// First heading of a document, used as a fallback phase title.
function firstHeading(md) {
    var blocks = parseBlocks(md);
    for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].type === "heading") return plain(blocks[i].text);
    }
    return "";
}

// Rough reading time in minutes, floored at 1. Code counts for less than
// prose because nobody reads a shell snippet word by word.
function readingMinutes(md) {
    var blocks = parseBlocks(md);
    var words = 0;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b.type === "rule" || b.type === "table") continue;
        var n = String(b.text || "").split(/\s+/).length;
        words += (b.type === "code") ? n * 0.4 : n;
    }
    return Math.max(1, Math.round(words / 200));
}
