<p align="center">
  <img src="logo.png" alt="The Missing Manual" width="96" height="96">
  <h1 align="center">The Missing Manual for Omarchy</h1>
  <p align="center">Search, browse and read developer guides without leaving your desktop.</p>
  <p align="center">
    <a href="https://themissingmanual.dev"><img src="https://img.shields.io/badge/docs-themissingmanual.dev-blue?style=flat-square" alt="docs"></a>
    <img src="https://img.shields.io/badge/omarchy-v4%20Quattro-purple?style=flat-square" alt="omarchy v4">
    <img src="https://img.shields.io/badge/version-0.4.0-green?style=flat-square" alt="version">
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
- **Quizzes you can actually answer** — the `Check your understanding` block at the end of a phase is a real quiz: a choice locks on first answer, a wrong one gets the diagnosis written for that specific distractor, and you can retry just the ones you missed
- **Diagrams, drawn in your theme** — the site bakes every mermaid diagram to SVG with placeholder colours its CSS remaps; the plugin makes the same substitution against your Omarchy palette, so a flowchart matches the desktop around it
- **Keyboard-first throughout** — arrows, `Enter`, `Tab`, `n`/`p`, `g`/`G`; the mouse is optional everywhere
- **Ask the guides** — press `?` and get an answer written from the manual itself, with the phases it came from listed underneath; press `1`–`9` to open one. Answers are cached locally, so asking the same thing twice is free and instant
- **Recents** on the empty search screen, shared between the overlay and the CLI, so "where was I" is one keystroke
- **Phase navigation** with a reading-progress hairline and an estimated reading time
- **Catalog browser by category** — `Tab` opens the 27 categories, `Enter` drills into one, and typing filters locally (the catalog is fetched once per session)
- **Offline fallback** — a phase you have read before still opens with no network, and says so
- **A bar button** — a book glyph in the Omarchy bar that toggles the overlay, so there is always something to click
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

Plugins are unsandboxed code, so Omarchy installs them **disabled** unless you
pass `--enable`, and waits for you to review them. If you leave the flag off —
or install by hand, as in Option B — finish with `omarchy plugin enable
tmm.manual`. A disabled plugin answers a summon by doing nothing at all, which
looks exactly like a broken install.

### Option B: manual install

Copy every QML and JS file plus `logo.png` — the overlay loads `Reader.qml`, `ResultList.qml`, `Markdown.js` and the logo as siblings, and `BarWidget.qml` is the bar button.

```bash
mkdir -p ~/.config/omarchy/plugins/tmm.manual
cp manifest.json Overlay.qml Reader.qml ResultList.qml Service.qml BarWidget.qml \
   Model.js Markdown.js logo.png \
   ~/.config/omarchy/plugins/tmm.manual/
cp bin/tmm ~/.local/bin/tmm && chmod +x ~/.local/bin/tmm
omarchy-shell shell rescanPlugins
omarchy plugin enable tmm.manual        # copied plugins start disabled
```

### Option C: menu + keybindings (recommended)

```bash
# Menu entries. Use the helper, do NOT copy the fragment over the file:
# Omarchy reads one shared user menu file, so a plain `cp` would wipe every
# other entry in it.
cp bin/tmm-menu ~/.local/bin/tmm-menu && chmod +x ~/.local/bin/tmm-menu
./bin/tmm-menu install
omarchy menu refresh

# Keybindings
cat bindings.lua.fragment >> ~/.config/hypr/bindings.lua
```

`tmm-menu status` shows what is in that file, `tmm-menu remove` takes our
entries back out, and every write keeps a `.bak` beside the original.

See [INSTALL.md](INSTALL.md) for the short checklist and troubleshooting.

## Usage

There are three ways in, and all of them go through the same shell IPC:

1. **The bar button** — a book glyph, added to the right of the bar when the
   plugin is enabled. Click it to toggle the overlay.
2. **`SUPER + ALT + M`** — requires `bindings.lua.fragment` to be appended to
   `~/.config/hypr/bindings.lua`.
3. **The menu** — *Missing Manual*, from `extensions/omarchy-menu.jsonc`.

If the bar button is not there after enabling the plugin, place it by hand:

```bash
omarchy bar put tmm.manual --section right
```

Or from a terminal:

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
| `?` | Ask the guides about what you typed |
| `Tab` | Browse the catalog |
| `Ctrl+R` | Open a random guide |
| `Backspace` / `Ctrl+U` | Delete a character / clear |
| `Esc` | Clear the query, then close |

**Ask** (`?` from search)

| Key | Action |
|-----|--------|
| `1`–`9` | Open the Nth source in the reader |
| `Enter` | Open the first source |
| `↑` `↓` / `j` `k` / `Space` | Scroll |
| `y` | Copy the answer |
| `o` | Open the search page in the browser |
| `Esc` / `Backspace` | Back to your results |

Answers come from the site's own `/ask.json`, which is public. Nothing about you
is sent — only the question. If the host has AI answers switched off, or the
month's budget is spent, the panel says so and search carries on working.

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
| `q` | Answer the quiz — or close, on a phase that has none |
| `Shift+Q` | Close |

**Quiz** (`q` in the reader; `Esc` leaves the quiz, not the reader)

| Key | Action |
|-----|--------|
| `a`–`d` / `1`–`4` | Answer the current question, then move to the next unanswered |
| `↑` `↓` / `j` `k` | Move between questions |
| `r` | Start over |
| `m` | Retry only the ones you missed |
| `Esc` | Back to reading |

Everything else keeps working mid-quiz — `n`/`p`, `y`, `o`, `Space` and `G` all still do
what they do in the reader.

**Catalog**

Two levels: the category list, then the guides inside one.

| Key | Action |
|-----|--------|
| *any character* | Filter locally (no network) |
| `↑` `↓` | Move |
| `Enter` | Open the category, then open the guide |
| `Backspace` (empty filter) | Back up to the categories |
| `Tab` | Back to search |
| `Esc` | Clear the filter, then back up a level, then close |

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
| diagrams | `GET /guides/:slug/:phase` HTML, figures extracted locally (open) | `Service.qml`, `bin/tmm-diagrams` |
| ask | `GET /ask.json?q=` (open) | `Service.qml` |
| offline book | `GET /guides/:slug/epub` (open) | `tmm offline` |

`/guides.json`, `/cheat-sheet.json` and `/api/*` need a site key or a self-hosted API, so the plugin avoids them on the public host.

Repo layout:

```
manifest.json                  # id tmm.manual, kinds overlay + service
Overlay.qml                    # layer-shell overlay: search / reader / catalog
BarWidget.qml                  # bar button that toggles the overlay
Reader.qml                     # markdown blocks drawn as themed QML
ResultList.qml                 # keyboard-first list, shared by search and catalog
Service.qml                    # headless API client, cache, recents, signals
Markdown.js                    # markdown -> blocks + inline rich text
logo.png                       # brand mark, shown in the header and on welcome
Model.js                       # URL builders, catalog parsing, phase nav
bin/tmm                        # terminal client with the same renderer
bin/tmm-diagrams               # pulls the baked mermaid SVGs out of a phase and re-themes them
bin/tmm-menu                   # merges/removes our entries in the shared menu file
extensions/omarchy-menu.jsonc  # menu fragment
bindings.lua.fragment          # Hyprland keybind fragment
```

Phase markdown is cached in `~/.cache/tmm/` as `<slug>-<phase>.md`, themed diagram SVGs
in `~/.cache/tmm/diagrams/` and answers in `~/.cache/tmm/ask/`; if a fetch fails the service falls back to that copy and the header says `offline`. Recents live in `~/.local/state/omarchy/tmm-recents.json` and are shared by the overlay and the CLI.

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
- **Overlay does not appear.** Work through these in order:

  ```bash
  # 1. Is it discovered, and is it enabled? (enabled:false is the usual answer)
  omarchy-shell shell listPlugins | python3 -m json.tool | grep -A4 tmm.manual

  # 2. Enable it
  omarchy plugin enable tmm.manual
  # or, equivalently:
  omarchy-shell shell setPluginEnabled tmm.manual true

  # 3. Are all the files there? Overlay.qml needs its siblings
  ls ~/.config/omarchy/plugins/tmm.manual/
  # expect: manifest.json Overlay.qml Reader.qml ResultList.qml Service.qml
  #         Model.js Markdown.js logo.png

  # 4. Reload the code and try it directly
  omarchy-shell shell rescanPlugins
  omarchy-shell shell summon tmm.manual
  ```

  `summon` answers `ok` on success; `unknown` means the shell has no such
  plugin loaded, which sends you back to steps 1–3.

  **`ok` but still nothing on screen?** Then the plugin loaded and a QML error
  stopped it drawing. `omarchy-launch-shell` runs Quickshell under
  `systemd-cat -t omarchy-shell`, so the error is in the journal:

  ```bash
  journalctl -t omarchy-shell -n 100 --no-pager | grep -i -A3 'tmm\|error\|warning'

  # watch it live while you summon from another terminal
  journalctl -t omarchy-shell -f
  ```

  `rescanPlugins` hot-reloads plugin code, but after editing files a full
  restart is the honest reset: `omarchy-restart-shell`.
- **Overlay appears unstyled**: you are on an Omarchy build without `qs.Commons` / `qs.Ui`; this plugin targets v4 Quattro.
- **Copy does nothing**: install `wl-copy` (`wl-clipboard`).
- **Menu rows show words like `search` instead of icons**: you have an old copy of `extensions/omarchy-menu.jsonc`. The menu draws `icon` literally, so it must be a Nerd Font glyph. Re-copy the fragment and run `omarchy menu refresh`.
- **Broken image in the header**: `logo.png` did not get copied next to `Overlay.qml`.
- **No `python3`**: the CLI prints raw JSON and unrendered markdown. That is the intended fallback.

## Contributing

Issues and PRs welcome. Take colors, spacing and type from `Color` / `Style` rather than hardcoding them, keep `bin/tmm` POSIX `sh` clean, and test with `sh -n`, JSON validation and `omarchy plugin validate`.

Keep a QML file to one job and split it when it grows a second one — that is what `Reader.qml` and `ResultList.qml` are. `Overlay.qml` is deliberately the largest file: it owns the window, the three modes and the key map, which are hard to separate without making the flow harder to follow. (An earlier version of this note asked for ~300 lines per file; that was never true of the shell's own plugins either.)

Content bugs (a wrong command in a guide) belong upstream in The Missing Manual repo, not here.

## Uninstall

The plugin scatters a few things outside its own directory, and deleting the
plugin folder leaves the rest behind — most visibly the menu entry, which lives
in Omarchy's shared menu file and will keep showing up until it is removed.

```bash
tmm-menu remove && omarchy menu refresh     # menu entries
omarchy plugin remove tmm.manual            # the plugin itself
rm -f ~/.local/bin/tmm ~/.local/bin/tmm-menu
rm -rf ~/.cache/tmm ~/.local/state/omarchy/tmm-recents.json
```

Then drop the `Missing Manual` lines from `~/.config/hypr/bindings.lua` and run
`hyprctl reload`.

## License

MIT. See [LICENSE](LICENSE). Guide content belongs to its upstream project at [themissingmanual.dev](https://themissingmanual.dev).
