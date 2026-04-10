#!/usr/bin/env bash
# Apply system theme environment variables
# Source this in your shell rc files: source ~/.config/hypr/theme_state/apply_theme.sh

THEME_ENV="${HOME}/.config/hypr/theme_state/system_theme.env"

# Source the generated theme environment if it exists
if [[ -f "$THEME_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$THEME_ENV"
fi

# Ensure QT_QPA_PLATFORMTHEME follows system preference for native look
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-kvantum}"

# Apply to current environment if variables are set
if [[ -n "${GTK_THEME_VARIANT:-}" ]]; then
  export GTK_THEME="${GTK_THEME}${GTK_THEME:+:}HighContrast"
fi

# Ensure color output preferences match theme
if [[ "${GTK_THEME_VARIANT:-dark}" == "light" ]]; then
  export COLORFGBG="7;0"  # Light mode
else
  export COLORFGBG="0;7"  # Dark mode
fi
