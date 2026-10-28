# dmgbuild settings for Carbon's install window, written straight into the DMG's .DS_Store
# (no Finder, so it runs headless in CI). make-dmg.sh passes app, background and volume_icon.
# Icon positions are icon centres from the window's top left, matching background.swift.
import os.path

app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]
icon = defines["volume_icon"]
background = defines["background"]

# Finder bounds, title bar included.
window_rect = ((200, 120), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (160, 140),
    "Applications": (440, 140),
}
