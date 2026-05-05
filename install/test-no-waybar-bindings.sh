#!/usr/bin/env bash
# TDD regression test: verify no active Hyprland binding files contain legacy waybar launch paths

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "Testing: no active Hyprland bindings should reference launch_waybar.sh"

BINDING_FILES=(
    ".config/hypr/source/bindings.conf"
    ".config/hypr/user-configs/user_bindings.conf"
    ".config/hypr/.hyprlua/bindings.lua"
)

FAILED=0

for file in "${BINDING_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  SKIP: $file (not found)"
        continue
    fi
    
    if grep -q "launch_waybar.sh" "$file"; then
        echo "  FAIL: $file still contains launch_waybar.sh"
        FAILED=1
    else
        echo "  PASS: $file"
    fi
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "❌ Test FAILED: legacy waybar bindings still present"
    exit 1
else
    echo ""
    echo "✅ Test PASSED: no waybar bindings found"
    exit 0
fi
