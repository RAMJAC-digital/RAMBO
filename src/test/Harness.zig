const std = @import("std");
const testing = std.testing;

const EmulationModule = @import("../emulation/State.zig");
const EmulationState = EmulationModule.EmulationState;
const Config = @import("../config/Config.zig");
const Ppu = @import("../ppu/Ppu.zig");
const PpuLogic = Ppu.Logic;
const Cartridge = @import("../cartridge/Cartridge.zig");
const RegistryModule = @import("../cartridge/mappers/registry.zig");
const AnyCartridge = RegistryModule.AnyCartridge;
const NromCart = Cartridge.NromCart;
const MirroringType = Cartridge.Mirroring;

pub const Harness = struct {
    config: *Config.Config,
    state: EmulationState,
    cart_loaded: bool = false,

    pub fn init() !Harness {
        const cfg = try testing.allocator.create(Config.Config);
        cfg.* = Config.Config.init(testing.allocator);

        var emu = EmulationState.init(cfg);
        emu.reset();

        return .{
            .config = cfg,
            .state = emu,
        };
    }

    pub fn initWithRom(rom_data: []const u8) !Harness {
        var harness = try Harness.init();
        errdefer harness.deinit();

        const cart = try NromCart.loadFromData(testing.allocator, rom_data);
        harness.loadNromCartridge(cart);
        // Reset to load PC from cartridge reset vector
        harness.state.reset();

        return harness;
    }

    pub fn deinit(self: *Harness) void {
        // Always deinit emulation state (cleans up cartridge/resources if present)
        self.state.deinit();
        self.config.deinit();
        testing.allocator.destroy(self.config);
    }

    fn cartPtr(self: *Harness) ?*AnyCartridge {
        if (self.state.cart) |*cart| {
            return cart;
        }
        return null;
    }

    pub fn setPpuTiming(self: *Harness, scanline: i16, dot: u16) void {
        // Directly set PPU's clock state (PPU owns its own timing now)
        self.state.ppu.scanline = scanline;
        self.state.ppu.cycle = dot;
    }

    /// Set PPU position directly without advancing emulation
    /// This positions the PPU at a specific scanline/dot WITHOUT triggering
    /// any side effects (VBlank flag changes, NMI signals, etc.)
    ///
    /// Use this for testing behavior BEFORE events at a specific position fire.
    /// Use seekTo() for advancing through time normally with all side effects.
    ///
    /// Example:
    ///   setPpuPosition(241, 1) - Position AT VBlank set point, flag NOT set yet
    ///   seekTo(241, 1) - Advance TO VBlank set point, flag IS set (tick completed)
    pub fn setPpuPosition(self: *Harness, scanline: i16, dot: u16) void {
        self.state.ppu.scanline = scanline;
        self.state.ppu.cycle = dot;
    }

    pub fn tickPpu(self: *Harness) void {
        const scanline = self.state.ppu.scanline;
        const dot = self.state.ppu.cycle;
        const rendering_enabled = self.state.ppu.mask.renderingEnabled();
        _ = PpuLogic.tick(&self.state.ppu, scanline, dot, self.cartPtr(), null);
        PpuLogic.advanceClock(&self.state.ppu, rendering_enabled);
        self.state.clock.advance();
    }

    pub fn tickPpuCycles(self: *Harness, cycles: usize) void {
        for (0..cycles) |_| self.tickPpu();
    }

    pub fn tick(self: *Harness, count: u64) void {
        for (0..count) |_| {
            self.state.tick();
        }
    }

    pub fn runCpuCycles(self: *Harness, count: u64) void {
        _ = self.state.emulateCpuCycles(count);
    }

    /// Load a slice of bytes into RAM at a specific address.
    pub fn loadRam(self: *Harness, data: []const u8, address: u16) void {
        const base: usize = @intCast(address);
        for (data, 0..) |byte, i| {
            const dest = (base + i) & 0x07FF;
            self.state.bus.ram[dest] = byte;
        }
    }

    /// Seek the emulator to a specific PPU scanline and dot by advancing through time.
    /// This advances emulation normally, triggering all side effects along the way.
    ///
    /// After this function returns, the PPU is positioned AT the target scanline/dot,
    /// and all events at that position HAVE ALREADY FIRED (VBlank flag set, NMI triggered, etc.)
    ///
    /// IMPORTANT: This does NOT reset the VBlank ledger. If you need a clean ledger
    /// state, call `self.state.vblank_ledger.reset()` before calling this function.
    ///
    /// For positioning WITHOUT side effects, use setPpuPosition() instead.
    pub fn seekTo(self: *Harness, target_scanline: i16, target_dot: u16) void {
        while (self.state.ppu.scanline != target_scanline or self.state.ppu.cycle != target_dot) {
            self.state.tick();
        }
    }

    /// Seek to a specific scanline/dot AND ensure we're at a CPU tick boundary.
    /// This is useful for CPU execution tests that need precise PPU timing.
    /// May overshoot the target by up to 2 PPU cycles to land on a CPU boundary.
    pub fn seekToCpuBoundary(self: *Harness, target_scanline: i16, target_dot: u16) void {
        self.seekTo(target_scanline, target_dot);

        // Ensure we're at a CPU tick boundary (may overshoot by 1-2 cycles)
        while (self.state.clock.master_cycles % 3 != 0) {
            self.state.tick();
        }
    }

    pub fn tickPpuWithFramebuffer(self: *Harness, framebuffer: []u32) void {
        const scanline = self.state.ppu.scanline;
        const dot = self.state.ppu.cycle;
        const rendering_enabled = self.state.ppu.mask.renderingEnabled();
        _ = PpuLogic.tick(&self.state.ppu, scanline, dot, self.cartPtr(), framebuffer);
        PpuLogic.advanceClock(&self.state.ppu, rendering_enabled);
        self.state.clock.advance();
    }

    pub fn ppuReadRegister(self: *Harness, address: u16) u8 {
        // Route through EmulationState bus logic so side effects (e.g. VBlank ledger) remain consistent
        return self.state.busRead(address);
    }

    pub fn ppuWriteRegister(self: *Harness, address: u16, value: u8) void {
        // Use the orchestrated bus path to keep open-bus and side effects accurate
        self.state.busWrite(address, value);
    }

    pub fn ppuReadVram(self: *Harness, address: u16) u8 {
        return PpuLogic.readVram(&self.state.ppu, self.cartPtr(), address);
    }

    pub fn ppuWriteVram(self: *Harness, address: u16, value: u8) void {
        PpuLogic.writeVram(&self.state.ppu, self.cartPtr(), address, value);
    }

    pub fn resetPpu(self: *Harness) void {
        PpuLogic.reset(&self.state.ppu);
        self.state.clock.reset();
    }

    pub fn loadCartridge(self: *Harness, cart: AnyCartridge) void {
        self.state.loadCartridge(cart);
        self.cart_loaded = true;
    }

    /// Helper: Load NROM cartridge (wraps in AnyCartridge for convenience)
    pub fn loadNromCartridge(self: *Harness, cart: NromCart) void {
        const any_cart = AnyCartridge{ .nrom = cart };
        self.loadCartridge(any_cart);
    }

    pub fn setMirroring(self: *Harness, mode: MirroringType) void {
        self.state.ppu.mirroring = mode;
    }

    /// Helper: Seek emulation to exact scanline.dot position
    /// Used for precise PPU timing tests (e.g., VBlank NMI timing)
    pub fn seekToScanlineDot(self: *Harness, target_scanline: i16, target_dot: u16) void {
        const max_cycles: usize = 100_000; // Safety limit
        var cycles: usize = 0;

        while (cycles < max_cycles) : (cycles += 1) {
            const current_sl = self.state.ppu.scanline;
            const current_dot = self.state.ppu.cycle;

            if (current_sl == target_scanline and current_dot == target_dot) {
                return; // Exact position reached
            }

            self.state.tick();
        }

        @panic("seekToScanlineDot: Failed to reach target position");
    }

    /// Advance emulation to a specific frame (efficient frame skipping)
    /// Advances until ppu.frame_count >= target_frame
    /// Preserves all side effects (VBlank ledger, etc.)
    pub fn advanceToFrame(self: *Harness, target_frame: u64) void {
        while (self.state.ppu.frame_count < target_frame) {
            self.state.tick();
        }
    }

    /// Advance emulation to a specific scanline within current or next frame
    /// Advances until ppu.scanline == target_scanline
    /// Preserves all side effects (VBlank ledger, etc.)
    pub fn advanceToScanline(self: *Harness, target_scanline: i16) void {
        const starting_frame = self.state.ppu.frame_count;
        const max_frames: u64 = 2; // Safety: don't advance more than 2 frames

        while (self.state.ppu.scanline != target_scanline) {
            if (self.state.ppu.frame_count > starting_frame + max_frames) {
                @panic("advanceToScanline: Target scanline not reached within 2 frames");
            }
            self.state.tick();
        }
    }

    /// Advance emulation by exact cycle count
    /// count: number of master clock cycles to advance
    /// Preserves all side effects (VBlank ledger, etc.)
    pub fn advanceCycles(self: *Harness, count: u64) void {
        for (0..count) |_| {
            self.state.tick();
        }
    }

    /// Helper: Get current scanline
    pub fn getScanline(self: *const Harness) u16 {
        return @intCast(self.state.ppu.scanline);
    }

    /// Helper: Get current dot
    pub fn getDot(self: *const Harness) u16 {
        return self.state.ppu.cycle;
    }

    /// Helper: Setup CPU to execute from a specific address
    /// This ensures the CPU is ready to execute the next instruction
    /// IMPORTANT: Should only be called at a CPU tick boundary (ppu_cycles % 3 == 0)
    /// Use this instead of manually setting cpu.pc/cpu.state/cpu.instruction_cycle
    pub fn setupCpuExecution(self: *Harness, start_pc: u16) void {
        // Verify we're at a CPU tick boundary
        if (self.state.clock.master_cycles % 3 != 0) {
            @panic("setupCpuExecution: Must be called at CPU tick boundary (master_cycles % 3 == 0)");
        }

        // Reset CPU to fetch_opcode state at the specified address
        self.state.cpu.pc = start_pc;
        self.state.cpu.state = .fetch_opcode;
        self.state.cpu.instruction_cycle = 0;
        self.state.cpu.halted = false;

        // Clear any pending interrupts to ensure clean execution
        self.state.cpu.pending_interrupt = .none;

        // Ensure DMA is not active
        self.state.dma.active = false;
        self.state.dmc_dma.rdy_low = false;
    }

    /// Helper: Tick by CPU cycles (not PPU cycles)
    /// Each CPU cycle = 3 PPU cycles
    pub fn tickCpu(self: *Harness, cpu_cycles: u64) void {
        self.tick(cpu_cycles * 3);
    }
};
