<p align="center">
  <img src="logo.png" alt="The Missing Manual" width="96" height="96">
  <h1 align="center">The Missing Manual for Omarchy</h1>
  <p align="center">Search, browse and read developer guides without leaving your desktop.</p>
  <p align="center">
    <a href="https://themissingmanual.dev"><img src="https://img.shields.io/badge/docs-themissingmanual.dev-blue?style=flat-square" alt="docs"></a>
    <img src="https://img.shields.io/badge/omarchy-v4%20Quattro-purple?style=flat-square" alt="omarchy v4">
    <img src="https://img.shields.io/badge/version-0.2.0-green?style=flat-square" alt="version">
    <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" alt="license">
  </p>
</p>

---

**tmm.manual** brings [The Missing Manual](https://themissingmanual.dev) into Omarchy as a native v4 Quattro plugin: a keyboard-first overlay reader backed by a headless search service, plus a CLI that renders the same guides in your terminal.

Upstream library: 367 guides, 1,575 phases, 27 categories — from Git and operating systems to networks, databases, security, DevOps, programming languages, math, logic and physics. This plugin only reads from it. It never uploads anything.

## It looks like your desktop

The overlay takes every color, font, radius and spacing value from the theme you are running. There is not a single hardcoded color in it.

- Surfaces use the `[menu]` theme tokens (`Color.menu.background`, `Color.menu.selectedText`, …), the same ones the Omarchy menu, clipboard and emoji pickers use — so a theme that styles those styles this too.
- Corner radius follows Hyprland's `decoration:rounding`; spacing and type scale follow `[font]` and `[spacing]` in `shell.toml`, including `omarchy display text size`.
- It is a real layer-shell overlay with exclusive keyboard focus, like every other summoned Omarchy surface.

Switch themes and the reader repaints with the desktop.

## Features

- **Live search** as you type, with typo tolerance and a "did you mean" you can accept with `Shift+Enter`
- **A real reader, not a text dump** — headings, lists, block quotes, tables and rules are drawn as themed QML; code lands in bordered cards you click to copy
- **Keyboard-first throughout** — arrows, `Enter`, `Tab`, `n`/`p`, `g`/`G`; the mouse is optional everywhere
- **Recents** on the empty search screen, shared between the overlay and the CLI, so "where was I" is one keystroke
- **Phase navigation** with a reading-progress hairline and an estimated reading time
- **Catalog browser** with instant local filtering (the catalog is fetched once per session)
- **Offline fallback** — a phase you have read before still opens with no network, and says so
- **A CLI that matches** — `tmm read` renders the same markdown with ANSI styling

## Requirements

| Need | Notes |
|------|-------|
| Omarchy v4 Quattro | Uses the QML `overlay` + `service` plugin kinds and the `qs.Commons` / `qs.Ui` theme modules. Not compatible with v3 Walker |
| `omarchy-shell` | Hosts the overlay and service |
| `curl` | All network calls go through it |
| `wl-copy` (optional) | Click-to-copy on code blocks and `y` in the reader |
| `python3` (optional) | Pretty CLI output and terminal markdown rendering. Raw output is the fallback |
| `less` or `$PAGER` (optional) | Used by `tmm open` |

## Install

### Option A: plugin manager

```bash
omarchy plugin add https://github.com/Topurrra/omarchy-tmm --enable
omarchy-shell shell rescanPlugins
```

### Option B: manual install

Copy every QML and JS file plus `logo.png` — the overlay loads `Reader.qml`, `ResultList.qml`, `Markdown.js` and the logo as siblings.

```bash
mkdir -p ~/.config/omarchy/plugins/tmm.manual
cp manifest.json Overlay.qml Reader.qml ResultList.qml Service.qml Model.js Markdown.js logo.png \
   ~/.config/omarchy/plugins/tmm.manual/
cp bin/tmm ~/.local/bin/tmm && chmod +x ~/.local/bin/tmm
omarchy-shell shell rescanPlugins
```

### Option C: menu + keybindings (recommended)

```bash
# Menu entries
mkdir -p ~/.config/omarchy/extensions
cp extensions/omarchy-menu.jsonc ~/.config/omarchy/extensions/omarchy-menu.jsonc
omarchy menu refresh

# Keybindings
cat bindings.lua.fragment >> ~/.config/hypr/bindings.lua
```

See [INSTALL.md](INSTALL.md) for the short checklist and troubleshooting.

## Usage

Open it with `SUPER + ALT + M`, or from a terminal:

```bash
omarchy-shell shell toggle tmm.manual
omarchy-shell shell summon tmm.manual
```

The overlay accepts an optional JSON payload:

```bash
omarchy-shell shell summon tmm.manual '{"query":"git rebase"}'        # open on a search
omarchy-shell shell summon tmm.manual '{"slug":"git-from-zero","phase":2}'  # exact phase
omarchy-shell shell summon tmm.manual '{"catalog":true}'              # browse everything
omarchy-shell shell summon tmm.manual '{"random":true}'               # surprise me
```

### Keys

Typing always goes to the filter — there is no field to click into first.

**Search**

| Key | Action |
|-----|--------|
| *any character* | Search as you type |
| `↑` `↓` / `Ctrl+N` `Ctrl+P` | Move the cursor |
| `PgUp` `PgDn` `Home` `End` | Jump |
| `Enter` | Open the highlighted hit |
| `Shift+Enter` | Accept the "did you mean" suggestion |
| `Tab` | Browse the catalog |
| `Ctrl+R` | Open a random guide |
| `Backspace` / `Ctrl+U` | Delete a character / clear |
| `Esc` | Clear the query, then close |

**Reader**

| Key | Action |
|-----|--------|
| `↑` `↓` / `j` `k` | Scroll |
| `Space` / `PgDn` / `PgUp` | Page |
| `g` / `G` / `Home` / `End` | Top / bottom |
| `n` `p` or `→` `←` | Next / previous phase |
| `y` | Copy the whole phase |
| `o` | Open this phase in the browser |
| *click a code block* | Copy that snippet |
| `Esc` / `Backspace` | Back to your results |
| `/` | Start a new search |
| `q` | Close |

**Catalog**

| Key | Action |
|-----|--------|
| *any character* | Filter locally (no network) |
| `↑` `↓`, `Enter` | Move, open |
| `Tab` | Back to search |
| `Esc` | Clear the filter, then back, then close |

### CLI

```bash
tmm search "git rebase"      # aligned results, with a suggestion on stderr
tmm open git-from-zero/2     # render into your pager
tmm read git-from-zero 2     # render to stdout
tmm list                     # every guide, with its category
tmm categories               # category names
tmm random                   # one random guide
tmm recent                   # what you last read, shared with the overlay
tmm offline git-from-zero    # download the EPUB into the cache
tmm close                    # stop pagers started by "tmm open"
```

Colors follow `NO_COLOR` and turn off when output is not a terminal. Point at a self-hosted instance with `TMM_BASE`:

```bash
TMM_BASE=http://localhost:5173 tmm search "networks"
```

## How it works

| Action | Endpoint | File |
|--------|----------|------|
| search | `GET /search.json?q=&limit=` (open) | `Service.qml` |
| catalog | `GET /llms.txt` parsed locally (open) | `Service.qml`, `Model.js` |
| open guide | `GET /guides/:slug.md` (open) | `Service.qml` |
| read phase | `GET /guides/:slug/:phase.md` (open) | `Service.qml`, `bin/tmm` |
| offline book | `GET /guides/:slug/epub` (open) | `tmm offline` |

`/guides.json`, `/cheat-sheet.json` and `/api/*` need a site key or a self-hosted API, so the plugin avoids them on the public host.

Repo layout:

```
manifest.json                  # id tmm.manual, kinds overlay + service
Overlay.qml                    # layer-shell overlay: search / reader / catalog
Reader.qml                     # markdown blocks drawn as themed QML
ResultList.qml                 # keyboard-first list, shared by search and catalog
Service.qml                    # headless API client, cache, recents, signals
Markdown.js                    # markdown -> blocks + inline rich text
logo.png                       # brand mark, shown in the header and on welcome
Model.js                       # URL builders, catalog parsing, phase nav
bin/tmm                        # terminal client with the same renderer
extensions/omarchy-menu.jsonc  # menu fragment
bindings.lua.fragment          # Hyprland keybind fragment
```

Phase markdown is cached in `~/.cache/tmm/` as `<slug>-<phase>.md`; if a fetch fails the service falls back to that copy and the header says `offline`. Recents live in `~/.local/state/omarchy/tmm-recents.json` and are shared by the overlay and the CLI.

## Troubleshooting

```bash
tmm --help
sh -n ~/.local/bin/tmm
curl -fsSL "https://themissingmanual.dev/search.json?q=git" | head -c 300
omarchy plugin validate ~/.config/omarchy/plugins/tmm.manual/
omarchy-shell shell rescanPlugins
```

- **Empty results**: check the network, then broaden the query. The API returns a `suggestion`, shown as "Did you mean".
- **Stale page**: delete `~/.cache/tmm/<slug>-<phase>.md` and reopen.
- **Overlay does not appear**: validate the manifest, rescan plugins, and check that `shell.json` lists `tmm.manual` under `plugins`.
- **Overlay appears unstyled**: you are on an Omarchy build without `qs.Commons` / `qs.Ui`; this plugin targets v4 Quattro.
- **Copy does nothing**: install `wl-copy` (`wl-clipboard`).
- **Broken image in the header**: `logo.png` did not get copied next to `Overlay.qml`.
- **No `python3`**: the CLI prints raw JSON and unrendered markdown. That is the intended fallback.

## Contributing

Issues and PRs welcome. Take colors, spacing and type from `Color` / `Style` rather than hardcoding them, keep `bin/tmm` POSIX `sh` clean, and test with `sh -n`, JSON validation and `omarchy plugin validate`.

Keep a QML file to one job and split it when it grows a second one — that is what `Reader.qml` and `ResultList.qml` are. `Overlay.qml` is deliberately the largest file: it owns the window, the three modes and the key map, which are hard to separate without making the flow harder to follow. (An earlier version of this note asked for ~300 lines per file; that was never true of the shell's own plugins either.)

Content bugs (a wrong command in a guide) belong upstream in The Missing Manual repo, not here.

## License

MIT. See [LICENSE](LICENSE). Guide content belongs to its upstream project at [themissingmanual.dev](https://themissingmanual.dev).
