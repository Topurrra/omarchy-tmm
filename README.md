# The Missing Manual — Omarchy Plugin

Search, open, read and close guides from The Missing Manual inside Omarchy.

Upstream: https://themissingmanual.dev

## Requirements

- Omarchy v4 Quattro
- `curl`
- `omarchy-shell`

## Install

```bash
omarchy plugin add <git-url> --enable
```

Manual install:

```bash
mkdir -p ~/.config/omarchy/plugins/tmm.manual
cp -r manifest.json Overlay.qml Service.qml bin/ ~/.config/omarchy/plugins/tmm.manual/
omarchy plugin rescan 2>/dev/null || omarchy-shell plugin rescan
```

## Usage

- Toggle overlay: `SUPER+ALT+M`
- Summon menu: `omarchy menu summon tmm.guides`
- CLI via service:
  - `tmm search <query>`
  - `tmm open <slug>`
  - `tmm read <slug> <phase>`
  - `tmm close`

## API mapping

| Action | Endpoint |
|--------|----------|
| search | `GET /search.json?q=<query>` |
| open | `GET /guides.json` + `GET /api/guides/:slug` |
| read | `GET /guides/:slug/:phase.md` with `Accept: text/markdown` |
| close | client-side only (clears local state) |

## Offline cache

Cached guides live under `~/.cache/tmm/`. If the network is unavailable, `read` falls back to cache when present.

## License

MIT. See `LICENSE`.
