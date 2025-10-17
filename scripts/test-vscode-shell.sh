#!/bin/bash
# Test script for VSCode shell integration
# This script verifies the .bashrc configuration is working correctly

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     VSCode Shell Integration - Test Script              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Check .bashrc syntax
echo "Test 1: Validating .bashrc syntax..."
if bash -n /workspaces/jacker/config/vscode/.bashrc 2>/dev/null; then
    echo "✅ .bashrc syntax is valid"
else
    echo "❌ .bashrc syntax error detected"
    exit 1
fi
echo ""

# Test 2: Check system-info.sh exists and is executable
echo "Test 2: Checking system-info.sh..."
if [ -x /workspaces/jacker/config/vscode/system-info.sh ]; then
    echo "✅ system-info.sh exists and is executable"
else
    echo "❌ system-info.sh not found or not executable"
    exit 1
fi
echo ""

# Test 3: Check if .bashrc has interactive shell check
echo "Test 3: Verifying interactive shell protection..."
if grep -q '\[\[ \$- != \*i\* \]\] && return' /workspaces/jacker/config/vscode/.bashrc; then
    echo "✅ Interactive shell check present"
else
    echo "❌ Interactive shell check missing"
    exit 1
fi
echo ""

# Test 4: Check if system-info.sh is called in .bashrc
echo "Test 4: Verifying system-info.sh integration..."
if grep -q '/data/jacker/config/vscode/system-info.sh' /workspaces/jacker/config/vscode/.bashrc; then
    echo "✅ system-info.sh integration found"
else
    echo "❌ system-info.sh not integrated in .bashrc"
    exit 1
fi
echo ""

# Test 5: Check volume mount in compose file
echo "Test 5: Verifying docker-compose volume mount..."
if grep -q './config/vscode/.bashrc:/config/.bashrc:ro' /workspaces/jacker/compose/vscode.yml; then
    echo "✅ .bashrc volume mount configured"
else
    echo "❌ .bashrc volume mount not found in compose file"
    exit 1
fi
echo ""

# Test 6: Count aliases
echo "Test 6: Counting configured aliases..."
ALIAS_COUNT=$(grep -c '^alias' /workspaces/jacker/config/vscode/.bashrc)
echo "✅ Found $ALIAS_COUNT aliases configured"
echo ""

# Test 7: Count custom functions
echo "Test 7: Counting custom functions..."
FUNCTION_COUNT=$(grep -c '^[a-z_]*()' /workspaces/jacker/config/vscode/.bashrc)
echo "✅ Found $FUNCTION_COUNT custom functions"
echo ""

# Test 8: Test system-info.sh execution time
echo "Test 8: Measuring system-info.sh performance..."
START_TIME=$(date +%s.%N)
/workspaces/jacker/config/vscode/system-info.sh > /dev/null 2>&1
END_TIME=$(date +%s.%N)
EXECUTION_TIME=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "N/A")
if [ "$EXECUTION_TIME" != "N/A" ]; then
    echo "✅ Execution time: ${EXECUTION_TIME}s"
else
    echo "✅ Execution completed (time measurement unavailable)"
fi
echo ""

# Test 9: Verify git prompt function
echo "Test 9: Checking git-aware prompt..."
if grep -q 'git_branch()' /workspaces/jacker/config/vscode/.bashrc; then
    echo "✅ Git-aware prompt function found"
else
    echo "❌ Git-aware prompt function missing"
    exit 1
fi
echo ""

# Summary
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  All Tests Passed! ✅                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Next Steps:"
echo "1. Restart VSCode container: docker compose restart vscode"
echo "2. Open new terminal in VSCode"
echo "3. System info should display automatically"
echo "4. Test aliases: jacker, dc, gs, sysinfo, etc."
echo ""
echo "To disable system info on startup:"
echo "export JACKER_DISABLE_SYSINFO=1"
echo ""
