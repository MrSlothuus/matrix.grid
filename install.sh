#!/bin/bash
# Hyprland half of the Grid plugin. `omarchy plugin add` installs the shell
# plugin; this links the layout into ~/.config/hypr and loads it from
# hyprland.lua. Safe to run again, e.g. after `omarchy plugin update`.
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
layout="$hypr_dir/cellgrid.lua"
config="$hypr_dir/hyprland.lua"
require_line='require("hypr.cellgrid")'

[[ -f $config ]] || { echo "No $config found. Grid needs Omarchy's Lua Hyprland config." >&2; exit 1; }

# Link the layout so plugin updates update it too. Keep any existing copy.
if [[ -e $layout && ! -L $layout ]]; then
  backup="$layout.bak.$(date +%Y%m%d-%H%M%S)"
  mv "$layout" "$backup"
  echo "Moved your existing cellgrid.lua to $backup"
fi
ln -sfn "$plugin_dir/hypr/cellgrid.lua" "$layout"
echo "Linked $layout"

# Load it last, after Omarchy's defaults, so its key and mouse bindings win.
if grep -qF "$require_line" "$config"; then
  echo "hyprland.lua already loads the grid"
else
  printf '\n-- Arrange tiled windows on a cell grid (omarchy-grid plugin).\n%s\n' "$require_line" >> "$config"
  echo "Added $require_line to $config"
fi

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  errors="$(hyprctl configerrors)"
  if [[ -n ${errors//[[:space:]]/} ]]; then
    echo "Hyprland reported config errors:" >&2
    echo "$errors" >&2
    exit 1
  fi
  echo "Hyprland reloaded. The grid is active."
fi
