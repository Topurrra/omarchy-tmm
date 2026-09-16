<p align="center">
  <h1 align="center">The Missing Manual for Omarchy</h1>
  <p align="center">Search, open, read, and close developer guides without leaving your desktop.</p>
  <p align="center">
    <a href="https://themissingmanual.dev"><img src="https://img.shields.io/badge/docs-themissingmanual.dev-blue?style=flat-square" alt="docs"></a>
    <img src="https://img.shields.io/badge/omarchy-v4%20Quattro-purple?style=flat-square" alt="omarchy v4">
    <img src="https://img.shields.io/badge/version-0.1.0-green?style=flat-square" alt="version">
    <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" alt="license">
  </p>
</p>

---

**tmm.manual** brings [The Missing Manual](https://themissingmanual.dev) into Omarchy as a native v4 Quattro plugin: a fullscreen overlay reader backed by a headless search service, plus a small CLI for terminals and scripts.

Upstream library: 367 guides, 1,575 phases, 27 categories, from Git and operating systems to networks, databases, security, DevOps, full programming languages, math, logic, and physics. This plugin only reads from it. It never uploads anything.

## Features

- Instant search with typo tolerance and "did you mean" suggestions
- Fullscreen reader: search, results, article view, catalog
- Phase navigation with prev and next, frontmatter stripped automatically
- Catalog browser, random guide picker, and cheat sheet shortcut
- Offline cache: previously read phases open with no network
- CLI that mirrors the overlay: `search`, `open`, `read`, `close`, `list`, `random`, `categories`, `cheat`, `offline`
- Menu entries and Hyprland keybindings included

## Requirements

| Need | Notes |
|------|-------|
| Omarchy v4 Quattro | Uses the QML `overlay` + `service` plugin kinds. Not compatible with v3 Walker |
| `omarchy-shell` | Hosts the overlay and service |
| `curl` | All network calls go through it |
| `python3` or `jq` (optional) | Pretty JSON parsing in the CLI. Raw JSON fallback works without them |
| `less` or `$PAGER` (optional) | Used by `tmm open` |

## Install

### Option A: plugin manager (once your repo is public)

```bash
omarchy plugin add https://github.com/YOU/omarchy-tmm.git --enable
omarchy-shell shell rescanPlugins
```

### Option B: manual install (works right now, no upload needed)

```bash
mkdir -p ~/.config/omarchy/plugins/tmm.manual
cp manifest.json Overlay.qml Service.qml Model.js ~/.config/omarchy/plugins/tmm.manual/
cp bin/tmm ~/.local/bin/tmm && chmod +x ~/.local/bin/tmm
omarchy-shell shell rescanPlugins
```

### Option C: menu + keybindings (recommended extras)

```bash
# Menu entries
mkdir -p ~/.config/omarchy/extensions
cp extensions/omarchy-menu.jsonc ~/.config/omarchy/extensions/omarchy-menu.jsonc
omarchy menu refresh

# Keybindings: append the fragment to your bindings file
cat bindings.lua.fragment >> ~/.config/hypr/bindings.lua
```

See [INSTALL.md](INSTALL.md) for the short checklist and troubleshooting.

## Usage

### Overlay

Open it with `SUPER + ALT + M`, or from a terminal:

```bash
omarchy-shell shell toggle tmm.manual
omarchy-shell shell summon tmm.manual
omarchy menu summon tmm.guides
```

| Key | Action |
|-----|--------|
| `Enter` | Search |
| `Click` or `Enter` on a hit | Open phase in reader |
| `n` / `p` | Next / previous phase |
| `/` | Jump back to search |
| `Esc` or `q` | Close overlay |
| `Catalog` button | Browse all categories and guides |
| `Random` button | Open a surprise guide |
| `CheatSheet` button | Jump to cheat sheet results |

The overlay accepts an optional JSON payload:

```bash
# Open search directly
omarchy-shell shell summon tmm.manual '{"query":"git rebase"}'

# Open an exact phase
omarchy-shell shell summon tmm.manual '{"slug":"git-from-zero","phase":2}'
```

### CLI

```bash
tmm search "git rebase"      # search, prints slug/phase and title
tmm open git-from-zero/2     # fetch to cache, open in pager
tmm read git-from-zero 2     # same fetch, print to stdout
tmm list                     # every guide from the catalog
tmm random                   # one random guide
tmm categories               # category slugs
tmm cheat                    # cheat sheet JSON
tmm offline git-from-zero    # download EPUB into cache
tmm close                    # stop open pager processes
```

Point at a self hosted instance with env override:

```bash
TMM_BASE=http://localhost:5173 tmm search "networks"
```

## How it works

| Action | Endpoint | File |
|--------|----------|------|
| search | `GET /search.json?q=&limit=` | `Service.qml`, `Model.js` |
| catalog | `GET /guides.json` | `Service.qml`, `Overlay.qml` catalog mode |
| open guide | `GET /api/guides/:slug` | `Service.qml` |
| read phase | `GET /guides/:slug/:phase.md` | `Service.qml`, `bin/tmm` |
| cheat sheet | `GET /cheat-sheet.json` | `Service.qml`, `tmm cheat` |
| full offline corpus | `GET /llms-full.txt` | `Model.js` helper |
| close | local only, clears overlay state | `Overlay.qml`, `tmm close` |

Repo layout:

```
manifest.json                  # id tmm.manual, kinds overlay + service
Service.qml                    # headless API client, cache, signals
Model.js                       # URL builders, frontmatter strip, phase nav
Overlay.qml                    # fullscreen SEARCH / READER / CATALOG UI
bin/tmm                        # terminal client mirroring the overlay
extensions/omarchy-menu.jsonc  # menu fragment
bindings.lua.fragment          # Hyprland keybind fragment
INSTALL.md                     # install checklist
```

Cache lives in `~/.cache/tmm/` as `<slug>-<phase>.md`. If a fetch fails, the service falls back to the cached file.

## Troubleshooting

```bash
tmm --help
sh -n ~/.local/bin/tmm
curl -fsSL "https://themissingmanual.dev/search.json?q=git" | head -c 300
omarchy plugin validate ~/.config/omarchy/plugins/tmm.manual/
omarchy-shell shell rescanPlugins
```

- Empty results: check network, then try a broader query. The API returns a `suggestion` field which the overlay shows as "Did you mean".
- Stale page: delete `~/.cache/tmm/<slug>-<phase>.md` and reopen.
- No `python3` or `jq`: CLI prints raw JSON. That is the intended fallback.
- Overlay does not appear: validate the manifest, rescan plugins, check `shell.json` lists `tmm.manual` under `plugins`.

## Contributing

Issues and PRs welcome. Keep QML under ~300 lines per file where possible, keep `bin/tmm` POSIX `sh` clean, and test with `sh -n`, JSON validation, and `omarchy plugin validate`.

Content bugs (a wrong command in a guide) belong upstream in The Missing Manual repo, not here.

## License

MIT. See [LICENSE](LICENSE). Guide content itself belongs to its upstream project at [themissingmanual.dev](https://themissingmanual.dev).
