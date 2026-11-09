# Omarchy Grid

A cell-grid tiling layout for [Omarchy](https://omarchy.org). Windows snap to
an adjustable grid (8 × 8 by default) instead of splitting the screen in
halves. Resize a window by dragging the dot in its corner, move it with
Super+drag, and control everything from a **Grid** panel in the bar.

<img src="screenshots/panel.png" alt="The Grid panel open from the Omarchy bar" width="350">

## Features

- **Cell-grid tiling.** Each window takes a rectangle of whole cells. New
  windows open at 3 × 3 (adjustable) in the first free spot. When the grid is
  full, rows are added so every window stays visible.
- **Corner resize dots.** A small dot sits in the bottom-right corner of every
  tiled window. Drag it and the grid lights up with an outline and a `4 × 2`
  label showing the size the window will snap to.
- **Super+drag to move.** Drag a window with Super held and it drops onto the
  nearest cells, with the grid shown while you drag.
- **Grid panel in the bar:**
  - Turn the grid on or off. Off falls back to Hyprland's standard
    `dwindle` tiling, and windows return to their cells when you turn it
    back on.
  - Size the focused window in one click: 1 × 1, 2 × 2, 3 × 3, 4 × 4 or Full.
  - Set the grid's columns and rows (2–16) and the size of new windows.
  - Tidy up: pack every window on the workspace toward the top-left, keeping
    its size.
  - Show or hide the resize dots.
- **Keyboard control** that leaves text editing alone:

  | Keys | Action |
  |---|---|
  | Super+Ctrl+← → | Shrink / grow width |
  | Super+Ctrl+↑ ↓ | Shrink / grow height |
  | Super+Ctrl+G | Grid mode: arrows move, Shift+arrows resize, 1–4 set sizes, Esc leaves |
  | Super+drag | Move a window to other cells |

Panel settings are saved to `~/.local/state/omarchy/cellgrid-settings.lua` and
survive Hyprland reloads and restarts.

## Requirements

- Omarchy 4 with the Lua Hyprland config (`~/.config/hypr/hyprland.lua`).
- The Omarchy shell (Quickshell).

It was built and tested on Omarchy 4.0.2, Hyprland 0.56.1 and Quickshell 0.3.1.

## Install

```bash
omarchy plugin add https://github.com/MrSlothuus/omarchy-grid.git --enable
~/.config/omarchy/plugins/slothuus.grid/install.sh
```

The first command installs the shell plugin, which adds the bar panel and the
resize dots. The second command sets up the Hyprland side:

- It links `hypr/cellgrid.lua` to `~/.config/hypr/cellgrid.lua`. If you
  already have a file there, it's moved aside first.
- It adds `require("hypr.cellgrid")` to the end of `hyprland.lua`.
- It reloads Hyprland.

The Grid button appears in the bar after the workspace numbers. To move it:

```bash
omarchy bar move slothuus.grid --section right
```

## Update

```bash
omarchy plugin update slothuus.grid
```

`cellgrid.lua` is a link into the plugin folder, so this updates the layout
too. Hyprland picks up the change the next time it reloads (`hyprctl reload`).

## Uninstall

```bash
~/.config/omarchy/plugins/slothuus.grid/uninstall.sh
omarchy plugin remove slothuus.grid
```

## How it works

The grid has three parts:

| File | Runs in | Does |
|---|---|---|
| `hypr/cellgrid.lua` | Hyprland | Registers the `lua:cellgrid` layout. Places and resizes tiles. Provides the key bindings and Super+drag. Saves settings. |
| `Overlay.qml` | Omarchy shell | Draws the grid during drags and the corner resize dots. |
| `Panel.qml` | Omarchy shell | The bar button and its Grid panel. |

The shell parts talk to the layout through Hyprland's Lua runtime. They read
state with `hyprctl repl 'return require("hypr.cellgrid").settings_json()'`
and make changes with `hyprctl eval`. Hyprland sends no event when a layout
moves windows, so `cellgrid.lua` rewrites
`$XDG_RUNTIME_DIR/cellgrid-layout-changed` after every change. The shell
watches that file to keep the dots and the panel up to date.

To change the defaults used before you've touched the panel, edit the
variables at the top of `hypr/cellgrid.lua`.

## License

MIT
