import json
import os
import tempfile
from datetime import datetime
from pathlib import Path

# Define the source path
MATUGEN_OUTPUT = Path.home() / ".config/matugen/generated/vscode.json"

# Define all target paths (VS Code, Arch VSCodium, Standard VSCodium)
TARGET_SETTINGS = [
    Path.home() / ".config/Code/User/settings.json",
    Path.home() / ".config/Code - OSS/User/settings.json",
    Path.home() / ".config/VSCodium/User/settings.json",
]


def update_settings():
    # 1. Load the new colors
    try:
        with open(MATUGEN_OUTPUT, "r") as f:
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
            with open(settings_path, "r") as f:
                current_settings = json.load(f)
        except FileNotFoundError:
            current_settings = {}
        except json.JSONDecodeError:
            backup_path = settings_path.with_suffix(
                settings_path.suffix
                + f".invalid-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            )
            try:
                os.replace(settings_path, backup_path)
                print(
                    f"JSON syntax error in: {settings_path} (backed up to {backup_path})"
                )
            except OSError:
                print(
                    f"JSON syntax error in: {settings_path} (could not create backup, rewriting anyway)"
                )
            current_settings = {}

        # 3. Merge the theme data
        if "workbench.colorCustomizations" not in current_settings:
            current_settings["workbench.colorCustomizations"] = {}
        if "editor.tokenColorCustomizations" not in current_settings:
            current_settings["editor.tokenColorCustomizations"] = {}

        current_settings.update(new_colors)

        # 4. Save atomically to avoid partial writes on interruption
        with tempfile.NamedTemporaryFile(
            "w", dir=settings_path.parent, delete=False, suffix=".tmp"
        ) as tf:
            json.dump(current_settings, tf, indent=4)
            tmp_name = tf.name
        os.replace(tmp_name, settings_path)

        print(f"Injected theme into: {settings_path}")


if __name__ == "__main__":
    update_settings()

