# dmgbuild settings for MacPen-macos-<arch>.dmg, called by Scripts/package_app.sh.
# Opens as a 540x380 window laid out like 页间's installer: MacPen on the left, the Applications
# shortcut on the right, a dashed arrow between them (drawn by Scripts/dmg/background.swift) and
# the install note on top.
#
# package_app.sh passes these with -D: app (the signed MacPen.app), readme, background, icon (volume icon).
import os.path

app = defines["app"]
readme = defines["readme"]

format = "UDZO"
files = [app, readme]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

window_rect = ((400, 530), (540, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 88
text_size = 12
icon_locations = {
    os.path.basename(app): (130, 220),
    "Applications": (410, 220),
    os.path.basename(readme): (270, 75),
}
