#!/usr/bin/env bash
# =============================================================================
# install-contract.sh — Pre-flight Test Suite for cloudyy-linux Installer
# =============================================================================
# Run from the install/ directory before executing the real installer.
# Does NOT install anything — read-only checks only.
# =============================================================================

set -uo pipefail  # Not -e, so individual failing tests don't abort the suite

# --- Colors ------------------------------------------------------------------
RED=$'\033[1;31m' GREEN=$'\033[1;32m' YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m' CYAN=$'\033[1;36m' BOLD=$'\033[1m' RESET=$'\033[0m'

# --- Test counters -----------------------------------------------------------
PASSED=0
FAILED=0
WARNED=0

# --- Output helpers ----------------------------------------------------------
print_test()  { printf '%s[TEST]%s %s\n'    "$BLUE"   "$RESET" "$1"; }
print_pass()  { printf '%s[PASS]%s %s\n'    "$GREEN"  "$RESET" "$1"; (( ++PASSED )); }
print_fail()  { printf '%s[FAIL]%s %s\n'    "$RED"    "$RESET" "$1"; (( ++FAILED )); }
print_warn()  { printf '%s[WARN]%s %s\n'    "$YELLOW" "$RESET" "$1"; (( ++WARNED )); }
print_info()  { printf '%s[INFO]%s %s\n'    "$CYAN"   "$RESET" "$1"; }
print_header(){ printf '\n%s%s=== %s ===%s\n' "$BOLD" "$YELLOW" "$1" "$RESET"; }

# --- Test runner -------------------------------------------------------------
# Usage: run_test "Description" "bash condition or command"
run_test() {
    local desc="$1"
    local cmd="$2"
    print_test "$desc"
    if eval "$cmd" &>/dev/null; then
        print_pass "$desc"
    else
        print_fail "$desc"
    fi
}

# --- Optional test (warns but doesn't count as failure) ----------------------
run_optional() {
    local desc="$1"
    local cmd="$2"
    print_test "$desc"
    if eval "$cmd" &>/dev/null; then
        print_pass "$desc"
    else
        print_warn "$desc (not available on this system — OK for non-Arch)"
    fi
}

# =============================================================================
# BANNER
# =============================================================================
clear
printf '%s' "$CYAN"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║       cloudyy-linux — Installer Test Suite               ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
printf '%s\n' "$RESET"
printf 'Running from: %s\n\n' "$(pwd)"

# =============================================================================
# TEST GROUP 1: File Existence
# =============================================================================
print_header "File Existence"
run_test "install.sh exists"           "[ -f './install.sh' ]"
run_test "packages/install.sh exists"  "[ -f './packages/install.sh' ]"
run_test "config/deploy.sh exists"     "[ -f './config/deploy.sh' ]"
run_test "packages/manifest.sh exists" "[ -f './packages/manifest.sh' ]"
run_test "verify/install-contract.sh exists" "[ -f './verify/install-contract.sh' ]"
run_test "Audio service setup exists"  "[ -f './user/audio-autoswitch.sh' ]"

# Every installer concern must be independently discoverable and runnable
# through its module entry point. `--help` is intentionally side-effect free.
for module in config hardware other login-user post-install user packages; do
    run_test "${module}/all.sh exposes an independent module entry point" \
        "./${module}/all.sh --help >/dev/null"
done

run_test "legacy installer state does not skip redesigned stages" \
    "state_home=\$(mktemp -d) && mkdir -p \"\$state_home/.local/share/cloudyy\" && printf 'packages\\n' > \"\$state_home/.local/share/cloudyy/.install_state\" && output=\$(HOME=\"\$state_home\" ./install.sh --dry-run) && rm -rf \"\$state_home\" && ! grep -q 'Package Installation.*\\[DONE\\]' <<<\"\$output\""

# =============================================================================
# TEST GROUP 2: Executable Permissions
# =============================================================================
print_header "Executable Permissions"
run_test "install.sh is executable"           "[ -x './install.sh' ]"
run_test "packages/install.sh is executable"  "[ -x './packages/install.sh' ]"
run_test "config/deploy.sh is executable"     "[ -x './config/deploy.sh' ]"
run_test "Audio service setup executable"     "[ -x './user/audio-autoswitch.sh' ]"
run_test "cloudyy-timer is executable"        "[ -x '../bin/cloudyy-timer' ]"
run_test "cloudyy command install glob covers cloudyy-timer" \
    "grep -Fq '\"\${REPO_DIR}\"/bin/cloudyy-*' ./user/all.sh"

# =============================================================================
# TEST GROUP 3: Bash Syntax Validation
# =============================================================================
print_header "Syntax Validation"
run_test "install.sh syntax valid"          "bash -n ./install.sh"
run_test "packages/install.sh syntax valid" "bash -n ./packages/install.sh"
run_test "config/deploy.sh syntax valid"    "bash -n ./config/deploy.sh"
run_test "packages/manifest.sh syntax valid" "bash -n ./packages/manifest.sh"
run_test "Audio service setup syntax valid" "bash -n ./user/audio-autoswitch.sh"

# =============================================================================
# TEST GROUP 4: Script Best Practices
# =============================================================================
print_header "Script Quality"

run_test "install.sh uses strict mode" \
    "grep -q 'set -euo pipefail' ./install.sh"

run_test "packages/install.sh uses strict mode" \
    "grep -q 'set -euo pipefail' ./packages/install.sh"

run_test "config/deploy.sh uses strict mode" \
    "grep -q 'set -euo pipefail' ./config/deploy.sh"

run_test "Audio service setup uses strict mode" \
    "grep -q 'set -euo pipefail' ./user/audio-autoswitch.sh"

run_test "install.sh prevents root execution" \
    "grep -q 'EUID' ./install.sh"

run_test "packages/install.sh prevents root execution" \
    "grep -q 'EUID' ./packages/install.sh"

run_test "install.sh has state/resume logic" \
    "grep -q 'STATE_FILE\|is_done\|mark_done' ./install.sh"

run_test "install.sh has --dry-run support" \
    "grep -q 'dry.run\|dry_run' ./install.sh"

run_test "config/deploy.sh creates backups" \
    "grep -q 'BACKUP_DIR\|backup_if_needed' ./config/deploy.sh"

run_test "packages/install.sh sources package manifest" \
    "grep -q 'source.*manifest\|source.*DEPS_FILE' ./packages/install.sh"

run_test "packages/install.sh has paru/yay fallback" \
    "grep -q 'paru\|yay' ./packages/install.sh && grep -q 'AUR_HELPER' ./packages/install.sh"

# =============================================================================
# TEST GROUP 5: dependencies.conf Content
# =============================================================================
print_header "Dependencies Configuration"

# shellcheck disable=SC1091
source ./packages/manifest.sh 2>/dev/null || true

run_test "CORE_PACKAGES alias exists and non-empty" \
    "[ ${#CORE_PACKAGES[@]} -gt 0 ]"

run_test "INTERFACE_PACKAGES alias exists and non-empty" \
    "[ ${#INTERFACE_PACKAGES[@]} -gt 0 ]"

run_test "UTILITY_PACKAGES alias exists and non-empty" \
    "[ ${#UTILITY_PACKAGES[@]} -gt 0 ]"

run_test "AUR_PACKAGES alias exists and non-empty" \
    "[ ${#AUR_PACKAGES[@]} -gt 0 ]"

run_test "AUDIO_PACKAGES alias exists and non-empty" \
    "[ ${#AUDIO_PACKAGES[@]} -gt 0 ]"

run_test "MINIMAL_GROUP array exists" \
    "[ ${#MINIMAL_GROUP[@]} -gt 0 ]"

run_test "STANDARD_GROUP array exists" \
    "[ ${#STANDARD_GROUP[@]} -gt 0 ]"

run_test "FULL_GROUP array exists" \
    "[ ${#FULL_GROUP[@]} -gt 0 ]"

run_test "hyprland is in CORE_PACKAGES" \
    "printf '%s\n' \"\${CORE_PACKAGES[@]}\" | grep -q '^hyprland$'"

run_test "No empty strings in CORE_PACKAGES" \
    "! printf '%s\n' \"\${CORE_PACKAGES[@]}\" | grep -q '^$'"

run_test "No empty strings in UTILITY_PACKAGES" \
    "! printf '%s\n' \"\${UTILITY_PACKAGES[@]}\" | grep -q '^$'"

run_test "No empty strings in gaming option groups" \
    "! printf '%s\n' \"\${OPTIONAL_AUR_GAMING[@]:-}\" \"\${OPTIONAL_OFFICIAL_GAMING[@]:-}\" | grep -q '^$'"

run_test "GPU arrays are defined (NVIDIA)" \
    "[ ${#OFFICIAL_GPU_NVIDIA[@]} -gt 0 ]"

run_test "GPU arrays are defined (AMD)" \
    "[ ${#OFFICIAL_GPU_AMD[@]} -gt 0 ]"

run_test "GPU arrays are defined (Intel)" \
    "[ ${#OFFICIAL_GPU_INTEL[@]} -gt 0 ]"

# Confirm removed problem packages
run_test "wlroots-nvidia removed (was non-existent)" \
    "! grep -q 'wlroots-nvidia' ./packages/manifest.sh"

run_test "hyprcap present in AUR_PACKAGES" \
    "printf '%s\n' \"\${AUR_PACKAGES[@]}\" | grep -q '^hyprcap$'"

run_test "Empty OPT_PRODUCTIVITY string removed" \
    "! grep -qE '^\s*\"\"' ./packages/manifest.sh"

# =============================================================================
# TEST GROUP 6: System Requirements
# =============================================================================
print_header "System Requirements"
run_test "bash 4.0+ available" \
    "[[ \${BASH_VERSINFO[0]} -ge 4 ]]"

run_optional "pacman available (Arch Linux)" \
    "command -v pacman"

run_optional "git available" \
    "command -v git"

run_optional "sudo available" \
    "command -v sudo"

# =============================================================================
# TEST GROUP 7: Package Statistics
# =============================================================================
print_header "Package Statistics"
# shellcheck disable=SC1091
source ./packages/manifest.sh 2>/dev/null || true

print_info "CORE_PACKAGES     : ${#CORE_PACKAGES[@]} packages"
print_info "INTERFACE_PACKAGES: ${#INTERFACE_PACKAGES[@]} packages"
print_info "UTILITY_PACKAGES  : ${#UTILITY_PACKAGES[@]} packages"
print_info "AUR_PACKAGES      : ${#AUR_PACKAGES[@]} packages"
print_info "AUDIO_PACKAGES    : ${#AUDIO_PACKAGES[@]} packages"
print_info "MINIMAL_GROUP     : ${#MINIMAL_GROUP[@]} packages"
print_info "STANDARD_GROUP    : ${#STANDARD_GROUP[@]} packages"
print_info "FULL_GROUP        : ${#FULL_GROUP[@]} packages"

# =============================================================================
# SUMMARY
# =============================================================================
printf '\n%s%s════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
printf '%s  Test Results%s\n' "$BOLD" "$RESET"
printf '%s%s════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
printf '  %sPassed%s : %d\n' "$GREEN"  "$RESET" "$PASSED"
printf '  %sFailed%s : %d\n' "$RED"    "$RESET" "$FAILED"
printf '  %sWarned%s : %d\n' "$YELLOW" "$RESET" "$WARNED"
printf '  Total  : %d\n\n'  $(( PASSED + FAILED ))

if (( FAILED == 0 )); then
    printf '%s✓ All tests passed. Scripts are ready.%s\n\n' "$GREEN" "$RESET"
    printf '%sNext step:%s\n' "$YELLOW" "$RESET"
    printf '  Run %s./install.sh --dry-run%s to preview the installation plan.\n'    "$BOLD" "$RESET"
    printf '  Run %s./install.sh%s          to start the actual installation.\n\n'   "$BOLD" "$RESET"
    exit 0
else
    printf '%s✗ %d test(s) failed. Review the output above before installing.%s\n\n' \
        "$RED" "$FAILED" "$RESET"
    exit 1
fi
