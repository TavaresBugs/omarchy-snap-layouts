# Contributing

Issues and pull requests are welcome. This is a small project, so please open an issue before starting anything large.

## Setup

Clone the repo, then copy it into your plugins folder so the shell loads your version:

```sh
omarchy plugin remove io.github.n0rthstar88.snap-layouts   # if installed
cp -r . ~/.config/omarchy/plugins/io.github.n0rthstar88.snap-layouts
omarchy plugin enable io.github.n0rthstar88.snap-layouts
omarchy restart shell
```

Copy your changes across (`SnapLayouts.qml`, and the `lib/`, `lua/`, `components/` and `controllers/` folders, plus `BarWidget.qml`, `Panel.qml`, `manifest.json` and `i18n/` if you changed them) and **restart the shell with `omarchy restart shell` after each change**. The shell reloads a changed plugin by itself, but a hot reload can leave an older instance running next to the new one, and the symptoms (an overview that does not open, keys that do nothing) look like bugs in your change.

Run `npm test` and `omarchy plugin validate .` before opening a pull request.

Put decisions that can be made from plain data in `lib/` with a test, keep views in `components/` driven by properties and signals, and keep `SnapLayouts.qml` for state and Hyprland I/O. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Tests

`npm test` needs only Node (and `luajit`, if installed, to check the Lua). It covers:

- every function in `lib/`, loaded the way QML loads it (`test/load.js`);
- `test/structure.test.js`, which holds the code base together: every library function the QML calls exists, no component is orphaned, components stay presentation, every Lua file and every Lua snippet the plugin sends to Hyprland parses, the events the submap reports are the ones the plugin listens for, and the manifest, README and changelog agree.

The QML itself can't run under Node, so anything visual or timing-related has to be tried on a desktop. Say in the pull request what you tried. A tip for animations: record the screen (`gpu-screen-recorder`) and step through the frames rather than judging by eye.

Avoid numbers that depend on one layout. If a value can be worked out from where the windows really are, do that (see `lib/motion.js`); what is left is a matter of taste and belongs in the tokens there.

## Pull requests

- Keep each pull request to one change.
- Say what you tested, and on which Omarchy and Hyprland versions.
- Check both ways of dragging if you touch the drag code: a Hyprland mouse bind and a title bar.

## Hyprland crash to avoid

Never call `remove()` on the mouse binds in `lua/hook.lua`. In Hyprland 0.56.2, `Keybind:remove()` deletes every bind on the same key and leaves the other handles dangling, and the next call on one of those crashes Hyprland. The binds are only ever added, and the plugin ignores their events when Snapping is off.

## Changing the overview's shortcuts

`lua/overview-mode.lua` defines a Hyprland submap, and Hyprland keeps a submap's binds until the config is reloaded. When you change the binds in it, bump `VERSION` at the top, so the new definition gets a new name and is used at once instead of being skipped or added twice.
