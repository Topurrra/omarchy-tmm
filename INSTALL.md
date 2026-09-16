# omarchy-tmm install (Omarchy v4 only)

> Requires Omarchy v4 plugin/menu APIs. Not compatible with v3.

1. Install plugin: `omarchy plugin add <url> --enable`
2. Manual CLI copy: `cp omarchy-tmm/bin/tmm ~/.local/bin/tmm && chmod +x ~/.local/bin/tmm`
3. Menu fragment: `cp omarchy-tmm/extensions/omarchy-menu.jsonc ~/.config/omarchy/extensions/omarchy-menu.jsonc`
4. Refresh menu: `omarchy menu refresh`
5. Keybinds: append `omarchy-tmm/bindings.lua.fragment` to `~/.config/hypr/bindings.lua`
6. Rescan: `omarchy-shell shell rescanPlugins`

## Troubleshooting

- Validate: `sh -n ~/.local/bin/tmm && tmm --help`
- Lint menu: `qmllint ~/.config/omarchy/extensions/omarchy-menu.jsonc` (if available)
- API check: `curl -fsSL "$TMM_BASE/search.json" | head -c 200` (default `TMM_BASE=https://themissingmanual.dev`)
- No `jq`/`python3`: raw JSON output is expected fallback.
- Cache lives in `~/.cache/tmm/`; delete stale `*.md` if pages look old.
