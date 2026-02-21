#!/usr/bin/env bash

get_fontmenu() {
  if [[ -z "$1" ]]; then
    fc-list : family | cut -d, -f1 | sort -u
  else
    local selected_font="$1"
    echo -n "$selected_font" | wl-copy
    notify-send "Font Selected" "Copied '$selected_font' to clipboard!"
  fi
}
get_fontmenu "$@"
