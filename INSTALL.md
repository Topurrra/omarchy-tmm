# omarchy-tmm install (Omarchy v4 Quattro only)

> Requires the Omarchy v4 plugin/menu APIs and the `qs.Commons` / `qs.Ui` QML
> modules the shell ships. Not compatible with v3.

1. Install the plugin: `omarchy plugin add <url> --enable`

   Installing by hand instead? Copy **all** the QML and JS files, the logo, and
   the `bin/` directory — the overlay loads `Reader.qml`, `ResultList.qml`,
   `Markdown.js` and `logo.png` as siblings, and the service runs
   `bin/tmm-diagrams` from the plugin folder:

   ```bash
   mkdir -p ~/.config/omarchy/plugins/tmm.manual
   cp manifest.json Overlay.qml Reader.qml ResultList.qml Service.qml \
      BarWidget.qml Model.js Markdown.js logo.png \
      ~/.config/omarchy/plugins/tmm.manual/
   cp -r bin ~/.config/omarchy/plugins/tmm.manual/
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

4. CLI: `cp bin/tmm ~/.local/bin/tmm && chmod +x ~/.local/bin/tmm`
5. Menu entries: `cp bin/tmm-menu ~/.local/bin/ && chmod +x ~/.local/bin/tmm-menu && tmm-menu install`

   Do **not** `cp` the fragment over `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
   Omarchy reads that one file for every user menu entry, so copying over it
   deletes anything else you have added. `tmm-menu` merges instead, keeps a
   `.bak`, and refuses to write anything that would not parse.

6. Refresh the menu: `omarchy menu refresh`
7. Keybinds: append `bindings.lua.fragment` to `~/.config/hypr/bindings.lua`

Then click the book glyph in the bar, or press `SUPER + ALT + M`, and start
typing. If the bar button does not appear on its own:
`omarchy bar put tmm.manual --section right`.

## Requirements

- `python3` — runs `bin/tmm-diagrams` (every rendered diagram) and `bin/tmm-menu`
  (the menu entries), and drives the CLI's pretty output. Omarchy ships it.
- `curl` — every request the service makes.

## Optional

- `wl-clipboard` — enables click-to-copy on code blocks and `y` in the reader.

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
- Overlay opens but looks unstyled: the shell could not resolve `qs.Commons`;
  confirm you are on v4 Quattro.
- Missing files after a manual copy: the overlay needs `Reader.qml`,
  `ResultList.qml`, `Markdown.js` and `logo.png` alongside `Overlay.qml`.
  A broken image in the header means `logo.png` was left behind.
- No `python3`/`jq`: raw JSON output is the expected fallback.
- Caches: phase markdown and diagram SVGs in `~/.cache/tmm/`, recents in
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
