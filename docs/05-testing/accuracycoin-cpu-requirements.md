# AccuracyCoin CPU Test Requirements

**Document Purpose**: Comprehensive CPU emulation requirements extracted from AccuracyCoin test suite for Test-Driven Development (TDD) of the RAMBO NES emulator.

**Source**: AccuracyCoin ROM - 128 accuracy tests for NTSC NES (RP2A03G CPU, RP2C02G PPU)

**Scope**: CPU-specific tests only (instruction behavior, timing, flags, addressing modes, interrupts, bus behavior)

---

## Table of Contents

1. [Memory and Bus Behavior](#1-memory-and-bus-behavior)
2. [Instruction Execution - Core Operations](#2-instruction-execution---core-operations)
3. [Instruction Execution - Unofficial Opcodes](#3-instruction-execution---unofficial-opcodes)
4. [Addressing Modes and Edge Cases](#4-addressing-modes-and-edge-cases)
5. [CPU Flags and Status Register](#5-cpu-flags-and-status-register)
6. [Interrupt Handling](#6-interrupt-handling)
7. [CPU Timing and Cycle Accuracy](#7-cpu-timing-and-cycle-accuracy)
8. [Dummy Read/Write Cycles](#8-dummy-readwrite-cycles)
9. [Open Bus Behavior](#9-open-bus-behavior)
10. [Power-On State](#10-power-on-state)
11. [TDD Implementation Roadmap](#11-tdd-implementation-roadmap)

---

## 1. Memory and Bus Behavior

### 1.1 ROM Write Protection (Test: "ROM is not Writable")

**AccuracyCoin Reference**: Error Code 1

- **Requirement**: Writing to ROM addresses must not modify ROM contents
- **Hardware Behavior**:
  - ROM is read-only memory mapped to $8000-$FFFF (NROM)
  - Write operations to ROM are ignored by hardware
  - Data bus may reflect write value temporarily, but ROM content unchanged
- **Edge Cases**:
  - Verify writes to all ROM address ranges ($8000-$FFFF)
  - Test partial writes (single byte vs multi-byte operations)
- **Validation**:
  - Write known value to ROM address
  - Read back same address
  - Verify original ROM value remains unchanged

---

### 1.2 RAM Mirroring (Test: "RAM Mirroring")

**AccuracyCoin Reference**: Error Codes 1-2

- **Requirement**: RAM must mirror correctly across entire 13-bit address space
- **Hardware Behavior**:
  - Physical RAM: 2KB ($0000-$07FF)
  - Address space: 8KB ($0000-$1FFF)
  - Mirroring: Every 2KB repeats (bits 11-12 ignored, only bits 0-10 used)
  - Example: $0000 = $0800 = $1000 = $1800
- **Edge Cases**:
  - Test all four mirror regions ($0000, $0800, $1000, $1800)
  - Verify reads from mirrors return same value
  - Verify writes to mirrors affect all mirror addresses
  - Test boundary addresses ($07FF, $0FFF, $17FF, $1FFF)
- **Validation**:
  - Write unique value to $0123
  - Read from $0923, $1123, $1923
  - All reads must return same value
  - Write to $0923, read from $0123
  - Verify write propagated to underlying RAM

---

### 1.3 Program Counter Wraparound (Test: "PC Wraparound")

**AccuracyCoin Reference**: Error Code 1

- **Requirement**: PC wraparound from $FFFF to $0000 must work correctly
- **Hardware Behavior**:
  - When executing instruction at $FFFF, operands wrap to $0000-$0001
  - 16-bit PC wraps without triggering any special behavior
  - No interrupt or exception on wraparound
- **Edge Cases**:
  - Multi-byte instruction at $FFFF (reads from $0000, $0001)
  - JMP instructions near boundary
  - Branch instructions crossing boundary
- **Validation**:
  - Place 2-byte instruction at $FFFF
  - Verify operand bytes read from $0000 and $0001
  - Execute instruction successfully

---

## 2. Instruction Execution - Core Operations

### 2.1 Decimal Flag Behavior (Test: "The Decimal Flag")

**AccuracyCoin Reference**: Error Codes 1-2

- **Requirement**: Decimal mode flag exists but does NOT affect ADC/SBC on NES
- **Hardware Behavior**:
  - D flag (bit 3) of status register can be set/cleared with SED/CLD
  - ADC and SBC operate in binary mode regardless of D flag state
  - D flag IS pushed to stack by PHP/BRK instructions
  - This differs from original 6502 which supports BCD arithmetic
- **Edge Cases**:
  - ADC with D=1 should give binary result, not BCD
  - SBC with D=1 should give binary result, not BCD
  - PHP should preserve D flag state
  - BRK should preserve D flag state
- **Validation**:
  - Set D flag with SED
  - Execute ADC $09 + $09 (expect $12, not $18 as in BCD)
  - PHP and verify D flag set in pushed value
  - Execute BRK and verify D flag set in pushed value

---

### 2.2 B Flag Behavior (Test: "The B Flag")

**AccuracyCoin Reference**: Error Codes 1-9

- **Requirement**: B flag behavior differs between software and hardware interrupts
- **Hardware Behavior**:
  - B flag doesn't physically exist in status register
  - When status pushed to stack, B flag bits determined by instruction type:
    - PHP: B=1, bit 5=1
    - BRK: B=1, bit 5=1
    - IRQ: B=0, bit 5=1
    - NMI: B=0, bit 5=1
  - Bit 5 is always set when status pushed (unused bit always 1)
- **Edge Cases**:
  - Verify each push mechanism sets correct B/bit5 combination
  - PLP restores all flags except B (B is synthetic)
- **Validation**:
  ```
  Error 1: PHP should set B flag (bit 4) in pushed byte
  Error 2: BRK should set B flag (bit 4) in pushed byte
  Error 3: IRQ must occur (test interrupt system works)
  Error 4: IRQ should NOT set B flag in pushed byte
  Error 5: NMI should NOT set B flag in pushed byte
  Error 6: PHP should set bit 5 in pushed byte
  Error 7: BRK should set bit 5 in pushed byte
  Error 8: IRQ should set bit 5 in pushed byte
  Error 9: NMI should set bit 5 in pushed byte
  ```

---

### 2.3 All NOP Instructions (Test: "All NOP Instructions")

**AccuracyCoin Reference**: Error Codes 1-S (19 different NOPs)

- **Requirement**: All NOP opcodes must execute without side effects (except timing/dummy reads)
- **Hardware Behavior**:
  - Official NOP: $EA (2 cycles, implied)
  - Unofficial NOPs with different addressing modes:
    - Implied: $1A, $3A, $5A, $7A, $DA, $FA (2 cycles)
    - Immediate: $80, $82, $89, $C2, $E2 (2 cycles, read operand)
    - Zero Page: $04, $44, $64 (3 cycles, read ZP address)
    - Zero Page,X: $14, $34, $54, $74, $D4, $F4 (4 cycles, read ZP,X)
    - Absolute: $0C (4 cycles, read absolute address)
    - Absolute,X: $1C, $3C, $5C, $7C, $DC, $FC (4-5 cycles, read abs,X)
- **Edge Cases**:
  - Verify correct cycle counts for each addressing mode
  - Verify dummy reads occur at correct addresses
  - Verify no registers/flags modified (except PC)
  - Page crossing behavior for Absolute,X NOPs
- **Validation**: For each NOP variant:
  - Save all register/flag state
  - Execute NOP instruction
  - Verify no state changed except PC advancement
  - Verify correct number of cycles elapsed

---

## 3. Instruction Execution - Unofficial Opcodes

### 3.1 Combo Instructions: SLO, RLA, SRE, RRA, DCP, ISC (Test: "Unofficial Instructions")

**AccuracyCoin Reference**: Error Codes 1, 3, 4, 6, I, K

- **Requirement**: Read-Modify-Write combo instructions must combine two operations atomically
- **Hardware Behavior**:
  - **SLO**: ASL memory, then ORA A with result (Error 1)
  - **RLA**: ROL memory, then AND A with result (Error 3)
  - **SRE**: LSR memory, then EOR A with result (Error 4)
  - **RRA**: ROR memory, then ADC A with result (Error 6)
  - **DCP**: DEC memory, then CMP A with result (Error I)
  - **ISC**: INC memory, then SBC A with result (Error K)
- **Edge Cases**:
  - Memory value modified atomically (no visible intermediate state)
  - All operations affect flags appropriately
  - Dummy write cycle occurs (writes old value before new value)
- **Validation** (Error Codes 0-6):
  ```
  0: Correct number of operand bytes
  1: Target memory address has correct value after test
  2: A register has correct value after test
  3: X register unchanged (or correct if modified)
  4: Y register unchanged (or correct if modified)
  5: CPU status flags correct after test
  6: Stack pointer correct (only for LAE)
  ```

---

### 3.2 Logic Immediate: ANC, ASR, ARR (Test: "Unofficial Instructions")

**AccuracyCoin Reference**: Error Codes 2, 5, 7

- **Requirement**: Immediate mode logic operations with carry flag side effects
- **Hardware Behavior**:
  - **ANC** (Error 2): AND immediate with A, then copy bit 7 to carry
    - Equivalent to: AND #imm; ROL; ROR
    - Used to test bit 7 and move to carry simultaneously
  - **ASR** (Error 5): AND immediate with A, then LSR A
    - Equivalent to: AND #imm; LSR A
  - **ARR** (Error 7): AND immediate with A, then ROR A
    - Equivalent to: AND #imm; ROR A
    - Also affects V flag based on bit 6 XOR bit 5
- **Edge Cases**:
  - ANC carry flag mirrors bit 7 of result
  - ARR overflow flag set if bit 6 XOR bit 5 of result
  - All affect N, Z flags based on result in A
- **Validation**:
  ```
  Error codes same as 3.1 (0-5)
  Special verification for carry/overflow flag behavior
  ```

---

### 3.3 Register Storage: SAX, SHA, SHX, SHY, SHS (Test: "Unofficial Instructions")

**AccuracyCoin Reference**: Error Codes 8, A, B, C, D, E

- **Requirement**: Combined register storage operations with AND logic
- **Hardware Behavior**:
  - **SAX** (Error 8): Store A AND X to memory
    - Simple AND operation, stable across revisions
  - **SHA** (Error A, E): Store A AND X AND (H+1) to memory
    - H = high byte of target address
    - Unstable: some revisions corrupt high byte differently
  - **SHX** (Error B): Store X AND (H+1) to memory
  - **SHY** (Error C): Store Y AND (H+1) to memory
  - **SHS** (Error D): Store A AND X to S, then store S AND (H+1) to memory
    - Also updates stack pointer: S = A AND X
- **Edge Cases**:
  - SHA has revision-dependent high byte corruption (AccuracyCoin tests both)
  - SHS affects stack pointer as side effect
  - When page boundary NOT crossed, H+1 may differ
  - RDY line interaction (errors 6-A for SHA/SHX/SHY, 7-C for SHS)
- **Validation** (SHA/SHX/SHY - Error Codes F, 0-A):
  ```
  F: High byte corruption matches known behavior (SHA only)
  0: Correct operand byte count
  1-5: Target address, A, X, Y, flags correct
  6-A: Same checks if RDY line goes low 2 cycles before write
  ```
- **Validation** (SHS - Error Codes F, 0-C):
  ```
  F: High byte corruption matches known behavior
  0-6: Same as above, plus stack pointer check
  7-C: Same checks if RDY line goes low 2 cycles before write
  ```

---

### 3.4 Register Load: LAX, LXA, LAE (Test: "Unofficial Instructions")

**AccuracyCoin Reference**: Error Codes F, G, H

- **Requirement**: Combined register load operations
- **Hardware Behavior**:
  - **LAX** (Error F): Load memory into A and X simultaneously
    - Equivalent to: LDA addr; TAX
    - Sets N, Z flags based on loaded value
  - **LXA** (Error G): Highly unstable immediate mode instruction
    - Approximately: A = (A OR magic) AND X AND imm
    - Magic constant varies by CPU (often $00, $FF, $EE, or other)
    - Not recommended for use, but must be tested
  - **LAE** (Error H): Load memory AND S into A, X, and S
    - A = X = S = memory AND S
    - Affects N, Z flags
- **Edge Cases**:
  - LXA magic constant varies - AccuracyCoin tests common values
  - LAE modifies three registers including stack pointer
  - All affect N, Z flags
- **Validation** (Error Codes 0-6):
  ```
  Same as 3.1, with special attention to:
  - Multiple register updates
  - Stack pointer changes (LAE only)
  - Magic constant handling (LXA)
  ```

---

### 3.5 Math with Immediate: AXS (Test: "Unofficial Instructions")

**AccuracyCoin Reference**: Error Code J

- **Requirement**: Combined comparison and subtraction
- **Hardware Behavior**:
  - **AXS** (SBX): X = (A AND X) - immediate (without borrow)
    - Compare (A AND X) with immediate value
    - Store result in X
    - Set carry flag as if CMP operation
    - Set N, Z flags based on result
- **Edge Cases**:
  - Carry flag set as comparison, not subtraction
  - No borrow from carry (unlike SBC)
  - A register not modified, only X
- **Validation** (Error Codes 0-5):
  ```
  0: Correct operand bytes
  2: A register unchanged
  3: X register has correct result
  4: Y register unchanged
  5: Flags correct (especially carry behavior)
  ```

---

### 3.6 Unofficial SBC (Test: "Unofficial Instructions: SBC")

**AccuracyCoin Reference**: Grouped with other unofficial instructions

- **Requirement**: Opcode $EB functions identically to official SBC $E9
- **Hardware Behavior**:
  - $EB = SBC #immediate (unofficial duplicate)
  - Identical behavior to $E9 in all respects
  - Uses same ALU logic, same flags, same timing
- **Edge Cases**: None (identical to official SBC)
- **Validation**: Same as official SBC immediate instruction

---

## 4. Addressing Modes and Edge Cases

### 4.1 Absolute Indexed Wraparound (Test: "Absolute Indexed Wraparound")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: Absolute indexed addressing wraps at $FFFF boundary back to zero page
- **Hardware Behavior**:
  - Base address + index wraps with 16-bit arithmetic
  - Example: $FFFF + X=2 = $0001 (wraps to zero page, not $10001)
  - Both X and Y indexing wrap identically
- **Edge Cases**:
  - Test addresses near boundary: $FFFx + index
  - Verify wrapped address is in zero page ($0000-$00FF)
  - No dummy read if wrapping to same page (though unlikely at boundary)
- **Validation**:
  ```
  Error 1: Absolute indexed read from correct address
  Error 2: X indexing beyond $FFFF reads from zero page
  Error 3: Y indexing beyond $FFFF reads from zero page
  ```

---

### 4.2 Zero Page Indexed Wraparound (Test: "Zero Page Indexed Wraparound")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: Zero page indexed addressing stays in zero page (8-bit wraparound)
- **Hardware Behavior**:
  - Base ZP address + index wraps with 8-bit arithmetic
  - Example: $FF + X=2 = $01 (stays in ZP, not $101)
  - Only low 8 bits used for effective address
  - Both X and Y indexing wrap (Y used only by LDX/STX)
- **Edge Cases**:
  - Test boundary cases: $FF + 1, $FE + 2, etc.
  - Verify no access outside $00-$FF range
  - Verify correct cycle count (no page cross penalty in ZP mode)
- **Validation**:
  ```
  Error 1: ZP indexed read from correct ZP address
  Error 2: X indexing beyond $FF stays in zero page
  Error 3: Y indexing beyond $FF stays in zero page
  ```

---

### 4.3 Indirect Addressing Wraparound (Test: "Indirect Addressing Wraparound")

**AccuracyCoin Reference**: Error Codes 1-2

- **Requirement**: JMP (Indirect) wraps within page boundary for pointer address
- **Hardware Behavior**:
  - JMP ($xxFF) reads low byte from $xxFF, high byte from $xx00 (not $xy00)
  - This is famous 6502 bug: page boundary not crossed when reading pointer
  - Example: JMP ($10FF) reads low from $10FF, high from $1000
- **Edge Cases**:
  - Only affects addresses ending in $FF
  - Test specifically: JMP ($xxFF) for various xx values
  - Other indirect modes don't have this bug (different timing)
- **Validation**:
  ```
  Error 1: JMP indirect moves PC to correct address
  Error 2: Pointer wraparound stays within same page
  ```

---

### 4.4 Indirect X Addressing Wraparound (Test: "Indirect Addressing, X Wraparound")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: (Indirect,X) addressing wraps pointer calculation and pointer read in ZP
- **Hardware Behavior**:
  - Pointer address = (ZP base + X) & $FF (8-bit wraparound)
  - Pointer read: low from ptr, high from (ptr+1) & $FF (ZP wraparound)
  - Example: LDA ($FF,X) where X=1
    - Pointer address: ($FF + $01) & $FF = $00
    - Read pointer: low from $00, high from $01
- **Edge Cases**:
  - X addition wraps in zero page
  - Pointer read wraps in zero page (if pointer at $FF)
  - Double wraparound: ZP+X=$FF, then pointer high byte from $00
- **Validation**:
  ```
  Error 1: (Indirect,X) reads from correct final address
  Error 2: X indexing wraps within zero page
  Error 3: Pointer read wraps within zero page
  ```

---

### 4.5 Indirect Y Addressing Wraparound (Test: "Indirect Addressing, Y Wraparound")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: (Indirect),Y allows Y indexing to cross pages, but pointer stays in ZP
- **Hardware Behavior**:
  - Pointer read: low from ZP, high from (ZP+1) & $FF (ZP wraparound)
  - Final address: pointer value + Y (16-bit, can cross pages)
  - Example: LDA ($FF),Y
    - Read pointer: low from $FF, high from $00 (ZP wrap)
    - Then add Y to 16-bit pointer (may cross page)
- **Edge Cases**:
  - Pointer read wraps in ZP (if base at $FF)
  - Y indexing does NOT wrap (full 16-bit addressing)
  - Page cross adds cycle for read instructions
- **Validation**:
  ```
  Error 1: (Indirect),Y reads from correct final address
  Error 2: Y indexing can cross page boundary with high byte update
  Error 3: Pointer read wraps within zero page
  ```

---

### 4.6 Relative Addressing Wraparound (Test: "Relative Addressing Wraparound")

**AccuracyCoin Reference**: Error Codes 1-2

- **Requirement**: Branch instructions can wrap between zero page and high memory
- **Hardware Behavior**:
  - Branch offset is signed 8-bit (-128 to +127)
  - PC + offset wraps with 16-bit arithmetic
  - Can branch from $00xx to $FFxx (backward)
  - Can branch from $FFxx to $00xx (forward)
- **Edge Cases**:
  - Test crossing from ZP to page $FF
  - Test crossing from page $FF to ZP
  - Verify signed offset handling (negative branches)
  - Page crossing adds cycle to branch
- **Validation**:
  ```
  Error 1: Can branch from Zero Page to page $FF
  Error 2: Can branch from page $FF to Zero Page
  ```

---

## 5. CPU Flags and Status Register

### 5.1 Decimal Flag (Covered in Section 2.1)

See **2.1 Decimal Flag Behavior** for complete requirements.

---

### 5.2 B Flag (Covered in Section 2.2)

See **2.2 B Flag Behavior** for complete requirements.

---

### 5.3 Interrupt Flag Latency (Test: "Interrupt Flag Latency")

**AccuracyCoin Reference**: Error Codes 1-C

- **Requirement**: Interrupt flag changes and interrupt polling have precise timing
- **Hardware Behavior**:
  - Instructions poll for interrupts at specific cycle
  - CLI polls BEFORE cycle 2, so IRQ earliest 2 instructions later
  - SEI polls BEFORE cycle 2, but I flag set after, so IRQ can occur 1 cycle after
  - PLP polls BEFORE cycle 2, so IRQ earliest 2 instructions later
  - RTI sets I flag before polling, so IRQ can occur 1 cycle after
  - Branch instructions poll before cycle 2, not cycle 3, and before cycle 4
- **Edge Cases**:
  - IRQ occurring between SEI completion and next instruction
  - IRQ after RTI when I flag was clear in popped status
  - Branch instruction interrupt polling at multiple points
  - Interrupt polling vs interrupt latching (interrupt set then cleared)
- **Validation**:
  ```
  Error 1: IRQ occurs when DMC sample ends, DMC IRQ enabled, I flag clear
  Error 2: IRQ occurs 2 instructions after CLI
  Error 3: IRQ can occur 1 cycle after SEI final cycle
  Error 4: If IRQ 1 cycle after SEI, I flag set in pushed value
  Error 5: IRQ runs again after RTI if not acknowledged and I flag was clear
  Error 6: IRQ occurs 1 cycle after RTI final cycle
  Error 7: IRQ occurs 2 instructions after PLP
  Error 8: DMA triggers IRQ on correct CPU cycle
  Error 9: Branch polls before cycle 2
  Error A: Branch does NOT poll before cycle 3
  Error B: Branch polls before cycle 4
  Error C: Interrupt polled, cleared, polled again still occurs
  ```

---

## 6. Interrupt Handling

### 6.1 NMI Overlap BRK (Test: "NMI Overlap BRK")

**AccuracyCoin Reference**: Error Codes 1-2

- **Requirement**: NMI during BRK execution causes interrupt hijacking
- **Hardware Behavior**:
  - BRK pushes PC+2, status with B=1, then reads IRQ vector
  - If NMI occurs during BRK execution, vector read changes to NMI vector
  - Return address still PC+2 (BRK's behavior)
  - Status still has B=1 (BRK's behavior)
  - But handler is NMI handler (interrupt hijacking)
- **Edge Cases**:
  - Precise NMI timing relative to BRK cycles
  - Return address must be BRK's PC+2
  - B flag still set (from BRK)
  - But execution goes to NMI vector
- **Validation**:
  ```
  Error 1: BRK returns to correct address
  Error 2: NMI timing or interrupt hijacking incorrect
  ```

---

### 6.2 NMI Overlap IRQ (Test: "NMI Overlap IRQ")

**AccuracyCoin Reference**: Error Code 1

- **Requirement**: NMI during IRQ execution causes interrupt hijacking
- **Hardware Behavior**:
  - Similar to NMI/BRK overlap
  - IRQ begins execution (push PC, push status with B=0)
  - If NMI occurs before vector read, NMI vector used instead
  - Status has B=0 (IRQ's behavior)
  - Handler is NMI handler (hijacked)
- **Edge Cases**:
  - Precise NMI timing relative to IRQ cycles
  - NMI can hijack IRQ, but IRQ cannot hijack NMI (NMI priority)
- **Validation**:
  ```
  Error 1: NMI timing, IRQ timing, or hijacking incorrect
  ```

---

## 7. CPU Timing and Cycle Accuracy

### 7.1 Instruction Timing (Test: "Instruction Timing")

**AccuracyCoin Reference**: Error Codes 1-P

- **Requirement**: Every instruction must take exact number of CPU cycles
- **Hardware Behavior**:
  - Immediate: 2 cycles
  - Zero Page (read): 3 cycles
  - Zero Page (RMW): 5 cycles
  - Zero Page,X/Y (read): 4 cycles
  - Zero Page,X/Y (RMW): 6 cycles
  - Absolute (read): 4 cycles
  - Absolute (RMW): 6 cycles
  - Absolute,X/Y (STA): 5 cycles always
  - Absolute,X/Y (read): 4 cycles (+1 if page cross)
  - Absolute,X/Y (RMW): 7 cycles always
  - (Indirect,X): 6 cycles (unofficial may vary)
  - (Indirect),Y: 5 cycles (+1 if page cross) for reads
  - Implied: 2 cycles
  - PHP: 3 cycles
  - PHA: 3 cycles
  - PLP: 4 cycles
  - PLA: 4 cycles
  - JMP: 3 cycles
  - JSR: 6 cycles
  - RTS: 6 cycles
  - RTI: 6 cycles
  - BRK: 7 cycles
  - JMP (Indirect): 5 cycles
- **Edge Cases**:
  - Page crossing detection for indexed modes
  - RMW instructions always take full cycles (no page cross variation)
  - Store instructions (STA, etc.) always take full cycles
- **Validation**: Each error code tests specific instruction class
  ```
  Error 1: DMA updates data bus (prerequisite)
  Error 2: DMA timing accurate (prerequisite)
  Error 3-P: Each tests specific instruction timing class
  ```

---

## 8. Dummy Read/Write Cycles

### 8.1 Dummy Read Cycles (Test: "Dummy read cycles")

**AccuracyCoin Reference**: Error Codes 1-B

- **Requirement**: Dummy reads occur at specific addresses during certain instructions
- **Hardware Behavior**:
  - Absolute,X/Y: If page crossed, dummy read from (base + index) & $xxFF
    - Read from wrong page (before high byte increment)
    - Then read from correct page
  - (Indirect),Y: If page crossed, dummy read similar to Absolute,Y
  - (Indirect,X): NO dummy read (different timing)
  - STA,X/Y: HAS dummy read even though it's a write instruction
  - Read-Modify-Write: Different dummy behavior (see 8.2)
- **Edge Cases**:
  - Dummy reads are actual memory accesses (can trigger side effects)
  - Reading from $2002 (PPU_STATUS) has side effects - test uses this
  - Store instructions have dummy reads despite being writes
  - (Indirect,X) has NO dummy read even if page would cross
- **Validation**:
  ```
  Error 1: LDA $20F2,X (X=$10) reads $2002 twice (dummy + real)
  Error 2: No dummy read if page boundary not crossed
  Error 3: Dummy read at incorrect address
  Error 4: STA,X has dummy read
  Error 5: STA,X dummy read at incorrect address
  Error 6: LDA (Indirect),Y no dummy if page not crossed
  Error 7: LDA (Indirect),Y dummy read if page crossed
  Error 8: STA (Indirect),Y no dummy if page not crossed
  Error 9: STA (Indirect),Y dummy read if page crossed
  Error A: LDA (Indirect,X) no dummy read
  Error B: STA (Indirect,X) no dummy read
  ```

---

### 8.2 Dummy Write Cycles (Test: "Dummy write cycles")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: Read-Modify-Write instructions write original value before final value
- **Hardware Behavior**:
  - RMW instructions: Read, Write (old value), Write (new value)
  - Middle write is "dummy write" with original value
  - Occurs for all RMW: INC, DEC, ASL, LSR, ROL, ROR, and unofficial RMW
  - Affects memory-mapped I/O (writing to $2006 twice in test)
- **Edge Cases**:
  - Dummy write is actual bus cycle (triggers I/O side effects)
  - Test uses $2006 (PPU address) to detect double write
  - Both indexed and non-indexed RMW have dummy write
- **Validation**:
  ```
  Error 1: PPU Open Bus exists (prerequisite)
  Error 2: RMW instructions write to $2006 twice
  Error 3: RMW with X indexing writes to $2006 twice
  ```

---

### 8.3 Implied Dummy Reads (Test: "Implied Dummy Reads")

**AccuracyCoin Reference**: Error Codes 1-X

- **Requirement**: Implied/accumulator instructions perform dummy read of next byte
- **Hardware Behavior**:
  - All 2-cycle implied instructions read from PC after fetching opcode
  - PC incremented after opcode read, so dummy read is from PC+1
  - This is actual memory read (updates data bus, can trigger I/O)
  - Affects: All register transfers, flag operations, accumulator RMW
  - Also affects stack operations on their second cycle
- **Edge Cases**:
  - Every implied instruction from NOP to TXS
  - Stack operations (PHP, PHA, PLP, PLA)
  - BRK, RTI, RTS also have dummy reads
  - Test uses open bus to detect dummy reads
- **Validation**: Each error code tests one implied instruction
  ```
  Error 1-4: Prerequisites (SLO, frame counter, DMC DMA, open bus)
  Error 5-X: Each tests specific implied instruction's dummy read
  ```

---

## 9. Open Bus Behavior

### 9.1 Open Bus (Test: "Open Bus")

**AccuracyCoin Reference**: Error Codes 1-8

- **Requirement**: Unmapped memory reads return last value on data bus
- **Hardware Behavior**:
  - Data bus retains last value driven on it
  - Reading from unmapped address returns this stale value
  - Writes always update data bus (even to unmapped addresses)
  - Different I/O registers have different bus update behavior
- **Edge Cases**:
  - Open bus not all zeroes (depends on last bus activity)
  - Reading absolute instruction from open bus reads high byte of operand
  - Indexed addressing doesn't update bus to new high byte during dummy read
  - Executing code from open bus reads from floating bus values
  - Dummy reads update data bus
  - Controller reads have upper 3 bits from open bus
  - $4015 read does NOT update data bus
  - Writes ALWAYS update data bus (even $4015 write)
- **Validation**:
  ```
  Error 1: Open bus is not all zeroes
  Error 2: LDA Absolute from open bus returns high byte of operand
  Error 3: Indexed page crossing doesn't update bus with new high byte
  Error 4: PC in open bus executes from floating bus values
  Error 5: Dummy reads update data bus
  Error 6: Controller upper 3 bits are open bus
  Error 7: Reading $4015 does not update data bus
  Error 8: Writing (even to $4015) updates data bus
  ```

---

### 9.2 JSR Edge Cases (Test: "JSR Edge Cases")

**AccuracyCoin Reference**: Error Codes 1-3

- **Requirement**: JSR has specific open bus behavior with operand handling
- **Hardware Behavior**:
  - JSR pushes return address PC+2 (address of next instruction -1)
  - Pushed value is address of last byte of JSR, not first byte of next instruction
  - JSR's second operand byte (high byte of target) left on data bus
  - This can be detected via open bus reads
- **Edge Cases**:
  - Return address is PC+2, not PC+3
  - Data bus holds second operand byte after JSR
  - Open bus can reveal JSR timing
- **Validation**:
  ```
  Error 1: Pushed return address is correct (PC+2)
  Error 2: Open bus emulation incorrect
  Error 3: JSR leaves second operand on data bus
  ```

---

## 10. Power-On State

### 10.1 CPU Registers Power On State (Test: "CPU Registers Power On State")

**AccuracyCoin Reference**: Error Codes 1-5

- **Requirement**: CPU registers must have correct initial state at power-on
- **Hardware Behavior**:
  - A = $00
  - X = $00
  - Y = $00
  - S = $FD (stack pointer)
  - P = $34 (flags: I=1, bit5=1, all others=0)
  - PC = read from $FFFC-$FFFD (reset vector)
- **Edge Cases**:
  - Flags specifically: I flag SET, D flag CLEAR, others undefined but typically clear
  - Stack pointer NOT $FF (starts at $FD on power-on, $FF after reset)
- **Validation**:
  ```
  Error 1: A register is $00 at power on
  Error 2: X register is $00 at power on
  Error 3: Y register is $00 at power on
  Error 4: Stack pointer is $FD at power on
  Error 5: I flag is set at power on
  ```

---

## 11. TDD Implementation Roadmap

This section provides a phased approach to implementing CPU emulation using TDD based on AccuracyCoin requirements.

---

### Phase 1: Foundation (Core Instructions and Memory)

**Goal**: Basic CPU operation with minimal instruction set

**Tests to Implement**:
1. Memory and Bus Behavior
   - [ ] 1.1 ROM Write Protection
   - [ ] 1.2 RAM Mirroring
   - [ ] 10.1 CPU Registers Power On State

2. Basic Load/Store Instructions
   - [ ] LDA (Immediate, Zero Page, Absolute)
   - [ ] STA (Zero Page, Absolute)
   - [ ] LDX, LDY, STX, STY (basic modes)
   - [ ] Verify N, Z flags set correctly

3. Register Transfers
   - [ ] TAX, TAY, TXA, TYA, TSX, TXS
   - [ ] Flag updates (N, Z)

4. Basic Arithmetic
   - [ ] ADC, SBC (Immediate mode)
   - [ ] 2.1 Decimal Flag (verify no BCD mode)
   - [ ] C, V, N, Z flags

**Success Criteria**: Can load values, store them, transfer between registers, perform basic math

---

### Phase 2: Control Flow and Branches

**Goal**: Program flow control and flag operations

**Tests to Implement**:
1. Branches
   - [ ] BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS
   - [ ] Branch timing (2 cycles no branch, 3 cycles same page, 4 cycles page cross)
   - [ ] 4.6 Relative Addressing Wraparound

2. Jumps and Calls
   - [ ] JMP (Absolute)
   - [ ] JMP (Indirect)
   - [ ] 4.3 Indirect Addressing Wraparound
   - [ ] JSR
   - [ ] 9.2 JSR Edge Cases
   - [ ] RTS

3. Flag Operations
   - [ ] CLC, SEC, CLI, SEI, CLD, SED, CLV
   - [ ] 2.1 Decimal Flag behavior

4. Stack Operations
   - [ ] PHA, PLA, PHP, PLP
   - [ ] 2.2 B Flag Behavior
   - [ ] Stack wraparound in zero page

**Success Criteria**: Can execute programs with loops, function calls, conditional logic

---

### Phase 3: Complete Addressing Modes

**Goal**: All addressing mode variants for existing instructions

**Tests to Implement**:
1. Zero Page Indexed
   - [ ] All instructions with ,X and ,Y modes
   - [ ] 4.2 Zero Page Indexed Wraparound

2. Absolute Indexed
   - [ ] All instructions with ,X and ,Y modes
   - [ ] 4.1 Absolute Indexed Wraparound
   - [ ] Page crossing cycle penalty

3. Indirect Indexed
   - [ ] (Indirect,X) all instructions
   - [ ] 4.4 Indirect X Addressing Wraparound
   - [ ] (Indirect),Y all instructions
   - [ ] 4.5 Indirect Y Addressing Wraparound

4. Remaining Instructions
   - [ ] INC, DEC, INX, INY, DEX, DEY
   - [ ] CMP, CPX, CPY
   - [ ] AND, ORA, EOR
   - [ ] ASL, LSR, ROL, ROR (all modes)
   - [ ] BIT
   - [ ] NOP
   - [ ] 2.3 All NOP Instructions (official $EA only for now)

**Success Criteria**: Complete official instruction set works with all addressing modes

---

### Phase 4: Cycle-Accurate Timing

**Goal**: Exact cycle timing for all operations

**Tests to Implement**:
1. Instruction Timing
   - [ ] 7.1 Instruction Timing (all error codes 3-P)
   - [ ] Verify every instruction takes correct cycles
   - [ ] Verify page crossing penalties

2. Dummy Reads and Writes
   - [ ] 8.1 Dummy Read Cycles
   - [ ] 8.2 Dummy Write Cycles
   - [ ] 8.3 Implied Dummy Reads
   - [ ] Verify all memory accesses occur at correct cycles

3. Program Counter Behavior
   - [ ] 1.3 Program Counter Wraparound
   - [ ] PC increment timing
   - [ ] PC during interrupts

**Success Criteria**: Cycle-accurate execution matches hardware timing

---

### Phase 5: Interrupts and Edge Cases

**Goal**: Complete interrupt system and edge case handling

**Tests to Implement**:
1. Interrupt Basics
   - [ ] BRK instruction
   - [ ] RTI instruction
   - [ ] 2.2 B Flag Behavior (complete all error codes)

2. Interrupt Timing
   - [ ] 5.3 Interrupt Flag Latency (all error codes)
   - [ ] CLI, SEI timing with interrupts
   - [ ] PLP, RTI timing with interrupts

3. Interrupt Overlap
   - [ ] 6.1 NMI Overlap BRK
   - [ ] 6.2 NMI Overlap IRQ
   - [ ] Interrupt hijacking

**Success Criteria**: All interrupt behaviors match hardware exactly

---

### Phase 6: Open Bus and Bus Behavior

**Goal**: Accurate data bus modeling

**Tests to Implement**:
1. Open Bus Reads
   - [ ] 9.1 Open Bus (all error codes 1-8)
   - [ ] Data bus decay
   - [ ] Different bus behaviors for different I/O

2. Bus Interaction Details
   - [ ] Indexed addressing bus behavior
   - [ ] Dummy read bus updates
   - [ ] Write bus updates

**Success Criteria**: Data bus behavior matches hardware in all scenarios

---

### Phase 7: Unofficial Instructions

**Goal**: Complete unofficial opcode support

**Tests to Implement**:
1. Stable Unofficial Instructions
   - [ ] 3.1 SLO, RLA, SRE, RRA, DCP, ISC (all addressing modes)
   - [ ] 3.2 ANC, ASR, ARR
   - [ ] 3.3 SAX
   - [ ] 3.4 LAX
   - [ ] 3.5 AXS
   - [ ] 3.6 Unofficial SBC

2. Unstable Unofficial Instructions
   - [ ] 3.3 SHA, SHX, SHY, SHS (with revision handling)
   - [ ] 3.4 LXA (with magic constant handling)
   - [ ] 3.4 LAE

3. All NOPs
   - [ ] 2.3 All NOP Instructions (all 19 NOPs)

**Success Criteria**: All 256 opcodes implemented and tested

---

### Phase 8: Integration and Accuracy Validation

**Goal**: Run complete AccuracyCoin test suite

**Tests to Implement**:
1. Run entire AccuracyCoin ROM
2. Verify all CPU tests pass
3. Document any revision-specific behaviors
4. Create regression test suite

**Success Criteria**: AccuracyCoin CPU tests 100% pass rate

---

## Test Implementation Guidelines

### TDD Workflow

For each requirement:

1. **Write Failing Test**
   ```zig
   test "1.2 RAM Mirroring - Error Code 1" {
       var cpu = try CPU.init(testing.allocator);
       defer cpu.deinit();

       // Write to $0123
       cpu.write(0x0123, 0x42);

       // Read from mirrors
       try testing.expectEqual(@as(u8, 0x42), cpu.read(0x0923));
       try testing.expectEqual(@as(u8, 0x42), cpu.read(0x1123));
       try testing.expectEqual(@as(u8, 0x42), cpu.read(0x1923));
   }
   ```

2. **Implement Minimal Code**
   - Only implement enough to pass current test
   - Don't anticipate future requirements

3. **Refactor**
   - Clean up code while keeping tests green
   - Extract common patterns

4. **Document**
   - Add comments referencing AccuracyCoin error codes
   - Document hardware behavior being emulated

### Test Organization

**File Structure**:
```
tests/
├── cpu/
│   ├── memory_tests.zig          // Section 1 tests
│   ├── instructions_core.zig     // Section 2 tests
│   ├── instructions_unofficial.zig // Section 3 tests
│   ├── addressing_modes.zig      // Section 4 tests
│   ├── flags_tests.zig           // Section 5 tests
│   ├── interrupts_tests.zig      // Section 6 tests
│   ├── timing_tests.zig          // Section 7 tests
│   ├── dummy_cycles_tests.zig    // Section 8 tests
│   ├── open_bus_tests.zig        // Section 9 tests
│   └── power_on_tests.zig        // Section 10 tests
└── integration/
    └── accuracycoin_tests.zig    // Full ROM tests
```

### Test Naming Convention

Use AccuracyCoin test names and error codes:
```zig
test "1.2 RAM Mirroring - Error Code 1: 13-bit mirror reads" { ... }
test "1.2 RAM Mirroring - Error Code 2: 13-bit mirror writes" { ... }
test "2.2 B Flag - Error Code 1: PHP sets B flag" { ... }
```

This makes it trivial to map test failures to AccuracyCoin documentation.

---

## Validation Strategy

### Unit Test Level
- Each instruction tested in isolation
- Each addressing mode tested separately
- Each flag behavior tested explicitly

### Integration Test Level
- Instruction sequences (JSR followed by RTS)
- Interrupt during instruction execution
- Page crossing scenarios

### Acceptance Test Level
- Run actual AccuracyCoin ROM
- Capture error codes
- Map to specific requirements in this document

### Regression Test Level
- Save ROM test results
- Automated testing on each commit
- Performance benchmarks

---

## Success Metrics

### Phase Completion Criteria

Each phase is complete when:
1. All tests in phase pass
2. Code coverage >95% for implemented features
3. No known bugs in phase scope
4. Documentation updated

### Overall CPU Emulation Complete When:

1. All AccuracyCoin CPU tests pass (PASS, not FAIL)
2. All 256 opcodes implemented (official + unofficial)
3. Cycle-accurate timing for all instructions
4. All addressing modes work correctly
5. Interrupt system fully functional
6. Open bus behavior accurate
7. All edge cases handled

---

## References

1. **AccuracyCoin ROM**: /home/colin/Development/RAMBO/AccuracyCoin/
2. **6502 Reference**: https://www.masswerk.at/6502/6502_instruction_set.html
3. **NES Dev Wiki**: https://www.nesdev.org/wiki/CPU
4. **Unofficial Opcodes**: https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes

---

## Appendix A: Quick Reference Tables

### Instruction Cycle Counts

| Addressing Mode | Read | Write | RMW |
|----------------|------|-------|-----|
| Immediate | 2 | - | - |
| Zero Page | 3 | 3 | 5 |
| Zero Page,X/Y | 4 | 4 | 6 |
| Absolute | 4 | 4 | 6 |
| Absolute,X/Y | 4* | 5 | 7 |
| (Indirect,X) | 6 | 6 | 8 |
| (Indirect),Y | 5* | 6 | 8 |
| Implied | 2 | - | - |

*+1 cycle if page boundary crossed for reads

### Flag Bit Positions

| Bit | Flag | Name | Description |
|-----|------|------|-------------|
| 7 | N | Negative | Set if result bit 7 is 1 |
| 6 | V | Overflow | Set if signed overflow occurred |
| 5 | - | Unused | Always 1 when pushed to stack |
| 4 | B | Break | Software (1) vs hardware (0) interrupt |
| 3 | D | Decimal | Ignored on NES (no BCD mode) |
| 2 | I | Interrupt Disable | IRQs disabled when set |
| 1 | Z | Zero | Set if result is zero |
| 0 | C | Carry | Set if carry/borrow occurred |

### Memory Map (CPU View)

| Address Range | Size | Description |
|--------------|------|-------------|
| $0000-$07FF | 2KB | RAM |
| $0800-$1FFF | 6KB | RAM mirrors (3x) |
| $2000-$2007 | 8B | PPU registers |
| $2008-$3FFF | 8KB | PPU register mirrors |
| $4000-$4017 | 24B | APU and I/O registers |
| $4018-$401F | 8B | APU test registers |
| $4020-$FFFF | ~48KB | Cartridge (ROM, RAM, mappers) |

---

**Document Version**: 1.0
**Last Updated**: 2025-10-02
**Maintained By**: RAMBO Development Team
