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

    pub fn setPpuTiming(self: *Harness, scanline: u16, dot: u16) void {
        self.state.clock.ppu_cycles = (@as(u64, scanline) * 341) + dot;
    }

    pub fn tickPpu(self: *Harness) void {
        const scanline = self.state.clock.scanline();
        const dot = self.state.clock.dot();
        _ = PpuLogic.tick(&self.state.ppu, scanline, dot, self.cartPtr(), null);
        self.state.clock.advance(1);
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

    /// Seek the emulator to a specific PPU scanline and dot.
    pub fn seekTo(self: *Harness, target_scanline: u16, target_dot: u16) void {
        while (self.state.clock.scanline() != target_scanline or self.state.clock.dot() != target_dot) {
            self.state.tick();
        }
    }

    pub fn tickPpuWithFramebuffer(self: *Harness, framebuffer: []u32) void {
        const scanline = self.state.clock.scanline();
        const dot = self.state.clock.dot();
        _ = PpuLogic.tick(&self.state.ppu, scanline, dot, self.cartPtr(), framebuffer);
        self.state.clock.advance(1);
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
    pub fn seekToScanlineDot(self: *Harness, target_scanline: u16, target_dot: u16) void {
        const max_cycles: usize = 100_000; // Safety limit
        var cycles: usize = 0;

        while (cycles < max_cycles) : (cycles += 1) {
            const current_sl = self.state.clock.scanline();
            const current_dot = self.state.clock.dot();

            if (current_sl == target_scanline and current_dot == target_dot) {
                return; // Exact position reached
            }

            self.state.tick();
        }

        @panic("seekToScanlineDot: Failed to reach target position");
    }

    /// Helper: Get current scanline
    pub fn getScanline(self: *const Harness) u16 {
        return self.state.clock.scanline();
    }

    /// Helper: Get current dot
    pub fn getDot(self: *const Harness) u16 {
        return self.state.clock.dot();
    }
};
