#!/usr/bin/env bash

# Paths
PERSONAL_MSG="$HOME/.config/hypr/welcome_message.txt"
USER_MSG="$HOME/.config/hypr/USER_WELCOME_MESSAGE.txt"

if [[ -f "$PERSONAL_MSG" ]]; then
  FILE="$PERSONAL_MSG"
else
  FILE="$USER_MSG"
fi

# Filter, Randomise.
grep '^>' "$FILE" | shuf -n 1 | sed 's/^>//;s/^"//;s/"$//'
