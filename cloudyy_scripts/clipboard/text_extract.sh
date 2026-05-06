#!/usr/bin/env bash

if ! command -v tesseract &> /dev/null; then
    notify-send "Live Text Extraction" "tesseract is not installed. Please install it (e.g. pacman -S tesseract tesseract-data-eng)."
    exit 1
fi

# Capture region, freeze screen, output raw image to tesseract, and suppress hyprcap's own notification
if hyprcap shot region -z -r -N | tesseract stdin stdout | wl-copy; then
    notify-send "Live Text Extraction" "Text copied to clipboard!"
else
    notify-send "Live Text Extraction" "Failed to extract text."
fi
