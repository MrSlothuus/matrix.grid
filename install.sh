#!/bin/bash
# Hyprland half of the Matrix Grid plugin. `omarchy plugin add` installs the
# shell plugin; this links the layout into ~/.config/hypr and loads it from
# hyprland.lua. With --screensaver it also makes Omarchy's idle screensaver
# play the matrix rain. Safe to run again, e.g. after `omarchy plugin update`.
set -euo pipefail

screensaver=false
for arg in "$@"; do
  case $arg in
    --screensaver) screensaver=true ;;
    *) echo "Usage: install.sh [--screensaver]" >&2; exit 2 ;;
  esac
done

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
hypr_dir="$config_home/hypr"
layout="$hypr_dir/cellgrid.lua"
config="$hypr_dir/hyprland.lua"
require_line='require("hypr.cellgrid")'

[[ -f $config ]] || { echo "No $config found. Matrix Grid needs Omarchy's Lua Hyprland config." >&2; exit 1; }

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
  printf '\n-- Arrange tiled windows on a cell grid (matrix.grid plugin).\n%s\n' "$require_line" >> "$config"
  echo "Added $require_line to $config"
fi

if $screensaver; then
  # Omarchy's idle service runs omarchy-launch-screensaver and has no setting
  # to change that, so point a clone of the service at the matrix rain.
  plugins_dir="$config_home/omarchy/plugins"
  launcher="$plugin_dir/screensaver/matrix-rain"
  stock_launch='|| omarchy-launch-screensaver"'
  matrix_launch="|| ${launcher/#$HOME/\$HOME}\""

  idle_clone() {
    local manifest
    for manifest in "$plugins_dir"/*/manifest.json; do
      if [[ -f $manifest ]] && jq -e '.omarchy.clonedFrom == "omarchy.idle"' "$manifest" >/dev/null 2>&1; then
        dirname "$manifest"
        return 0
      fi
    done
    return 1
  }

  if ! idle_dir="$(idle_clone)"; then
    omarchy plugin clone omarchy.idle >/dev/null
    idle_dir="$(idle_clone)" || { echo "Could not clone Omarchy's idle service." >&2; exit 1; }
    echo "Cloned Omarchy's idle service to $idle_dir"
  fi

  service="$idle_dir/Service.qml"
  content="$(<"$service")"
  if [[ $content == *"$matrix_launch"* ]]; then
    echo "The idle screensaver already plays the matrix rain"
  elif [[ $content == *"$stock_launch"* ]]; then
    printf '%s\n' "${content//"$stock_launch"/"$matrix_launch"}" > "$service"
    echo "The idle screensaver now plays the matrix rain ($service)"
  else
    echo "Your idle service's screensaver command is customised already." >&2
    echo "Point it at $launcher in $service" >&2
  fi
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
