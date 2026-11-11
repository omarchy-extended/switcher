#!/bin/bash
# Removes what install.sh added: Alt + Tab is Omarchy's again.
set -uo pipefail
omarchy plugin disable omext.switcher >/dev/null 2>&1
[[ -L $HOME/.config/omarchy/plugins/omext.switcher ]] && rm "$HOME/.config/omarchy/plugins/omext.switcher"
hypr_conf=$HOME/.config/hypr/hyprland.lua
[[ -f $hypr_conf ]] && sed -i "/^-- BEGIN omext-switcher\$/,/^-- END omext-switcher\$/d" "$hypr_conf" && hyprctl reload >/dev/null
menu_conf=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
[[ -f $menu_conf ]] && sed -i "\|^ *// BEGIN omext-switcher\$|,\|^ *// END omext-switcher\$|d" "$menu_conf"
echo "uninstall: done (your settings are still in ~/.config/omext/switcher.json)"
