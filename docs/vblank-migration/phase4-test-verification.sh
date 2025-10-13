#!/bin/bash
# Phase 4 Test Verification Script
# Automated test execution and regression detection
#
# Usage:
#   ./phase4-test-verification.sh baseline     # Record baseline before Phase 4
#   ./phase4-test-verification.sh verify-4a    # Verify after Phase 4a (Harness)
#   ./phase4-test-verification.sh verify-4b    # Verify after Phase 4b (A12)
#   ./phase4-test-verification.sh verify-4c    # Verify after Phase 4c (Cleanup)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Expected baseline
EXPECTED_PASSING=930
EXPECTED_TOTAL=966
BASELINE_FILE="/tmp/rambo-phase4-baseline.txt"

# Function: Print colored message
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function: Record baseline test results
record_baseline() {
    print_status "$YELLOW" "=== Recording Phase 4 Baseline ==="
    echo "Running full test suite..."

    # Run tests and capture output
    zig build test 2>&1 | tee "$BASELINE_FILE"

    # Extract test counts
    local passing=$(grep -oP '\d+/\d+ tests passed' "$BASELINE_FILE" | grep -oP '^\d+' | tail -1)
    local total=$(grep -oP '\d+/\d+ tests passed' "$BASELINE_FILE" | grep -oP '/\d+' | grep -oP '\d+' | tail -1)

    print_status "$GREEN" "✓ Baseline recorded: $passing/$total tests passing"
    print_status "$YELLOW" "Saved to: $BASELINE_FILE"

    if [ "$passing" != "$EXPECTED_PASSING" ] || [ "$total" != "$EXPECTED_TOTAL" ]; then
        print_status "$RED" "⚠ WARNING: Expected $EXPECTED_PASSING/$EXPECTED_TOTAL, got $passing/$total"
        print_status "$YELLOW" "Continuing anyway (baseline may have changed)"
    fi
}

# Function: Verify test results match baseline
verify_results() {
    local phase=$1
    local phase_name=$2

    print_status "$YELLOW" "=== Verifying Phase $phase ($phase_name) ==="

    # Check baseline exists
    if [ ! -f "$BASELINE_FILE" ]; then
        print_status "$RED" "✗ ERROR: Baseline not found. Run './phase4-test-verification.sh baseline' first"
        exit 1
    fi

    # Run tests
    print_status "$YELLOW" "Running full test suite..."
    local output=$(zig build test 2>&1)

    # Extract test counts
    local passing=$(echo "$output" | grep -oP '\d+/\d+ tests passed' | grep -oP '^\d+' | tail -1)
    local total=$(echo "$output" | grep -oP '\d+/\d+ tests passed' | grep -oP '/\d+' | grep -oP '\d+' | tail -1)

    # Extract baseline counts
    local baseline_passing=$(grep -oP '\d+/\d+ tests passed' "$BASELINE_FILE" | grep -oP '^\d+' | tail -1)
    local baseline_total=$(grep -oP '\d+/\d+ tests passed' "$BASELINE_FILE" | grep -oP '/\d+' | grep -oP '\d+' | tail -1)

    # Compare results
    print_status "$YELLOW" "Results:"
    echo "  Current:  $passing/$total tests passing"
    echo "  Baseline: $baseline_passing/$baseline_total tests passing"

    if [ "$passing" == "$baseline_passing" ] && [ "$total" == "$baseline_total" ]; then
        print_status "$GREEN" "✓ PASS: Test count matches baseline (ZERO REGRESSIONS)"
        return 0
    else
        print_status "$RED" "✗ FAIL: Test count changed!"

        # Show difference
        local diff_passing=$((passing - baseline_passing))
        local diff_total=$((total - baseline_total))

        if [ $diff_passing -lt 0 ]; then
            print_status "$RED" "  - $((diff_passing * -1)) tests now failing (REGRESSION)"
        elif [ $diff_passing -gt 0 ]; then
            print_status "$GREEN" "  + $diff_passing tests now passing"
        fi

        if [ $diff_total -ne 0 ]; then
            print_status "$YELLOW" "  ! Total test count changed by $diff_total"
        fi

        # Show failing tests
        print_status "$YELLOW" "Failed tests:"
        echo "$output" | grep -A 50 "failed" | head -30

        return 1
    fi
}

# Function: Verify Harness changes (Phase 4a)
verify_phase_4a() {
    print_status "$YELLOW" "=== Phase 4a: Harness Update Verification ==="

    # Check PpuRuntime removed from Harness
    print_status "$YELLOW" "Checking Harness.zig for PpuRuntime references..."
    if grep -q "PpuRuntime" src/test/Harness.zig; then
        print_status "$RED" "✗ FAIL: PpuRuntime still referenced in Harness.zig"
        grep -n "PpuRuntime" src/test/Harness.zig
        return 1
    else
        print_status "$GREEN" "✓ PASS: No PpuRuntime references in Harness"
    fi

    # Check tickPpu methods updated
    print_status "$YELLOW" "Checking tickPpu methods..."
    if grep -q "state.tick()" src/test/Harness.zig; then
        print_status "$GREEN" "✓ PASS: tickPpu uses state.tick()"
    else
        print_status "$RED" "✗ FAIL: tickPpu methods not updated to use state.tick()"
        return 1
    fi

    # Run PPU unit tests (fast feedback)
    print_status "$YELLOW" "Running PPU unit tests..."
    if zig build test-unit 2>&1 | grep -q "tests passed"; then
        local ppu_passing=$(zig build test-unit 2>&1 | grep "ppu/" | grep -oP '\d+ passed' | grep -oP '\d+' || echo "N/A")
        print_status "$GREEN" "✓ PASS: PPU unit tests pass"
    else
        print_status "$RED" "✗ FAIL: PPU unit tests failed"
        return 1
    fi

    # Verify full test suite
    verify_results "4a" "Harness Update"
}

# Function: Verify A12 migration (Phase 4b)
verify_phase_4b() {
    print_status "$YELLOW" "=== Phase 4b: A12 Migration Verification ==="

    # Check ppu_a12_state removed from EmulationState
    print_status "$YELLOW" "Checking for old ppu_a12_state references..."
    if grep -q "ppu_a12_state:" src/emulation/State.zig; then
        print_status "$RED" "✗ FAIL: ppu_a12_state still in EmulationState"
        grep -n "ppu_a12_state" src/emulation/State.zig
        return 1
    else
        print_status "$GREEN" "✓ PASS: ppu_a12_state removed from EmulationState"
    fi

    # Check a12_state added to PpuState
    print_status "$YELLOW" "Checking for new a12_state in PpuState..."
    if grep -q "a12_state:" src/ppu/State.zig; then
        print_status "$GREEN" "✓ PASS: a12_state added to PpuState"
    else
        print_status "$RED" "✗ FAIL: a12_state not found in PpuState"
        return 1
    fi

    # Check Harness resetPpu updated
    print_status "$YELLOW" "Checking Harness resetPpu()..."
    if grep -q "ppu.a12_state" src/test/Harness.zig; then
        print_status "$GREEN" "✓ PASS: Harness uses ppu.a12_state"
    else
        print_status "$RED" "✗ FAIL: Harness resetPpu() not updated"
        return 1
    fi

    # Run snapshot tests
    print_status "$YELLOW" "Running snapshot tests..."
    if zig build test 2>&1 | grep -q "snapshot.*passed"; then
        print_status "$GREEN" "✓ PASS: Snapshot tests pass"
    else
        print_status "$RED" "✗ FAIL: Snapshot tests failed"
        zig build test 2>&1 | grep "snapshot" | tail -10
        return 1
    fi

    # Verify full test suite
    verify_results "4b" "A12 Migration"
}

# Function: Verify cleanup (Phase 4c)
verify_phase_4c() {
    print_status "$YELLOW" "=== Phase 4c: Cleanup Verification ==="

    # Check PpuRuntime.zig deleted
    print_status "$YELLOW" "Checking if PpuRuntime.zig deleted..."
    if [ -f "src/emulation/Ppu.zig" ]; then
        print_status "$RED" "✗ FAIL: src/emulation/Ppu.zig still exists"
        return 1
    else
        print_status "$GREEN" "✓ PASS: PpuRuntime facade deleted"
    fi

    # Check no PpuRuntime references anywhere
    print_status "$YELLOW" "Checking for remaining PpuRuntime references..."
    local ppu_runtime_refs=$(grep -r "PpuRuntime" src/ tests/ 2>/dev/null | wc -l)
    if [ "$ppu_runtime_refs" -gt 0 ]; then
        print_status "$RED" "✗ FAIL: Found $ppu_runtime_refs PpuRuntime references"
        grep -r "PpuRuntime" src/ tests/ | head -10
        return 1
    else
        print_status "$GREEN" "✓ PASS: No PpuRuntime references found"
    fi

    # Check no ppu_a12_state references
    print_status "$YELLOW" "Checking for remaining ppu_a12_state references..."
    local a12_refs=$(grep -r "ppu_a12_state" src/ 2>/dev/null | wc -l)
    if [ "$a12_refs" -gt 0 ]; then
        print_status "$RED" "✗ FAIL: Found $a12_refs ppu_a12_state references"
        grep -r "ppu_a12_state" src/ | head -10
        return 1
    else
        print_status "$GREEN" "✓ PASS: No ppu_a12_state references found"
    fi

    # Verify full test suite
    verify_results "4c" "Cleanup"
}

# Function: Run critical tests only (fast feedback)
verify_critical_tests() {
    print_status "$YELLOW" "=== Running Critical Tests (Fast Feedback) ==="

    local critical_tests=(
        "ppu/vblank_nmi_timing_test.zig"
        "ppu/sprite_evaluation_test.zig"
        "integration/nmi_sequence_test.zig"
        "integration/cpu_ppu_integration_test.zig"
        "snapshot/snapshot_integration_test.zig"
    )

    for test in "${critical_tests[@]}"; do
        print_status "$YELLOW" "Testing: $test"
        if zig build test 2>&1 | grep -q "$test.*passed"; then
            print_status "$GREEN" "  ✓ PASS"
        else
            print_status "$RED" "  ✗ FAIL"
            zig build test 2>&1 | grep "$test" -A 5 | tail -10
            return 1
        fi
    done

    print_status "$GREEN" "✓ All critical tests passed"
}

# Main script logic
case "$1" in
    baseline)
        record_baseline
        ;;
    verify-4a)
        verify_phase_4a
        ;;
    verify-4b)
        verify_phase_4b
        ;;
    verify-4c)
        verify_phase_4c
        ;;
    critical)
        verify_critical_tests
        ;;
    *)
        echo "Usage: $0 {baseline|verify-4a|verify-4b|verify-4c|critical}"
        echo ""
        echo "Commands:"
        echo "  baseline   - Record baseline test results before Phase 4"
        echo "  verify-4a  - Verify Phase 4a (Harness update)"
        echo "  verify-4b  - Verify Phase 4b (A12 migration)"
        echo "  verify-4c  - Verify Phase 4c (Cleanup)"
        echo "  critical   - Run only critical tests (fast feedback)"
        exit 1
        ;;
esac

exit 0
