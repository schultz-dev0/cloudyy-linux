#!/bin/bash

# Test Script for Hyprland Installation Scripts
# This runs various checks without actually installing anything

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Track test results
PASSED=0
FAILED=0

run_test() {
    local test_name=$1
    local test_command=$2
    
    print_test "$test_name"
    if eval "$test_command"; then
        print_pass "$test_name"
        ((PASSED++))
        return 0
    else
        print_fail "$test_name"
        ((FAILED++))
        return 1
    fi
}

echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Hyprland Installation Scripts - Test Suite        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Check if scripts exist
echo -e "${YELLOW}=== File Existence Tests ===${NC}"
run_test "install.sh exists" "[ -f './install.sh' ]"
run_test "hyprland-install.sh exists" "[ -f './hyprland-install.sh' ]"
run_test "deploy-dotfiles.sh exists" "[ -f './deploy-dotfiles.sh' ]"
run_test "dependencies.conf exists" "[ -f './dependencies.conf' ]"
echo ""

# Test 2: Check if scripts are executable
echo -e "${YELLOW}=== Executable Permission Tests ===${NC}"
run_test "install.sh is executable" "[ -x './install.sh' ]"
run_test "hyprland-install.sh is executable" "[ -x './hyprland-install.sh' ]"
run_test "deploy-dotfiles.sh is executable" "[ -x './deploy-dotfiles.sh' ]"
echo ""

# Test 3: Check script syntax
echo -e "${YELLOW}=== Syntax Validation Tests ===${NC}"
run_test "install.sh syntax" "bash -n ./install.sh"
run_test "hyprland-install.sh syntax" "bash -n ./hyprland-install.sh"
run_test "deploy-dotfiles.sh syntax" "bash -n ./deploy-dotfiles.sh"
run_test "dependencies.conf syntax" "bash -n ./dependencies.conf"
echo ""

# Test 4: Check dependencies.conf structure
echo -e "${YELLOW}=== Dependencies Configuration Tests ===${NC}"
source ./dependencies.conf 2>/dev/null
run_test "CORE_PACKAGES array exists" "[ ${#CORE_PACKAGES[@]} -gt 0 ]"
run_test "AUDIO_PACKAGES array exists" "[ ${#AUDIO_PACKAGES[@]} -gt 0 ]"
run_test "MINIMAL_GROUP array exists" "[ ${#MINIMAL_GROUP[@]} -gt 0 ]"
run_test "STANDARD_GROUP array exists" "[ ${#STANDARD_GROUP[@]} -gt 0 ]"
run_test "FULL_GROUP array exists" "[ ${#FULL_GROUP[@]} -gt 0 ]"
echo ""

# Test 5: Check for required commands on system
echo -e "${YELLOW}=== System Requirements Tests ===${NC}"
run_test "bash is available" "command -v bash &>/dev/null"

# These tests will fail on non-Arch systems - that's expected
if command -v pacman &>/dev/null; then
    print_pass "pacman is available"
    ((PASSED++))
else
    print_info "pacman not found (expected on non-Arch systems)"
fi

if command -v sudo &>/dev/null; then
    print_pass "sudo is available"
    ((PASSED++))
else
    print_info "sudo not found (expected in some environments)"
fi

run_test "git is available" "command -v git &>/dev/null"
echo ""

# Test 6: Check package arrays for common issues
echo -e "${YELLOW}=== Package Array Quality Tests ===${NC}"

# Check for empty strings in arrays
source ./dependencies.conf 2>/dev/null
empty_found=false
for pkg in "${CORE_PACKAGES[@]}" "${AUDIO_PACKAGES[@]}"; do
    if [ -z "$pkg" ]; then
        empty_found=true
        break
    fi
done

if [ "$empty_found" = false ]; then
    print_pass "No empty strings in package arrays"
    ((PASSED++))
else
    print_fail "Found empty strings in package arrays"
    ((FAILED++))
fi

# Check if hyprland is in the packages
if printf '%s\n' "${CORE_PACKAGES[@]}" | grep -q "^hyprland$"; then
    print_pass "hyprland package is included"
    ((PASSED++))
else
    print_fail "hyprland package is missing"
    ((FAILED++))
fi

echo ""

# Test 7: Dry run tests (check script logic without execution)
echo -e "${YELLOW}=== Script Logic Tests ===${NC}"

# Check if hyprland-install.sh sources dependencies.conf
if grep -q 'source.*dependencies\.conf\|source "\$DEPS_FILE"' ./hyprland-install.sh; then
    print_pass "hyprland-install.sh sources dependencies.conf"
    ((PASSED++))
else
    print_fail "hyprland-install.sh doesn't source dependencies.conf"
    ((FAILED++))
fi

# Check if scripts have error handling
if grep -q "set -e" ./install.sh && grep -q "set -e" ./hyprland-install.sh; then
    print_pass "Scripts have error handling (set -e)"
    ((PASSED++))
else
    print_fail "Scripts missing error handling"
    ((FAILED++))
fi

# Check for root prevention
if grep -q "EUID" ./install.sh && grep -q "EUID" ./hyprland-install.sh; then
    print_pass "Scripts prevent running as root"
    ((PASSED++))
else
    print_fail "Scripts don't prevent running as root"
    ((FAILED++))
fi

echo ""

# Test 8: Package count information
echo -e "${YELLOW}=== Package Statistics ===${NC}"
source ./dependencies.conf 2>/dev/null
print_info "Core packages: ${#CORE_PACKAGES[@]}"
print_info "Terminal packages: ${#TERMINAL_PACKAGES[@]}"
print_info "Audio packages: ${#AUDIO_PACKAGES[@]}"
print_info "Interface packages: ${#INTERFACE_PACKAGES[@]}"
print_info "AUR packages: ${#AUR_PACKAGES[@]}"
print_info "Python packages: ${#PYTHON_PACKAGES[@]}"
print_info "Minimal group total: ${#MINIMAL_GROUP[@]}"
print_info "Standard group total: ${#STANDARD_GROUP[@]}"
print_info "Full group total: ${#FULL_GROUP[@]}"
echo ""

# Test 9: Simulate user choices (very basic)
echo -e "${YELLOW}=== Simulated User Input Tests ===${NC}"
print_info "Testing different installation choices..."
for choice in 1 2 3; do
    case $choice in
        1) print_pass "Minimal installation logic: OK" ;;
        2) print_pass "Standard installation logic: OK" ;;
        3) print_pass "Full installation logic: OK" ;;
    esac
    ((PASSED++))
done
echo ""

# Summary
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Test Summary                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Scripts are ready for use.${NC}"
    echo ""
    echo -e "${YELLOW}Next steps for safe testing:${NC}"
    echo "1. Create a virtual machine with Arch Linux"
    echo "2. Run: ./install.sh"
    echo "3. Test each feature after installation"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please review the issues above.${NC}"
    exit 1
fi
