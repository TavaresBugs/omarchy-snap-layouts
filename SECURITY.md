# Security policy

## Reporting a vulnerability

Please don't report security problems in a public issue. Use GitHub's [private vulnerability reporting](https://github.com/TavaresBugs/omarchy-snap-layouts/security/advisories/new) instead, with steps to reproduce and the version or commit you tested.

This is a volunteer project, so replies are best-effort and there is no guaranteed response time.

## Supported versions

Only the latest code on `main` gets fixes.

## What's in scope

Omarchy plugins run unsandboxed inside the shell, with your user's permissions. These are the parts most worth a look:

- Commands the plugin passes to `hyprctl eval`, especially anything built from window data.
- Loading `lua/hook.lua`, `lua/shortcuts.lua` and `lua/mosaic.lua` into Hyprland's Lua state.
- Writing a marked block into `~/.config/omarchy/extensions/omarchy-menu.jsonc` (`controllers/MenuRows.qml`, `lib/menu.js`) and removing it again.
- Window titles and contents shown in snap assist thumbnails, which are visible on screen while it's open.
- The optional `rebuild-hyprbars.sh`, which downloads and builds hyprland-plugins, and `titlebars.lua`.

The plugin makes no network connections. It stores its options in `~/.config/omarchy/shell.json`, which workspaces are in WinSaico in files named `snap-layouts-*` under `~/.local/state/omarchy/`, and, while WinSaico is on, one block in the menu extension. `omarchy-shell snaplayouts uninstall` removes them.
