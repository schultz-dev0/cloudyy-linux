from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
ROFI_MAIN = REPO_ROOT / "cloudyy_scripts" / "rofi" / "main.sh"


def test_cloudcenter_rofi_entry_uses_valid_hyprctl_exec_command():
    text = ROFI_MAIN.read_text(encoding="utf-8")
    assert 'exec "${HOME}/cloudyy_scripts/cloud-center"' in text
    assert 'hyprctl dispatch exec' not in text
