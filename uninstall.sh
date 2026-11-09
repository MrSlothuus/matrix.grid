#!/bin/bash
# Undo install.sh: stop loading the layout and remove its link. Afterwards,
# remove the shell plugin with: omarchy plugin remove slothuus.grid
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hypr_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
layout="$hypr_dir/cellgrid.lua"
config="$hypr_dir/hyprland.lua"

if [[ -f $config ]] && grep -qF 'require("hypr.cellgrid")' "$config"; then
  cp "$config" "$config.bak.$(date +%Y%m%d-%H%M%S)"
  sed -i -e '/^-- Arrange tiled windows on a cell grid (omarchy-grid plugin)\.$/d' \
    -e '/^require("hypr\.cellgrid")$/d' "$config"
  echo "Stopped loading the grid in $config (backup saved next to it)"
fi

if [[ -L $layout && $(readlink "$layout") == "$plugin_dir/hypr/cellgrid.lua" ]]; then
  rm "$layout"
  echo "Removed $layout"
fi

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  echo "Hyprland reloaded with its standard layout."
fi
echo "Now run: omarchy plugin remove slothuus.grid"
