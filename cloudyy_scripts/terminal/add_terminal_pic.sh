#!/usr/bin/env bash

PIC_DIR="${HOME}/cloudyy-linux/extras/terminal_pic"
mkdir -p "$PIC_DIR"

# Pick a file using zenity
SELECTED_FILE=$(zenity --file-selection --title="Select Terminal Mascot" --file-filter="Images | *.png *.jpg *.jpeg *.webp")

if [[ -z "$SELECTED_FILE" ]]; then
    exit 0
fi

# Get base name without extension
BASE_NAME=$(basename "$SELECTED_FILE")
NAME_NO_EXT="${BASE_NAME%.*}"

# Copy original to PIC_DIR
cp "$SELECTED_FILE" "${PIC_DIR}/${BASE_NAME}"

# Convert to base64
base64 "$SELECTED_FILE" > "${PIC_DIR}/${NAME_NO_EXT}.b64"

notify-send "Cloud Center" "Added terminal mascot: ${NAME_NO_EXT}"
