#!/usr/bin/env bash
# TDD regression test: verify quickshell is the ONLY active shell path
# Checks all surfaces: Cloud Center, matugen templates, deploy scripts, and Hyprland bindings

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "Testing: quickshell must be the only active shell path"
echo ""

FAILED=0

# Test 0: Lua autostart must reference source/quickshell.conf as runtime source
echo "[0/9] Checking .config/hypr/.hyprlua/autostart.lua for unified quickshell startup..."
LUA_FAILED=0
# Must NOT hardcode the quickshell command in exec_cmd
if grep -E 'exec_cmd.*qs\s+-d' .config/hypr/.hyprlua/autostart.lua | grep -qv "^[[:space:]]*--"; then
    echo "  FAIL: autostart.lua contains hardcoded 'qs -d' in exec_cmd"
    LUA_FAILED=1
fi
# MUST read from source/quickshell.conf
if ! grep -q "source/quickshell.conf" .config/hypr/.hyprlua/autostart.lua; then
    echo "  FAIL: autostart.lua does not reference source/quickshell.conf as startup source"
    LUA_FAILED=1
fi
if [ $LUA_FAILED -eq 0 ]; then
    echo "  PASS: autostart.lua references source/quickshell.conf (no hardcoded startup)"
else
    FAILED=1
fi

# Test 1: deploy-dotfiles.sh must fail-closed on missing/non-executable widget_bridge.sh
echo "[1/9] Checking install/deploy-dotfiles.sh for fail-closed widget_bridge.sh handling..."
if grep -A 5 "widget_bridge.sh" install/deploy-dotfiles.sh | grep -qE "(exit 1|\|\| exit 1)"; then
    echo "  PASS: deploy-dotfiles.sh treats missing/non-executable widget_bridge.sh as fatal"
else
    echo "  FAIL: deploy-dotfiles.sh does not fail-closed on widget_bridge.sh issues"
    FAILED=1
fi

# Test 2: deploy-dotfiles.sh must exclude legacy shell dirs from active symlinking
echo "[2/9] Checking install/deploy-dotfiles.sh link_config_dirs() excludes waybar/swaync..."
# Check if link_config_dirs has exclusion logic for waybar/swaync
if grep -A 20 "^link_config_dirs()" install/deploy-dotfiles.sh | grep -B 1 -A 1 -E "(waybar|swaync)" | grep -q "continue"; then
    echo "  PASS: link_config_dirs() excludes legacy shell dirs"
else
    echo "  FAIL: link_config_dirs() still symlinks all .config/* including waybar/swaync without exclusions"
    FAILED=1
fi

# Test 3: Hyprland Lua windowrules must not contain active Waybar handling
echo "[3/9] Checking .config/hypr/.hyprlua/windowrules.lua for Waybar rules..."
WINDOWRULE_FAILED=0
if grep -E "WaybarEditor" .config/hypr/.hyprlua/windowrules.lua | grep -qv "^[[:space:]]*--"; then
    echo "  FAIL: windowrules.lua still has active WaybarEditor window rule"
    WINDOWRULE_FAILED=1
fi
if grep -E 'namespace.*=.*"waybar"' .config/hypr/.hyprlua/windowrules.lua | grep -qv "^[[:space:]]*--"; then
    echo "  FAIL: windowrules.lua still has active waybar layer rule"
    WINDOWRULE_FAILED=1
fi
if [ $WINDOWRULE_FAILED -eq 0 ]; then
    echo "  PASS: No active Waybar rules in windowrules.lua"
else
    FAILED=1
fi

# Test 4: Cloud Center config.yaml must not expose active Waybar page block
echo "[4/9] Checking cloudyy_scripts/cloud-center-v2/config.yaml..."
if grep -E "^\s+- id: waybar$" cloudyy_scripts/cloud-center-v2/config.yaml >/dev/null 2>&1; then
    echo "  FAIL: Cloud Center config still has active Waybar page block (id: waybar)"
    FAILED=1
else
    echo "  PASS: No active Waybar page in Cloud Center config"
fi

# Test 5: Cloud Center Python must not expose waybar CLI/page route
echo "[5/9] Checking cloudyy_scripts/cloud-center-v2/cloud-center.py..."
if grep -E '(^[^#]*"waybar"|^[^#]*--waybar)' cloudyy_scripts/cloud-center-v2/cloud-center.py | grep -q .; then
    echo "  FAIL: Cloud Center Python still has active waybar route/CLI handling"
    FAILED=1
else
    echo "  PASS: No active waybar route in Cloud Center Python"
fi

# Test 6: matugen config must not have active Waybar/SwayNC template outputs
echo "[6/9] Checking .config/matugen/config.toml..."
if grep -E "(waybar|swaync)" .config/matugen/config.toml | grep -E "(output_path|input_path|\[templates\.(waybar|swaync)\])" | grep -qv "^#"; then
    echo "  FAIL: matugen config still has active Waybar/SwayNC template blocks"
    FAILED=1
else
    echo "  PASS: No active Waybar/SwayNC templates in matugen config"
fi

# Test 7: deploy-dotfiles.sh must not verify/manage Waybar/SwayNC as active shell state
echo "[7/9] Checking install/deploy-dotfiles.sh for legacy state file management..."
DEPLOY_FAILED=0

# Check if waybar is still in critical_links verification
if grep -E '^\s+"\$\{HOME\}/\.config/waybar"' install/deploy-dotfiles.sh >/dev/null 2>&1; then
    echo "  FAIL: deploy-dotfiles.sh still verifies ~/.config/waybar as critical"
    DEPLOY_FAILED=1
fi

# Check if legacy Waybar/SwayNC state files are still in skip-worktree list
if grep -E '\.config/(waybar/\.(current_position|current_preset|vertical_side)|matugen/generated/(colors-swaync|waybar-colors)\.css)' install/deploy-dotfiles.sh >/dev/null 2>&1; then
    echo "  FAIL: deploy-dotfiles.sh still manages legacy Waybar/SwayNC state files"
    DEPLOY_FAILED=1
fi

if [ $DEPLOY_FAILED -eq 0 ]; then
    echo "  PASS: deploy-dotfiles.sh does not manage Waybar/SwayNC as active state"
else
    FAILED=1
fi

# Test 8: Hyprland bindings must not reference launch_waybar.sh
echo "[8/9] Checking Hyprland binding files..."
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

# Test 9: source/quickshell.conf must exist and contain the canonical startup command
echo "[9/9] Checking .config/hypr/source/quickshell.conf for canonical command..."
if [ ! -f ".config/hypr/source/quickshell.conf" ]; then
    echo "  FAIL: source/quickshell.conf does not exist"
    FAILED=1
elif ! grep -q "exec-once.*qs .*-d" .config/hypr/source/quickshell.conf; then
    echo "  FAIL: source/quickshell.conf does not contain quickshell startup command"
elif ! grep -q "QS_NO_RELOAD_POPUP" .config/hypr/source/quickshell.conf; then
    echo "  FAIL: source/quickshell.conf must set QS_NO_RELOAD_POPUP=1"
    FAILED=1
else
    echo "  PASS: source/quickshell.conf contains canonical startup command"
fi

echo ""
if [ $FAILED -eq 1 ]; then
    echo "❌ Test FAILED: Legacy shell surfaces still active"
    exit 1
else
    echo "✅ Test PASSED: quickshell is the only active shell path"
    exit 0
fi
