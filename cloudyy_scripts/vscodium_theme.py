import json
import os
from pathlib import Path

MATUGEN_OUTPUT = Path.home() / ".config/matugen/generated/vscode-theme.json"
VSCODIUM_SETTINGS = Path.home() / ".config/VSCodium/User/settings.json"

def update_settings():
    try:
        with open(MATUGEN_OUTPUT, 'r') as f:
            new_colors = json.load(f)
    except FileNotFoundError:
        print("Matugen output not found. Run Matugen first.")
        return

    try:
        with open(VSCODIUM_SETTINGS, 'r') as f:
            current_settings = json.load(f)
    except FileNotFoundError:
        current_settings = {}
    except json.JSONDecodeError:
        print("Error reading VSCodium settings. Ensure it is valid JSON.")
        return

    if "workbench.colorCustomizations" not in current_settings:
        current_settings["workbench.colorCustomizations"] = {}
    current_settings.update(new_colors)
    with open(VSCODIUM_SETTINGS, 'w') as f:
        json.dump(current_settings, f, indent=4)

    print("Successfully injected Matugen colors into VSCodium.")

if __name__ == "__main__":
    update_settings()
