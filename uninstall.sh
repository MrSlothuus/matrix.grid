#!/bin/bash
# Undo install.sh: stop loading the layout, remove its link, and point the idle
# screensaver back at Omarchy's own. Afterwards, remove the shell plugin with:
# omarchy plugin remove matrix.grid
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
hypr_dir="$config_home/hypr"
layout="$hypr_dir/cellgrid.lua"
config="$hypr_dir/hyprland.lua"

if [[ -f $config ]] && grep -qF 'require("hypr.cellgrid")' "$config"; then
  cp "$config" "$config.bak.$(date +%Y%m%d-%H%M%S)"
  sed -i -e '/^-- Arrange tiled windows on a cell grid (matrix\.grid plugin)\.$/d' \
    -e '/^require("hypr\.cellgrid")$/d' "$config"
  echo "Stopped loading the grid in $config (backup saved next to it)"
fi

if [[ -L $layout && $(readlink "$layout") == "$plugin_dir/hypr/cellgrid.lua" ]]; then
  rm "$layout"
  echo "Removed $layout"
fi

launcher="$plugin_dir/screensaver/matrix-rain"
matrix_launch="|| ${launcher/#$HOME/\$HOME}\""
stock_launch='|| omarchy-launch-screensaver"'
for service in "$config_home"/omarchy/plugins/*/Service.qml; do
  [[ -f $service ]] || continue
  content="$(<"$service")"
  if [[ $content == *"$matrix_launch"* ]]; then
    printf '%s\n' "${content//"$matrix_launch"/"$stock_launch"}" > "$service"
    echo "The idle screensaver is Omarchy's own again ($service)"
  fi
done

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  echo "Hyprland reloaded with its standard layout."
fi
# Stop loading the rain shader into the wallpaper engine.
"$plugin_dir/screensaver/matrix-rain-wallpaper" --remove &&
  echo "The wallpaper engine no longer loads the matrix rain shader."
echo "Now run: omarchy plugin remove matrix.grid"
