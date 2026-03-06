import json
from pathlib import Path

# Define the source path
MATUGEN_OUTPUT = Path.home() / ".config/matugen/generated/vscode.json"

# Define all target paths (VS Code, Arch VSCodium, Standard VSCodium)
TARGET_SETTINGS = [
    Path.home() / ".config/Code/User/settings.json",
    Path.home() / ".config/Code - OSS/User/settings.json",
    Path.home() / ".config/VSCodium/User/settings.json"
]

def update_settings():
    # 1. Load the new colors
    try:
        with open(MATUGEN_OUTPUT, 'r') as f:
            new_colors = json.load(f)
    except FileNotFoundError:
        print("Matugen output not found.")
        return

    # 2. Iterate through each IDE's configuration path
    for settings_path in TARGET_SETTINGS:
        # Skip this iteration if the IDE's config folder doesn't exist
        if not settings_path.parent.exists():
            continue

        # Load existing settings
        try:
            with open(settings_path, 'r') as f:
                current_settings = json.load(f)
        except FileNotFoundError:
            current_settings = {}
        except json.JSONDecodeError:
            print(f"JSON syntax error in: {settings_path}")
            continue

        # 3. Merge the theme data
        if "workbench.colorCustomizations" not in current_settings:
            current_settings["workbench.colorCustomizations"] = {}
        if "editor.tokenColorCustomizations" not in current_settings:
            current_settings["editor.tokenColorCustomizations"] = {}
            
        current_settings.update(new_colors)

        # 4. Save the file back to disk
        with open(settings_path, 'w') as f:
            json.dump(current_settings, f, indent=4)
            
        print(f"Injected theme into: {settings_path}")

if __name__ == "__main__":
    update_settings()