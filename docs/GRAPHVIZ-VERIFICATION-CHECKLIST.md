# GraphViz Documentation Verification Checklist

Use this checklist to verify GraphViz documentation accuracy after major changes.

---

## Quick Verification (5 minutes)

### 1. Mailbox Count (CRITICAL)

```bash
# Count active mailboxes in Mailboxes.zig
grep -c ":" src/mailboxes/Mailboxes.zig | grep -E "controller_input|emulation_command|debug_command|frame|debug_event|xdg_window_event|xdg_input_event"
# Should be: 7

# Verify architecture.dot label
grep "7 Active Mailboxes" docs/dot/architecture.dot
# Should find: "Lock-Free Mailboxes\n(Thread Communication)\n7 Active Mailboxes"
```

**Expected**: 7 active mailboxes

### 2. VBlank Flag Location (CRITICAL)

```bash
# Verify VBlank flag NOT in PpuStatus
grep -i "vblank" src/ppu/State.zig
# Should be: NO matches (VBlank is in VBlankLedger, not PpuStatus)

# Verify VBlankLedger exists
grep "VBlankLedger" src/emulation/state/VBlankLedger.zig
# Should find: struct definition
```

**Expected**: VBlank flag in VBlankLedger ONLY, not in PpuStatus

### 3. Test Count (if documented)

```bash
# Run tests and check count
zig build test 2>&1 | grep "Build Summary"
# Should match: 949/986 tests passed (or current count)
```

**Expected**: Match CLAUDE.md documented count

### 4. GraphViz Compilation

```bash
# Test all diagrams compile
cd docs/dot
for file in *.dot; do
    echo "Compiling $file..."
    dot -Tpng "$file" -o "${file%.dot}.png" || echo "FAILED: $file"
done
```

**Expected**: All files compile without errors

---

## Detailed Verification (30 minutes)

### Module Structure Files

#### CPU Module (cpu-module-structure.dot)

**Verify**:
- [ ] CpuState fields match `src/cpu/State.zig`
- [ ] ExecutionState enum has 17 states
- [ ] StatusFlags is packed struct(u8) with 8 fields
- [ ] Dispatch table is [256]DispatchEntry
- [ ] 13 opcode modules documented

**Check**:
```bash
# Count execution states
grep -c "^\." src/cpu/State.zig  # Should be ~17
# Verify StatusFlags
grep "packed struct(u8)" src/cpu/State.zig
```

#### PPU Module (ppu-module-structure.dot)

**Verify**:
- [ ] PpuStatus does NOT have vblank field
- [ ] VBlank migration note present (lines 28-31)
- [ ] Sprite state has oam_source_index field
- [ ] Critical timing: 241.1 SET, 261.1 CLEAR
- [ ] Memory map $0000-$3FFF accurate

**Check**:
```bash
# Verify no vblank in PpuStatus
grep -A 10 "pub const PpuStatus" src/ppu/State.zig | grep -i vblank
# Should be: NO matches

# Verify sprite source tracking
grep "oam_source_index" src/ppu/State.zig
# Should find: [8]u8 field
```

#### APU Module (apu-module-structure.dot)

**Verify**:
- [ ] Frame counter timing: 4-step (29,830), 5-step (37,281)
- [ ] DMC rate tables present
- [ ] Envelope/Sweep components documented
- [ ] Register map $4000-$4017 accurate

**Check**:
```bash
# Verify frame counter cycles
grep "29830\|37281" src/apu/logic/frame_counter.zig
```

### System Architecture Files

#### Architecture Overview (architecture.dot)

**Verify**:
- [ ] 7 mailboxes (NOT 9)
- [ ] emu_status_mb and speed_mb REMOVED
- [ ] Orphaned mailbox note present
- [ ] 3-thread architecture documented
- [ ] VBlankLedger in EmulationState

**Check**:
```bash
# Verify mailbox count
grep -E "mb \[label" docs/dot/architecture.dot | wc -l
# Should be: 7

# Verify no orphaned mailboxes
! grep -E "emu_status_mb|speed_mb" docs/dot/architecture.dot
# Should exit with code 0 (no matches)
```

#### Emulation Coordination (emulation-coordination.dot)

**Verify**:
- [ ] VBlankLedger complete implementation (lines 113-134)
- [ ] MasterClock single counter (ppu_cycles)
- [ ] TimingStep struct with pre/post-advance coordinates
- [ ] Execution order: PPU → APU → CPU

**Check**:
```bash
# Verify VBlankLedger fields
grep -E "span_active|nmi_edge_pending" src/emulation/state/VBlankLedger.zig
```

#### Cartridge/Mailboxes (cartridge-mailbox-systems.dot)

**Verify**:
- [ ] 7 mailboxes documented (CORRECT, unlike architecture.dot pre-fix)
- [ ] NO emu_status_mb or speed_mb mentioned
- [ ] FrameMailbox triple-buffered (720 KB stack)
- [ ] Comptime generics (Cartridge(MapperType))

**Check**:
```bash
# Verify triple-buffering
grep "RING_BUFFER_SIZE = 3" src/mailboxes/FrameMailbox.zig
```

### Historical Documentation

#### Investigation Workflow (investigation-workflow.dot)

**Verify**:
- [ ] Date: 2025-10-09 (historical)
- [ ] BIT $2002 investigation documented
- [ ] Root cause identified
- [ ] Deliverables referenced

**Check**: This is historical documentation - accuracy frozen at investigation date.

#### PPU Timing (ppu-timing.dot)

**Verify**:
- [ ] Frame structure: 262 scanlines × 341 dots
- [ ] VBlank SET: 241.1, cycle 82,181
- [ ] VBlank CLEAR: 261.1, cycle 89,001
- [ ] CPU:PPU ratio 1:3

**Check**:
```bash
# Verify frame constants
grep -E "262|341|89342" src/ppu/timing.zig
```

---

## Automated Verification Script

Save as `scripts/verify-graphviz-docs.sh`:

```bash
#!/bin/bash
set -e

echo "GraphViz Documentation Verification"
echo "==================================="
echo

# 1. Mailbox count
echo "1. Checking mailbox count..."
MB_COUNT=$(grep -E "controller_input:|emulation_command:|debug_command:|frame:|debug_event:|xdg_window_event:|xdg_input_event:" src/mailboxes/Mailboxes.zig | wc -l)
if [ "$MB_COUNT" -eq 7 ]; then
    echo "   ✅ 7 active mailboxes found"
else
    echo "   ❌ Expected 7 mailboxes, found $MB_COUNT"
    exit 1
fi

# 2. VBlank flag location
echo "2. Checking VBlank flag location..."
if grep -q "vblank_flag\|vblank:" src/ppu/State.zig; then
    echo "   ❌ VBlank flag found in PpuStatus (should be in VBlankLedger)"
    exit 1
else
    echo "   ✅ VBlank flag correctly NOT in PpuStatus"
fi

if grep -q "VBlankLedger" src/emulation/state/VBlankLedger.zig; then
    echo "   ✅ VBlankLedger exists"
else
    echo "   ❌ VBlankLedger not found"
    exit 1
fi

# 3. GraphViz compilation
echo "3. Checking GraphViz compilation..."
cd docs/dot
FAILED=0
for file in *.dot; do
    if ! dot -Tpng "$file" -o "${file%.dot}.png" 2>/dev/null; then
        echo "   ❌ Failed to compile: $file"
        FAILED=1
    fi
done
cd ../..

if [ $FAILED -eq 0 ]; then
    echo "   ✅ All .dot files compile successfully"
else
    echo "   ❌ Some .dot files failed to compile"
    exit 1
fi

# 4. Orphaned mailboxes documented
echo "4. Checking orphaned mailbox documentation..."
if grep -q "orphaned" docs/dot/architecture.dot; then
    echo "   ✅ Orphaned mailboxes documented in architecture.dot"
else
    echo "   ⚠️  Orphaned mailboxes not mentioned (optional)"
fi

echo
echo "==================================="
echo "✅ All critical checks passed!"
echo
echo "Documentation is accurate as of $(date +%Y-%m-%d)"
```

**Usage**:
```bash
chmod +x scripts/verify-graphviz-docs.sh
./scripts/verify-graphviz-docs.sh
```

---

## When to Re-verify

### Required Re-verification Triggers

1. **Mailbox changes**:
   - Adding/removing mailboxes in `Mailboxes.zig`
   - Creating new mailbox types
   - Changing mailbox communication patterns

2. **VBlank system changes**:
   - Modifying `VBlankLedger` structure
   - Changing NMI edge detection logic
   - PPU register modifications

3. **Major architectural changes**:
   - Thread architecture modifications
   - State/Logic pattern changes
   - Execution flow refactoring

4. **Test count changes** (if >50 tests added/removed):
   - Update CLAUDE.md test counts
   - Re-verify against documentation

### Optional Re-verification

- After adding new mappers (update cartridge-mailbox-systems.dot)
- After APU output implementation (update apu-module-structure.dot)
- After major bug fixes (update investigation docs if relevant)

---

## Common Issues and Fixes

### Issue: Mailbox count mismatch

**Symptom**: `architecture.dot` shows different count than `Mailboxes.zig`

**Fix**:
1. Count mailboxes in `src/mailboxes/Mailboxes.zig` struct fields
2. Update `architecture.dot` cluster label: "7 Active Mailboxes" (or current count)
3. Remove/add mailbox nodes as needed
4. Update all edges involving changed mailboxes

### Issue: VBlank flag in wrong location

**Symptom**: Diagram shows VBlank in PpuStatus

**Fix**:
1. Verify source: `grep -i vblank src/ppu/State.zig` should return NO matches
2. Update diagram to show VBlank in `VBlankLedger`
3. Add migration note if not present

### Issue: Test count mismatch

**Symptom**: Documented test count doesn't match build output

**Fix**:
1. Run `zig build test 2>&1 | grep "Build Summary"`
2. Update CLAUDE.md with actual count
3. Update any diagrams mentioning test counts (currently none)

### Issue: GraphViz compilation fails

**Symptom**: `dot -Tpng file.dot` produces errors

**Common causes**:
- Missing semicolons in node/edge definitions
- Unclosed subgraphs (`}` missing)
- Invalid node names (spaces without quotes)
- Duplicate node IDs

**Fix**: Check syntax around error line, ensure all `{` have matching `}`

---

## Audit History

- **2025-10-11**: Initial comprehensive audit
  - Fixed mailbox count (9→7)
  - Verified VBlank migration
  - Verified all 9 diagrams
  - Created this checklist

- **Next audit**: After major architectural changes

---

**Maintained by**: Documentation team
**Last updated**: 2025-10-11
**Next review**: After threading changes or mapper additions
