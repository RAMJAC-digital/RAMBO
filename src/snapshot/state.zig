// EmulationState serialization/deserialization functions
const std = @import("std");
const Config = @import("../config/Config.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const MasterClock = @import("../emulation/State.zig").MasterClock;
const CpuState = @import("../cpu/State.zig").CpuState;
const StatusFlags = @import("../cpu/State.zig").StatusFlags;
const ExecutionState = @import("../cpu/State.zig").ExecutionState;
const AddressingMode = @import("../cpu/State.zig").AddressingMode;
const InterruptType = @import("../cpu/State.zig").InterruptType;
const PpuState = @import("../ppu/State.zig").PpuState;
const PpuCtrl = @import("../ppu/State.zig").PpuCtrl;
const PpuMask = @import("../ppu/State.zig").PpuMask;
const PpuStatus = @import("../ppu/State.zig").PpuStatus;
const BusState = @import("../bus/State.zig").BusState;
const Mirroring = @import("../cartridge/ines.zig").Mirroring;

/// Config values for serialization (skip arena and mutex)
pub const ConfigValues = struct {
    console: Config.ConsoleVariant,
    cpu_variant: Config.CpuVariant,
    cpu_region: Config.VideoRegion,
    ppu_variant: Config.PpuVariant,
    ppu_region: Config.VideoRegion,
    ppu_accuracy: Config.AccuracyLevel,
    cic_variant: Config.CicVariant,
    cic_emulation: Config.CicEmulation,
};

/// Extract serializable config values from Config
pub fn extractConfigValues(config: *const Config.Config) ConfigValues {
    return .{
        .console = config.console,
        .cpu_variant = config.cpu.variant,
        .cpu_region = config.cpu.region,
        .ppu_variant = config.ppu.variant,
        .ppu_region = config.ppu.region,
        .ppu_accuracy = config.ppu.accuracy,
        .cic_variant = config.cic.variant,
        .cic_emulation = config.cic.emulation,
    };
}

/// Verify that provided config matches serialized values
pub fn verifyConfigValues(config: *const Config.Config, values: ConfigValues) !void {
    if (config.console != values.console) return error.ConfigMismatch;
    if (config.cpu.variant != values.cpu_variant) return error.ConfigMismatch;
    if (config.cpu.region != values.cpu_region) return error.ConfigMismatch;
    if (config.ppu.variant != values.ppu_variant) return error.ConfigMismatch;
    if (config.ppu.region != values.ppu_region) return error.ConfigMismatch;
}

/// Write config values to binary format
pub fn writeConfig(writer: anytype, config: *const Config.Config) !void {
    const values = extractConfigValues(config);

    try writer.writeByte(@intFromEnum(values.console));
    try writer.writeByte(@intFromEnum(values.cpu_variant));
    try writer.writeByte(@intFromEnum(values.cpu_region));
    try writer.writeByte(@intFromEnum(values.ppu_variant));
    try writer.writeByte(@intFromEnum(values.ppu_region));
    try writer.writeByte(@intFromEnum(values.ppu_accuracy));
    try writer.writeByte(@intFromEnum(values.cic_variant));
    try writer.writeByte(@intFromEnum(values.cic_emulation));
}

/// Read config values from binary format
pub fn readConfig(reader: anytype) !ConfigValues {
    return .{
        .console = @enumFromInt(try reader.readByte()),
        .cpu_variant = @enumFromInt(try reader.readByte()),
        .cpu_region = @enumFromInt(try reader.readByte()),
        .ppu_variant = @enumFromInt(try reader.readByte()),
        .ppu_region = @enumFromInt(try reader.readByte()),
        .ppu_accuracy = @enumFromInt(try reader.readByte()),
        .cic_variant = @enumFromInt(try reader.readByte()),
        .cic_emulation = @enumFromInt(try reader.readByte()),
    };
}

/// Write MasterClock to binary format
pub fn writeClock(writer: anytype, clock: *const MasterClock) !void {
    try writer.writeInt(u64, clock.ppu_cycles, .little);
}

/// Read MasterClock from binary format
pub fn readClock(reader: anytype) !MasterClock {
    return .{
        .ppu_cycles = try reader.readInt(u64, .little),
    };
}

/// Write CpuState to binary format
pub fn writeCpuState(writer: anytype, cpu: *const CpuState) !void {
    // Registers (7 bytes)
    try writer.writeByte(cpu.a);
    try writer.writeByte(cpu.x);
    try writer.writeByte(cpu.y);
    try writer.writeByte(cpu.sp);
    try writer.writeInt(u16, cpu.pc, .little);
    try writer.writeByte(cpu.p.toByte());

    // Cycle tracking (10 bytes)
    try writer.writeInt(u64, cpu.cycle_count, .little);
    try writer.writeByte(cpu.instruction_cycle);
    try writer.writeByte(@intFromEnum(cpu.state));

    // Instruction context (7 bytes)
    try writer.writeByte(cpu.opcode);
    try writer.writeByte(cpu.operand_low);
    try writer.writeByte(cpu.operand_high);
    try writer.writeInt(u16, cpu.effective_address, .little);
    try writer.writeByte(@intFromEnum(cpu.address_mode));
    try writer.writeByte(@intFromBool(cpu.page_crossed));

    // Open bus (1 byte)
    try writer.writeByte(cpu.data_bus);

    // Interrupts (4 bytes)
    try writer.writeByte(@intFromEnum(cpu.pending_interrupt));
    try writer.writeByte(@intFromBool(cpu.nmi_line));
    try writer.writeByte(@intFromBool(cpu.nmi_edge_detected));
    try writer.writeByte(@intFromBool(cpu.irq_line));

    // Misc (4 bytes)
    try writer.writeByte(@intFromBool(cpu.halted));
    try writer.writeByte(cpu.temp_value);
    try writer.writeInt(u16, cpu.temp_address, .little);
}

/// Read CpuState from binary format
pub fn readCpuState(reader: anytype) !CpuState {
    return .{
        // Registers
        .a = try reader.readByte(),
        .x = try reader.readByte(),
        .y = try reader.readByte(),
        .sp = try reader.readByte(),
        .pc = try reader.readInt(u16, .little),
        .p = StatusFlags.fromByte(try reader.readByte()),

        // Cycle tracking
        .cycle_count = try reader.readInt(u64, .little),
        .instruction_cycle = try reader.readByte(),
        .state = @enumFromInt(try reader.readByte()),

        // Instruction context
        .opcode = try reader.readByte(),
        .operand_low = try reader.readByte(),
        .operand_high = try reader.readByte(),
        .effective_address = try reader.readInt(u16, .little),
        .address_mode = @enumFromInt(try reader.readByte()),
        .page_crossed = try reader.readByte() != 0,

        // Open bus
        .data_bus = try reader.readByte(),

        // Interrupts
        .pending_interrupt = @enumFromInt(try reader.readByte()),
        .nmi_line = try reader.readByte() != 0,
        .nmi_edge_detected = try reader.readByte() != 0,
        .irq_line = try reader.readByte() != 0,

        // Misc
        .halted = try reader.readByte() != 0,
        .temp_value = try reader.readByte(),
        .temp_address = try reader.readInt(u16, .little),
    };
}

/// Write PpuState to binary format
pub fn writePpuState(writer: anytype, ppu: *const PpuState) !void {
    // Registers (4 bytes)
    try writer.writeByte(ppu.ctrl.toByte());
    try writer.writeByte(ppu.mask.toByte());
    try writer.writeByte(ppu.status.toByte(0)); // Status open bus bits not preserved
    try writer.writeByte(ppu.oam_addr);

    // Open bus (3 bytes)
    try writer.writeByte(ppu.open_bus.value);
    try writer.writeInt(u16, ppu.open_bus.decay_timer, .little);

    // Internal registers (10 bytes)
    try writer.writeInt(u16, ppu.internal.v, .little);
    try writer.writeInt(u16, ppu.internal.t, .little);
    try writer.writeByte(ppu.internal.x); // 3-bit value stored as u8
    try writer.writeByte(@intFromBool(ppu.internal.w));
    try writer.writeByte(ppu.internal.read_buffer);

    // Background state (10 bytes)
    try writer.writeInt(u16, ppu.bg_state.pattern_shift_lo, .little);
    try writer.writeInt(u16, ppu.bg_state.pattern_shift_hi, .little);
    try writer.writeByte(ppu.bg_state.attribute_shift_lo);
    try writer.writeByte(ppu.bg_state.attribute_shift_hi);
    try writer.writeByte(ppu.bg_state.nametable_latch);
    try writer.writeByte(ppu.bg_state.attribute_latch);
    try writer.writeByte(ppu.bg_state.pattern_latch_lo);
    try writer.writeByte(ppu.bg_state.pattern_latch_hi);

    // OAM (288 bytes)
    try writer.writeAll(&ppu.oam);
    try writer.writeAll(&ppu.secondary_oam);

    // VRAM (2080 bytes)
    try writer.writeAll(&ppu.vram);
    try writer.writeAll(&ppu.palette_ram);

    // Metadata (15 bytes)
    try writer.writeByte(@intFromEnum(ppu.mirroring));
    try writer.writeByte(@intFromBool(ppu.nmi_occurred));
    try writer.writeInt(u16, ppu.scanline, .little);
    try writer.writeInt(u16, ppu.dot, .little);
    try writer.writeInt(u64, ppu.frame, .little);
}

/// Read PpuState from binary format
pub fn readPpuState(reader: anytype) !PpuState {
    var ppu = PpuState{};

    // Registers
    ppu.ctrl = PpuCtrl.fromByte(try reader.readByte());
    ppu.mask = PpuMask.fromByte(try reader.readByte());
    ppu.status = PpuStatus.fromByte(try reader.readByte());
    ppu.oam_addr = try reader.readByte();

    // Open bus
    ppu.open_bus.value = try reader.readByte();
    ppu.open_bus.decay_timer = try reader.readInt(u16, .little);

    // Internal registers
    ppu.internal.v = try reader.readInt(u16, .little);
    ppu.internal.t = try reader.readInt(u16, .little);
    ppu.internal.x = @truncate(try reader.readByte());
    ppu.internal.w = try reader.readByte() != 0;
    ppu.internal.read_buffer = try reader.readByte();

    // Background state
    ppu.bg_state.pattern_shift_lo = try reader.readInt(u16, .little);
    ppu.bg_state.pattern_shift_hi = try reader.readInt(u16, .little);
    ppu.bg_state.attribute_shift_lo = try reader.readByte();
    ppu.bg_state.attribute_shift_hi = try reader.readByte();
    ppu.bg_state.nametable_latch = try reader.readByte();
    ppu.bg_state.attribute_latch = try reader.readByte();
    ppu.bg_state.pattern_latch_lo = try reader.readByte();
    ppu.bg_state.pattern_latch_hi = try reader.readByte();

    // OAM
    try reader.readNoEof(&ppu.oam);
    try reader.readNoEof(&ppu.secondary_oam);

    // VRAM
    try reader.readNoEof(&ppu.vram);
    try reader.readNoEof(&ppu.palette_ram);

    // Metadata
    ppu.mirroring = @enumFromInt(try reader.readByte());
    ppu.nmi_occurred = try reader.readByte() != 0;
    ppu.scanline = try reader.readInt(u16, .little);
    ppu.dot = try reader.readInt(u16, .little);
    ppu.frame = try reader.readInt(u64, .little);

    // Note: cartridge pointer will be set externally via connectComponents()

    return ppu;
}

/// Write BusState to binary format
pub fn writeBusState(writer: anytype, bus: *const BusState) !void {
    // RAM (2048 bytes)
    try writer.writeAll(&bus.ram);

    // Cycle (8 bytes)
    try writer.writeInt(u64, bus.cycle, .little);

    // Open bus (9 bytes)
    try writer.writeByte(bus.open_bus.value);
    try writer.writeInt(u64, bus.open_bus.last_update_cycle, .little);
}

/// Read BusState from binary format
pub fn readBusState(reader: anytype) !BusState {
    var bus = BusState{};

    // RAM
    try reader.readNoEof(&bus.ram);

    // Cycle
    bus.cycle = try reader.readInt(u64, .little);

    // Open bus
    bus.open_bus.value = try reader.readByte();
    bus.open_bus.last_update_cycle = try reader.readInt(u64, .little);

    // Note: cartridge and ppu pointers will be set externally via connectComponents()

    return bus;
}

/// Write EmulationState flags to binary format
pub fn writeEmulationStateFlags(writer: anytype, state: *const EmulationState) !void {
    try writer.writeByte(@intFromBool(state.frame_complete));
    try writer.writeByte(@intFromBool(state.odd_frame));
    try writer.writeByte(@intFromBool(state.rendering_enabled));
}

/// Read EmulationState flags from binary format
pub fn readEmulationStateFlags(reader: anytype) !struct { frame_complete: bool, odd_frame: bool, rendering_enabled: bool } {
    return .{
        .frame_complete = try reader.readByte() != 0,
        .odd_frame = try reader.readByte() != 0,
        .rendering_enabled = try reader.readByte() != 0,
    };
}
