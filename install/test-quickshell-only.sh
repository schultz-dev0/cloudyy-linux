#!/usr/bin/env bash
# TDD regression test: verify quickshell is the ONLY active shell path
# Checks all surfaces: Cloud Center, matugen templates, deploy scripts, and Hyprland bindings

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "Testing: quickshell must be the only active shell path"
echo ""

FAILED=0

# Test 1: Cloud Center config.yaml must not expose active Waybar page
echo "[1/5] Checking cloudyy_scripts/cloud-center-v2/config.yaml..."
if grep -A5 "name: Waybar" cloudyy_scripts/cloud-center-v2/config.yaml | grep -q "icon:"; then
    echo "  FAIL: Cloud Center config still exposes active Waybar page block"
    FAILED=1
else
    echo "  PASS: No active Waybar page in Cloud Center config"
fi

# Test 2: Cloud Center Python must not expose waybar CLI/page route
echo "[2/5] Checking cloudyy_scripts/cloud-center-v2/cloud-center.py..."
if grep -E '(^[^#]*"waybar"|^[^#]*--waybar)' cloudyy_scripts/cloud-center-v2/cloud-center.py | grep -q .; then
    echo "  FAIL: Cloud Center Python still has active waybar route/CLI handling"
    FAILED=1
else
    echo "  PASS: No active waybar route in Cloud Center Python"
fi

# Test 3: matugen config must not have active Waybar/SwayNC template outputs
echo "[3/5] Checking .config/matugen/config.toml..."
if grep -E "(waybar|swaync)" .config/matugen/config.toml | grep -E "(output_path|input_path|\[templates\.(waybar|swaync)\])" | grep -qv "^#"; then
    echo "  FAIL: matugen config still has active Waybar/SwayNC template blocks"
    FAILED=1
else
    echo "  PASS: No active Waybar/SwayNC templates in matugen config"
fi

# Test 4: deploy-dotfiles.sh must not verify/manage Waybar/SwayNC as active shell state
echo "[4/5] Checking install/deploy-dotfiles.sh..."
if grep -E "(waybar|swaync)" install/deploy-dotfiles.sh | grep -v "^#" | grep -qE "(VERIFICATION|STATE|MANAGED|DEPLOY)"; then
    echo "  FAIL: deploy-dotfiles.sh still treats Waybar/SwayNC as active shell state"
    FAILED=1
else
    echo "  PASS: deploy-dotfiles.sh does not manage Waybar/SwayNC as active state"
fi

# Test 5: Hyprland bindings must not reference launch_waybar.sh
echo "[5/5] Checking Hyprland binding files..."
BINDING_FILES=(
    ".config/hypr/source/bindings.conf"
    ".config/hypr/user-configs/user_bindings.conf"
    ".config/hypr/.hyprlua/bindings.lua"
)

BINDING_FAILED=0
for file in "${BINDING_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  SKIP: $file (not found)"
        continue
    fi
    
    if grep -q "launch_waybar.sh" "$file"; then
        echo "  FAIL: $file still contains launch_waybar.sh"
        BINDING_FAILED=1
    else
        echo "  PASS: $file"
    fi
done

if [ $BINDING_FAILED -eq 1 ]; then
    FAILED=1
fi

echo ""
if [ $FAILED -eq 1 ]; then
    echo "❌ Test FAILED: Legacy shell surfaces still active"
    exit 1
else
    echo "✅ Test PASSED: quickshell is the only active shell path"
    exit 0
fi
