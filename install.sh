#!/bin/bash
# Installs omext switcher (omarchy-extended) on Omarchy, from this folder: a
# link, so a git pull here updates it. Safe to run again. To undo: ./uninstall.sh
set -euo pipefail

dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
plugins=$HOME/.config/omarchy/plugins
shell_conf=$HOME/.config/omarchy/shell.json
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
hypr_conf=$HOME/.config/hypr/hyprland.lua
mark=omext-switcher

die() { echo "install: $*" >&2; exit 1; }
info() { echo "install: $*"; }

for cmd in jq hyprctl omarchy omarchy-shell; do
  command -v "$cmd" >/dev/null || die "needs $cmd (Omarchy)"
done
[[ -e $HOME/.local/share/omarchy-addons/enabled/switcher ]] && die "switcher is already deployed by omx here"
[[ -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins ]] || die "needs Omarchy 4.5 or later (its shell plugins)"
[[ -f $hypr_conf ]] || die "no $hypr_conf"

target=$plugins/omext.switcher
if [[ -e $target && ! -L $target ]]; then die "$target is there already (not a link); move it away first"; fi
mkdir -p "$plugins"
ln -sfn "$dir/plugins/omext.switcher" "$target"

# omext core (what the omext addons share): installed too when it's missing,
# and brought up to date when it's the copy installed this way.
core=${XDG_DATA_HOME:-$HOME/.local/share}/omext-core
if [[ ! -e $plugins/omext.core ]]; then
  [[ -d $core ]] || git clone -q https://github.com/omarchy-extended/core.git "$core" || die "needs omext core (https://github.com/omarchy-extended/core)"
  "$core/install.sh" >/dev/null || die "omext core's install failed"
elif [[ -d $core/.git && $(readlink -f "$plugins/omext.core") == "$core"/* ]]; then
  git -C "$core" pull -q --ff-only 2>/dev/null || info "couldn't update omext core (run: git -C $core pull)"
fi

# Hyprland: Alt + Tab (hypr/switcher.lua), loaded at every (re)load.
sed -i "/^-- BEGIN $mark\$/,/^-- END $mark\$/d" "$hypr_conf"
{
  echo "-- BEGIN $mark"
  echo "pcall(dofile, \"$dir/hypr/switcher.lua\")"
  echo "-- END $mark"
} >> "$hypr_conf"
hyprctl reload >/dev/null

# The Omarchy menu: its entries, before the file's last brace.
mkdir -p "$(dirname "$menu_conf")"
[[ -s $menu_conf ]] || printf '{\n}\n' > "$menu_conf"
sed -i "\|^ *// BEGIN $mark\$|,\|^ *// END $mark\$|d" "$menu_conf"
block=$(sed '1d;$d' "$dir/menu.jsonc")
tmp=$(mktemp)
# The block through the environment: awk -v would take its backslashes as escapes.
BLOCK=$block awk -v begin="  // BEGIN $mark" -v end="  // END $mark" '
  { lines[NR] = $0 }
  /^[[:space:]]*}[[:space:]]*$/ { last = NR }
  END {
    # The entry before ours needs its comma (JSON has no trailing one to rely on).
    p = last - 1
    while (p > 0 && lines[p] ~ /^[[:space:]]*(\/\/.*)?$/) p--
    if (p > 0 && lines[p] !~ /[,{][[:space:]]*$/) lines[p] = lines[p] ","
    for (i = 1; i <= NR; i++) { if (i == last) { print begin; print ENVIRON["BLOCK"]; print end } print lines[i] } }
' "$menu_conf" > "$tmp"
cat "$tmp" > "$menu_conf"
rm "$tmp"

# The switcher on (a service plugin), then Hyprland reads its keys again:
# hypr/switcher.lua takes Alt + Tab only while the plugin is on.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1  # the rescan finishes in the background
grep -q '"omext.switcher"' "$HOME/.config/omarchy/shell.json" 2>/dev/null || omarchy plugin enable omext.switcher >/dev/null
sleep 0.5
hyprctl reload >/dev/null
info "done. Hold Alt and press Tab: the open windows, last used first. Let go of Alt to go to the one chosen."
