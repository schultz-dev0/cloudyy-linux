# Cloud Center

Universal control center for Hyprland — embeds hkbm, hcm, and theme-ui in
one GTK4 window. Fully modular and expandable.

## Dependencies

```bash
sudo pacman -S python-gobject gtk4 libadwaita vte4
```

## Install

Place this folder inside `~/cloudyy_scripts/cloudyy-other/cloud-center/`.

Make executable:
```bash
chmod +x cloud-center.py
```

Install desktop entry (for rofi drun):
```bash
cp cloud-center.desktop ~/.local/share/applications/
```

## Launch

```bash
python3 ~/cloudyy_scripts/cloudyy-other/cloud-center/cloud-center.py
```

Or add to Hyprland:
```conf
bind = $mod, C, exec, python3 ~/cloudyy_scripts/cloudyy-other/cloud-center/cloud-center.py

windowrulev2 = float,          class:cloud-center
windowrulev2 = size 1200 750,  class:cloud-center
windowrulev2 = center,         class:cloud-center
```

## Adding a new module

1. Create `modules/<id>.py`:

```python
from base import BaseModule
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

class Module(BaseModule):
    name = "My Tool"
    icon = "some-icon-name"          # any Adwaita icon name

    def build(self) -> Gtk.Widget:
        # For a TUI binary:
        term = self.make_terminal("mybinary")
        return self.make_page("My Tool", "Short description", term)

        # For a native GTK panel, return any Gtk.Widget instead
```

2. Add an entry to `REGISTRY` in `cloud-center.py`:

```python
("myid", "My Tool", "some-icon-name", "Category"),
```

That's it. The module is lazily loaded on first click.

## Module interface

`BaseModule` provides:
- `self.bin_dir` — path to `cloudyy-other/`, where binaries live
- `make_terminal(command)` — spawns command in a VTE widget, auto-restarts on exit
- `make_page(title, subtitle, widget)` — wraps any widget in the standard page header

## File structure

```
cloud-center/
├── cloud-center.py       # entry point, window, sidebar, module loader
├── modules/
│   ├── __init__.py
│   ├── base.py           # BaseModule — inherit from this
│   ├── theme.py          # theme-ui
│   ├── keybinds.py       # hkbm
│   └── configs.py        # hcm
├── assets/
│   └── style.css         # styling on top of Adwaita
└── cloud-center.desktop  # launcher entry
```
