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

// Interactive fences carry structured data rather than source to display.
// Anything that fails to parse falls back to a plain code block: a malformed
// quiz should still show its content, never vanish.
function _fencedBlock(lang, text) {
    var kind = String(lang || "").toLowerCase();

    if (kind === "quiz") {
        try {
            var questions = JSON.parse(text);
            if (Array.isArray(questions) && questions.length) {
                var ok = true;
                for (var i = 0; i < questions.length; i++) {
                    var q = questions[i];
                    if (!q || typeof q.q !== "string" || !Array.isArray(q.choices)
                            || typeof q.answer !== "number"
                            || q.answer < 0 || q.answer >= q.choices.length) { ok = false; break; }
                }
                if (ok) return { type: "quiz", questions: questions };
            }
        } catch (e) { /* fall through to a code block */ }
    }

    if (kind === "lesson" || kind === "exercise") {
        try {
            var lesson = JSON.parse(text);
            if (lesson && typeof lesson === "object" && !Array.isArray(lesson)
                    && (lesson.starterCode || lesson.solution)) {
                return { type: "lesson", lang: kind, lesson: lesson };
            }
        } catch (e) { /* fall through */ }
    }

    // Diagrams have a themed SVG upstream; the reader fetches and recolors it.
    if (kind === "mermaid") return { type: "diagram", kind: kind, text: text, ord: 0 };

    // Browser-only widgets. We cannot run them, but we can say what they are
    // instead of printing their JSON.
    if (kind.indexOf("playground-") === 0 || kind.indexOf("explainer-") === 0) {
        return { type: "embed", kind: kind, text: text };
    }

    return { type: "code", lang: lang || "", text: text };
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
            blocks.push(_fencedBlock(fence[2] || "", body.join("\n").replace(/\s+$/, "")));
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

    // The Nth diagram block matches the Nth baked figure in the phase HTML,
    // which is the only handle we get -- the figures carry no id.
    var ord = 0;
    for (var b = 0; b < blocks.length; b++)
        if (blocks[b].type === "diagram") blocks[b].ord = ord++;

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

// Search snippets arrive as HTML carrying <b> marks around the matched words.
// Keep those as an accent-coloured span and escape everything else.
function highlight(snippet, color) {
    var parts = String(snippet === undefined || snippet === null ? "" : snippet).split(/(<\/?b>)/i);
    var out = "", open = false;
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i];
        if (/^<b>$/i.test(p)) { open = true; continue; }
        if (/^<\/b>$/i.test(p)) { open = false; continue; }
        var text = escapeHtml(p);
        out += open ? '<font color="' + (color || "#8aa9d6") + '">' + text + "</font>" : text;
    }
    return out;
}

// ------------------------------------------------------------- code color
//
// Fenced code gets basic syntax coloring: keywords, strings, comments,
// numbers, etc. This is not a real parser -- just enough regex-driven
// tokenizing, scanned left to right, to make a snippet readable. `dark`
// picks one of two tuned palettes so it reads well on either background.
// Unknown or empty languages fall back to a generic pass. Anything that
// goes wrong, or a pathologically large block, degrades to escaped-but-
// uncolored text (still with the layout conversion below) rather than
// breaking the reader.
//
// Named `highlightCode` (not `highlight`) to avoid shadowing the existing
// `highlight(snippet, color)` above, which tints search-match spans -- a
// different job, same file.
const CODE_MAX_LEN = 20000;

function _codeLayout(html) {
    var lines = html.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var lead = /^[ \t]+/.exec(line);
        if (lead) {
            var rep = "";
            var s = lead[0];
            for (var c = 0; c < s.length; c++) {
                rep += (s.charAt(c) === "\t") ? "&nbsp;&nbsp;&nbsp;&nbsp;" : "&nbsp;";
            }
            line = rep + line.slice(s.length);
        }
        lines[i] = line.replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;");
    }
    return lines.join("<br/>");
}

function _codePalette(dark) {
    return dark ? {
        keyword: "#c792ea",
        string: "#c3e88d",
        comment: "#6b7280",
        number: "#f78c6c",
        func: "#82aaff",
        type: "#ffcb6b",
        boolNull: "#ff5370"
    } : {
        keyword: "#a626a4",
        string: "#50a14f",
        comment: "#a0a1a7",
        number: "#b76b01",
        func: "#4078f2",
        type: "#c18401",
        boolNull: "#e45649"
    };
}

function _codeFamily(lang) {
    var l = String(lang || "").toLowerCase().replace(/^\s+|\s+$/g, "");
    switch (l) {
        case "js": case "javascript": case "jsx": case "mjs": case "cjs":
        case "ts": case "typescript": case "tsx":
            return "js";
        case "python": case "py": case "py3":
            return "python";
        case "bash": case "sh": case "shell": case "zsh":
            return "bash";
        case "rust": case "rs":
            return "rust";
        case "go": case "golang":
            return "go";
        case "json": case "jsonc":
            return "json";
        case "sql":
            return "sql";
        case "yaml": case "yml":
            return "yaml";
        case "html": case "xml": case "svg":
            return "html";
        case "css": case "scss": case "less":
            return "css";
        default:
            return "generic";
    }
}

// One rule list per language family: [{name, re}], tried in priority order
// at each scan position. `re` carries the sticky ("y") flag, so a rule
// either matches exactly at the current position or is skipped -- no
// runaway forward scanning on a pathological snippet. Comments and strings
// are listed first in every family so a keyword sitting inside one is
// never re-highlighted.
function _codeRules(fam) {
    var FUNC = /\b[A-Za-z_$][\w$]*(?=\s*\()/y;
    var NUM = /\b0[xX][0-9a-fA-F]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/y;
    var BLOCK_CMT = /\/\*[\s\S]*?\*\//y;
    var LINE_CMT = /\/\/[^\n]*/y;
    var HASH_CMT = /#[^\n]*/y;
    var DASH_CMT = /--[^\n]*/y;
    var DQ = /"(?:[^"\\]|\\.)*"/y;
    var SQ = /'(?:[^'\\]|\\.)*'/y;
    var BT = /`(?:[^`\\]|\\.)*`/y;

    switch (fam) {
    case "js":
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "comment", re: LINE_CMT },
            { name: "string", re: BT },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false|null|undefined|NaN)\b/y },
            { name: "type", re: /\b(?:string|number|boolean|any|unknown|never|object|symbol|bigint|void|Array|Promise|Record|Partial|Readonly|Pick|Omit)\b/y },
            { name: "keyword", re: /\b(?:const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|class|extends|super|new|this|typeof|instanceof|in|of|try|catch|finally|throw|async|await|yield|import|export|default|from|as|static|get|set|public|private|protected|readonly|interface|type|enum|implements|namespace|declare|delete)\b/y },
            { name: "func", re: FUNC }
        ];
    case "python":
        return [
            { name: "comment", re: HASH_CMT },
            { name: "string", re: /(?:"""[\s\S]*?"""|'''[\s\S]*?''')/y },
            { name: "string", re: /[rRbBfFuU]{0,2}"(?:[^"\\]|\\.)*"/y },
            { name: "string", re: /[rRbBfFuU]{0,2}'(?:[^'\\]|\\.)*'/y },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:True|False|None)\b/y },
            { name: "type", re: /\b(?:int|str|float|bool|list|dict|tuple|set|frozenset|bytes|complex|object)\b/y },
            { name: "keyword", re: /\b(?:def|class|return|if|elif|else|for|while|break|continue|pass|import|from|as|with|try|except|finally|raise|lambda|yield|global|nonlocal|assert|del|is|not|and|or|in|async|await|self|cls)\b/y },
            { name: "func", re: FUNC }
        ];
    case "bash":
        return [
            { name: "comment", re: HASH_CMT },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false)\b/y },
            { name: "type", re: /\$\{[^}\n]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\$[0-9@#*?$!-]/y },
            { name: "keyword", re: /\b(?:if|then|elif|else|fi|for|while|until|do|done|case|esac|function|return|local|export|readonly|shift|break|continue|in|select|time|trap|source|exit|set|unset|echo)\b/y },
            { name: "func", re: FUNC }
        ];
    case "rust":
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "comment", re: LINE_CMT },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false)\b/y },
            { name: "type", re: /\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc|HashMap|HashSet|Self)\b/y },
            { name: "keyword", re: /\b(?:fn|let|mut|const|static|struct|enum|impl|trait|pub|use|mod|crate|self|super|match|if|else|for|while|loop|break|continue|return|as|where|dyn|move|ref|unsafe|async|await|in|type|extern)\b/y },
            { name: "func", re: FUNC }
        ];
    case "go":
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "comment", re: LINE_CMT },
            { name: "string", re: /`[^`]*`/y },
            { name: "string", re: DQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false|nil|iota)\b/y },
            { name: "type", re: /\b(?:string|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|uintptr|float32|float64|bool|byte|rune|error|any)\b/y },
            { name: "keyword", re: /\b(?:func|package|import|var|const|type|struct|interface|map|chan|go|defer|select|switch|case|default|if|else|for|range|return|break|continue|fallthrough|goto)\b/y },
            { name: "func", re: FUNC }
        ];
    case "json":
        return [
            { name: "type", re: /"(?:[^"\\]|\\.)*"(?=\s*:)/y },
            { name: "string", re: DQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false|null)\b/y }
        ];
    case "sql":
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "comment", re: DASH_CMT },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:NULL|null|Null|TRUE|true|True|FALSE|false|False)\b/y },
            { name: "keyword", re: /\b(?:SELECT|select|Select|FROM|from|From|WHERE|where|Where|INSERT|insert|INTO|into|VALUES|values|UPDATE|update|SET|set|DELETE|delete|CREATE|create|TABLE|table|ALTER|alter|DROP|drop|JOIN|join|INNER|inner|LEFT|left|RIGHT|right|OUTER|outer|ON|on|AS|as|AND|and|OR|or|NOT|not|IN|in|EXISTS|exists|GROUP|group|BY|by|ORDER|order|HAVING|having|LIMIT|limit|OFFSET|offset|UNION|union|ALL|all|DISTINCT|distinct|CASE|case|WHEN|when|THEN|then|ELSE|else|END|end|PRIMARY|primary|KEY|key|FOREIGN|foreign|REFERENCES|references|DEFAULT|default|CONSTRAINT|constraint|INDEX|index|VIEW|view|WITH|with)\b/y },
            { name: "func", re: FUNC }
        ];
    case "yaml":
        return [
            { name: "comment", re: HASH_CMT },
            { name: "type", re: /\b[A-Za-z0-9_.-]+(?=\s*:(?:\s|$))/y },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false|null|True|False|Null|TRUE|FALSE|NULL|yes|no|Yes|No)\b/y }
        ];
    case "html":
        return [
            { name: "comment", re: /&lt;!--[\s\S]*?--&gt;/y },
            { name: "keyword", re: /&lt;\/?[A-Za-z][\w:-]*/y },
            { name: "type", re: /\b[a-zA-Z-][\w-]*(?=\s*=)/y },
            { name: "string", re: DQ },
            { name: "string", re: SQ }
        ];
    case "css":
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: /#[0-9a-fA-F]{3,8}\b/y },
            { name: "number", re: /\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|vmin|vmax|s|ms|deg|fr)?\b/y },
            { name: "keyword", re: /!important\b/y },
            { name: "keyword", re: /@[A-Za-z-]+/y },
            { name: "type", re: /\b[a-zA-Z-]+(?=\s*:)/y },
            { name: "func", re: FUNC }
        ];
    default:
        return [
            { name: "comment", re: BLOCK_CMT },
            { name: "comment", re: LINE_CMT },
            { name: "comment", re: HASH_CMT },
            { name: "string", re: DQ },
            { name: "string", re: SQ },
            { name: "number", re: NUM },
            { name: "boolNull", re: /\b(?:true|false|null|None|True|False|nil|undefined)\b/y },
            { name: "keyword", re: /\b(?:function|return|if|else|elif|for|foreach|while|do|switch|case|break|continue|class|def|import|from|export|default|const|let|var|try|catch|finally|throw|new|public|private|static|void)\b/y },
            { name: "func", re: FUNC }
        ];
    }
}

// Scan `text` left to right, wrapping whatever a rule matches at the
// current position in a colored span; text no rule claims stays as-is
// (the reader's default text color already shows through it).
function _scanTokens(text, rules, palette) {
    var out = "";
    var i = 0, n = text.length;
    while (i < n) {
        var matched = false;
        for (var r = 0; r < rules.length; r++) {
            var re = rules[r].re;
            re.lastIndex = i;
            var m = re.exec(text);
            if (m && m[0].length > 0) {
                var color = palette[rules[r].name];
                out += color
                    ? '<span style="color:' + color + '">' + m[0] + "</span>"
                    : m[0];
                i += m[0].length;
                matched = true;
                break;
            }
        }
        if (!matched) { out += text.charAt(i); i++; }
    }
    return out;
}

// code -> RichText HTML with syntax-colored spans, for one fenced block.
// `lang` is the fence's language tag (may be ""); `dark` picks the palette
// tuned for a dark or light card background.
function highlightCode(code, lang, dark) {
    var raw = String(code === undefined || code === null ? "" : code);
    var isDark = dark !== false;

    if (raw.length > CODE_MAX_LEN) return _codeLayout(escapeHtml(raw));

    try {
        var escaped = escapeHtml(raw);
        var rules = _codeRules(_codeFamily(lang));
        var colored = rules.length ? _scanTokens(escaped, rules, _codePalette(isDark)) : escaped;
        return _codeLayout(colored);
    } catch (e) {
        return _codeLayout(escapeHtml(raw));
    }
}

// Rough reading time in minutes, floored at 1. Code counts for less than
// prose because nobody reads a shell snippet word by word.
function readingMinutes(md) {
    var blocks = parseBlocks(md);
    var words = 0;
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i];
        if (b.type === "rule" || b.type === "table") continue;
        // Answering a question is real time even though it is not prose.
        if (b.type === "quiz") { words += (b.questions.length || 0) * 100; continue; }
        if (b.type === "diagram" || b.type === "embed" || b.type === "lesson") continue;
        var n = String(b.text || "").split(/\s+/).length;
        words += (b.type === "code") ? n * 0.4 : n;
    }
    return Math.max(1, Math.round(words / 200));
}
