# Title bars (optional)

This adds a header with close, maximize and minimize buttons to every window, using the official [hyprbars](https://github.com/hyprwm/hyprland-plugins) plugin. Snap Layouts works without it: you can drag with Super+drag instead.

Hyprbars stops Hyprland's mouse binds from seeing a title bar drag, so a stock hyprbars build won't open the picker. `rebuild-hyprbars.sh` builds it with `hyprbars:dragstart` and `hyprbars:dragend` events added, which the plugin listens for.

## Build

You need `git`, `jq`, `make`, a C++ compiler and the Hyprland headers (on Arch, the `hyprland` package includes them). From this folder, run:

```sh
./rebuild-hyprbars.sh --build-only
```

The script:

1. Downloads hyprland-plugins and picks the commit that upstream's `hyprpm.toml` lists for your Hyprland. If none is listed yet, it uses the latest and says so.
2. Adds the events next to hyprbars' "Dragging initiated" and "Dragging ended" log lines, with a flag so every `dragstart` gets exactly one `dragend`. That also holds when the window closes mid-drag, another window takes focus, or you release over the picker, which hyprbars would otherwise ignore. If some of that code has changed upstream, it warns and adds simpler events, which can leave the picker open in those cases.
3. Builds the plugin and installs it to `~/.local/lib/hyprland/libhyprbars.so`.

To see whether the events can be added to your version without building anything, run `./rebuild-hyprbars.sh --check`.

## Enable

1. Copy `titlebars.lua` from this folder to `~/.config/hypr/titlebars.lua`.
2. Add this line to `~/.config/hypr/hyprland.lua`, after `require("hypr.looknfeel")`:

   ```lua
   require("hypr.titlebars")
   ```

3. Log out and back in.

If you change `bar_height`, set `titleBarHeight` in `SnapLayouts.qml` to match.

## After a Hyprland update

Hyprland refuses to load a plugin built for a different version. It shows a red "Version mismatch" notification and the title bars disappear, but nothing else breaks. To bring them back, run:

```sh
./rebuild-hyprbars.sh
```

This builds, installs and loads the plugin without logging out.

If a new version stops the events from being added or compiling, the script warns you and builds plain title bars. They'll work, but dragging one won't open the picker until the script is updated. Super+drag and the keyboard shortcut still work. If nothing compiles at all, your installed plugin is left as it was.

## Tested versions

Title bar drags were tested on Hyprland 0.56.2 (hyprland-plugins `7644cec`) in a nested Hyprland: a normal drag, a click, closing the window mid-drag, a focus change mid-drag and a release over an overlay layer each send the right events, and the next drag after each sends a fresh pair. The simpler events fail the last three. The script's download, commit lookup and event steps were also checked against a newer hyprland-plugins commit (`d2427d4`), but that source hasn't been compiled.

## Remove

Delete the `require("hypr.titlebars")` line, `~/.config/hypr/titlebars.lua` and `~/.local/lib/hyprland/libhyprbars.so`, then log out and back in.
