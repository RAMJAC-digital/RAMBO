# GraphViz Documentation Update Checklist

**Audit Date:** 2025-10-16
**Status:** Audits Complete - Updates Pending

Use this checklist to track diagram update progress.

---

## Phase 1: Critical Fixes (P0 - Blocking) ⏰ 7-11 hours

### ☐ emulation-coordination.dot (4-6 hours)

**Current Status:** 40% Accurate - CRITICAL

**Required Updates:**

- [ ] **VBlankLedger Section (Lines 113-134)** - Complete rewrite
  - [ ] Remove 7 non-existent methods (recordVBlankSet, recordVBlankClear, etc.)
  - [ ] Show 5 fields: last_set_cycle, last_clear_cycle, last_read_cycle, last_nmi_ack_cycle, race_hold
  - [ ] Document pure data struct pattern
  - [ ] Add race_hold usage notes

- [ ] **PpuReadResult Pattern** - Add documentation
  - [ ] Create PpuReadResult struct node
  - [ ] Show .value and .read_2002 fields
  - [ ] Document purpose (signal side effects without mutation)

- [ ] **busRead() Flow (Lines 263-324)** - Update data flow
  - [ ] Remove call to recordStatusRead() (doesn't exist)
  - [ ] Show PpuReadResult capture
  - [ ] Show direct ledger field assignment
  - [ ] Document race condition detection logic

- [ ] **busWrite() VBlank Tracking** - Remove outdated edge
  - [ ] Delete edge: bus_write → vblank_record_ctrl

- [ ] **applyPpuCycleResult()** - Fix mutation pattern
  - [ ] Remove calls to recordVBlankSet/SpanEnd
  - [ ] Show direct assignment: `ledger.last_set_cycle = clock.ppu_cycles`

- [ ] **readRegister() Signature (Line 274)** - Update signature
  - [ ] Change return type: u8 → PpuReadResult
  - [ ] Add vblank_ledger parameter

**Verification Commands:**
```bash
grep -n "pub const VBlankLedger" src/emulation/VBlankLedger.zig
grep -n "pub fn" src/emulation/VBlankLedger.zig  # Should only show reset()
grep -n "race_hold" src/emulation/VBlankLedger.zig src/emulation/State.zig
```

**Detailed Instructions:** `docs/audits/emulation-coordination-dot-audit-2025-10-16.md`

---

### ☐ ppu-module-structure.dot (2-3 hours)

**Current Status:** 86% Accurate - Major Updates Needed

**Required Updates:**

- [ ] **readRegister() Signature (Line 108)** - Fix signature
  - [ ] Add 4th parameter: vblank_ledger
  - [ ] Change return type: u8 → PpuReadResult
  - [ ] Update side-effects comment to reflect pure function

- [ ] **PpuReadResult Struct** - Add new node
  - [ ] Create struct node in cluster_ppu_types
  - [ ] Show fields: value (u8), read_2002 (bool)
  - [ ] Document purpose

- [ ] **buildStatusByte() Function** - Add new node
  - [ ] Create function node in cluster_register_logic
  - [ ] Show signature: (sprite_overflow, sprite_0_hit, vblank_flag, data_bus_latch) u8
  - [ ] Mark as PURE HELPER function

- [ ] **VBlank Flag Computation** - Add architecture note
  - [ ] Document on-demand computation from timestamps
  - [ ] Show race_hold flag usage
  - [ ] Explain pure functional design

- [ ] **PpuLogic Facade** - Update delegation note
  - [ ] Show VBlankLedger parameter threading
  - [ ] Emphasize stateless architecture

**Verification Commands:**
```bash
grep -A 5 "pub fn readRegister" src/ppu/logic/registers.zig
grep -A 4 "pub const PpuReadResult" src/ppu/logic/registers.zig
grep -A 20 "pub fn buildStatusByte" src/ppu/logic/registers.zig
```

**Detailed Instructions:** PPU audit report (agent output)

---

### ☐ architecture.dot (1-2 hours)

**Current Status:** 95% Accurate - Minor Additions Needed

**Required Updates:**

- [ ] **VBlankLedger Integration** - Add 3 missing data flow edges
  - [ ] Add edge: PPU → VBlankLedger (label: "nmi_signal, vblank_clear")
  - [ ] Add edge: VBlankLedger → CPU (label: "NMI edge detection")
  - [ ] Add edge: BusRouting → VBlankLedger (label: "$2002 read + race_hold")

- [ ] **PPU Description** - Update VBlank flag location
  - [ ] Change "VBlank flag stored in PpuStatus"
  - [ ] To: "VBlank flag computed from VBlankLedger timestamps"

- [ ] **Execution Order** - Add timing note
  - [ ] Document tick() sequence: Clock → PPU → APU → CPU

**Verification Commands:**
```bash
grep -A 10 "if (result.nmi_signal)" src/emulation/State.zig
grep -A 10 "if (result.read_2002)" src/emulation/State.zig
```

**Detailed Instructions:** `docs/audits/architecture-dot-audit-2025-10-13.md`

---

## Phase 2: High Priority (P1) ⏰ 3-5 hours

### ☐ ppu-timing.dot (1-2 hours)

**Current Status:** Mixed - Split Required

**Required Actions:**

- [ ] **Create Hardware Reference** - `docs/reference/ppu-ntsc-timing.dot`
  - [ ] Copy hardware specifications section
  - [ ] Remove "Investigation Findings" (lines 157-172)
  - [ ] Remove "Diagnostic Data" (lines 174-185)
  - [ ] Remove "CURRENT BUG" annotations
  - [ ] Add header: "NTSC PPU Timing Reference - Hardware Specifications"

- [ ] **Archive Investigation** - `docs/archive/2025-10/ppu-timing-investigation-2025-10-09.dot`
  - [ ] Copy full original diagram
  - [ ] Add header: "Historical investigation from 2025-10-09"
  - [ ] Add note: "RESOLVED - See sessions/2025-10-14-smb-integration-session.md"

- [ ] **Delete Original** - Remove `docs/dot/ppu-timing.dot`

**Verification:**
- Confirm resolved bug: `docs/sessions/2025-10-14-smb-integration-session.md`
- Check current status: `docs/CURRENT-ISSUES.md:15-25`

---

### ☐ apu-module-structure.dot (2-3 hours)

**Current Status:** 97% Accurate - Minor Updates

**Required Updates:**

- [ ] **Envelope.clock() Architecture** - Fix pure function pattern
  - [ ] Change signature: `clock(envelope: *Envelope) void`
  - [ ] To: `clock(envelope: *const Envelope) Envelope`
  - [ ] Add "PURE FUNCTION" annotation
  - [ ] Add "NO SIDE EFFECTS" note

- [ ] **Sweep.clock() Architecture** - Fix pure function pattern
  - [ ] Change signature: `clock(sweep: *Sweep, ...) void`
  - [ ] To: `clock(sweep: *const Sweep, ...) SweepClockResult`
  - [ ] Add SweepClockResult struct node
  - [ ] Document return fields: sweep, period

- [ ] **Phase 5 Architecture Note** - Add refactor documentation
  - [ ] Add note explaining State/Logic separation
  - [ ] Document pure functional Envelope/Sweep design
  - [ ] Add reference to logic/envelope.zig and logic/sweep.zig

**Verification Commands:**
```bash
grep -A 3 "pub fn clock" src/apu/Envelope.zig
grep -A 3 "pub fn clock" src/apu/Sweep.zig
grep -A 5 "pub const SweepClockResult" src/apu/Sweep.zig
```

**Detailed Instructions:** `docs/audits/apu-module-structure-audit-2025-10-13.md`

---

## Phase 3: Medium Priority (P2) ⏰ 4-5 hours

### ☐ cartridge-mailbox-systems.dot (3-4 hours)

**Current Status:** 75% Accurate - Missing Mailboxes

**Required Updates:**

- [ ] **Add Missing Mailboxes** - 5 completely absent
  - [ ] Add ConfigMailbox node with structure
  - [ ] Add SpeedControlMailbox node with structure
  - [ ] Add EmulationStatusMailbox node with structure
  - [ ] Add RenderStatusMailbox node with structure
  - [ ] Complete EmulationCommandMailbox documentation

- [ ] **Fix XdgInputEventMailbox** - Add missing field
  - [ ] Add modifiers field to key events

- [ ] **Fix XdgWindowEventMailbox** - Correct event types
  - [ ] Remove non-existent .frame_done event
  - [ ] Add 3 missing event types

- [ ] **Fix DebugCommandMailbox** - Correct buffer size
  - [ ] Change 32 → 64 buffer size

- [ ] **Update Thread Communication Flow** - Show all 13 mailboxes

**Verification Commands:**
```bash
find src/mailboxes -name "*.zig" -type f | wc -l  # Count mailbox files
grep -r "pub const.*Mailbox" src/mailboxes/
```

**Detailed Instructions:** `docs/dot/cartridge-mailbox-systems-audit-report.md`

---

### ☐ cpu-execution-flow.dot (1 hour)

**Current Status:** 85% Accurate - Update Paths

**Required Updates:**

- [ ] **File Paths** - Update to current structure
  - [ ] Change: `src/cpu/execution.zig`
  - [ ] To: `src/emulation/cpu/execution.zig`
  - [ ] Change: `bus/routing.zig`
  - [ ] To: Note inline in `src/emulation/State.zig`

- [ ] **Line Numbers** - Remove specific references
  - [ ] Remove "registers.zig lines 20-106" references
  - [ ] Add generic "see source" references

- [ ] **VBlankLedger Node** - Update to Phase 4 architecture
  - [ ] Show pure data struct pattern
  - [ ] Add race_hold field

- [ ] **Header Note** - Add context
  - [ ] Add: "Reference diagram - shows architecture patterns"

**Optional:**
- [ ] Consider moving to `docs/reference/` directory

---

## Phase 4: Optional Polish (P3)

### ☐ cpu-module-structure.dot (Optional enhancements)

**Current Status:** 96% Accurate - Excellent

**Optional Enhancements:**
- [ ] Clarify variants.zig comptime dispatch usage
- [ ] Add VBlank NMI synchronization note
- [ ] Add DMA coordination note
- [ ] Expand microsteps documentation (37 functions)

**Note:** No blocking issues - already production-ready

---

### ☐ investigation-workflow.dot (Optional polish)

**Current Status:** 100% Accurate - Perfect

**Optional Enhancement:**
- [ ] Add header annotation explaining methodology reference
- [ ] Consider moving to `docs/examples/` directory

**Note:** Keep as-is - already excellent

---

## Completion Tracking

### Progress Overview

- **Phase 1 (P0):** ☐☐☐ (0/3 complete) - 7-11 hours remaining
- **Phase 2 (P1):** ☐☐ (0/2 complete) - 3-5 hours remaining
- **Phase 3 (P2):** ☐☐ (0/2 complete) - 4-5 hours remaining
- **Phase 4 (P3):** ☐☐ (0/2 complete) - Optional

### Total Time Investment

- **Audit Time:** 8 hours (Complete ✅)
- **Update Time:** 14-21 hours (Pending)
- **Total Project:** 22-29 hours

---

## Validation Steps

After completing each diagram update:

1. **Visual Check** - Generate PNG and review
   ```bash
   cd docs/dot
   dot -Tpng <diagram>.dot -o <diagram>.png
   ```

2. **Code Verification** - Run verification commands from audit reports

3. **Cross-Reference Check** - Ensure consistency with related diagrams

4. **Peer Review** - Have another developer review changes

5. **Update Master Report** - Mark completed in this checklist

---

## Resources

**Master Audit Report:** `docs/audits/GRAPHVIZ-MASTER-AUDIT-2025-10-16.md`

**Executive Summary:** `docs/audits/GRAPHVIZ-AUDIT-EXECUTIVE-SUMMARY.md`

**Individual Audit Reports:**
- emulation-coordination: `docs/audits/emulation-coordination-dot-audit-2025-10-16.md`
- ppu-module-structure: Agent output (comprehensive)
- cpu-module-structure: `docs/dot/audit-cpu-module-structure.md`
- apu-module-structure: `docs/audits/apu-module-structure-audit-2025-10-13.md`
- architecture: `docs/audits/architecture-dot-audit-2025-10-13.md`
- cartridge-mailbox: `docs/dot/cartridge-mailbox-systems-audit-report.md`

---

## Notes

- All updates have specific GraphViz code snippets in detailed reports
- Verification commands provided for each section
- Priority rankings guide execution order
- Phase 1 is blocking - complete before new development

---

**Checklist Created:** 2025-10-16
**Last Updated:** 2025-10-16
**Next Review:** After Phase 1 completion

---

**End of Checklist**
