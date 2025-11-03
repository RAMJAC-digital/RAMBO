//! State modification logic
//! Functions that mutate EmulationState with modification tracking

const std = @import("std");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const types = @import("types.zig");
const StateModification = types.StateModification;
const StatusFlag = types.StatusFlag;

// ============================================================================
// CPU Register Modification
// ============================================================================

/// Set accumulator register
pub fn setRegisterA(state: anytype, emu_state: *EmulationState, value: u8) void {
    emu_state.cpu.a = value;
    logModification(state, .{ .register_a = value });
}

/// Set X index register
pub fn setRegisterX(state: anytype, emu_state: *EmulationState, value: u8) void {
    emu_state.cpu.x = value;
    logModification(state, .{ .register_x = value });
}

/// Set Y index register
pub fn setRegisterY(state: anytype, emu_state: *EmulationState, value: u8) void {
    emu_state.cpu.y = value;
    logModification(state, .{ .register_y = value });
}

/// Set stack pointer to any value
///
/// **IMPORTANT FOR TAS USERS:**
/// Stack pointer can be set to any u8 value, including edge cases that may
/// cause stack overflow/underflow or corrupt critical memory regions.
///
/// Edge Cases (INTENTIONALLY SUPPORTED):
/// - SP = 0x00: Stack at $0100, pushes will wrap to $01FF (stack overflow into page 0)
/// - SP = 0xFF: Stack at $01FF, pops will wrap to $0100 (stack underflow)
/// - Manipulating SP can expose/corrupt zero page or stack variables
///
/// TAS Use Cases:
/// - Wrong warp glitches: Manipulate SP + RTS to jump to arbitrary addresses
/// - Stack underflow exploits: Pop corrupted return addresses
/// - ACE setup: Position stack to execute crafted data
///
/// Hardware Behavior:
/// Stack lives at $0100-$01FF (page 1). SP is 8-bit offset from $0100.
/// Overflow/underflow wrap within page 1 - no hardware protection.
pub fn setStackPointer(state: anytype, emu_state: *EmulationState, value: u8) void {
    emu_state.cpu.sp = value;
    logModification(state, .{ .stack_pointer = value });
}

/// Set program counter to any address
///
/// **IMPORTANT FOR TAS (Tool-Assisted Speedrun) USERS:**
/// This function allows setting PC to ANY address, including undefined regions.
/// The debugger intentionally supports setting invalid/corrupted states for TAS techniques.
///
/// Undefined Behaviors (INTENTIONALLY SUPPORTED):
/// - PC in RAM ($0000-$1FFF): Executes data as code (ACE - Arbitrary Code Execution)
/// - PC in I/O ($2000-$401F): Undefined behavior, may crash or glitch
/// - PC in unmapped regions: Reads open bus values as opcodes
/// - PC in CHR-ROM: Executes graphics data as code
///
/// TAS Use Cases:
/// - Wrong warp glitches (manipulate PC + stack for level skips)
/// - ACE exploits (execute crafted RAM data as code)
/// - Game ending glitches (jump directly to credits sequence)
///
/// Hardware Behavior:
/// The 6502 CPU will attempt to execute whatever bytes are at PC,
/// regardless of whether they're valid code, data, or unmapped regions.
/// This can crash the system or produce unexpected behavior - THIS IS INTENTIONAL.
pub fn setProgramCounter(state: anytype, emu_state: *EmulationState, value: u16) void {
    emu_state.cpu.pc = value;
    logModification(state, .{ .program_counter = value });
}

/// Set individual status flag
pub fn setStatusFlag(
    state: anytype,
    emu_state: *EmulationState,
    flag: StatusFlag,
    value: bool,
) void {
    switch (flag) {
        .carry => emu_state.cpu.p.carry = value,
        .zero => emu_state.cpu.p.zero = value,
        .interrupt => emu_state.cpu.p.interrupt = value,
        .decimal => emu_state.cpu.p.decimal = value,
        .overflow => emu_state.cpu.p.overflow = value,
        .negative => emu_state.cpu.p.negative = value,
    }
    logModification(state, .{ .status_flag = .{ .flag = flag, .value = value } });
}

/// Set complete status register from byte
///
/// **IMPORTANT FOR TAS USERS:**
/// All status flags can be set to any value, including combinations that are
/// unusual or don't normally occur during regular game execution.
///
/// Status Flags (bits 7-0):
/// - Bit 7: Negative (N) - Set if result is negative (bit 7 = 1)
/// - Bit 6: Overflow (V) - Set on signed overflow
/// - Bit 5: (unused, always 1 when read)
/// - Bit 4: Break (B) - Set by BRK, clear by IRQ/NMI (only on stack)
/// - Bit 3: Decimal (D) - Decimal mode (IGNORED on NES - no BCD)
/// - Bit 2: Interrupt (I) - Interrupt disable
/// - Bit 1: Zero (Z) - Set if result is zero
/// - Bit 0: Carry (C) - Set on arithmetic carry/borrow
///
/// Edge Cases (INTENTIONALLY SUPPORTED):
/// - Decimal flag: Can be set but has NO EFFECT on NES (no BCD mode)
/// - Unusual flag combinations: Any combination is valid for TAS
/// - Break flag: Only meaningful on stack, not in register
///
/// TAS Use Cases:
/// - Setting flags for branch manipulation (wrong warps)
/// - Creating unusual flag states to trigger game bugs
/// - Testing edge cases in game logic
///
/// Note: Bits 4 and 5 are not stored in P register but this function
/// accepts full 8-bit values for convenience. Bit 5 is always 1, bit 4
/// only appears on stack during BRK/IRQ.
pub fn setStatusRegister(state: anytype, emu_state: *EmulationState, value: u8) void {
    emu_state.cpu.p.carry = (value & 0x01) != 0;
    emu_state.cpu.p.zero = (value & 0x02) != 0;
    emu_state.cpu.p.interrupt = (value & 0x04) != 0;
    emu_state.cpu.p.decimal = (value & 0x08) != 0;
    emu_state.cpu.p.overflow = (value & 0x40) != 0;
    emu_state.cpu.p.negative = (value & 0x80) != 0;
    logModification(state, .{ .status_register = value });
}

// ============================================================================
// Memory Modification
// ============================================================================

/// Write single byte to memory (via bus)
///
/// **IMPORTANT FOR TAS USERS:**
/// This function tracks INTENT rather than success. Writes to read-only regions
/// (like ROM) are logged in modifications history even though they don't affect
/// actual memory. This is intentional for TAS workflows.
///
/// Hardware Behaviors:
/// - Writes to RAM ($0000-$1FFF): Succeed, data is stored
/// - Writes to I/O ($2000-$401F): Trigger hardware side effects (PPU, APU, etc.)
/// - Writes to ROM ($8000-$FFFF): Update data bus but DON'T modify cartridge ROM
///   (hardware write protection - ROM is read-only)
/// - Writes to unmapped regions: Update data bus only (open bus behavior)
///
/// Intent Tracking:
/// All writes are logged in modifications history regardless of success.
/// This allows TAS users to:
/// - Track attempted ROM corruption (for glitch setup documentation)
/// - Monitor I/O register manipulation sequences
/// - Verify memory state before attempting exploits
///
/// TAS Use Cases:
/// - Setting up RAM state for ACE exploits
/// - Manipulating PPU registers for graphical glitches
/// - Corrupting sprite data for position manipulation
///
/// Note: ROM writes update the data bus (affecting open bus reads) but don't
/// modify the actual ROM. This matches real NES hardware behavior.
pub fn writeMemory(
    state: anytype,
    emu_state: *EmulationState,
    address: u16,
    value: u8,
) void {
    emu_state.busWrite(address, value);
    logModification(state, .{ .memory_write = .{
        .address = address,
        .value = value,
    } });
}

/// Write byte range to memory
pub fn writeMemoryRange(
    state: anytype,
    emu_state: *EmulationState,
    start_address: u16,
    data: []const u8,
) void {
    for (data, 0..) |byte, offset| {
        const addr = start_address +% @as(u16, @intCast(offset));
        emu_state.busWrite(addr, byte);
    }
    logModification(state, .{ .memory_range = .{
        .start = start_address,
        .length = @intCast(data.len),
    } });
}

// ============================================================================
// PPU Modification
// ============================================================================

/// Set PPU scanline (for testing)
pub fn setPpuScanline(state: anytype, emu_state: *EmulationState, scanline: i16) void {
    // Directly set PPU's clock state (PPU owns its own timing now)
    emu_state.ppu.scanline = scanline;
    logModification(state, .{ .ppu_scanline = scanline });
}

/// Set PPU frame counter
pub fn setPpuFrame(state: anytype, emu_state: *EmulationState, frame: u64) void {
    // Directly set PPU's frame counter (PPU owns its own timing now)
    emu_state.ppu.frame_count = frame;
    logModification(state, .{ .ppu_frame = frame });
}

// ============================================================================
// Modification History
// ============================================================================

/// Log state modification for debugging history (bounded circular buffer)
/// Automatically removes oldest entry when max size reached
fn logModification(state: anytype, modification: StateModification) void {
    // Implement circular buffer - remove oldest when full
    if (state.modifications.items.len >= state.modifications_max_size) {
        _ = state.modifications.orderedRemove(0);
    }

    _ = state.modifications.append(state.allocator, modification) catch {};
}

/// Clear modification history
pub fn clearModifications(state: anytype) void {
    state.modifications.clearRetainingCapacity();
}
