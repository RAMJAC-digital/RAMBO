# RAMBO NES Emulator - 6502 Opcode Implementation Status

**Generated:** 2025-10-02
**Project:** RAMBO - Cycle-Accurate NES Emulator
**Target:** AccuracyCoin Test Suite Compatibility

---

## Executive Summary

**OFFICIAL OPCODES: 100% COMPLETE ✅**

- **151/151 official opcodes implemented** (all 56 instruction patterns)
- All addressing modes complete
- Cycle-accurate timing implemented
- Hardware quirks implemented (RMW dummy writes, page crossing)

**UNOFFICIAL OPCODES: 0% COMPLETE ❌**

- **0/105 unofficial opcodes implemented**
- Required for AccuracyCoin full compatibility
- Opcodes defined in opcodes.zig but not dispatched
- Infrastructure ready for implementation

**OVERALL PROGRESS: 151/256 opcodes (59%)**

---

## Official Opcodes - COMPLETE ✅

All 56 official 6502 instruction patterns are fully implemented with cycle-accurate timing:

### Arithmetic (16 opcodes)
- **ADC** (Add with Carry): 8 addressing modes ✅
- **SBC** (Subtract with Carry): 8 addressing modes ✅

### Logical Operations (24 opcodes)
- **AND** (Logical AND): 8 addressing modes ✅
- **ORA** (Logical OR): 8 addressing modes ✅
- **EOR** (Exclusive OR): 8 addressing modes ✅

### Shifts & Rotates (20 opcodes)
- **ASL** (Arithmetic Shift Left): 5 addressing modes ✅
- **LSR** (Logical Shift Right): 5 addressing modes ✅
- **ROL** (Rotate Left): 5 addressing modes ✅
- **ROR** (Rotate Right): 5 addressing modes ✅

### Load/Store (33 opcodes)
- **LDA** (Load Accumulator): 8 addressing modes ✅
- **LDX** (Load X): 5 addressing modes ✅
- **LDY** (Load Y): 5 addressing modes ✅
- **STA** (Store Accumulator): 7 addressing modes ✅
- **STX** (Store X): 3 addressing modes ✅
- **STY** (Store Y): 3 addressing modes ✅

### Increment/Decrement (12 opcodes)
- **INC** (Increment Memory): 4 addressing modes ✅
- **DEC** (Decrement Memory): 4 addressing modes ✅
- **INX** (Increment X): implied ✅
- **INY** (Increment Y): implied ✅
- **DEX** (Decrement X): implied ✅
- **DEY** (Decrement Y): implied ✅

### Compare (19 opcodes)
- **CMP** (Compare Accumulator): 8 addressing modes ✅
- **CPX** (Compare X): 3 addressing modes ✅
- **CPY** (Compare Y): 3 addressing modes ✅
- **BIT** (Bit Test): 2 addressing modes ✅

### Branches (8 opcodes)
- **BCC** (Branch if Carry Clear) ✅
- **BCS** (Branch if Carry Set) ✅
- **BEQ** (Branch if Equal) ✅
- **BNE** (Branch if Not Equal) ✅
- **BMI** (Branch if Minus) ✅
- **BPL** (Branch if Plus) ✅
- **BVC** (Branch if Overflow Clear) ✅
- **BVS** (Branch if Overflow Set) ✅

### Jumps & Subroutines (5 opcodes)
- **JMP** (Jump): 2 addressing modes ✅
- **JSR** (Jump to Subroutine) ✅
- **RTS** (Return from Subroutine) ✅
- **RTI** (Return from Interrupt) ✅
- **BRK** (Force Interrupt) ✅

### Stack Operations (4 opcodes)
- **PHA** (Push Accumulator) ✅
- **PLA** (Pull Accumulator) ✅
- **PHP** (Push Processor Status) ✅
- **PLP** (Pull Processor Status) ✅

### Register Transfers (6 opcodes)
- **TAX** (Transfer A to X) ✅
- **TXA** (Transfer X to A) ✅
- **TAY** (Transfer A to Y) ✅
- **TYA** (Transfer Y to A) ✅
- **TSX** (Transfer SP to X) ✅
- **TXS** (Transfer X to SP) ✅

### Flag Operations (7 opcodes)
- **CLC** (Clear Carry) ✅
- **SEC** (Set Carry) ✅
- **CLI** (Clear Interrupt Disable) ✅
- **SEI** (Set Interrupt Disable) ✅
- **CLV** (Clear Overflow) ✅
- **CLD** (Clear Decimal) ✅
- **SED** (Set Decimal) ✅

### Miscellaneous (1 opcode)
- **NOP** (No Operation): 0xEA ✅

---

## Unofficial Opcodes - MISSING ❌

**Total Missing: 105 opcodes**

All unofficial opcodes are defined in `src/cpu/opcodes.zig` but not dispatched in `src/cpu/dispatch.zig`.

### HIGH PRIORITY (Required for most AccuracyCoin tests)

#### 1. RMW Combo Instructions (42 opcodes)
**Status:** Infrastructure ready (RMW addressing modes implemented)
**Complexity:** Medium (combine existing shift/rotate + logic/arithmetic)

- **SLO** (ASL + ORA): 7 addressing modes
  - $07 (zp), $17 (zp,X), $0F (abs), $1F (abs,X), $1B (abs,Y), $03 (ind,X), $13 (ind),Y

- **RLA** (ROL + AND): 7 addressing modes
  - $27 (zp), $37 (zp,X), $2F (abs), $3F (abs,X), $3B (abs,Y), $23 (ind,X), $33 (ind),Y

- **SRE** (LSR + EOR): 7 addressing modes
  - $47 (zp), $57 (zp,X), $4F (abs), $5F (abs,X), $5B (abs,Y), $43 (ind,X), $53 (ind),Y

- **RRA** (ROR + ADC): 7 addressing modes
  - $67 (zp), $77 (zp,X), $6F (abs), $7F (abs,X), $7B (abs,Y), $63 (ind,X), $73 (ind),Y

- **DCP** (DEC + CMP): 7 addressing modes
  - $C7 (zp), $D7 (zp,X), $CF (abs), $DF (abs,X), $DB (abs,Y), $C3 (ind,X), $D3 (ind),Y

- **ISC** (INC + SBC): 7 addressing modes
  - $E7 (zp), $F7 (zp,X), $EF (abs), $FF (abs,X), $FB (abs,Y), $E3 (ind,X), $F3 (ind),Y

**Implementation Notes:**
- All use RMW addressing modes (already implemented for ASL/LSR/ROL/ROR/INC/DEC)
- Must perform dummy write on cycle 4 (original value before modification)
- Combine two operations: shift/rotate/inc/dec + logic/arithmetic/compare
- Hardware-accurate timing critical for AccuracyCoin

#### 2. Load/Store Combo (10 opcodes)
**Status:** Addressing modes implemented
**Complexity:** Low (combine existing load/store operations)

- **LAX** (LDA + TAX): 6 addressing modes
  - $A7 (zp), $B7 (zp,Y), $AF (abs), $BF (abs,Y), $A3 (ind,X), $B3 (ind),Y
  - Stable and commonly used

- **SAX** (STA A&X): 4 addressing modes
  - $87 (zp), $97 (zp,Y), $8F (abs), $83 (ind,X)
  - Stores A AND X to memory (bitwise AND of registers)
  - Stable and commonly used

**Implementation Notes:**
- LAX: Load value into both A and X, set N/Z flags
- SAX: Store (A & X) to memory, no flags affected

#### 3. NOP Variants (27 opcodes)
**Status:** Partially implemented (5/27)
**Complexity:** Very Low (just consume cycles)

**Currently Implemented (5 opcodes):**
- $80, $82, $89, $C2, $E2 (immediate mode NOPs)

**Missing (22 opcodes):**

- **Implied NOPs** (5 opcodes): $1A, $3A, $5A, $7A, $DA, $FA
  - 2 cycles, no operand

- **DOP - Double NOP** (10 opcodes): $04, $14, $34, $44, $54, $64, $74, $D4, $F4
  - 2-byte instruction (read and discard operand)
  - Zero page or zero page,X addressing
  - 3-4 cycles

- **TOP - Triple NOP** (7 opcodes): $0C, $1C, $3C, $5C, $7C, $DC, $FC
  - 3-byte instruction (read and discard 16-bit operand)
  - Absolute or absolute,X addressing
  - 4 cycles (+1 on page cross for abs,X variants)

**Implementation Notes:**
- Just consume correct number of cycles
- Read operands (update open bus) but perform no operations
- Easy win for improving coverage

### MEDIUM PRIORITY (Required for full AccuracyCoin pass)

#### 4. Immediate Logic/Math (4 opcodes)
**Complexity:** Low (immediate mode only, simple logic)

- **ANC** (AND + set carry = bit 7): 2 opcodes
  - $0B, $2B (both immediate, same behavior)
  - A = A & operand, C = N (carry equals negative flag)

- **ALR/ASR** (AND + LSR): 1 opcode
  - $4B (immediate)
  - A = (A & operand) >> 1
  - C = bit 0 of (A & operand)

- **ARR** (AND + ROR): 1 opcode
  - $6B (immediate)
  - A = (A & operand) ROR 1
  - Complex flag behavior (C/V affected)

- **AXS/SBX** (A&X - operand → X): 1 opcode
  - $CB (immediate)
  - X = (A & X) - operand (no borrow)
  - C = result >= 0

**Implementation Notes:**
- All immediate mode (2 cycles)
- Stable behavior across hardware
- Simple to test and validate

#### 5. Unstable Store Operations (4 opcodes)
**Complexity:** High (hardware-dependent, unstable behavior)

- **SHA/AHX** (A & X & (H+1) → memory): 2 opcodes
  - $9F (abs,Y), $93 (ind),Y
  - Store A & X & (high byte of address + 1)
  - Unstable: sometimes high byte calculation fails

- **SHX** (X & (H+1) → memory): 1 opcode
  - $9E (abs,Y)
  - Store X & (high byte of address + 1)
  - Unstable behavior

- **SHY** (Y & (H+1) → memory): 1 opcode
  - $9C (abs,X)
  - Store Y & (high byte of address + 1)
  - Unstable behavior

- **TAS/SHS** (A&X → SP, then A&X&(H+1) → memory): 1 opcode
  - $9B (abs,Y)
  - SP = A & X, then store A & X & (high byte + 1)
  - Highly unstable

**Implementation Notes:**
- Behavior varies by hardware revision
- Implement NMOS 6502 behavior (most common)
- Document that behavior may differ on real hardware
- Critical for AccuracyCoin but difficult to test

### LOW PRIORITY (Tested but rarely used)

#### 6. Other Unstable (3 opcodes)
**Complexity:** High (unstable, magic constants)

- **LAE/LAS** (M & SP → A, X, SP): 1 opcode
  - $BB (abs,Y)
  - value = memory & SP, then A = X = SP = value
  - Relatively stable

- **XAA/ANE** (unstable): 1 opcode
  - $8B (immediate)
  - A = (A | magic) & X & operand
  - Magic constant varies by chip ($00, $EE, $FF common)

- **LXA** (unstable): 1 opcode
  - $AB (immediate)
  - A = X = (A | magic) & operand
  - Highly unstable, magic constant varies

**Implementation Notes:**
- XAA/LXA: Use magic constant $EE (most common NMOS behavior)
- Document unstable behavior in tests
- May fail on different hardware revisions

#### 7. JAM/KIL - Halt CPU (12 opcodes)
**Complexity:** Medium (requires special CPU state handling)

- **JAM/KIL**: 12 opcodes
  - $02, $12, $22, $32, $42, $52, $62, $72, $92, $B2, $D2, $F2
  - Halts CPU (infinite loop in hardware)
  - Requires RESET to recover
  - 0 cycles (locks up)

**Implementation Notes:**
- Need special "halted" CPU state
- Only RESET can recover (not NMI/IRQ)
- Easy to detect in emulation
- Rarely used except for deliberate CPU lockup

#### 8. Duplicate Official Opcode (1 opcode)
**Complexity:** Very Low (already implemented)

- **SBC** (duplicate): 1 opcode
  - $EB (immediate)
  - Identical behavior to official $E9
  - Just point to existing SBC implementation

---

## Implementation Priority & Timeline

### Phase 1: HIGH PRIORITY (Immediate - Required for AccuracyCoin)
**Estimated Effort:** 2-3 days

1. **NOP Variants** (22 missing opcodes) - 2 hours
   - Easiest quick win
   - Add implied, DOP, TOP variants to dispatch table
   - Reuse addressing modes

2. **LAX/SAX** (10 opcodes) - 4 hours
   - Combine existing load/store operations
   - Simple, stable behavior
   - Create `src/cpu/instructions/unofficial.zig`

3. **RMW Combo Instructions** (42 opcodes) - 1-2 days
   - SLO, RLA, SRE, RRA, DCP, ISC
   - Reuse existing RMW addressing modes
   - Combine existing instruction logic
   - Most complex but critical for AccuracyCoin

**Deliverable:** 74 opcodes, 70% unofficial coverage, AccuracyCoin basic tests passing

### Phase 2: MEDIUM PRIORITY (Full AccuracyCoin Compatibility)
**Estimated Effort:** 1-2 days

4. **Immediate Logic/Math** (4 opcodes) - 3 hours
   - ANC, ALR, ARR, AXS
   - All immediate mode, simple logic

5. **Unstable Store Operations** (4 opcodes) - 4 hours
   - SHA, SHX, SHY, TAS
   - Implement NMOS behavior
   - Document unstable behavior

**Deliverable:** 82 opcodes, 78% unofficial coverage, AccuracyCoin full compatibility

### Phase 3: LOW PRIORITY (Complete Coverage)
**Estimated Effort:** 1 day

6. **Other Unstable** (3 opcodes) - 2 hours
   - LAE, XAA, LXA
   - Use magic constant $EE

7. **JAM/KIL** (12 opcodes) - 3 hours
   - Add CPU halted state
   - Special handling in execution loop

8. **Duplicate SBC** (1 opcode) - 5 minutes
   - Point $EB to existing SBC implementation

**Deliverable:** 98 opcodes, 93% unofficial coverage, 100% 6502 coverage

---

## Test Strategy

### Unit Tests
Location: `tests/cpu/instructions_test.zig`

For each unofficial opcode:
1. **Cycle-accurate timing tests**
   - Verify exact cycle count matches hardware
   - Test RMW dummy writes at correct cycles

2. **Flag behavior tests**
   - Verify N, Z, C, V flags set correctly
   - Test edge cases (zero, negative, overflow)

3. **Register state tests**
   - Verify correct register values after execution
   - Test all addressing modes

4. **Memory state tests**
   - Verify correct memory writes
   - Test RMW operations write sequence
   - Verify open bus behavior

### Integration Tests
Location: AccuracyCoin.nes ROM execution

1. **Run AccuracyCoin test suite**
   - Full ROM execution with unofficial opcodes
   - Verify all 128 tests pass

2. **Cycle-level trace comparison**
   - Compare execution traces with reference emulator
   - Validate timing accuracy

3. **Hardware quirk validation**
   - RMW dummy writes visible to memory-mapped I/O
   - Page crossing behavior
   - Open bus retention

### Test Coverage Targets
- **Unit tests:** 100% of implemented opcodes
- **Integration tests:** All AccuracyCoin tests passing
- **Cycle accuracy:** Exact hardware timing match
- **Edge cases:** Boundary conditions, wraparound, flags

---

## Implementation Files

### New Files to Create
- **`src/cpu/instructions/unofficial.zig`**
  - All unofficial instruction implementations
  - RMW combos, LAX/SAX, ANC/ALR/ARR/AXS
  - Unstable operations (SHA/SHX/SHY/TAS/LAE/XAA/LXA)
  - JAM/KIL halt handling

### Files to Modify
- **`src/cpu/dispatch.zig`**
  - Add dispatch entries for all 105 unofficial opcodes
  - Wire up to implementations in unofficial.zig
  - Add NOP variant dispatch entries

- **`src/cpu/Cpu.zig`**
  - Add `halted` state flag for JAM/KIL
  - Modify tick() to check halted state

- **`tests/cpu/instructions_test.zig`**
  - Add comprehensive tests for each unofficial opcode
  - Cycle-accurate timing validation
  - Flag and register behavior tests

### Existing Infrastructure (Ready to Use)
- **RMW addressing modes:** `src/cpu/addressing.zig`
  - Already implemented for ASL/LSR/ROL/ROR/INC/DEC
  - Ready for SLO/RLA/SRE/RRA/DCP/ISC

- **Instruction helpers:** `src/cpu/helpers.zig`
  - Flag manipulation functions
  - Arithmetic/logic helpers ready to reuse

---

## Hardware Quirks & Edge Cases

### RMW Dummy Write (CRITICAL)
All RMW unofficial opcodes must:
1. Read from target address (cycle N)
2. **Write original value back** (cycle N+1) ← CRITICAL
3. Write modified value (cycle N+2)

This is visible to memory-mapped I/O and tested by AccuracyCoin.

### Unstable Opcode Behavior
- **SHA, SHX, SHY, TAS:** High byte calculation sometimes fails
- **XAA, LXA:** Magic constant varies ($00, $EE, $FF)
- **Implementation:** Use most common NMOS 6502 behavior
- **Documentation:** Note variance across hardware revisions

### JAM/KIL Halt Behavior
- CPU enters infinite internal loop
- Only RESET recovers (NMI/IRQ ignored)
- PC does NOT increment
- Bus shows last read value

---

## Documentation References

### External Resources
- **NESDev Wiki:** https://www.nesdev.org/wiki/CPU_unofficial_opcodes
- **6502.org Illegal Opcodes:** http://www.6502.org/tutorials/6502opcodes.html
- **AccuracyCoin Test Suite:** Required test ROM for validation

### Project Documentation
- **`docs/05-testing/accuracycoin-cpu-requirements.md`**
  - AccuracyCoin test requirements
  - Required unofficial opcode list

- **`docs/06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md`**
  - RMW dummy write behavior
  - Page crossing quirks
  - Open bus behavior

- **`docs/06-implementation-notes/STATUS.md`**
  - Current implementation status
  - Known issues and deviations

---

## Success Metrics

### Phase 1 Success (HIGH Priority Complete)
- ✅ 74/105 unofficial opcodes implemented (70%)
- ✅ NOP variants working (27 opcodes)
- ✅ LAX/SAX combo instructions working (10 opcodes)
- ✅ All 6 RMW combo instructions working (42 opcodes)
- ✅ Basic AccuracyCoin tests passing

### Phase 2 Success (MEDIUM Priority Complete)
- ✅ 82/105 unofficial opcodes implemented (78%)
- ✅ All immediate logic/math opcodes working (4 opcodes)
- ✅ Unstable store operations implemented (4 opcodes)
- ✅ Full AccuracyCoin test suite passing (128/128 tests)

### Phase 3 Success (LOW Priority Complete)
- ✅ 98/105 unofficial opcodes implemented (93%)
- ✅ All unstable opcodes with documented behavior
- ✅ JAM/KIL halt behavior working
- ✅ 249/256 total opcodes (97% - excludes 7 fully undefined)
- ✅ 100% AccuracyCoin compatibility

---

## Current Status Summary

**Strengths:**
- ✅ All 151 official opcodes complete and tested
- ✅ Cycle-accurate timing infrastructure in place
- ✅ RMW addressing modes implemented and validated
- ✅ Hardware quirks (dummy writes, page crossing) implemented
- ✅ Clean modular architecture ready for expansion
- ✅ Comprehensive test infrastructure

**Gaps:**
- ❌ 0/105 unofficial opcodes implemented (0%)
- ❌ AccuracyCoin ROM cannot execute without unofficial opcodes
- ❌ Missing critical RMW combo instructions (SLO/RLA/SRE/RRA/DCP/ISC)
- ❌ Missing common LAX/SAX instructions
- ❌ Only 5/27 NOP variants dispatched

**Next Action:**
**START WITH PHASE 1 - HIGH PRIORITY OPCODES**
1. Add remaining NOP variants (2 hours)
2. Implement LAX/SAX (4 hours)
3. Implement RMW combo instructions (1-2 days)

**Estimated time to AccuracyCoin compatibility:** 3-5 days total

---

**End of Report**
