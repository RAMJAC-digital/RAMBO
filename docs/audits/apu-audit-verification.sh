#!/usr/bin/env bash
# APU Module Structure Audit Verification Script
# Generated: 2025-10-13
# Verifies findings from apu-module-structure-audit-2025-10-13.md

set -e

echo "=========================================="
echo "APU Module Structure Audit Verification"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

run_check() {
    local description="$1"
    local command="$2"
    local expected="$3"

    echo -n "Checking: $description... "

    if output=$(eval "$command" 2>&1); then
        if echo "$output" | grep -q "$expected"; then
            echo -e "${GREEN}PASS${NC}"
            ((pass_count++))
        else
            echo -e "${RED}FAIL${NC}"
            echo "  Expected: $expected"
            echo "  Got: $output"
            ((fail_count++))
        fi
    else
        echo -e "${RED}ERROR${NC}"
        echo "  Command failed: $command"
        ((fail_count++))
    fi
}

echo "1. CRITICAL CHECKS: Pure Functional Architecture"
echo "=================================================="

run_check \
    "Envelope.clock is pure function (*const Envelope)" \
    "grep 'pub fn clock' src/apu/logic/envelope.zig" \
    '*const Envelope'

run_check \
    "Envelope.clock returns Envelope" \
    "grep -A 1 'pub fn clock' src/apu/logic/envelope.zig" \
    'Envelope'

run_check \
    "Sweep.clock is pure function (*const Sweep)" \
    "grep 'pub fn clock' src/apu/logic/sweep.zig" \
    '*const Sweep'

run_check \
    "Sweep.clock returns SweepClockResult" \
    "grep -A 1 'pub fn clock' src/apu/logic/sweep.zig" \
    'SweepClockResult'

run_check \
    "SweepClockResult struct exists" \
    "grep 'pub const SweepClockResult' src/apu/logic/sweep.zig" \
    'SweepClockResult'

echo ""
echo "2. MODULE EXISTENCE CHECKS"
echo "==========================="

run_check \
    "logic/envelope.zig exists" \
    "test -f src/apu/logic/envelope.zig && echo 'exists'" \
    'exists'

run_check \
    "logic/sweep.zig exists" \
    "test -f src/apu/logic/sweep.zig && echo 'exists'" \
    'exists'

run_check \
    "logic/registers.zig exists" \
    "test -f src/apu/logic/registers.zig && echo 'exists'" \
    'exists'

run_check \
    "logic/frame_counter.zig exists" \
    "test -f src/apu/logic/frame_counter.zig && echo 'exists'" \
    'exists'

run_check \
    "logic/tables.zig exists" \
    "test -f src/apu/logic/tables.zig && echo 'exists'" \
    'exists'

echo ""
echo "3. APU.ZIG EXPORT CHECKS"
echo "========================"

run_check \
    "Apu.zig exports envelope_logic" \
    "grep 'pub const envelope_logic' src/apu/Apu.zig" \
    'envelope_logic'

run_check \
    "Apu.zig exports sweep_logic" \
    "grep 'pub const sweep_logic' src/apu/Apu.zig" \
    'sweep_logic'

echo ""
echo "4. PURE FUNCTION USAGE VERIFICATION"
echo "===================================="

run_check \
    "registers.zig uses envelope_logic.clock correctly" \
    "grep 'pulse1_envelope = envelope_logic' src/apu/logic/registers.zig" \
    'pulse1_envelope = envelope_logic'

run_check \
    "registers.zig uses envelope_logic.restart" \
    "grep 'envelope_logic.restart' src/apu/logic/registers.zig" \
    'envelope_logic.restart'

run_check \
    "frame_counter.zig uses sweep_logic.clock" \
    "grep 'sweep_logic.clock' src/apu/logic/frame_counter.zig" \
    'sweep_logic.clock'

run_check \
    "frame_counter.zig assigns sweep result" \
    "grep 'pulse1_sweep = pulse1_result.sweep' src/apu/logic/frame_counter.zig" \
    'pulse1_sweep = pulse1_result.sweep'

run_check \
    "frame_counter.zig assigns period result" \
    "grep 'pulse1_period = pulse1_result.period' src/apu/logic/frame_counter.zig" \
    'pulse1_period = pulse1_result.period'

echo ""
echo "5. FRAME COUNTER TIMING VERIFICATION"
echo "====================================="

run_check \
    "FRAME_4STEP_TOTAL = 29830" \
    "grep 'FRAME_4STEP_TOTAL' src/apu/logic/frame_counter.zig" \
    '29830'

run_check \
    "FRAME_5STEP_TOTAL = 37281" \
    "grep 'FRAME_5STEP_TOTAL' src/apu/logic/frame_counter.zig" \
    '37281'

echo ""
echo "6. STATE STRUCTURE VERIFICATION"
echo "================================"

run_check \
    "ApuState contains pulse1_envelope" \
    "grep 'pulse1_envelope: Envelope' src/apu/State.zig" \
    'pulse1_envelope'

run_check \
    "ApuState contains pulse1_sweep" \
    "grep 'pulse1_sweep: Sweep' src/apu/State.zig" \
    'pulse1_sweep'

run_check \
    "Envelope struct has start_flag" \
    "grep 'start_flag: bool' src/apu/Envelope.zig" \
    'start_flag'

run_check \
    "Sweep struct has reload_flag" \
    "grep 'reload_flag: bool' src/apu/Sweep.zig" \
    'reload_flag'

echo ""
echo "=========================================="
echo "RESULTS SUMMARY"
echo "=========================================="
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Audit findings verified.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some checks failed. Review the audit report for details.${NC}"
    exit 1
fi
