import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
HYPR_DIR = REPO_ROOT / ".config/hypr"


def test_source_colors_bridge_is_explicit():
    colors_bridge = (HYPR_DIR / "source/colors.lua").read_text(encoding="utf-8")
    lookandfeel = (HYPR_DIR / "source/lookandfeel.lua").read_text(encoding="utf-8")
    assert '.hyprlua/colors.lua' in colors_bridge
    assert 'dofile(' in colors_bridge
    assert 'require("source.colors")' in lookandfeel
    assert 'require("colors")' not in lookandfeel
    assert 'return require("colors")' not in colors_bridge


def test_source_lookandfeel_omits_removed_dwindle_pseudotile_key():
    lookandfeel = (HYPR_DIR / "source/lookandfeel.lua").read_text(encoding="utf-8")
    assert "pseudotile" not in lookandfeel


def test_user_lookandfeel_does_not_emit_invalid_stayfocused_field():
    user_lookandfeel = (HYPR_DIR / "user-configs/user_lookandfeel.lua").read_text(encoding="utf-8")
    assert "stayfocused" not in user_lookandfeel


def test_source_bindings_live_text_extract_uses_valid_key_string():
    bindings = (HYPR_DIR / "source/bindings.lua").read_text(encoding="utf-8")
    assert 'mainMod .. " + SHIFT + E"' in bindings
    assert 'mainMod .. " SHIFT + E"' not in bindings
