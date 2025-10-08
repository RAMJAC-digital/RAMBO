# CRITICAL FINDING: NMI Interrupt Handling Not Implemented

**Date:** 2025-10-08
**Session:** Commercial ROM Investigation
**Status:** 🔴 **BLOCKING** - All commercial games non-functional
**Priority:** **P0 SHOWSTOPPER**

---

## Executive Summary

**DISCOVERY:** While all commercial games load successfully, NONE progress past initialization because **NMI interrupt handling is completely unimplemented** in the CPU emulation.

The interrupt states (`.interrupt_dummy`, `.interrupt_push_pch`, etc.) are **defined in the ExecutionState enum but have ZERO implementation** in `stepCpuCycle()`. When an NMI fires, the CPU enters `.interrupt_dummy` state and **becomes stuck forever**.

**Impact:**
- ✅ Test ROMs work (AccuracyCoin validates with $00 $00 $00 $00)
- ❌ ALL commercial games hang waiting for NMI
- ❌ Games never reach title screens
- ❌ Controller input irrelevant - games stuck in init loops

---

## Investigation Timeline

### 1. Initial Symptoms

**User Report:** Commercial games display blank screens while test ROMs work.

**Observations:**
- AccuracyCoin: Full CPU/PPU validation passes
- Mario 1, Donkey Kong, BurgerTime: Blank screens
- Bomberman: "Displays something" (partial success)

### 2. First Hypothesis: Rendering Disabled

**Test Results:**
```
Mario 1:       PPUMASK=$06 (bits 1,2 only - leftmost 8 pixels)
Donkey Kong:   PPUMASK=$06
BurgerTime:    PPUMASK=$00 (all rendering disabled)
AccuracyCoin:  PPUMASK=$1E (full rendering enabled)
```

**Finding:** Games ARE setting PPUMASK, but to initialization values only. They never enable full rendering ($18 or $1E).

### 3. Second Hypothesis: PPU Warm-Up Period

**Issue Discovered:** Integration tests called `reset()` which sets `warmup_complete=true`, skipping the PPU warm-up period.

**Fix Applied:**
```zig
// BEFORE: reset() sets warmup_complete=true (RESET button behavior)
state.reset();

// AFTER: Power-on behavior (warm-up required)
const reset_vector = state.busRead16(0xFFFC);
state.cpu.pc = reset_vector;
state.cpu.sp = 0xFD;
state.cpu.p.interrupt = true;
// warmup_complete remains FALSE for first ~29,658 cycles
```

**Result:** Early PPUCTRL writes now correctly ignored, but games still hang.

### 4. Third Hypothesis: VBlank Not Setting

**Test:**
```zig
Frame 60: PPUCTRL=$90, PPUMASK=$06, VBlank=false
```

**Finding:** VBlank flag checked AFTER frame completes (scanline 261, dot 340), but VBlank clears at scanline 261, dot 1. This is correct hardware behavior - VBlank is transient within the frame.

### 5. Fourth Hypothesis: NMI Not Firing

**Test Added:**
```zig
var nmi_executed_count: usize = 0;
// Track if PC jumps to NMI vector
if (state.cpu.pc == nmi_vector and last_pc != nmi_vector) {
    nmi_executed_count += 1;
}
```

**Result:**
```
Frame 60: NMI executed=0, PC=$8057
Frame 180: NMI executed=0, PC=$8057  // Stuck in infinite loop!
```

### 6. Breakthrough: Tracing the NMI Pipeline

**Added Debug Output at Every Stage:**

#### Stage 1: PPU VBlank Set (✅ WORKING)
```
[PPU] VBlank set at scanline 241, dot 1: nmi_enable=true, assert_nmi=true
```
**Code:** `src/emulation/Ppu.zig:131-143`

#### Stage 2: Emulation NMI Assertion (✅ WORKING)
```
[EMU] NMI asserted! Setting cpu.nmi_line=true
```
**Code:** `src/emulation/State.zig:674-678`

#### Stage 3: CPU Edge Detection (✅ WORKING)
```
[CPU] NMI edge detected! Setting pending_interrupt=.nmi (PC=$8057)
```
**Code:** `src/cpu/Logic.zig:83-86`

#### Stage 4: Interrupt Sequence Start (✅ WORKING)
```
[CPU] Starting interrupt sequence: .nmi (PC=$8057)
```
**Code:** `src/emulation/State.zig:1152-1153`

#### Stage 5: Execution (❌ **MISSING IMPLEMENTATION**)

**What SHOULD happen:**
1. Dummy read at current PC (1 cycle)
2. Push PCH to stack (1 cycle)
3. Push PCL to stack (1 cycle)
4. Push P register to stack (1 cycle)
5. Fetch NMI vector low byte from $FFFA (1 cycle)
6. Fetch NMI vector high byte from $FFFB (1 cycle)
7. Jump to NMI handler (PC = vector)

**Total: 7 cycles for NMI sequence**

**What ACTUALLY happens:**
```zig
pub fn startInterruptSequence(state: *CpuState) void {
    state.state = .interrupt_dummy;  // ← Sets state but...
    state.instruction_cycle = 0;
}
```

**NO CODE EXISTS** to handle `.interrupt_dummy`, `.interrupt_push_pch`, `.interrupt_push_pcl`, `.interrupt_push_p`, `.interrupt_fetch_vector_low`, `.interrupt_fetch_vector_high`.

The CPU sits at `state = .interrupt_dummy` **FOREVER**.

---

## Root Cause Analysis

### Missing Implementation in `stepCpuCycle()`

**File:** `src/emulation/State.zig:1138-1750`

**Current Structure:**
```zig
fn stepCpuCycle(self: *EmulationState) void {
    // Warm-up check (lines 1138-1141)
    // Halt check (lines 1143-1146)

    // Interrupt detection and start (lines 1148-1156) ✅ IMPLEMENTED
    if (self.cpu.state == .fetch_opcode) {
        CpuLogic.checkInterrupts(&self.cpu);
        if (self.cpu.pending_interrupt != .none) {
            CpuLogic.startInterruptSequence(&self.cpu);
            return;  // ← Sets state to .interrupt_dummy and RETURNS
        }
    }

    // Normal instruction handling (lines 1158-1750)
    if (self.cpu.state == .fetch_opcode) { ... }
    if (self.cpu.state == .fetch_operand_low) { ... }
    // ... addressing modes, execute, write_result ...

    // ❌ NO HANDLING FOR INTERRUPT STATES!
    // .interrupt_dummy
    // .interrupt_push_pch
    // .interrupt_push_pcl
    // .interrupt_push_p
    // .interrupt_fetch_vector_low
    // .interrupt_fetch_vector_high
}
```

### State Enum Definitions

**File:** `src/cpu/State.zig:94-125`

```zig
pub const ExecutionState = enum(u8) {
    fetch_opcode,
    fetch_operand_low,
    fetch_operand_high,
    calc_address_low,
    calc_address_high,
    dummy_read,
    dummy_write,
    execute,
    write_result,
    push_high,
    push_low,
    pull,

    // ⚠️ DEFINED BUT NOT IMPLEMENTED ⚠️
    interrupt_dummy,           // Cycle 1: Dummy read at current PC
    interrupt_push_pch,        // Cycle 2: Push PC high byte
    interrupt_push_pcl,        // Cycle 3: Push PC low byte
    interrupt_push_p,          // Cycle 4: Push status register
    interrupt_fetch_vector_low,  // Cycle 5: Fetch vector low from $FFFA/$FFFE
    interrupt_fetch_vector_high, // Cycle 6: Fetch vector high from $FFFB/$FFFF
    interrupt_complete,        // Cycle 7: Jump to handler
};
```

---

## Required Implementation

### Interrupt Sequence (7 Cycles)

Based on nesdev.org hardware documentation:

#### Cycle 1: Dummy Read
```zig
if (self.cpu.state == .interrupt_dummy) {
    _ = self.busRead(self.cpu.pc);  // Dummy read at current PC
    self.cpu.state = .interrupt_push_pch;
    return;
}
```

#### Cycle 2: Push PCH
```zig
if (self.cpu.state == .interrupt_push_pch) {
    const pch = @as(u8, @intCast((self.cpu.pc >> 8) & 0xFF));
    self.busWrite(0x0100 | @as(u16, self.cpu.sp), pch);
    self.cpu.sp -%= 1;
    self.cpu.state = .interrupt_push_pcl;
    return;
}
```

#### Cycle 3: Push PCL
```zig
if (self.cpu.state == .interrupt_push_pcl) {
    const pcl = @as(u8, @intCast(self.cpu.pc & 0xFF));
    self.busWrite(0x0100 | @as(u16, self.cpu.sp), pcl);
    self.cpu.sp -%= 1;
    self.cpu.state = .interrupt_push_p;
    return;
}
```

#### Cycle 4: Push Status Register
```zig
if (self.cpu.state == .interrupt_push_p) {
    var flags = self.cpu.p;

    // BRK sets B flag, NMI/IRQ don't
    if (self.cpu.pending_interrupt == .brk) {
        flags.break_flag = true;
    } else {
        flags.break_flag = false;
    }

    const p_byte: u8 = @bitCast(flags);
    self.busWrite(0x0100 | @as(u16, self.cpu.sp), p_byte);
    self.cpu.sp -%= 1;

    // Set interrupt disable flag (prevents IRQ during NMI)
    self.cpu.p.interrupt = true;

    self.cpu.state = .interrupt_fetch_vector_low;
    return;
}
```

#### Cycle 5: Fetch Vector Low Byte
```zig
if (self.cpu.state == .interrupt_fetch_vector_low) {
    const vector_addr = switch (self.cpu.pending_interrupt) {
        .nmi => @as(u16, 0xFFFA),
        .irq => @as(u16, 0xFFFE),
        .brk => @as(u16, 0xFFFE),
        .reset => @as(u16, 0xFFFC),
        .none => unreachable,
    };

    self.cpu.address_low = self.busRead(vector_addr);
    self.cpu.state = .interrupt_fetch_vector_high;
    return;
}
```

#### Cycle 6: Fetch Vector High Byte
```zig
if (self.cpu.state == .interrupt_fetch_vector_high) {
    const vector_addr = switch (self.cpu.pending_interrupt) {
        .nmi => @as(u16, 0xFFFB),
        .irq => @as(u16, 0xFFFF),
        .brk => @as(u16, 0xFFFF),
        .reset => @as(u16, 0xFFFD),
        .none => unreachable,
    };

    self.cpu.address_high = self.busRead(vector_addr);
    self.cpu.state = .interrupt_complete;
    return;
}
```

#### Cycle 7: Jump to Handler
```zig
if (self.cpu.state == .interrupt_complete) {
    self.cpu.pc = (@as(u16, self.cpu.address_high) << 8) |
                  @as(u16, self.cpu.address_low);

    // Clear pending interrupt
    self.cpu.pending_interrupt = .none;

    // Return to fetch_opcode state
    self.cpu.state = .fetch_opcode;
    return;
}
```

---

## Testing Strategy

### Unit Tests Needed

1. **NMI Sequence Test**
   ```zig
   test "CPU: NMI executes 7-cycle sequence" {
       var state = EmulationState.init(&config);
       state.cpu.nmi_line = true;

       // Cycle 1: Edge detection
       CpuLogic.checkInterrupts(&state.cpu);
       try testing.expect(state.cpu.pending_interrupt == .nmi);

       // Cycle 1: Dummy read
       state.stepCpuCycle();
       try testing.expect(state.cpu.state == .interrupt_push_pch);

       // Cycle 2-6: Stack pushes and vector fetch
       // ... (detailed cycle-by-cycle validation)

       // Cycle 7: PC should be at NMI vector
       try testing.expect(state.cpu.pc == nmi_vector);
   }
   ```

2. **NMI vs IRQ vs BRK Differentiation**
   - B flag behavior (set for BRK, clear for NMI/IRQ)
   - Vector addresses ($FFFA for NMI, $FFFE for IRQ/BRK)

3. **Stack Pointer Verification**
   - SP decrements by 3 during interrupt
   - Stack contains PCH, PCL, P in correct order

### Integration Tests

**Commercial ROM validation** (already created):
```zig
test "Commercial ROM: Super Mario Bros - enables rendering" {
    // After NMI implementation, this should pass:
    // - NMI fires at VBlank
    // - Game initializes PPU
    // - PPUMASK set to $1E (full rendering)
    // - Title screen displays
}
```

---

## Files Modified This Session

### Created Files

1. **`tests/helpers/FramebufferValidator.zig`** (252 lines)
   - Pixel counting utilities
   - Framebuffer hashing for regression tests
   - PPM export for visual debugging
   - 10 unit tests passing

2. **`tests/integration/commercial_rom_test.zig`** (356 lines)
   - End-to-end ROM loading tests
   - Rendering validation
   - NMI execution tracking
   - 6 test cases (currently failing - waiting for NMI fix)

### Modified Files

1. **`src/ppu/Logic.zig`**
   - Added debug output for PPUCTRL/PPUMASK writes (lines 282-283, 293-304)
   - Added debug output for VBlank set (lines 140-143)

2. **`src/emulation/State.zig`**
   - Added debug output for NMI assertion (lines 674-676)
   - Added debug output for interrupt sequence start (line 1152)

3. **`src/emulation/Ppu.zig`**
   - Added debug output for VBlank set (lines 140-143)

4. **`src/cpu/Logic.zig`**
   - Added debug output for NMI edge detection (line 85)

5. **`build.zig`**
   - Registered FramebufferValidator tests (lines 603-626)
   - Registered commercial ROM tests (lines 603-626, 982-983, 1036-1037)

---

## Cleanup Required

Before implementing NMI handling, remove ALL debug output:

```bash
grep -r "std.debug.print.*\[PPU\]\|\[EMU\]\|\[CPU\]" src/
```

**Files with debug output to clean:**
- `src/ppu/Logic.zig` (PPUCTRL/PPUMASK/VBlank prints)
- `src/emulation/State.zig` (NMI assertion, interrupt start prints)
- `src/emulation/Ppu.zig` (VBlank print)
- `src/cpu/Logic.zig` (NMI edge detection print)

---

## Next Steps

### Phase 1: Remove Debug Output (30 minutes)
- Remove all `std.debug.print` statements added this session
- Verify tests still compile
- Commit cleanup

### Phase 2: Implement NMI Handling (4-6 hours)
- Add interrupt state handling to `stepCpuCycle()`
- Implement 7-cycle sequence
- Handle NMI/IRQ/BRK differences
- Add cycle-accurate timing tests

### Phase 3: Validate Commercial ROMs (2-3 hours)
- Run Mario 1, Donkey Kong, BurgerTime
- Verify NMI execution
- Confirm rendering enables
- Check title screen display

### Phase 4: Regression Testing (1 hour)
- Ensure AccuracyCoin still passes
- Run full test suite
- Document any timing changes

**Total Estimated Time:** 8-11 hours

---

## References

- **nesdev.org:** Interrupt handling sequence
- **6502 Hardware Manual:** NMI timing and stack behavior
- **AccuracyCoin Tests:** Interrupt validation requirements

---

**Documented by:** Claude Code
**Session:** 2025-10-08 Commercial ROM Investigation
**Status:** Ready for implementation planning
