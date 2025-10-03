//! Emulation State Machine - RT Loop Design
//!
//! This module implements the hybrid architecture's RT emulation loop:
//! - Pure state machine: state_n+1 = tick(state_n)
//! - PPU cycle granularity (finest timing unit)
//! - Deterministic, reproducible execution
//! - Zero coupling between components (communication via Bus)
//!
//! References:
//! - docs/06-implementation-notes/design-decisions/final-hybrid-architecture.md

const std = @import("std");
const Config = @import("../config/Config.zig");
const CpuModule = @import("../cpu/Cpu.zig");
const CpuState = CpuModule.State.State;
const CpuLogic = CpuModule.Logic;
const BusType = @import("../bus/Bus.zig").Bus;
const Ppu = @import("../ppu/Ppu.zig").Ppu;

/// Master timing clock - tracks total PPU cycles
/// PPU cycles are the finest granularity in NES hardware
/// All other timing is derived from PPU cycles
pub const MasterClock = struct {
    /// Total PPU cycles elapsed since power-on
    /// NTSC: 5.37 MHz (3× CPU frequency of 1.79 MHz)
    /// PAL: 5.00 MHz (3× CPU frequency of 1.66 MHz)
    ppu_cycles: u64 = 0,

    /// Derived CPU cycles (PPU ÷ 3)
    /// CPU runs at 1/3 PPU speed in hardware
    pub fn cpuCycles(self: MasterClock) u64 {
        return self.ppu_cycles / 3;
    }

    /// Current scanline (0-261 NTSC, 0-311 PAL)
    /// Calculated from PPU cycles and configuration
    pub fn scanline(self: MasterClock, config: Config.PpuConfig) u16 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        const cycle_in_frame = self.ppu_cycles % frame_cycles;
        return @intCast(cycle_in_frame / cycles_per_scanline);
    }

    /// Current dot/cycle within scanline (0-340)
    /// Each scanline is 341 PPU cycles for both NTSC and PAL
    pub fn dot(self: MasterClock, config: Config.PpuConfig) u16 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        return @intCast(self.ppu_cycles % cycles_per_scanline);
    }

    /// Current frame number
    /// Increments at the start of VBlank (scanline 241, dot 1 for NTSC)
    pub fn frame(self: MasterClock, config: Config.PpuConfig) u64 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        return self.ppu_cycles / frame_cycles;
    }

    /// CPU cycles within current frame
    pub fn cpuCyclesInFrame(self: MasterClock, config: Config.PpuConfig) u32 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        const ppu_cycles_in_frame = self.ppu_cycles % frame_cycles;
        return @intCast(ppu_cycles_in_frame / 3);
    }
};

/// Complete emulation state (pure data, no hidden state)
/// This is the core of the RT emulation loop
pub const EmulationState = struct {
    /// Master clock (PPU cycle granularity)
    clock: MasterClock = .{},

    /// Component states
    cpu: CpuState,
    ppu: Ppu,
    bus: BusType,

    /// Hardware configuration (immutable during emulation)
    config: *const Config.Config,

    /// Frame completion flag (VBlank start)
    frame_complete: bool = false,

    /// Odd/even frame tracking (for frame skip behavior)
    /// Odd frames skip dot 0 of scanline 0 when rendering enabled
    odd_frame: bool = false,

    /// Rendering enabled flag (PPU $2001 bits 3-4)
    /// Used to determine if odd frame skip should occur
    rendering_enabled: bool = false,

    /// Initialize emulation state from configuration
    /// Requires the Bus to be already initialized with cartridge
    pub fn init(config: *const Config.Config, bus: BusType) EmulationState {
        const cpu = CpuLogic.init();
        const ppu = Ppu.init();

        // Note: PPU pointer in bus will be connected in connectComponents()
        return .{
            .cpu = cpu,
            .ppu = ppu,
            .bus = bus,
            .config = config,
        };
    }

    /// Connect component pointers (must be called after init)
    /// This connects the PPU to the bus and cartridge CHR provider
    pub fn connectComponents(self: *EmulationState) void {
        // Connect PPU to bus (non-owning pointer)
        self.bus.ppu = &self.ppu;

        // Connect CHR provider and mirroring from cartridge to PPU
        if (self.bus.cartridge) |cart| {
            self.ppu.setChrProvider(cart.chrProvider());
            self.ppu.setMirroring(cart.mirroring);
        }
    }

    /// Reset emulation to power-on state
    /// Loads PC from RESET vector ($FFFC-$FFFD)
    pub fn reset(self: *EmulationState) void {
        self.clock.ppu_cycles = 0;
        self.frame_complete = false;
        self.odd_frame = false;
        self.rendering_enabled = false;

        // Reconnect components after reset
        self.connectComponents();

        CpuLogic.reset(&self.cpu, &self.bus);
        self.ppu.reset();
    }

    /// RT emulation loop - advances state by exactly 1 PPU cycle
    /// This is the core tick function for cycle-accurate emulation
    ///
    /// Timing relationships:
    /// - PPU: Every PPU cycle (1x)
    /// - CPU: Every 3 PPU cycles (1/3)
    /// - APU: Every 3 PPU cycles (same as CPU)
    ///
    /// Execution order matters for same-cycle interactions:
    /// 1. PPU first (may trigger NMI)
    /// 2. CPU second (may read PPU registers)
    /// 3. APU third (synchronized with CPU)
    ///
    /// Hardware quirks implemented:
    /// - Odd frame skip: Dot 0 of scanline 0 skipped when rendering enabled on odd frames
    /// - VBlank timing: Sets at scanline 241, dot 1
    /// - Pre-render scanline: Clears VBlank at scanline -1/261, dot 1
    pub fn tick(self: *EmulationState) void {
        const current_scanline = self.clock.scanline(self.config.ppu);
        const current_dot = self.clock.dot(self.config.ppu);

        // Hardware quirk: Odd frame skip
        // On odd frames with rendering enabled, skip dot 0 of scanline 0 (pre-render)
        // This shortens odd frames by 1 PPU cycle (341→340 dots on scanline 261)
        if (self.odd_frame and self.rendering_enabled and
            current_scanline == 261 and current_dot == 340)
        {
            // Skip dot 0 of next scanline (scanline 0)
            // Advance clock by 2 instead of 1 to skip the dot
            self.clock.ppu_cycles += 2;
            self.odd_frame = false; // Next frame is even
            return; // Skip normal tick processing
        }

        // Advance master clock
        self.clock.ppu_cycles += 1;

        // Determine which components need to tick this PPU cycle
        const cpu_tick = (self.clock.ppu_cycles % 3) == 0;
        const ppu_tick = true; // PPU ticks every cycle
        const apu_tick = cpu_tick; // APU synchronized with CPU

        // Tick components in hardware order
        if (ppu_tick) {
            self.tickPpu();
        }

        if (cpu_tick) {
            self.tickCpu();
        }

        if (apu_tick) {
            self.tickApu();
        }

        // Frame timing events
        const new_scanline = self.clock.scanline(self.config.ppu);
        const new_dot = self.clock.dot(self.config.ppu);

        // VBlank start: Scanline 241, dot 1
        if (new_scanline == 241 and new_dot == 1) {
            self.frame_complete = true;
            // VBlank/NMI timing handled by PPU.tick() - already implemented
        }

        // Pre-render scanline: Scanline -1/261, dot 1
        // Clears VBlank and sprite 0 hit flags
        if (new_scanline == 261 and new_dot == 1) {
            // VBlank/sprite flag clearing handled by PPU.tick() - already implemented
        }

        // Frame boundary: End of scanline 261 (start of scanline 0)
        // Toggle odd/even frame
        if (new_scanline == 0 and current_scanline == 261) {
            self.odd_frame = !self.odd_frame;
        }
    }

    /// Tick CPU state machine (called every 3 PPU cycles)
    fn tickCpu(self: *EmulationState) void {
        // Call existing CPU tick function
        // CPU maintains its own internal state machine
        _ = CpuLogic.tick(&self.cpu, &self.bus);
    }

    /// Tick PPU state machine (called every PPU cycle)
    fn tickPpu(self: *EmulationState) void {
        // Tick PPU (manages its own scanline/dot tracking)
        // TODO: Pass framebuffer when implementing display output
        self.ppu.tick(null);

        // Update rendering_enabled flag for odd frame skip logic
        self.rendering_enabled = self.ppu.mask.renderingEnabled();
    }

    /// Tick APU state machine (called every 3 PPU cycles, same as CPU)
    /// Future: APU implementation
    fn tickApu(_: *EmulationState) void {
        // APU not yet implemented - see docs/ROADMAP.md for priority
    }

    /// Emulate a complete frame (convenience wrapper)
    /// Advances emulation until frame_complete flag is set
    /// Returns number of PPU cycles elapsed
    pub fn emulateFrame(self: *EmulationState) u64 {
        const start_cycle = self.clock.ppu_cycles;
        self.frame_complete = false;

        // Advance until VBlank (scanline 241, dot 1)
        // NTSC: 89,342 PPU cycles per frame
        // PAL: 106,392 PPU cycles per frame
        while (!self.frame_complete) {
            self.tick();

            // Safety: Prevent infinite loop if something goes wrong
            // Maximum frame cycles + 1000 cycle buffer
            const max_cycles: u64 = 110_000;
            if (self.clock.ppu_cycles - start_cycle > max_cycles) {
                std.debug.print("WARNING: Frame emulation exceeded {d} PPU cycles\n", .{max_cycles});
                break;
            }
        }

        return self.clock.ppu_cycles - start_cycle;
    }

    /// Emulate N CPU cycles (convenience wrapper)
    /// Returns actual PPU cycles elapsed (N × 3)
    pub fn emulateCpuCycles(self: *EmulationState, cpu_cycles: u64) u64 {
        const start_cycle = self.clock.ppu_cycles;
        const target_cpu_cycle = self.clock.cpuCycles() + cpu_cycles;

        while (self.clock.cpuCycles() < target_cpu_cycle) {
            self.tick();
        }

        return self.clock.ppu_cycles - start_cycle;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "MasterClock: PPU to CPU cycle conversion" {
    var clock = MasterClock{};

    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.cpuCycles());

    clock.ppu_cycles = 3;
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    clock.ppu_cycles = 6;
    try testing.expectEqual(@as(u64, 2), clock.cpuCycles());

    clock.ppu_cycles = 100;
    try testing.expectEqual(@as(u64, 33), clock.cpuCycles());
}

test "MasterClock: scanline calculation NTSC" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Scanline 0, dot 0
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u16, 0), clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 0), clock.dot(config.ppu));

    // Scanline 0, dot 100
    clock.ppu_cycles = 100;
    try testing.expectEqual(@as(u16, 0), clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 100), clock.dot(config.ppu));

    // Scanline 1, dot 0 (after 341 cycles)
    clock.ppu_cycles = 341;
    try testing.expectEqual(@as(u16, 1), clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 0), clock.dot(config.ppu));

    // Scanline 10, dot 50
    clock.ppu_cycles = (10 * 341) + 50;
    try testing.expectEqual(@as(u16, 10), clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 50), clock.dot(config.ppu));

    // VBlank start: Scanline 241, dot 1
    clock.ppu_cycles = (241 * 341) + 1;
    try testing.expectEqual(@as(u16, 241), clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 1), clock.dot(config.ppu));
}

test "MasterClock: frame calculation NTSC" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Frame 0
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.frame(config.ppu));

    // Still frame 0 (one cycle before frame boundary)
    clock.ppu_cycles = 89_341;
    try testing.expectEqual(@as(u64, 0), clock.frame(config.ppu));

    // Frame 1 (262 scanlines × 341 cycles = 89,342 cycles)
    clock.ppu_cycles = 89_342;
    try testing.expectEqual(@as(u64, 1), clock.frame(config.ppu));

    // Frame 10
    clock.ppu_cycles = 89_342 * 10;
    try testing.expectEqual(@as(u64, 10), clock.frame(config.ppu));
}

test "MasterClock: CPU cycles in frame" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Start of frame
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u32, 0), clock.cpuCyclesInFrame(config.ppu));

    // 300 PPU cycles = 100 CPU cycles
    clock.ppu_cycles = 300;
    try testing.expectEqual(@as(u32, 100), clock.cpuCyclesInFrame(config.ppu));

    // Just before frame boundary (89,342 PPU cycles = 29,780 CPU cycles)
    clock.ppu_cycles = 89_341;
    try testing.expectEqual(@as(u32, 29_780), clock.cpuCyclesInFrame(config.ppu));

    // Start of next frame (wraps back to 0)
    clock.ppu_cycles = 89_342;
    try testing.expectEqual(@as(u32, 0), clock.cpuCyclesInFrame(config.ppu));
}

test "EmulationState: initialization" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();

    try testing.expectEqual(@as(u64, 0), state.clock.ppu_cycles);
    try testing.expect(!state.frame_complete);
}

test "EmulationState: tick advances PPU clock" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Initial state
    try testing.expectEqual(@as(u64, 0), state.clock.ppu_cycles);

    // Tick once
    state.tick();
    try testing.expectEqual(@as(u64, 1), state.clock.ppu_cycles);

    // Tick 10 times
    for (0..10) |_| {
        state.tick();
    }
    try testing.expectEqual(@as(u64, 11), state.clock.ppu_cycles);
}

test "EmulationState: CPU ticks every 3 PPU cycles" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    const initial_cpu_cycles = state.cpu.cycle_count;

    // Tick 2 PPU cycles (CPU should NOT tick)
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 2), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles, state.cpu.cycle_count);

    // Tick 3rd PPU cycle (CPU SHOULD tick)
    state.tick();
    try testing.expectEqual(@as(u64, 3), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.cpu.cycle_count);

    // Tick 3 more PPU cycles (CPU should tick once more)
    state.tick();
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 6), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 2, state.cpu.cycle_count);
}

test "EmulationState: emulateCpuCycles advances correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Emulate 10 CPU cycles (should be 30 PPU cycles)
    const ppu_cycles = state.emulateCpuCycles(10);
    try testing.expectEqual(@as(u64, 30), ppu_cycles);
    try testing.expectEqual(@as(u64, 30), state.clock.ppu_cycles);
    try testing.expectEqual(@as(u64, 10), state.clock.cpuCycles());
}

test "EmulationState: VBlank timing at scanline 241, dot 1" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Advance to scanline 241, dot 0 (just before VBlank)
    const target_cycle = (241 * 341) + 0;
    state.clock.ppu_cycles = target_cycle;
    try testing.expect(!state.frame_complete);

    // Tick once to reach scanline 241, dot 1 (VBlank start)
    state.tick();
    try testing.expectEqual(@as(u16, 241), state.clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 1), state.clock.dot(config.ppu));
    try testing.expect(state.frame_complete); // VBlank flag set
}

test "EmulationState: odd frame skip when rendering enabled" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Set up odd frame with rendering enabled
    state.odd_frame = true;
    state.rendering_enabled = true;

    // Advance to scanline 261, dot 340 (last dot of pre-render scanline on odd frame)
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Current position: scanline 261, dot 340
    try testing.expectEqual(@as(u16, 261), state.clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 340), state.clock.dot(config.ppu));

    // Tick should skip dot 0 of scanline 0, advancing by 2 PPU cycles instead of 1
    state.tick();

    // After tick: Should be at scanline 0, dot 1 (skipped dot 0)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 1), state.clock.dot(config.ppu));

    // Odd frame should be cleared (next frame is even)
    try testing.expect(!state.odd_frame);
}

test "EmulationState: even frame does not skip dot" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Set up even frame with rendering enabled
    state.odd_frame = false; // Even frame
    state.rendering_enabled = true;

    // Advance to scanline 261, dot 340
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip, advancing by 1 PPU cycle normally
    state.tick();

    // After tick: Should be at scanline 0, dot 0 (normal progression)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 0), state.clock.dot(config.ppu));
}

test "EmulationState: odd frame without rendering does not skip" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Set up odd frame WITHOUT rendering enabled
    state.odd_frame = true;
    state.rendering_enabled = false; // Rendering disabled

    // Advance to scanline 261, dot 340
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip (rendering disabled), advancing by 1 PPU cycle
    state.tick();

    // After tick: Should be at scanline 0, dot 0 (normal progression)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline(config.ppu));
    try testing.expectEqual(@as(u16, 0), state.clock.dot(config.ppu));
}

test "EmulationState: frame toggle at scanline boundary" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    const bus = BusType.init();

    var state = EmulationState.init(&config, bus);
    state.connectComponents();
    state.reset();

    // Start with even frame (odd_frame = false)
    try testing.expect(!state.odd_frame);

    // Advance to end of scanline 261 (last scanline of frame)
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Tick to cross into scanline 0 of next frame
    state.tick();

    // Should now be odd frame
    try testing.expect(state.odd_frame);

    // Tick again and frame should toggle back to even
    // Advance to next frame boundary
    state.clock.ppu_cycles = (262 * 341) - 1; // Just before next frame
    state.tick();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);
}
