-- omext switcher: Alt + Tab steps through the open windows in a list, last used
-- first, and letting go of Alt goes to the one chosen (Shift + Tab steps back).
-- Only while the switcher is on in the shell: off, Omarchy's own Alt + Tab
-- (focus the next window) stays.
local config = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omarchy/shell.json"
local f = io.open(config, "r")
local text = f and f:read("*a") or ""
if f then f:close() end
if text:find('"omext.switcher"', 1, true) then
  pcall(hl.unbind, "ALT + TAB")
  pcall(hl.unbind, "ALT + SHIFT + TAB")
  hl.bind("ALT + TAB", hl.dsp.global("omext:switcher-next"), { description = "Switch window", repeating = true })
  hl.bind("ALT + SHIFT + TAB", hl.dsp.global("omext:switcher-prev"), { description = "Switch window, backwards", repeating = true })
  -- Alt let go: there. (The list also sees it, having the keyboard while it's
  -- up; this is for a quick Alt + Tab, let go before the list shows.)
  for _, key in ipairs({ "Alt_L", "Alt_R" }) do
    hl.bind(key, hl.dsp.global("omext:switcher-release"),
      { release = true, transparent = true, ignore_mods = true, non_consuming = true })
  end
end
