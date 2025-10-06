const std = @import("std");
const testing = std.testing;

const EmulationModule = @import("../emulation/State.zig");
const EmulationState = EmulationModule.EmulationState;
const Config = @import("../config/Config.zig");
const Ppu = @import("../ppu/Ppu.zig");
const PpuLogic = Ppu.Logic;
const PpuRuntime = @import("../emulation/Ppu.zig");
const Cartridge = @import("../cartridge/Cartridge.zig");
const CartridgeType = Cartridge.NromCart;
const MirroringType = @import("../cartridge/ines.zig").Mirroring;

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

    pub fn deinit(self: *Harness) void {
        if (self.cart_loaded) {
            if (self.state.cart) |*cart| {
                cart.deinit();
                self.state.cart = null;
            }
        }
        self.config.deinit();
        testing.allocator.destroy(self.config);
    }

    fn cartPtr(self: *Harness) ?*CartridgeType {
        if (self.state.cart) |*cart| {
            return cart;
        }
        return null;
    }

    pub fn setPpuTiming(self: *Harness, scanline: u16, dot: u16) void {
        self.state.ppu_timing.scanline = scanline;
        self.state.ppu_timing.dot = dot;
    }

    pub fn tickPpu(self: *Harness) void {
        _ = PpuRuntime.tick(&self.state.ppu, &self.state.ppu_timing, self.cartPtr(), null);
    }

    pub fn tickPpuCycles(self: *Harness, cycles: usize) void {
        for (0..cycles) |_| self.tickPpu();
    }

    pub fn tickPpuWithFramebuffer(self: *Harness, framebuffer: []u32) void {
        _ = PpuRuntime.tick(&self.state.ppu, &self.state.ppu_timing, self.cartPtr(), framebuffer);
    }

    pub fn ppuReadRegister(self: *Harness, address: u16) u8 {
        return PpuLogic.readRegister(&self.state.ppu, self.cartPtr(), address);
    }

    pub fn ppuWriteRegister(self: *Harness, address: u16, value: u8) void {
        PpuLogic.writeRegister(&self.state.ppu, self.cartPtr(), address, value);
    }

    pub fn ppuReadVram(self: *Harness, address: u16) u8 {
        return PpuLogic.readVram(&self.state.ppu, self.cartPtr(), address);
    }

    pub fn ppuWriteVram(self: *Harness, address: u16, value: u8) void {
        PpuLogic.writeVram(&self.state.ppu, self.cartPtr(), address, value);
    }

    pub fn resetPpu(self: *Harness) void {
        PpuLogic.reset(&self.state.ppu);
        self.state.ppu_timing = .{};
    }

    pub fn loadCartridge(self: *Harness, cart: CartridgeType) void {
        self.state.loadCartridge(cart);
        self.cart_loaded = true;
    }

    pub fn setMirroring(self: *Harness, mode: MirroringType) void {
        self.state.ppu.mirroring = mode;
    }
};
