# VBlank vs DMA Pattern Architectural Comparison

## Executive Summary

After analyzing the working VBlank pattern and comparing it with the DMA pause/resume implementation, I've identified several critical architectural deviations that may be causing the duplication issues.

## 1. What VBlank Does Right (Reference Pattern)

### 1.1 Pure Data Structure
```zig
// VBlankLedger - Pure timestamp-based data
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,      // When VBlank was set
    last_clear_cycle: u64 = 0,    // When VBlank was cleared
    last_read_cycle: u64 = 0,     // When $2002 was read
    race_hold: bool = false,       // Race condition flag
};
```
**Key Pattern:** Simple timestamp recording with minimal state.

### 1.2 Edge Detection in CPU Execution
```zig
// execution.zig - Simple timestamp comparison
const vblank_active = (state.vblank_ledger.last_set_cycle > state.vblank_ledger.last_clear_cycle);
const nmi_line_should_assert = vblank_active and state.ppu.ctrl.nmi_enable and !state.vblank_ledger.race_hold;
state.cpu.nmi_line = nmi_line_should_assert;
```
**Key Pattern:** Direct boolean logic, no complex state machine.

### 1.3 Mutation Locations (Centralized)
- **PPU sets VBlank:** `State.zig:646` - `last_set_cycle = clock.ppu_cycles`
- **PPU clears VBlank:** `State.zig:651` - `last_clear_cycle = clock.ppu_cycles`
- **CPU reads $2002:** `State.zig:334` - `last_read_cycle = clock.ppu_cycles`
- **Total:** 3 mutation points, all in EmulationState

### 1.4 NMI Edge Detection
```zig
// cpu/Logic.zig - Simple edge detection
const nmi_prev = state.nmi_edge_detected;
state.nmi_edge_detected = state.nmi_line;
if (state.nmi_line and !nmi_prev) {
    // Falling edge detected - trigger NMI
}
```
**Key Pattern:** Simple previous/current comparison, no complex timing.

## 2. What DMA Does Differently (Deviations)

### 2.1 Complex Data Structure
```zig
// DmaInteractionLedger - More complex state
pub const DmaInteractionLedger = struct {
    last_dmc_active_cycle: u64 = 0,
    last_dmc_inactive_cycle: u64 = 0,
    oam_pause_cycle: u64 = 0,
    oam_resume_cycle: u64 = 0,
    interrupted_state: InterruptedState = .{},  // NESTED STRUCTURE
    duplication_pending: bool = false,          // EXTRA STATE
};
```
**Deviation:** More complex with nested structures and additional flags.

### 2.2 8-Phase State Machine (Over-Engineered)
```zig
pub const OamDmaPhase = enum {
    idle,
    aligning,
    reading,
    writing,
    paused_during_read,      // Extra states
    paused_during_write,     // Extra states
    resuming_with_duplication,  // Extra states
    resuming_normal,         // Extra states
};
```
**Deviation:** VBlank has NO phase machine. DMA has 8 phases!

### 2.3 Mutation Locations (Scattered)
- **execution.zig:133** - DMC active edge
- **execution.zig:136** - DMC inactive edge
- **execution.zig:161-164** - Pause state mutations
- **execution.zig:176** - DMC inactive (duplicate)
- **execution.zig:189** - Resume cycle
- **actions.zig:160** - Phase transitions
- **actions.zig:171-172** - Bookkeeping updates
- **Total:** 7+ mutation points across multiple files

**Deviation:** Mutations scattered across files, not centralized.

### 2.4 Complex Edge Detection
```zig
// execution.zig - Complex conditional logic
const prev_dmc_active = DmaInteraction.isDmcActive(&state.dma_interaction_ledger);
const curr_dmc_active = state.dmc_dma.rdy_low;
const dmc_rising_edge = curr_dmc_active and !prev_dmc_active;

if (dmc_rising_edge and DmaInteraction.shouldOamPause(...)) {
    // Complex pause logic with multiple conditions
}
```
**Deviation:** Multiple helper functions and complex conditions vs simple boolean logic.

## 3. Architectural Inconsistencies (Violations)

### 3.1 Pattern Violation: State Machine Complexity
- **VBlank:** No state machine, just timestamps
- **DMA:** 8-phase state machine with complex transitions
- **Issue:** State machine may be introducing timing bugs

### 3.2 Pattern Violation: Mutation Centralization
- **VBlank:** ALL mutations in EmulationState
- **DMA:** Mutations scattered across execution.zig, actions.zig, interaction.zig
- **Issue:** Hard to track state changes, potential for inconsistency

### 3.3 Pattern Violation: Edge Detection Location
- **VBlank:** Edge detection in CPU Logic (checkInterrupts)
- **DMA:** Edge detection mixed into execution.zig flow
- **Issue:** Edge detection happening at wrong abstraction level

### 3.4 Pattern Violation: Helper Function Complexity
- **VBlank:** Direct field access, no helper functions
- **DMA:** Multiple helper functions (isDmcActive, shouldOamPause, shouldOamResume)
- **Issue:** Extra indirection may be hiding timing bugs

## 4. Suspected Root Causes

### 4.1 Double Edge Detection
```zig
// Line 136 and 176 both set last_dmc_inactive_cycle
if (!curr_dmc_active and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
// ... later ...
if (!state.dmc_dma.rdy_low and prev_dmc_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
```
**Bug:** DMC inactive edge recorded twice, may cause double resume.

### 4.2 Phase Machine Race Conditions
The 8-phase state machine introduces complexity:
- Resume phases (resuming_with_duplication, resuming_normal) may not transition correctly
- Phase transitions happen in actions.zig, separate from edge detection
- Timing between phase changes and actual operations may be off

### 4.3 Timestamp vs Phase Disagreement
The system uses BOTH timestamps AND phase machine:
- Timestamps say when things happened
- Phase machine says what state we're in
- These can disagree, causing inconsistency

### 4.4 Edge Detection Timing
```zig
// Line 198 - Exact cycle match required
ledger.last_dmc_inactive_cycle == cycle
```
**Issue:** If edge detection misses exact cycle, resume never happens.

## 5. Recommendations (Align DMA with VBlank Pattern)

### 5.1 Simplify to Timestamp-Only Pattern
Remove the phase machine entirely. Use timestamps like VBlank:
```zig
// Proposed simplification
const oam_paused = (ledger.oam_pause_cycle > ledger.oam_resume_cycle);
const should_duplicate = ledger.interrupted_state.was_reading and
                         (clock.cycles == ledger.oam_resume_cycle + 1);
```

### 5.2 Centralize All Mutations
Move ALL DMA ledger mutations to EmulationState methods:
```zig
// EmulationState methods
pub fn recordDmcActive(self: *EmulationState) void
pub fn recordDmcInactive(self: *EmulationState) void
pub fn recordOamPause(self: *EmulationState) void
pub fn recordOamResume(self: *EmulationState) void
```

### 5.3 Simplify Edge Detection
Use simple prev/current comparison like NMI:
```zig
const dmc_prev = self.dmc_prev_state;
self.dmc_prev_state = state.dmc_dma.rdy_low;
if (state.dmc_dma.rdy_low and !dmc_prev) {
    // DMC rising edge
}
```

### 5.4 Remove Helper Function Indirection
Access fields directly like VBlank:
```zig
// Instead of: DmaInteraction.isDmcActive(&ledger)
// Use: ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle
```

### 5.5 Fix Double Edge Recording
Remove duplicate edge detection at line 176. Only detect edges ONCE per cycle.

## 6. Critical Finding: Architectural Mismatch

**The fundamental issue:** DMA implementation uses a **hybrid timestamp + phase machine** approach while VBlank uses **pure timestamps**. This architectural mismatch is likely the root cause of timing bugs.

**The phase machine adds complexity without benefit** - all the same logic can be expressed with timestamp comparisons, as proven by the working VBlank implementation.

## 7. Immediate Action Items

1. **Remove line 176** (duplicate DMC inactive edge detection)
2. **Add logging** to track phase transitions vs timestamp updates
3. **Consider removing phase machine** entirely in favor of pure timestamps
4. **Centralize mutations** into EmulationState methods
5. **Simplify edge detection** to match NMI pattern

## Conclusion

The DMA implementation deviates significantly from the proven VBlank pattern. The addition of an 8-phase state machine, scattered mutations, and complex helper functions has introduced unnecessary complexity that appears to be causing timing bugs. Aligning DMA with the simpler, working VBlank pattern should resolve the duplication issues.