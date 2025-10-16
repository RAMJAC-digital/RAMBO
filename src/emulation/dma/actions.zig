//! DMA Actions - Clean single-responsibility action architecture
//!
//! Each action represents a single operation that can be performed during a DMA tick.
//! Actions are determined by pure functions, executed with single side effects,
//! and followed by bookkeeping updates.
//!
//! Architecture:
//! 1. Query: determineAction() - Pure function, no mutations
//! 2. Execute: executeAction() - Single side effect only
//! 3. Update: updateBookkeeping() - State mutations after action

const std = @import("std");
const OamDma = @import("../state/peripherals/OamDma.zig").OamDma;
const OamDmaPhase = @import("../state/peripherals/OamDma.zig").OamDmaPhase;
const DmaInteractionLedger = @import("../DmaInteractionLedger.zig").DmaInteractionLedger;

/// Single DMA action (one per tick)
pub const DmaAction = union(enum) {
    /// Do nothing this tick (paused or inactive)
    skip,

    /// Alignment wait cycle (odd CPU cycle start)
    alignment_wait,

    /// Read byte from source RAM into temp_value
    read: ReadInfo,

    /// Write temp_value to OAM
    write,

    /// Write captured byte from ledger (byte duplication bug)
    duplication_write: DuplicationInfo,

    pub const ReadInfo = struct {
        source_page: u8,
        source_offset: u8,
    };

    pub const DuplicationInfo = struct {
        byte_value: u8,
        target_oam_addr: u8,
    };
};

/// Calculate effective cycle (accounting for alignment)
fn calculateEffectiveCycle(dma: *const OamDma) i32 {
    const cycle: i32 = @intCast(dma.current_cycle);
    return if (dma.needs_alignment) cycle - 1 else cycle;
}

/// Determine what action to take this tick (PURE - no mutations)
pub fn determineAction(
    dma: *const OamDma,
    ledger: *const DmaInteractionLedger,
) DmaAction {
    // Handle paused states
    switch (dma.phase) {
        .idle => return .skip,
        .paused_during_read, .paused_during_write => return .skip,
        else => {},
    }

    // Handle duplication (resuming after DMC interrupt)
    if (dma.phase == .resuming_with_duplication) {
        return .{ .duplication_write = .{
            .byte_value = ledger.interrupted_state.byte_value,
            .target_oam_addr = ledger.interrupted_state.oam_addr,
        }};
    }

    const effective_cycle = calculateEffectiveCycle(dma);

    // Alignment wait (cycle -1)
    if (effective_cycle < 0) {
        return .alignment_wait;
    }

    // Completion check (handled in updateBookkeeping)
    // DMA runs for 512 data cycles (0-511), but 513 total with dummy read
    // Skip action at cycle 512 (completion happens after cycle 511)
    if (effective_cycle >= 512) {
        return .skip;
    }

    // Normal operation: alternate read/write based on cycle parity
    if (@rem(effective_cycle, 2) == 0) {
        // Even cycle: READ
        return .{ .read = .{
            .source_page = dma.source_page,
            .source_offset = dma.current_offset,
        }};
    } else {
        // Odd cycle: WRITE
        return .write;
    }
}

/// Execute action (SINGLE side effect only)
pub fn executeAction(state: anytype, action: DmaAction) void {
    switch (action) {
        .skip, .alignment_wait => {
            // No side effects
        },

        .read => |info| {
            // ONLY side effect: read from RAM
            const addr = (@as(u16, info.source_page) << 8) | @as(u16, info.source_offset);
            state.dma.temp_value = state.busRead(addr);
        },

        .write => {
            // ONLY side effect: write to OAM
            state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
        },

        .duplication_write => |info| {
            // ONLY side effect: write captured byte to OAM
            state.ppu.oam[info.target_oam_addr] = info.byte_value;
        },
    }
}

/// Update bookkeeping after action (state mutations)
pub fn updateBookkeeping(
    dma: *OamDma,
    ppu_oam_addr: *u8,
    ledger: *DmaInteractionLedger,
    action: DmaAction,
) void {
    switch (action) {
        .skip => {
            // Skip action still consumes a cycle (for completion check)
            dma.current_cycle += 1;
        },

        .alignment_wait => {
            dma.phase = .aligning;
            dma.current_cycle += 1;
        },

        .read => {
            dma.phase = .reading;
            dma.current_cycle += 1;
        },

        .write => {
            dma.phase = .writing;
            ppu_oam_addr.* +%= 1;
            dma.current_offset +%= 1;
            dma.current_cycle += 1;
        },

        .duplication_write => {
            // Hardware behavior: The interrupted byte is written to current OAM slot
            // Then the SAME byte is RE-READ and written again (byte duplication)
            // This is a "free" operation that doesn't consume a cycle
            ppu_oam_addr.* +%= 1; // OAM address advances (byte written)
            // Do NOT advance offset - we need to RE-READ the same source byte next cycle
            // Do NOT advance cycle - duplication is "free"
            dma.phase = .resuming_normal;
            ledger.duplication_pending = false; // Direct field assignment
        },
    }

    // Check for completion (after updates)
    // 513 total cycles: 1 dummy + 512 data (even start) or 514 (odd start with alignment)
    // Complete AFTER cycle 512 executes (cycles 0-512 inclusive = 513 cycles)
    // BUG #2/#3 FIX: Complete at cycle 513, not 512
    const effective_cycle = calculateEffectiveCycle(dma);
    if (effective_cycle > 512) {
        dma.reset();
        // Clear pause state - direct field assignment
        ledger.oam_pause_cycle = 0;
        ledger.oam_resume_cycle = 0;
    }
}

// Unit tests
const testing = std.testing;

test "actions: determineAction skip when idle" {
    const dma = OamDma{ .phase = .idle };
    const ledger = DmaInteractionLedger{};

    const action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.skip, action);
}

test "actions: determineAction skip when paused" {
    var dma = OamDma{ .active = true, .phase = .paused_during_read };
    const ledger = DmaInteractionLedger{};

    var action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.skip, action);

    dma.phase = .paused_during_write;
    action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.skip, action);
}

test "actions: determineAction alignment_wait on cycle 0 with alignment" {
    const dma = OamDma{
        .active = true,
        .phase = .reading,
        .current_cycle = 0,
        .needs_alignment = true,
    };
    const ledger = DmaInteractionLedger{};

    const action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.alignment_wait, action);
}

test "actions: determineAction read on even effective cycle" {
    const dma = OamDma{
        .active = true,
        .phase = .reading,
        .current_cycle = 0,
        .needs_alignment = false,
        .source_page = 0x03,
        .current_offset = 50,
    };
    const ledger = DmaInteractionLedger{};

    const action = determineAction(&dma, &ledger);
    try testing.expect(action == .read);
    try testing.expectEqual(@as(u8, 0x03), action.read.source_page);
    try testing.expectEqual(@as(u8, 50), action.read.source_offset);
}

test "actions: determineAction write on odd effective cycle" {
    const dma = OamDma{
        .active = true,
        .phase = .writing,
        .current_cycle = 1,
        .needs_alignment = false,
    };
    const ledger = DmaInteractionLedger{};

    const action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.write, action);
}

test "actions: determineAction duplication_write when resuming" {
    const dma = OamDma{
        .active = true,
        .phase = .resuming_with_duplication,
        .current_cycle = 100,
    };
    var ledger = DmaInteractionLedger{};
    ledger.interrupted_state = .{
        .was_reading = true,
        .byte_value = 0xAA,
        .oam_addr = 50,
        .offset = 50,
    };

    const action = determineAction(&dma, &ledger);
    try testing.expect(action == .duplication_write);
    try testing.expectEqual(@as(u8, 0xAA), action.duplication_write.byte_value);
    try testing.expectEqual(@as(u8, 50), action.duplication_write.target_oam_addr);
}

test "actions: determineAction skip on completion" {
    const dma = OamDma{
        .active = true,
        .phase = .writing,
        .current_cycle = 512,
        .needs_alignment = false,
    };
    const ledger = DmaInteractionLedger{};

    const action = determineAction(&dma, &ledger);
    try testing.expectEqual(DmaAction.skip, action);
}

test "actions: updateBookkeeping alignment_wait" {
    var dma = OamDma{
        .active = true,
        .phase = .idle,
        .current_cycle = 0,
    };
    var oam_addr: u8 = 0;
    var ledger = DmaInteractionLedger{};

    updateBookkeeping(&dma, &oam_addr, &ledger, .alignment_wait);

    try testing.expectEqual(OamDmaPhase.aligning, dma.phase);
    try testing.expectEqual(@as(u16, 1), dma.current_cycle);
    try testing.expectEqual(@as(u8, 0), oam_addr);  // Unchanged
}

test "actions: updateBookkeeping read" {
    var dma = OamDma{
        .active = true,
        .phase = .aligning,
        .current_cycle = 1,
        .current_offset = 0,
    };
    var oam_addr: u8 = 0;
    var ledger = DmaInteractionLedger{};

    const action = DmaAction{ .read = .{ .source_page = 0x03, .source_offset = 0 }};
    updateBookkeeping(&dma, &oam_addr, &ledger, action);

    try testing.expectEqual(OamDmaPhase.reading, dma.phase);
    try testing.expectEqual(@as(u16, 2), dma.current_cycle);
    try testing.expectEqual(@as(u8, 0), dma.current_offset);  // Unchanged
    try testing.expectEqual(@as(u8, 0), oam_addr);  // Unchanged
}

test "actions: updateBookkeeping write" {
    var dma = OamDma{
        .active = true,
        .phase = .reading,
        .current_cycle = 2,
        .current_offset = 0,
    };
    var oam_addr: u8 = 0;
    var ledger = DmaInteractionLedger{};

    updateBookkeeping(&dma, &oam_addr, &ledger, .write);

    try testing.expectEqual(OamDmaPhase.writing, dma.phase);
    try testing.expectEqual(@as(u16, 3), dma.current_cycle);
    try testing.expectEqual(@as(u8, 1), dma.current_offset);  // Incremented
    try testing.expectEqual(@as(u8, 1), oam_addr);  // Incremented
}

test "actions: updateBookkeeping duplication_write" {
    var dma = OamDma{
        .active = true,
        .phase = .resuming_with_duplication,
        .current_cycle = 100,
        .current_offset = 50,
    };
    var oam_addr: u8 = 50;
    var ledger = DmaInteractionLedger{};
    ledger.duplication_pending = true;

    const action = DmaAction{ .duplication_write = .{
        .byte_value = 0xAA,
        .target_oam_addr = 50,
    }};
    updateBookkeeping(&dma, &oam_addr, &ledger, action);

    try testing.expectEqual(OamDmaPhase.resuming_normal, dma.phase);
    try testing.expectEqual(@as(u16, 100), dma.current_cycle);  // Unchanged ("free" operation)
    try testing.expectEqual(@as(u8, 50), dma.current_offset);  // NOT advanced - byte will be re-read (hardware duplication)
    try testing.expectEqual(@as(u8, 51), oam_addr);  // Incremented (byte written)
    try testing.expect(!ledger.duplication_pending);  // Cleared
}

test "actions: updateBookkeeping completion" {
    var dma = OamDma{
        .active = true,
        .phase = .writing,
        .current_cycle = 512,
        .needs_alignment = false,
    };
    var oam_addr: u8 = 0;
    var ledger = DmaInteractionLedger{};
    ledger.oam_pause_cycle = 100;

    updateBookkeeping(&dma, &oam_addr, &ledger, .skip);

    try testing.expect(!dma.active);  // Reset
    try testing.expectEqual(OamDmaPhase.idle, dma.phase);  // Reset
    try testing.expectEqual(@as(u64, 0), ledger.oam_pause_cycle);  // Cleared
}
