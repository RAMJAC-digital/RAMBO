// State Snapshot System - Main API
//
// Complete emulation state serialization to binary format.
// Supports save/load for debugging, testing, and state persistence.

const std = @import("std");
const binary = @import("binary.zig");
const cartridge_snap = @import("cartridge.zig");
const state_ser = @import("state.zig");

const Config = @import("../config/Config.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Cartridge = @import("../cartridge/Cartridge.zig");

/// Snapshot metadata (extracted from header without full load)
pub const SnapshotMetadata = struct {
    version: u32,
    timestamp: i64,
    emulator_version: [16]u8,
    total_size: u64,
    state_size: u32,
    cartridge_size: u32,
    framebuffer_size: u32,
    flags: binary.SnapshotFlags,
};

/// Save EmulationState to binary format
///
/// Parameters:
/// - allocator: Memory allocator for snapshot buffer
/// - state: Emulation state to save
/// - config: Hardware configuration
/// - cartridge_mode: reference (ROM path/hash) or embed (full ROM data)
/// - include_framebuffer: Whether to include rendered framebuffer
/// - framebuffer: Optional framebuffer data (256×240×4 RGBA), required if include_framebuffer=true
///
/// Returns: Allocated snapshot buffer (caller owns memory)
///
/// Error handling: Returns error if allocation fails or serialization error occurs
pub fn saveBinary(
    allocator: std.mem.Allocator,
    state: *const EmulationState,
    config: *const Config.Config,
    cartridge_mode: cartridge_snap.CartridgeSnapshotMode,
    include_framebuffer: bool,
    framebuffer: ?[]const u8,
) ![]u8 {
    // Validate framebuffer if requested
    if (include_framebuffer) {
        if (framebuffer == null) return error.FramebufferRequired;
        if (framebuffer.?.len != 256 * 240 * 4) return error.InvalidFramebufferSize;
    }

    // Calculate sizes
    var state_size: u32 = 0;
    state_size += 10; // Config values
    state_size += 8;  // MasterClock
    state_size += 33; // CpuState
    state_size += getSizeForPpuState(); // PpuState (~2407 bytes)
    state_size += 2048 + 8 + 9; // BusState (ram + cycle + open_bus)
    state_size += 3; // EmulationState flags

    // Create cartridge snapshot
    var cart_snapshot: cartridge_snap.CartridgeSnapshot = undefined;
    var cart_allocated = false;
    defer if (cart_allocated) cartridge_snap.freeCartridgeSnapshot(allocator, &cart_snapshot);

    if (state.bus.cartridge) |cart| {
        cart_snapshot = try createCartridgeSnapshot(allocator, cart, cartridge_mode);
        cart_allocated = true;
    } else {
        // No cartridge loaded - use empty reference
        cart_snapshot = .{
            .reference = .{
                .rom_path = "",
                .rom_hash = [_]u8{0} ** 32,
                .mapper_state = &[_]u8{},
            },
        };
    }

    const cartridge_size: u32 = @intCast(cart_snapshot.getSerializedSize());
    const framebuffer_size: u32 = if (include_framebuffer) 256 * 240 * 4 else 0;
    const total_size: u64 = 72 + state_size + cartridge_size + framebuffer_size;

    // Create header
    const flags = binary.SnapshotFlags{
        .has_framebuffer = include_framebuffer,
        .cartridge_embedded = (cartridge_mode == .embed),
    };

    var header = binary.createHeader(
        total_size,
        state_size,
        cartridge_size,
        framebuffer_size,
        flags,
    );

    // Allocate buffer for complete snapshot
    var buffer = std.ArrayListUnmanaged(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Write header (placeholder, will update checksum later)
    try binary.writeHeader(writer, &header);

    // Mark position after header for checksum calculation
    const data_start = buffer.items.len;

    // Write config values
    try state_ser.writeConfig(writer, config);

    // Write MasterClock
    try state_ser.writeClock(writer, &state.clock);

    // Write component states
    try state_ser.writeCpuState(writer, &state.cpu);
    try state_ser.writePpuState(writer, &state.ppu);
    try state_ser.writeBusState(writer, &state.bus);

    // Write EmulationState flags
    try state_ser.writeEmulationStateFlags(writer, state);

    // Write cartridge snapshot
    try cartridge_snap.writeCartridgeSnapshot(writer, &cart_snapshot);

    // Write framebuffer if requested
    if (include_framebuffer) {
        try writer.writeAll(framebuffer.?);
    }

    // Calculate checksum over data after header
    const data = buffer.items[data_start..];
    binary.updateChecksum(&header, data);

    // Rewrite header with correct checksum
    var fbs = std.io.fixedBufferStream(buffer.items[0..72]);
    try binary.writeHeader(fbs.writer(), &header);

    return try buffer.toOwnedSlice(allocator);
}

/// Load EmulationState from binary format
///
/// Parameters:
/// - allocator: Memory allocator for any dynamic allocations during load
/// - data: Complete snapshot buffer
/// - config: Hardware configuration (must match snapshot config values)
/// - cartridge: Optional cartridge pointer for reference mode restore
///
/// Returns: Fully reconstructed EmulationState with all pointers connected
///
/// Error handling: Returns error if checksum fails, version mismatch, or incompatible config
pub fn loadBinary(
    allocator: std.mem.Allocator,
    data: []const u8,
    config: *const Config.Config,
    cartridge: anytype, // ?*NromCart or similar
) !EmulationState {
    if (data.len < 72) return error.InvalidSnapshot;

    // Read and verify header
    var fbs = std.io.fixedBufferStream(data);
    const header = try binary.readHeader(fbs.reader());
    try binary.verifyHeader(&header);

    // Verify checksum
    const data_start: usize = 72;
    const data_section = data[data_start..];
    try binary.verifyChecksum(&header, data_section);

    // Create reader for data section
    var data_fbs = std.io.fixedBufferStream(data_section);
    const reader = data_fbs.reader();

    // Read and verify config values
    const config_values = try state_ser.readConfig(reader);
    try state_ser.verifyConfigValues(config, config_values);

    // Read component states
    const clock = try state_ser.readClock(reader);
    const cpu = try state_ser.readCpuState(reader);
    const ppu = try state_ser.readPpuState(reader);
    const bus = try state_ser.readBusState(reader);
    const flags = try state_ser.readEmulationStateFlags(reader);

    // Read cartridge snapshot
    const cart_snapshot = try cartridge_snap.readCartridgeSnapshot(allocator, reader);
    defer {
        var mut_snapshot = cart_snapshot;
        cartridge_snap.freeCartridgeSnapshot(allocator, &mut_snapshot);
    }

    // Handle cartridge restoration
    // For reference mode: caller must provide matching cartridge (unless it's empty reference)
    // For embed mode: we have the ROM data but currently only support reference mode fully
    // TODO: Implement full cartridge reconstruction from embedded data
    if (cart_snapshot == .reference) {
        const is_empty_reference = cart_snapshot.reference.rom_path.len == 0;
        if (!is_empty_reference and cartridge == null) return error.CartridgeRequired;
        // TODO: Verify cartridge hash matches snapshot hash when cartridge provided
    }

    // Construct EmulationState
    var emu_state = EmulationState{
        .clock = clock,
        .cpu = cpu,
        .ppu = ppu,
        .bus = bus,
        .config = config,
        .frame_complete = flags.frame_complete,
        .odd_frame = flags.odd_frame,
        .rendering_enabled = flags.rendering_enabled,
    };

    // Connect cartridge pointer
    if (cartridge) |cart| {
        emu_state.bus.cartridge = cart;
    }

    // Wire up internal pointers (bus.ppu, ppu.cartridge, etc.)
    emu_state.connectComponents();

    return emu_state;
}

/// Verify snapshot integrity without full load
///
/// Checks magic, version, and checksum
pub fn verify(data: []const u8) !void {
    if (data.len < 72) return error.InvalidSnapshot;

    var fbs = std.io.fixedBufferStream(data);
    const header = try binary.readHeader(fbs.reader());
    try binary.verifyHeader(&header);

    const data_section = data[72..];
    try binary.verifyChecksum(&header, data_section);
}

/// Get snapshot metadata without full load
///
/// Useful for inspecting snapshots before loading
pub fn getMetadata(data: []const u8) !SnapshotMetadata {
    if (data.len < 72) return error.InvalidSnapshot;

    var fbs = std.io.fixedBufferStream(data);
    const header = try binary.readHeader(fbs.reader());
    try binary.verifyHeader(&header);

    return .{
        .version = header.version,
        .timestamp = header.timestamp,
        .emulator_version = header.emulator_version,
        .total_size = header.total_size,
        .state_size = header.state_size,
        .cartridge_size = header.cartridge_size,
        .framebuffer_size = header.framebuffer_size,
        .flags = binary.SnapshotFlags.fromU32(header.flags),
    };
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get serialized size for PpuState
fn getSizeForPpuState() u32 {
    var size: u32 = 0;
    size += 4;   // Registers (ctrl, mask, status, oam_addr)
    size += 3;   // Open bus (value + decay_timer)
    size += 10;  // Internal registers (v, t, x, w, read_buffer)
    size += 10;  // Background state (shift regs + latches)
    size += 256; // OAM
    size += 32;  // Secondary OAM
    size += 2048; // VRAM
    size += 32;  // Palette RAM
    size += 15;  // Metadata (mirroring, nmi_occurred, scanline, dot, frame)
    return size;
}

/// Create cartridge snapshot from loaded cartridge
fn createCartridgeSnapshot(
    allocator: std.mem.Allocator,
    cart: anytype,
    mode: cartridge_snap.CartridgeSnapshotMode,
) !cartridge_snap.CartridgeSnapshot {
    return switch (mode) {
        .reference => blk: {
            // For reference mode, we need ROM path (not available in current cart structure)
            // Use hash of PRG ROM as identifier
            const rom_hash = cartridge_snap.calculateRomHash(cart.prg_rom);

            // Allocate path string (empty for now - would need to track ROM path in cartridge)
            const rom_path = try allocator.dupe(u8, "");
            errdefer allocator.free(rom_path);

            // Get mapper state (empty for Mapper0, will expand for other mappers)
            const mapper_state = try allocator.dupe(u8, &[_]u8{});
            errdefer allocator.free(mapper_state);

            break :blk cartridge_snap.CartridgeSnapshot{
                .reference = .{
                    .rom_path = rom_path,
                    .rom_hash = rom_hash,
                    .mapper_state = mapper_state,
                },
            };
        },
        .embed => blk: {
            // Allocate and copy ROM data
            const prg_rom = try allocator.dupe(u8, cart.prg_rom);
            errdefer allocator.free(prg_rom);

            const chr_data = try allocator.dupe(u8, cart.chr_data);
            errdefer allocator.free(chr_data);

            const mapper_state = try allocator.dupe(u8, &[_]u8{});
            errdefer allocator.free(mapper_state);

            break :blk cartridge_snap.CartridgeSnapshot{
                .embed = .{
                    .header = cart.header,
                    .prg_rom = prg_rom,
                    .chr_data = chr_data,
                    .mirroring = cart.mirroring,
                    .mapper_state = mapper_state,
                },
            };
        },
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Snapshot: create and verify minimal snapshot" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = @import("../bus/State.zig").BusState.init();
    var state = EmulationState.init(&config, bus);
    state.connectComponents();

    // Save snapshot (no cartridge, no framebuffer)
    const snapshot = try saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Verify snapshot integrity
    try verify(snapshot);

    // Get metadata
    const metadata = try getMetadata(snapshot);
    try testing.expectEqual(binary.SNAPSHOT_VERSION, metadata.version);
}

test "Snapshot: round-trip without cartridge" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = @import("../bus/State.zig").BusState.init();
    var state = EmulationState.init(&config, bus);
    state.connectComponents();

    // Modify state to have non-default values
    state.clock.ppu_cycles = 12345;
    state.cpu.a = 0x42;
    state.cpu.pc = 0x8000;
    state.ppu.ctrl = .{ .nmi_enable = true };

    // Save snapshot
    const snapshot = try saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Load snapshot
    const restored = try loadBinary(
        testing.allocator,
        snapshot,
        &config,
        @as(?*Cartridge.NromCart, null),
    );

    // Verify state matches
    try testing.expectEqual(state.clock.ppu_cycles, restored.clock.ppu_cycles);
    try testing.expectEqual(state.cpu.a, restored.cpu.a);
    try testing.expectEqual(state.cpu.pc, restored.cpu.pc);
    try testing.expectEqual(state.ppu.ctrl.nmi_enable, restored.ppu.ctrl.nmi_enable);
}
