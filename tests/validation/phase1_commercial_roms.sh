#!/bin/bash
# Phase 1 Validation: Commercial ROM Boot Test
# Tests NMI fix with commercial games

echo "=== Phase 1 Validation: Commercial ROM Boot Test ==="
echo ""

# Build with fix
echo "[1/5] Building with NMI fix..."
zig build || exit 1

# Test 1: Baseline (AccuracyCoin should boot and enable rendering)
echo ""
echo "[2/5] Baseline: AccuracyCoin..."
timeout 10s ./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes 2>&1 | tee /tmp/accuracycoin.log
if grep -q "Frame" /tmp/accuracycoin.log && grep -qE "PPUMASK=0x0[89abcdef]" /tmp/accuracycoin.log; then
    echo "✅ AccuracyCoin: Boots and enables rendering"
else
    echo "❌ AccuracyCoin: Failed to boot or rendering not enabled"
    exit 1
fi

# Test 2: Mario 1
echo ""
echo "[3/5] Super Mario Bros..."
timeout 5s ./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" 2>&1 | tee /tmp/mario.log
if grep -q "Frame" /tmp/mario.log; then
    echo "✅ Mario 1: Boots (check rendering manually)"
else
    echo "❌ Mario 1: Failed to boot"
fi

# Test 3: BurgerTime
echo ""
echo "[4/5] BurgerTime..."
timeout 3s ./zig-out/bin/RAMBO "tests/data/BurgerTime (USA).nes" 2>&1 | tee /tmp/burgertime.log
if grep -q "Frame" /tmp/burgertime.log; then
    echo "✅ BurgerTime: Boots"
else
    echo "❌ BurgerTime: Failed"
fi

# Test 4: Donkey Kong
echo ""
echo "[5/5] Donkey Kong..."
timeout 4s ./zig-out/bin/RAMBO "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes" 2>&1 | tee /tmp/dk.log
if grep -q "Frame" /tmp/dk.log; then
    echo "✅ Donkey Kong: Boots"
else
    echo "❌ Donkey Kong: Failed"
fi

echo ""
echo "=== Phase 1 Validation Complete ==="
echo "Visual Check: Run games manually and verify rendering enabled"
