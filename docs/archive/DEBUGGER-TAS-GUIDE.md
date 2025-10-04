# Debugger TAS (Tool-Assisted Speedrun) Guide

This guide documents how the RAMBO debugger intentionally supports TAS workflows including undefined behaviors, memory corruption, and exploit techniques.

## Overview

The RAMBO debugger is designed to enable TAS users to manipulate emulation state in ways that would normally be impossible or undefined. Unlike production debuggers that protect against corrupted states, the RAMBO debugger **intentionally allows** any hardware-acceptable value, including those that may crash the system or trigger undefined behavior.

This design philosophy supports advanced TAS techniques such as:
- **ACE (Arbitrary Code Execution)**: Execute crafted data as code
- **Wrong Warps**: Manipulate PC and stack to skip to arbitrary game locations
- **Memory Corruption**: Set up specific RAM states to trigger glitches
- **Graphical Glitches**: Manipulate PPU state for visual exploits

## Design Philosophy

### Intent Tracking vs. Success Validation

The debugger tracks **INTENT** rather than enforcing **SUCCESS**. For example:

- **ROM Writes**: `writeMemory()` to ROM ($8000-$FFFF) logs the write attempt even though ROM is hardware-protected and the write fails
- **Invalid PC**: `setProgramCounter()` accepts RAM/I/O addresses that would execute data as code
- **Stack Overflow**: `setStackPointer()` accepts 0x00 or 0xFF which can corrupt adjacent memory

This intent tracking is critical for TAS workflows because it allows documentation of attempted corruptions that are part of the exploit setup, even if they don't directly modify memory.

### Zero Validation Philosophy

The debugger performs **ZERO validation** on values. Any value the 6502 CPU can physically accept is allowed:

- **No range checking** on registers or addresses
- **No protection** against stack overflow/underflow
- **No prevention** of PC in undefined regions
- **No blocking** of unusual status flag combinations

This matches the hardware's behavior - the real NES has no memory protection or validation. The debugger reflects this reality.

## TAS Techniques Supported

### 1. Arbitrary Code Execution (ACE)

**What it is**: Executing crafted RAM data as CPU instructions.

**How the debugger supports it**:

```zig
// Write crafted "code" to RAM
debugger.writeMemory(&state, 0x0200, 0xA9); // LDA #$42
debugger.writeMemory(&state, 0x0201, 0x42);
debugger.writeMemory(&state, 0x0202, 0x60); // RTS

// Set PC to RAM address - CPU will execute data as code
debugger.setProgramCounter(&state, 0x0200);
```

**Hardware behavior**: The 6502 CPU has no concept of "code" vs "data" - it executes whatever bytes are at PC. Setting PC to RAM ($0000-$1FFF) is perfectly valid hardware behavior, though unusual.

**Use case**: TAS runners craft specific byte sequences in RAM (often by manipulating sprite positions, player input, etc.) then jump to that RAM to execute arbitrary code.

### 2. Wrong Warp Glitches

**What it is**: Manipulating PC and stack pointer to jump to unintended game locations.

**How the debugger supports it**:

```zig
// Set up corrupted stack state
debugger.setStackPointer(&state, 0x00); // Stack overflow risk
debugger.writeMemory(&state, 0x0100, 0x50); // Return address low
debugger.writeMemory(&state, 0x0101, 0x80); // Return address high

// When RTS executes, will jump to $8050 (wrong location)
```

**Hardware behavior**: Stack lives at $0100-$01FF. When SP wraps (e.g., SP=0x00 then push), it wraps to $01FF, potentially corrupting critical data. RTS pops the return address from stack - if stack is corrupted, RTS jumps to wrong location.

**Use case**: Super Mario Bros. 3 wrong warp uses stack manipulation to jump directly to the ending sequence.

### 3. ROM Write Intent Tracking

**What it is**: Documenting attempted writes to ROM for exploit setup.

**How the debugger supports it**:

```zig
// Write to ROM (will update data bus but not modify ROM)
debugger.writeMemory(&state, 0x8000, 0xFF);

// Modification is LOGGED even though ROM wasn't modified
const mods = debugger.getModifications();
// mods[0].memory_write.address == 0x8000 (logged!)
```

**Hardware behavior**: ROM is read-only. Writes to ROM ($8000-$FFFF) update the data bus (affecting subsequent open bus reads) but don't modify the actual ROM chip.

**Use case**: Some TAS setups involve writing to ROM as part of a multi-step exploit. The debugger logs these attempts so TAS documentation can accurately reflect the full sequence, even "failed" writes.

### 4. Stack Overflow and Underflow

**What it is**: Manipulating stack pointer to extreme values that cause wrapping.

**How the debugger supports it**:

```zig
// Stack overflow (SP = 0x00)
debugger.setStackPointer(&state, 0x00);
// Stack now at $0100 - pushes will wrap to $01FF

// Stack underflow (SP = 0xFF)
debugger.setStackPointer(&state, 0xFF);
// Stack now at $01FF - pops will wrap to $0100
```

**Hardware behavior**: Stack pointer is 8-bit, lives in page 1 ($0100-$01FF). Overflow/underflow wraps within page 1. No hardware protection exists.

**Use case**: Stack manipulation is core to wrong warp glitches. By controlling SP precisely, TAS can force RTS to pop corrupted addresses, enabling arbitrary jumps.

### 5. Unusual Status Flag Combinations

**What it is**: Setting processor status flags to combinations that don't normally occur.

**How the debugger supports it**:

```zig
// Set decimal flag (ignored on NES)
debugger.setStatusRegister(&state, 0b00001000); // D flag

// Set ALL flags simultaneously
debugger.setStatusRegister(&state, 0xFF);

// Clear ALL flags (also unusual)
debugger.setStatusRegister(&state, 0x00);
```

**Hardware behavior**: All flag combinations are valid. Decimal flag (D) can be set but has no effect on NES (no BCD arithmetic). Games may have bugs triggered by unusual flag states.

**Use case**: TAS may manipulate flags to:
- Trigger game bugs (e.g., branch behavior with unusual Z/N combinations)
- Set up exploit prerequisites
- Test edge cases in game logic

### 6. PC in I/O Regions (Undefined Behavior)

**What it is**: Setting program counter to memory-mapped I/O addresses.

**How the debugger supports it**:

```zig
// Set PC to PPU register
debugger.setProgramCounter(&state, 0x2000); // PPUCTRL

// Set PC to APU register
debugger.setProgramCounter(&state, 0x4000);

// Set PC to controller I/O
debugger.setProgramCounter(&state, 0x4016);
```

**Hardware behavior**: CPU will attempt to fetch opcodes from I/O registers. Each read may trigger hardware side effects (PPU state changes, etc.). Behavior is undefined and may crash.

**Use case**: While rare, some TAS exploits intentionally jump to I/O regions to trigger specific hardware glitches or timing-dependent bugs.

## API Reference

### State Manipulation Functions

All state manipulation functions intentionally accept ANY value without validation:

#### `setProgramCounter(state: *EmulationState, value: u16)`

Sets PC to any address. Supports:
- PC in RAM ($0000-$1FFF) for ACE
- PC in I/O ($2000-$401F) for undefined behavior
- PC in unmapped regions (open bus opcodes)
- PC in CHR-ROM (graphics as code)

**No validation** - accepts any u16 value.

#### `writeMemory(state: *EmulationState, address: u16, value: u8)`

Writes to any address. Tracks INTENT even if write fails:
- RAM writes ($0000-$1FFF): Succeed
- I/O writes ($2000-$401F): Trigger hardware side effects
- ROM writes ($8000-$FFFF): Update data bus only, **logged in history**
- Unmapped writes: Update data bus only

**Intent tracking** - all writes logged, even failed ROM writes.

#### `setStackPointer(state: *EmulationState, value: u8)`

Sets SP to any value. Supports:
- SP = 0x00: Stack overflow risk
- SP = 0xFF: Stack underflow risk
- Any value 0x00-0xFF valid

**No validation** - accepts any u8 value.

#### `setStatusRegister(state: *EmulationState, value: u8)`

Sets all status flags from byte. Supports:
- Decimal flag (ignored on NES but can be set)
- All flags set (0xFF)
- All flags clear (0x00)
- Any combination

**No validation** - accepts any u8 value.

### Modification History

All state manipulations are logged in modification history, accessible via:

```zig
const mods = debugger.getModifications();
```

This includes:
- ✅ **Successful writes** (RAM, I/O)
- ✅ **Failed writes** (ROM) - intent is tracked
- ✅ **Register changes** (A, X, Y, SP, PC, P)
- ✅ **Status flag changes**

The history is bounded (default 1000 entries, configurable via `modifications_max_size`) and uses a circular buffer that automatically evicts oldest entries.

### Side-Effect-Free Inspection

For TAS analysis without affecting state:

```zig
// Read memory WITHOUT updating open bus
const value = debugger.readMemory(&state, address);

// Read memory range
const data = debugger.readMemoryRange(&state, start, length);
```

These use `Logic.peekMemory()` internally, which reads without hardware side effects. Critical for time-travel debugging where inspection must not corrupt the state being examined.

## Intentional Crashes and Undefined Behavior

**IMPORTANT**: The debugger can intentionally create states that crash or produce undefined behavior. This is **BY DESIGN**.

Examples of intentional crashes:

1. **PC in RAM + Invalid Opcode**: Setting PC to RAM containing invalid opcode
2. **Stack Underflow**: SP=0xFF then multiple pops
3. **I/O as Code**: PC in PPU/APU register range
4. **Open Bus Execution**: PC in unmapped region

The debugger makes NO attempt to prevent these scenarios. TAS users may intentionally create these states to:
- Test crash recovery
- Trigger timing-dependent glitches
- Explore undefined hardware behavior

## Testing

TAS support is validated by comprehensive tests in `tests/debugger/debugger_test.zig`:

1. **TAS Support: PC in RAM for ACE** - Validates ACE technique
2. **TAS Support: ROM write intent tracking** - Verifies failed writes are logged
3. **TAS Support: Stack overflow and underflow** - Tests extreme SP values
4. **TAS Support: Unusual status flag combinations** - Tests all flag states
5. **TAS Support: PC in I/O region** - Tests undefined behavior

All tests verify the debugger **does NOT prevent** these scenarios while maintaining accurate modification history.

## Best Practices for TAS Users

### 1. Document Your Intent

Use the modification history to document your exploit sequence:

```zig
// Step 1: Corrupt RAM
debugger.writeMemory(&state, 0x0300, 0x4C); // JMP opcode
debugger.writeMemory(&state, 0x0301, 0x00);
debugger.writeMemory(&state, 0x0302, 0x80); // Jump to $8000

// Step 2: Execute RAM (ACE)
debugger.setProgramCounter(&state, 0x0300);

// Get full history for documentation
const history = debugger.getModifications();
```

### 2. Use Snapshots for Exploit States

Create snapshots at critical points in your exploit:

```zig
// Save state before exploit attempt
const before_snapshot = try debugger.createSnapshot(&state);

// Attempt exploit
debugger.setProgramCounter(&state, 0x0200);

// If exploit fails, restore
try debugger.restoreSnapshot(&state, before_snapshot);
```

### 3. Monitor Open Bus

ROM writes update open bus. Track this for accuracy:

```zig
// Write to ROM (updates bus)
debugger.writeMemory(&state, 0x8000, 0xFF);

// Check bus state
const bus_value = state.bus.open_bus.value; // Now 0xFF
```

### 4. Verify Modification Bounds

For long TAS sessions, check history isn't truncated:

```zig
debugger.modifications_max_size = 10000; // Increase limit
```

## Differences from Production Debuggers

Traditional debuggers (GDB, LLDB) **prevent** invalid states. The RAMBO debugger **enables** them:

| Traditional Debugger | RAMBO Debugger (TAS) |
|---------------------|---------------------|
| Validates register ranges | Accepts any value |
| Prevents invalid PC | Allows PC anywhere |
| Blocks ROM writes | Logs ROM write intent |
| Warns on stack overflow | Allows stack wrap |
| Protects against corruption | Enables intentional corruption |

This reflects the target use case: TAS runners need **full hardware control** including undefined behaviors.

## Related Documentation

- **DEBUGGER-ARCHITECTURE-FIXES.md**: Complete implementation plan for debugger fixes
- **DEBUGGER-ENHANCEMENT-PLAN.md**: Future enhancement roadmap
- **debugger-api-guide.md**: Complete API reference
- **DEBUGGER-STATUS.md**: Current implementation status

## References

- [TASVideos Wiki: Arbitrary Code Execution](http://tasvideos.org/EmulatorResources/ACE.html)
- [TASVideos Wiki: Wrong Warp](http://tasvideos.org/GameResources/NES/SuperMarioBros3.html#WrongWarp)
- [6502 Stack Behavior](http://www.obelisk.me.uk/6502/architecture.html#stack)
- [NES Hardware Specifications](https://www.nesdev.org/wiki/CPU)
