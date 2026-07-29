import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import lib.utility as utility
from lib.ccd import model

FIXTURE_YAML = """
pages:
  - id: home
    title: Home
    icon: "\U000f02dc"
    layout:
      - type: section
        properties:
          title: Quick Actions
        items:
          - type: toggle
            properties:
              title: Dark Mode
              icon: "\U000f0594"
              key: theme/dark_mode
              default: true
            on_toggle:
              enabled: {command: "echo on"}
              disabled: {command: "echo off"}
          - type: slider
            properties:
              title: Gaps
              key: hypr/gaps
              min: 0
              max: 40
              step: 1
              default: 8
            on_change:
              command: "hcm apply general:gaps_in {value}"
      - type: section
        properties:
          title: Info
        items:
          - type: label
            properties:
              title: CPU
              icon: "\U000f01c4"
            value:
              type: system
              key: cpu
          - type: selection
            properties:
              title: Layout
              key: hypr/layout
              options: [dwindle, master]
            on_change:
              command: "hcm apply general:layout {value}"
"""


class ModelTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp_path = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

        self.config_path = tmp_path / "config.yaml"
        self.config_path.write_text(FIXTURE_YAML)

        settings_patch = mock.patch.object(
            utility, "SETTINGS_DIR", tmp_path / "settings"
        )
        settings_patch.start()
        self.addCleanup(settings_patch.stop)

        thumb_patch = mock.patch.object(model, "THUMB_DIR", tmp_path / "thumbs")
        thumb_patch.start()
        self.addCleanup(thumb_patch.stop)


class TestLoadModel(ModelTest):
    def test_pages_sections_items_come_through(self):
        result = model.load_model(self.config_path)
        home = result["pages"][0]
        self.assertEqual(home["id"], "home")
        self.assertEqual(home["kind"], "yaml")
        self.assertEqual(home["sections"][0]["title"], "Quick Actions")
        titles = [i["title"] for i in home["sections"][0]["items"]]
        self.assertEqual(titles, ["Dark Mode", "Gaps"])

    def test_items_get_stable_ids(self):
        result = model.load_model(self.config_path)
        items = result["pages"][0]["sections"][0]["items"]
        self.assertEqual(items[0]["id"], "home/0/0")
        self.assertEqual(items[1]["id"], "home/0/1")
        second_section = result["pages"][0]["sections"][1]["items"]
        self.assertEqual(second_section[0]["id"], "home/1/0")

    def test_icons_pass_through_unchanged(self):
        # config.yaml holds literal Nerd Font glyphs directly — no name-to-glyph
        # translation layer — so the model's icon field is exactly what's there.
        result = model.load_model(self.config_path)
        home = result["pages"][0]
        dark_mode = home["sections"][0]["items"][0]
        self.assertEqual(home["icon"], "\U000f02dc")
        self.assertEqual(dark_mode["icon"], "\U000f0594")

    def test_toggle_initial_state_from_settings(self):
        utility.save_setting("theme/dark_mode", False)
        result = model.load_model(self.config_path)
        dark_mode = result["pages"][0]["sections"][0]["items"][0]
        self.assertIs(dark_mode["value"], False)

    def test_toggle_initial_state_falls_back_to_default(self):
        result = model.load_model(self.config_path)
        dark_mode = result["pages"][0]["sections"][0]["items"][0]
        self.assertIs(dark_mode["value"], True)

    def test_slider_and_selection_initial_values(self):
        utility.save_setting("hypr/gaps", 12)
        result = model.load_model(self.config_path)
        items = result["pages"][0]["sections"][0]["items"]
        self.assertEqual(items[1]["value"], 12.0)
        selection = result["pages"][0]["sections"][1]["items"][1]
        self.assertEqual(selection["options"], ["dwindle", "master"])

    def test_native_pages_are_appended_with_qml_kinds(self):
        result = model.load_model(self.config_path)
        by_id = {p["id"]: p for p in result["pages"]}
        wifi = by_id["__wifi__"]
        self.assertEqual(wifi["kind"], "wifi")
        self.assertEqual(wifi["title"], "Wi-Fi")
        self.assertNotIn("deep_link", wifi)

    def test_ported_native_pages_get_their_own_kind(self):
        result = model.load_model(self.config_path)
        by_id = {p["id"]: p for p in result["pages"]}
        self.assertEqual(by_id["__mon__"]["kind"], "monitors")
        self.assertEqual(by_id["__rules__"]["kind"], "rules_startup")
        self.assertEqual(by_id["__hkbm__"]["kind"], "keybinds")
        self.assertEqual(by_id["__bt__"]["kind"], "bluetooth")
        self.assertEqual(by_id["__wifi__"]["kind"], "wifi")
        self.assertEqual(by_id["__battery__"]["kind"], "battery")
        self.assertEqual(by_id["__audio__"]["kind"], "audio")
        self.assertEqual(by_id["__region__"]["kind"], "region")
        self.assertNotIn("deep_link", by_id["__mon__"])
        self.assertNotIn("deep_link", by_id["__bt__"])

    def test_categories_reference_page_ids(self):
        result = model.load_model(self.config_path)
        categories = {c["title"]: c["pages"] for c in result["categories"]}
        self.assertIn("__wifi__", categories["System"])
        self.assertIn("appearance", categories["Visuals"])

    def test_items_registry_holds_raw_item_config(self):
        model.load_model(self.config_path)
        raw = model.ITEMS["home/0/0"]
        self.assertEqual(raw["on_toggle"]["enabled"]["command"], "echo on")


class TestRealConfig(unittest.TestCase):
    def test_real_config_parses_with_full_icon_coverage(self):
        result = model.load_model()
        page_ids = [p["id"] for p in result["pages"]]
        self.assertIn("home", page_ids)
        self.assertIn("__wifi__", page_ids)

        # Icons are literal glyphs now, no ICON_MAP to fall back on — catch a
        # stale freedesktop-style name (e.g. copy-pasted from an old page)
        # rendering as literal text instead of an icon.
        def walk_icons(pages):
            for page in pages:
                if page.get("icon"):
                    yield page["id"], page["icon"]
                for section in page.get("sections", []):
                    for item in section.get("items", []):
                        if item.get("icon"):
                            yield item["id"], item["icon"]

        stale = [
            (owner, icon) for owner, icon in walk_icons(result["pages"])
            if icon.isascii()
        ]
        self.assertEqual(stale, [], f"non-glyph icon values: {stale}")


WALLPAPER_YAML = """
pages:
  - id: walls
    title: Walls
    layout:
      - type: section
        properties: {title: Pick}
        items:
          - type: wallpaper_picker
            properties:
              title: Wallpaper
              key: wallpaper/current
              directory: "{dir}"
              columns: 4
            on_select: {command: "echo {path}"}
"""


class TestWallpaperPickerModel(ModelTest):
    def test_wallpapers_listed_sorted_with_current(self):
        wall_dir = Path(self.tmp.name) / "walls"
        wall_dir.mkdir()
        (wall_dir / "b.png").write_bytes(b"x")
        (wall_dir / "a.jpg").write_bytes(b"x")
        (wall_dir / "notes.txt").write_bytes(b"x")
        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(WALLPAPER_YAML.replace("{dir}", str(wall_dir)))
        utility.save_setting("wallpaper/current", str(wall_dir / "a.jpg"))

        result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        self.assertEqual(
            [w["path"] for w in item["wallpapers"]],
            [str(wall_dir / "a.jpg"), str(wall_dir / "b.png")],
        )
        self.assertTrue(all("thumb" in w for w in item["wallpapers"]))
        self.assertEqual(item["current"], str(wall_dir / "a.jpg"))

    def test_missing_directory_property_yields_empty_list(self):
        # cwd contains an image: an empty directory must not fall back to cwd.
        cwd_dir = Path(self.tmp.name) / "cwd"
        cwd_dir.mkdir()
        (cwd_dir / "sneaky.jpg").write_bytes(b"x")
        old_cwd = Path.cwd()
        os.chdir(cwd_dir)
        self.addCleanup(os.chdir, old_cwd)

        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(
            WALLPAPER_YAML.replace('              directory: "{dir}"\n', "")
        )

        result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        self.assertEqual(item["wallpapers"], [])

    def test_nonexistent_directory_yields_empty_list(self):
        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(
            WALLPAPER_YAML.replace("{dir}", str(Path(self.tmp.name) / "missing"))
        )

        result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        self.assertEqual(item["wallpapers"], [])

    def test_max_items_caps_the_list_like_gtk_picker(self):
        wall_dir = Path(self.tmp.name) / "walls"
        wall_dir.mkdir()
        for name in ["a.jpg", "b.jpg", "c.jpg"]:
            (wall_dir / name).write_bytes(b"x")
        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(
            WALLPAPER_YAML.replace('directory: "{dir}"', f'directory: "{wall_dir}"\n              max_items: 2')
        )

        result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        self.assertEqual(len(item["wallpapers"]), 2)

    def test_undecodable_file_falls_back_to_original_path(self):
        wall_dir = Path(self.tmp.name) / "walls"
        wall_dir.mkdir()
        (wall_dir / "a.jpg").write_bytes(b"x")  # not a real image
        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(WALLPAPER_YAML.replace("{dir}", str(wall_dir)))

        result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        # b"x" isn't decodable by Pillow either way; thumb falls back to path.
        self.assertEqual(item["wallpapers"][0]["thumb"], str(wall_dir / "a.jpg"))

    def test_mode_subdirs_scanned_recursively_like_gtk_picker(self):
        # ~/Wallpapers layout: Dark/, Light/nested/, user_wallpapers/Light/.
        # With THEME_MODE=light only the Light trees are listed, recursively.
        base = Path(self.tmp.name) / "walls"
        for sub in ["Dark", "Light/nested", "user_wallpapers/Light"]:
            (base / sub).mkdir(parents=True)
        (base / "Dark" / "d.jpg").write_bytes(b"x")
        (base / "Light" / "a.jpg").write_bytes(b"x")
        (base / "Light" / "nested" / "b.png").write_bytes(b"x")
        (base / "user_wallpapers" / "Light" / "u.webp").write_bytes(b"x")

        state = Path(self.tmp.name) / "state.conf"
        state.write_text('THEME_MODE="light"\n')

        config = Path(self.tmp.name) / "walls.yaml"
        config.write_text(WALLPAPER_YAML.replace("{dir}", str(base)))

        with mock.patch.object(model, "THEME_STATE", state):
            result = model.load_model(config)
        item = result["pages"][0]["sections"][0]["items"][0]
        self.assertEqual(
            [w["path"] for w in item["wallpapers"]],
            sorted([
                str(base / "Light" / "a.jpg"),
                str(base / "Light" / "nested" / "b.png"),
                str(base / "user_wallpapers" / "Light" / "u.webp"),
            ]),
        )


if __name__ == "__main__":
    unittest.main()
