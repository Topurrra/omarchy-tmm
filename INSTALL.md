# omarchy-tmm install (Omarchy v4 Quattro only)

> Requires the Omarchy v4 plugin/menu APIs and the `qs.Commons` / `qs.Ui` QML
> modules the shell ships. Not compatible with v3.

> **Where the files end up.** `omarchy plugin add` clones into
> `~/.config/omarchy/plugins/tmm.manual/` and leaves nothing in your working
> directory — there is no repo checkout to stand in afterwards. The steps below
> therefore point *into the installed plugin*:
>
> ```bash
> P=~/.config/omarchy/plugins/tmm.manual
> ```
>
> Set that once and paste the rest as-is. (The one exception is the hand-install
> block in step 1, which is the only place you really are inside a clone.)

1. Install the plugin: `omarchy plugin add <url> --enable`

   Installing by hand instead? From a clone of this repo, copy **all** the QML and
   JS files, the `components/` directory, the logo, and
   the `bin/` directory — the panel window (`Panel.qml`) loads `Controller.qml`,
   `Reader.qml`, `ResultList.qml`, `Markdown.js`, `components/` and `logo.png`
   as siblings, and the service runs `bin/tmm-diagrams` from the plugin folder:

   ```bash
   mkdir -p ~/.config/omarchy/plugins/tmm.manual
   cp manifest.json Panel.qml Controller.qml Reader.qml ResultList.qml Service.qml \
      BarWidget.qml Model.js Markdown.js logo.png \
      ~/.config/omarchy/plugins/tmm.manual/
   cp -r components bin ~/.config/omarchy/plugins/tmm.manual/
   chmod +x ~/.config/omarchy/plugins/tmm.manual/bin/*
   ```

   Leave `bin/` out and the plugin still works, but every diagram stays a
   `Diagram · mermaid` card and nothing says why — a missing helper is not an
   error the reader can show you.

2. Rescan so the shell sees it: `omarchy-shell shell rescanPlugins`
3. **If you copied by hand, or left `--enable` off: `omarchy plugin enable tmm.manual`**

   Omarchy installs plugins disabled on purpose — they are unsandboxed code and
   it wants you to read them first. A disabled plugin does nothing at all when
   summoned, which looks exactly like a broken install.

4. CLI and menu tool:

   ```bash
   mkdir -p ~/.local/bin
   cp "$P"/bin/tmm "$P"/bin/tmm-menu ~/.local/bin/
   chmod +x ~/.local/bin/tmm ~/.local/bin/tmm-menu
   ```

5. Menu entries: `tmm-menu install`

   Do **not** `cp` the fragment over `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
   Omarchy reads that one file for every user menu entry, so copying over it
   deletes anything else you have added. `tmm-menu` merges instead, keeps a
   `.bak`, and refuses to write anything that would not parse.

6. Refresh the menu: `omarchy menu refresh`
7. Keybinds:

   ```bash
   cat "$P"/bindings.lua.fragment >> ~/.config/hypr/bindings.lua
   ```

Then click the book glyph in the bar, or press `SUPER + ALT + M`, and start
typing. If the bar button does not appear on its own:
`omarchy bar put tmm.manual --section right`.

## Updating

```bash
omarchy plugin update tmm.manual
omarchy-shell shell rescanPlugins
```

That pulls the repo in place and keeps the plugin enabled, so nothing else needs
redoing — `bin/tmm-diagrams` lives inside the plugin folder and comes with it.

`rescanPlugins` is enough on its own: it unloads the plugin's panels, services and
widgets, clears Qt's component cache and rescans, so new QML really is picked up.
`omarchy-restart-shell` is the stronger reset to reach for when a reload does not
seem to have taken.

Two things live outside the plugin folder and are only worth redoing when they
change: `bin/tmm` in `~/.local/bin`, and the menu entries
(`tmm-menu install && omarchy menu refresh`).

Check which version is actually loaded:

```bash
grep version ~/.config/omarchy/plugins/tmm.manual/manifest.json
```

Old caches are safe to drop if an update seems not to have taken:
`rm -rf ~/.cache/tmm`.

## Requirements

- `python3` — runs `bin/tmm-diagrams` (every rendered diagram) and `bin/tmm-menu`
  (the menu entries), and drives the CLI's pretty output. Omarchy ships it.
- `curl` — every request the service makes.

## Optional

- `wl-clipboard` — enables click-to-copy on code blocks and `y` in the reader.
- `rsvg-convert` (librsvg) — renders diagrams inline in the reader. Ships with
  Omarchy; without it, diagrams fall back to a `Diagram · mermaid` card.

## AI study chat (optional)

Optional, and off by default. Press `Ctrl+K` in the window to try it — with
nothing configured it still answers in retrieval mode (relevant manual
sections plus clickable source chips).

To turn on real conversational answers, bring your own LLM key: create
`~/.config/tmm/ai.json` with your `provider` (`openai` or `anthropic`),
`baseUrl` (for `openai`-compatible endpoints, including local Ollama/LM
Studio), `apiKey` and `model`. It hot-reloads, so no restart is needed. See
the [README's AI study chat section](README.md#ai-study-chat-bring-your-own-key)
for the full field list and example configs.

## Troubleshooting

- Validate the CLI: `sh -n ~/.local/bin/tmm && tmm --help`
- Nothing happens on the keybind or menu entry? Check it is enabled first:
  `omarchy-shell shell listPlugins | python3 -m json.tool | grep -A4 tmm.manual`
  then `omarchy plugin enable tmm.manual`. Test directly with
  `omarchy-shell shell summon tmm.manual` — it prints `ok` or `unknown`.
- Menu rows showing the words `search` / `shuffle` instead of icons means an
  old `omarchy-menu.jsonc`; re-copy it and run `omarchy menu refresh`.
- `summon` says `ok` but nothing appears? The plugin loaded and a QML error
  stopped it drawing. The shell logs to the journal under its own tag:
  `journalctl -t omarchy-shell -n 100 --no-pager`, or `-f` to watch live while
  you summon. After editing plugin files, `omarchy-restart-shell` is a cleaner
  reset than `rescanPlugins`.
- Diagrams all showing as `Diagram · mermaid` cards? The helper is missing or
  cannot run. It lives beside the QML, not on your PATH:

  ```bash
  ls -l ~/.config/omarchy/plugins/tmm.manual/bin/tmm-diagrams   # exists, +x?
  command -v python3
  curl -fsSL https://themissingmanual.dev/guides/deadlocks-explained/1 \
    | ~/.config/omarchy/plugins/tmm.manual/bin/tmm-diagrams /tmp/d test
  ```

  That last line prints one `path<TAB>width<TAB>height` per diagram. No output
  means the page had no baked figures; an error means python3 is the problem.
- Check the API: `curl -fsSL "$TMM_BASE/search.json?q=git" | head -c 200`
  (default `TMM_BASE=https://themissingmanual.dev`)
- Window opens but looks unstyled: the shell could not resolve `qs.Commons`;
  confirm you are on v4 Quattro.
- Missing files after a manual copy: the panel needs `Controller.qml`,
  `Reader.qml`, `ResultList.qml`, `Markdown.js`, `components/` and `logo.png`
  alongside `Panel.qml`. A broken image in the header means `logo.png` was
  left behind.
- No `python3`/`jq`: raw JSON output is the expected fallback.
- Caches: phase markdown, diagram SVGs and AI answers in `~/.cache/tmm/`, recents in
  `~/.local/state/omarchy/tmm-recents.json`. Both are safe to delete.
- Menu entry still there after deleting the plugin? It lives in Omarchy's
  shared menu file, not in the plugin folder: `tmm-menu remove && omarchy menu
  refresh`. `tmm-menu status` lists what that file currently holds.

## Uninstall

```bash
tmm-menu remove && omarchy menu refresh
omarchy plugin remove tmm.manual
rm -f ~/.local/bin/tmm ~/.local/bin/tmm-menu
rm -rf ~/.cache/tmm ~/.local/state/omarchy/tmm-recents.json
```

Then remove the `Missing Manual` lines from `~/.config/hypr/bindings.lua`.
