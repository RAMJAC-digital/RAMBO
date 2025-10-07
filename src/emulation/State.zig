//! Emulation State Machine - RT Loop Design
//!
//! This module implements the hybrid architecture's RT emulation loop:
//! - Pure state machine: state_n+1 = tick(state_n)
//! - PPU cycle granularity (finest timing unit)
//! - Deterministic, reproducible execution
//! - Direct data ownership (no pointer wiring)
//!
//! References:
//! - docs/implementation/design-decisions/final-hybrid-architecture.md

const std = @import("std");
const Config = @import("../config/Config.zig");
const CpuModule = @import("../cpu/Cpu.zig");
const CpuState = CpuModule.State.CpuState;
const CpuLogic = CpuModule.Logic;
const PpuModule = @import("../ppu/Ppu.zig");
const PpuState = PpuModule.State.PpuState;
const PpuLogic = PpuModule.Logic;
const PpuRuntime = @import("Ppu.zig");
const PpuTiming = PpuRuntime.Timing;
const ApuModule = @import("../apu/Apu.zig");
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;
const CartridgeModule = @import("../cartridge/Cartridge.zig");
const RegistryModule = @import("../cartridge/mappers/registry.zig");
const AnyCartridge = RegistryModule.AnyCartridge;

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
    pub fn scanline(self: MasterClock, config: Config.PpuModel) u16 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        const cycle_in_frame = self.ppu_cycles % frame_cycles;
        return @intCast(cycle_in_frame / cycles_per_scanline);
    }

    /// Current dot/cycle within scanline (0-340)
    /// Each scanline is 341 PPU cycles for both NTSC and PAL
    pub fn dot(self: MasterClock, config: Config.PpuModel) u16 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        return @intCast(self.ppu_cycles % cycles_per_scanline);
    }

    /// Current frame number
    /// Increments at the start of VBlank (scanline 241, dot 1 for NTSC)
    pub fn frame(self: MasterClock, config: Config.PpuModel) u64 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        return self.ppu_cycles / frame_cycles;
    }

    /// CPU cycles within current frame
    pub fn cpuCyclesInFrame(self: MasterClock, config: Config.PpuModel) u32 {
        const cycles_per_scanline: u64 = config.cyclesPerScanline();
        const scanlines_per_frame: u64 = config.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        const ppu_cycles_in_frame = self.ppu_cycles % frame_cycles;
        return @intCast(ppu_cycles_in_frame / 3);
    }
};

/// Memory bus state owned by the emulator runtime
/// Stores all data required to service CPU/PPU bus accesses.
pub const BusState = struct {
    /// Internal RAM: 2KB ($0000-$07FF), mirrored through $0000-$1FFF
    ram: [2048]u8 = std.mem.zeroes([2048]u8),

    /// Last value observed on the CPU data bus (open bus behaviour)
    open_bus: u8 = 0,

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,
};

/// OAM DMA State Machine
/// Cycle-accurate DMA transfer from CPU RAM to PPU OAM
/// Follows microstep pattern for hardware accuracy
pub const DmaState = struct {
    /// DMA active flag
    active: bool = false,

    /// Source page number (written to $4014)
    /// DMA copies from ($source_page << 8) to ($source_page << 8) + 255
    source_page: u8 = 0,

    /// Current byte offset within page (0-255)
    current_offset: u8 = 0,

    /// Cycle counter within DMA transfer
    /// Used for read/write cycle alternation
    current_cycle: u16 = 0,

    /// Alignment wait needed (odd CPU cycle start)
    /// True if DMA triggered on odd cycle (adds 1 extra wait cycle)
    needs_alignment: bool = false,

    /// Temporary value for read/write pair
    /// Cycle N (even): Read into temp_value
    /// Cycle N+1 (odd): Write temp_value to OAM
    temp_value: u8 = 0,

    /// Trigger DMA transfer
    /// Called when $4014 is written
    pub fn trigger(self: *DmaState, page: u8, on_odd_cycle: bool) void {
        self.active = true;
        self.source_page = page;
        self.current_offset = 0;
        self.current_cycle = 0;
        self.needs_alignment = on_odd_cycle;
        self.temp_value = 0;
    }

    /// Reset DMA state
    pub fn reset(self: *DmaState) void {
        self.* = .{};
    }
};

/// NES Controller State
/// Implements cycle-accurate 4021 8-bit shift register behavior
/// Button order: A, B, Select, Start, Up, Down, Left, Right
pub const ControllerState = struct {
    /// Controller 1 shift register
    /// Bits shift out LSB-first on each read
    shift1: u8 = 0,

    /// Controller 2 shift register
    shift2: u8 = 0,

    /// Strobe state (latched buttons or shifting mode)
    /// True = reload shift registers on each read (strobe high)
    /// False = shift out bits on each read (strobe low)
    strobe: bool = false,

    /// Button data for controller 1
    /// Reloaded into shift1 when strobe goes high
    buttons1: u8 = 0,

    /// Button data for controller 2
    buttons2: u8 = 0,

    /// Latch controller buttons into shift registers
    /// Called when strobe transitions high (bit 0 of $4016 write)
    pub fn latch(self: *ControllerState) void {
        self.shift1 = self.buttons1;
        self.shift2 = self.buttons2;
    }

    /// Update button data from mailbox
    /// Called each frame to sync with current input
    pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
        self.buttons1 = buttons1;
        self.buttons2 = buttons2;
        // If strobe is high, immediately reload shift registers
        if (self.strobe) {
            self.latch();
        }
    }

    /// Read controller 1 serial data (bit 0)
    /// Returns next bit from shift register
    pub fn read1(self: *ControllerState) u8 {
        if (self.strobe) {
            // Strobe high: continuously reload shift register
            return self.buttons1 & 0x01;
        } else {
            // Strobe low: shift out bits
            const bit = self.shift1 & 0x01;
            self.shift1 = (self.shift1 >> 1) | 0x80; // Shift right, fill with 1
            return bit;
        }
    }

    /// Read controller 2 serial data (bit 0)
    pub fn read2(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons2 & 0x01;
        } else {
            const bit = self.shift2 & 0x01;
            self.shift2 = (self.shift2 >> 1) | 0x80;
            return bit;
        }
    }

    /// Write strobe state ($4016 write, bit 0)
    /// Transition high→low starts shift mode
    /// Transition low→high latches button state
    pub fn writeStrobe(self: *ControllerState, value: u8) void {
        const new_strobe = (value & 0x01) != 0;
        const rising_edge = new_strobe and !self.strobe;

        self.strobe = new_strobe;

        // Latch on rising edge (0→1 transition)
        if (rising_edge) {
            self.latch();
        }
    }

    /// Reset controller state
    pub fn reset(self: *ControllerState) void {
        self.* = .{};
    }
};

/// DMC DMA State Machine
/// Simulates RDY line (CPU stall) during DMC sample fetch
/// NTSC (2A03) only: Causes controller/PPU register corruption
pub const DmcDmaState = struct {
    /// RDY line active (CPU stalled)
    rdy_low: bool = false,

    /// Cycles remaining in RDY stall (0-4)
    /// Hardware: 3 idle cycles + 1 fetch cycle
    stall_cycles_remaining: u8 = 0,

    /// Sample address to fetch
    sample_address: u16 = 0,

    /// Sample byte fetched (returned to APU)
    sample_byte: u8 = 0,

    /// Last CPU read address (for repeat reads during stall)
    /// This is where corruption happens
    last_read_address: u16 = 0,

    /// Trigger DMC sample fetch
    /// Called by APU when it needs next sample byte
    pub fn triggerFetch(self: *DmcDmaState, address: u16) void {
        self.rdy_low = true;
        self.stall_cycles_remaining = 4; // 3 idle + 1 fetch
        self.sample_address = address;
    }

    /// Reset DMC DMA state
    pub fn reset(self: *DmcDmaState) void {
        self.* = .{};
    }
};

/// Complete emulation state (pure data, no hidden state)
/// This is the core of the RT emulation loop
///
/// Architecture: Single source of truth with direct data ownership
/// - No pointer wiring (connectComponents() pattern eliminated)
/// - Bus routing is inline logic, not separate abstraction
/// - All state directly owned by EmulationState
pub const EmulationState = struct {
    /// Master clock (PPU cycle granularity)
    clock: MasterClock = .{},

    /// Component states
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,

    /// PPU timing owned by emulator runtime
    ppu_timing: PpuTiming = .{},

    /// Memory bus state (RAM, open bus, optional test RAM)
    bus: BusState = .{},

    /// Cartridge (direct ownership)
    /// Supports all mappers via tagged union dispatch
    cart: ?AnyCartridge = null,

    /// DMA state machine
    dma: DmaState = .{},

    /// DMC DMA state machine (RDY line / DPCM sample fetch)
    dmc_dma: DmcDmaState = .{},

    /// Controller state (shift registers, strobe, buttons)
    controller: ControllerState = .{},

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

    /// Optional framebuffer for PPU pixel output (256×240 RGBA)
    /// Set by emulation thread before each frame
    framebuffer: ?[]u32 = null,

    /// Initialize emulation state from configuration
    /// Cartridge can be loaded later with loadCartridge()
    pub fn init(config: *const Config.Config) EmulationState {
        const cpu = CpuLogic.init();
        const ppu = PpuState.init();
        const apu = ApuState.init();

        return .{
            .cpu = cpu,
            .ppu = ppu,
            .apu = apu,
            .config = config,
        };
    }

    /// Cleanup emulation state resources
    /// MUST be called to prevent memory leaks
    pub fn deinit(self: *EmulationState) void {
        if (self.cart) |*cart| {
            cart.deinit();
        }
    }

    /// Load a cartridge into the emulator (takes ownership)
    /// Caller MUST NOT use or deinit the cartridge after this call
    /// Also updates PPU mirroring based on cartridge
    ///
    /// Example:
    ///   var nrom_cart = try NromCart.load(allocator, "game.nes");
    ///   var any_cart = AnyCartridge{ .nrom = nrom_cart };
    ///   state.loadCartridge(any_cart);  // state now owns cart
    ///   // any_cart is now invalid - do not use or deinit
    pub fn loadCartridge(self: *EmulationState, cart: AnyCartridge) void {
        // Clean up existing cartridge if present
        if (self.cart) |*existing| {
            existing.deinit();
        }

        // Take ownership of new cartridge
        self.cart = cart;
        self.ppu.mirroring = cart.getMirroring();
    }

    /// Unload current cartridge (if any)
    pub fn unloadCartridge(self: *EmulationState) void {
        if (self.cart) |*cart| {
            cart.deinit();
        }
        self.cart = null;
    }

    /// Reset emulation to power-on state
    /// Loads PC from RESET vector ($FFFC-$FFFD)
    pub fn reset(self: *EmulationState) void {
        self.clock.ppu_cycles = 0;
        self.frame_complete = false;
        self.odd_frame = false;
        self.rendering_enabled = false;
        self.ppu_timing = .{};
        self.bus.open_bus = 0;
        self.dma.reset();
        self.dmc_dma.reset();
        self.controller.reset();

        const reset_vector = self.busRead16(0xFFFC);
        self.cpu.pc = reset_vector;
        self.cpu.sp = 0xFD;
        self.cpu.p.interrupt = true;

        PpuLogic.reset(&self.ppu);
        self.apu.reset();
    }

    // =========================================================================
    // Bus Routing (inline logic - no separate abstraction)
    // =========================================================================

    /// Read from NES memory bus
    /// Routes to appropriate component and updates open bus
    pub inline fn busRead(self: *EmulationState, address: u16) u8 {
        const cart_ptr = self.cartPtr();
        const value = switch (address) {
            // RAM + mirrors ($0000-$1FFF)
            // 2KB RAM mirrored 4 times through $0000-$1FFF
            0x0000...0x1FFF => self.bus.ram[address & 0x7FF],

            // PPU registers + mirrors ($2000-$3FFF)
            // 8 registers mirrored through $2000-$3FFF
            0x2000...0x3FFF => PpuLogic.readRegister(&self.ppu, cart_ptr, address & 0x07),

            // APU and I/O registers ($4000-$4017)
            0x4000...0x4013 => self.bus.open_bus, // APU channels write-only
            0x4014 => self.bus.open_bus, // OAMDMA write-only
            0x4015 => blk: {
                // APU status register (read has side effect)
                const status = ApuLogic.readStatus(&self.apu);
                // Side effect: Clear frame IRQ flag
                ApuLogic.clearFrameIrq(&self.apu);
                break :blk status;
            },
            0x4016 => self.controller.read1() | (self.bus.open_bus & 0xE0), // Controller 1 + open bus bits 5-7
            0x4017 => self.controller.read2() | (self.bus.open_bus & 0xE0), // Controller 2 + open bus bits 5-7

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => blk: {
                if (self.cart) |*cart| {
                    break :blk cart.cpuRead(address);
                }
                // No cartridge - check test RAM
                if (self.bus.test_ram) |test_ram| {
                    if (address >= 0x8000) {
                        break :blk test_ram[address - 0x8000];
                    } else if (address >= 0x6000 and address < 0x8000) {
                        // PRG RAM region - read from test_ram offset
                        const prg_ram_offset = (address - 0x6000);
                        if (test_ram.len > 16384 + prg_ram_offset) {
                            break :blk test_ram[16384 + prg_ram_offset];
                        }
                    }
                }
                // No cartridge or test RAM - open bus
                break :blk self.bus.open_bus;
            },

            // Unmapped regions - return open bus
            else => self.bus.open_bus,
        };

        // Hardware: All reads update open bus (except $4015 which is a special case)
        // $4015 (APU Status) doesn't update open bus because the value is synthesized
        if (address != 0x4015) {
            self.bus.open_bus = value;
        }
        return value;
    }

    /// Helper to obtain pointer to owned cartridge (if any)
    fn cartPtr(self: *EmulationState) ?*AnyCartridge {
        if (self.cart) |*cart_ref| {
            return cart_ref;
        }
        return null;
    }

    /// Write to NES memory bus
    /// Routes to appropriate component and updates open bus
    pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) void {
        const cart_ptr = self.cartPtr();
        // Hardware: All writes update open bus
        self.bus.open_bus = value;

        switch (address) {
            // RAM + mirrors ($0000-$1FFF)
            0x0000...0x1FFF => {
                self.bus.ram[address & 0x7FF] = value;
            },

            // PPU registers + mirrors ($2000-$3FFF)
            0x2000...0x3FFF => {
                PpuLogic.writeRegister(&self.ppu, cart_ptr, address & 0x07, value);
            },

            // APU and I/O registers ($4000-$4017)
            // Pulse 1 ($4000-$4003)
            0x4000...0x4003 => |addr| ApuLogic.writePulse1(&self.apu, @intCast(addr & 0x03), value),

            // Pulse 2 ($4004-$4007)
            0x4004...0x4007 => |addr| ApuLogic.writePulse2(&self.apu, @intCast(addr & 0x03), value),

            // Triangle ($4008-$400B)
            0x4008...0x400B => |addr| ApuLogic.writeTriangle(&self.apu, @intCast(addr & 0x03), value),

            // Noise ($400C-$400F)
            0x400C...0x400F => |addr| ApuLogic.writeNoise(&self.apu, @intCast(addr & 0x03), value),

            // DMC ($4010-$4013)
            0x4010...0x4013 => |addr| ApuLogic.writeDmc(&self.apu, @intCast(addr & 0x03), value),

            0x4014 => {
                // OAM DMA trigger
                // Check if we're on an odd CPU cycle (PPU runs at 3x CPU speed)
                const cpu_cycle = self.clock.ppu_cycles / 3;
                const on_odd_cycle = (cpu_cycle & 1) != 0;
                self.dma.trigger(value, on_odd_cycle);
            },

            // APU Control ($4015)
            0x4015 => ApuLogic.writeControl(&self.apu, value),

            0x4016 => {
                // Controller strobe (bit 0 controls latch/shift mode)
                self.controller.writeStrobe(value);
            },

            // APU Frame Counter ($4017)
            0x4017 => ApuLogic.writeFrameCounter(&self.apu, value),

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => {
                if (self.cart) |*cart| {
                    cart.cpuWrite(address, value);
                } else if (self.bus.test_ram) |test_ram| {
                    // Allow test RAM writes to PRG ROM ($8000+) and PRG RAM ($6000-$7FFF)
                    if (address >= 0x8000) {
                        test_ram[address - 0x8000] = value;
                    } else if (address >= 0x6000 and address < 0x8000) {
                        // PRG RAM region - write to test_ram offset
                        // Map $6000-$7FFF to end of test_ram (after PRG ROM)
                        const prg_ram_offset = (address - 0x6000);
                        if (test_ram.len > 16384 + prg_ram_offset) {
                            test_ram[16384 + prg_ram_offset] = value;
                        }
                    }
                }
                // No cartridge or test RAM - write ignored
            },

            // Unmapped regions - write ignored
            else => {},
        }
    }

    /// Read 16-bit value (little-endian)
    /// Used for reading interrupt vectors and 16-bit operands
    pub inline fn busRead16(self: *EmulationState, address: u16) u16 {
        const low = self.busRead(address);
        const high = self.busRead(address +% 1);
        return (@as(u16, high) << 8) | @as(u16, low);
    }

    /// Read 16-bit value with JMP indirect page wrap bug
    /// The 6502 has a bug where JMP ($xxFF) wraps within the page
    pub inline fn busRead16Bug(self: *EmulationState, address: u16) u16 {
        const low_addr = address;
        // If low byte is $FF, wrap to $x00 instead of crossing page
        const high_addr = if ((address & 0x00FF) == 0x00FF)
            address & 0xFF00
        else
            address +% 1;

        const low = self.busRead(low_addr);
        const high = self.busRead(high_addr);
        return (@as(u16, high) << 8) | @as(u16, low);
    }

    /// Peek memory without side effects (for debugging/inspection)
    /// Does NOT update open bus - safe for debugger inspection
    ///
    /// This is distinct from busRead() which updates open bus (hardware behavior).
    /// Use this for debugger inspection where side effects are undesirable.
    ///
    /// Parameters:
    ///   - address: 16-bit CPU address to read from
    ///
    /// Returns: Byte value at address (or open bus value if unmapped)
    pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
        return switch (address) {
            // RAM + mirrors ($0000-$1FFF)
            0x0000...0x1FFF => self.bus.ram[address & 0x7FF],

            // PPU registers + mirrors ($2000-$3FFF)
            // Note: PPU register reads have side effects, but for debugging we return the raw value
            0x2000...0x3FFF => blk: {
                // For debugging, return raw PPU state without side effects
                // This is safe because we're not triggering PPU read logic
                break :blk switch (address & 0x07) {
                    0 => @as(u8, @bitCast(self.ppu.ctrl)), // PPUCTRL
                    1 => @as(u8, @bitCast(self.ppu.mask)), // PPUMASK
                    2 => @as(u8, @bitCast(self.ppu.status)), // PPUSTATUS
                    3 => self.ppu.oam_addr, // OAMADDR
                    4 => self.ppu.oam[self.ppu.oam_addr], // OAMDATA
                    5 => self.bus.open_bus, // PPUSCROLL (write-only)
                    6 => self.bus.open_bus, // PPUADDR (write-only)
                    7 => self.ppu.internal.read_buffer, // PPUDATA (return buffer, not live read)
                    else => unreachable,
                };
            },

            // APU and I/O registers ($4000-$4017)
            0x4000...0x4013 => self.bus.open_bus, // APU not implemented
            0x4014 => self.bus.open_bus, // OAMDMA write-only
            0x4015 => self.bus.open_bus, // APU status not implemented
            0x4016 => (self.controller.shift1 & 0x01) | (self.bus.open_bus & 0xE0), // Controller 1 peek (no shift)
            0x4017 => (self.controller.shift2 & 0x01) | (self.bus.open_bus & 0xE0), // Controller 2 peek (no shift)

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => blk: {
                if (self.cart) |cart| {
                    break :blk cart.cpuRead(address);
                }
                // No cartridge - check test RAM
                if (self.bus.test_ram) |test_ram| {
                    if (address >= 0x8000) {
                        break :blk test_ram[address - 0x8000];
                    }
                }
                // No cartridge or test RAM - open bus
                break :blk self.bus.open_bus;
            },

            // Unmapped regions - return open bus
            else => self.bus.open_bus,
        };
        // NO open_bus update - this is the key difference from busRead()
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
            // Check DMA priority: DMC DMA (RDY line) > OAM DMA > CPU
            if (self.dmc_dma.rdy_low) {
                // DMC DMA active - CPU stalled by RDY line
                self.tickDmcDma();
            } else if (self.dma.active) {
                // OAM DMA active - CPU stalled
                self.tickDma();
            } else {
                // Normal CPU execution
                self.tickCpu();
                // TODO: Track last read address for DMC corruption detection
                // This requires CPU state tracking during reads
            }

            // Poll mapper for IRQ assertion (every CPU cycle)
            // Mappers like MMC3 can assert IRQ based on PPU scanline counter
            if (self.cart) |*cart| {
                if (cart.tickIrq()) {
                    self.cpu.irq_line = true;
                }
            }
        }

        if (apu_tick) {
            self.tickApu();
        }
    }

    // ========================================================================
    // PRIVATE MICROSTEP HELPERS
    // ========================================================================
    // These atomic functions perform cycle-accurate CPU operations.
    // All side effects (bus access, state mutation) happen here.
    // Previously in execution.zig, now integrated into EmulationState.
    // ========================================================================

    // Fetch operand low byte (immediate/zero page address)
    fn fetchOperandLow(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;
        return false;
    }

    // Fetch absolute address low byte
    fn fetchAbsLow(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;
        return false;
    }

    // Fetch absolute address high byte
    fn fetchAbsHigh(self: *EmulationState) bool {
        self.cpu.operand_high = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;
        return false;
    }

    // Add X index to zero page address (wraps within page 0)
    fn addXToZeroPage(self: *EmulationState) bool {
        _ = self.busRead(@as(u16, self.cpu.operand_low)); // Dummy read
        self.cpu.effective_address = @as(u16, self.cpu.operand_low +% self.cpu.x);
        return false;
    }

    // Add Y index to zero page address (wraps within page 0)
    fn addYToZeroPage(self: *EmulationState) bool {
        _ = self.busRead(@as(u16, self.cpu.operand_low)); // Dummy read
        self.cpu.effective_address = @as(u16, self.cpu.operand_low +% self.cpu.y);
        return false;
    }

    // Calculate absolute,X address with page crossing check
    fn calcAbsoluteX(self: *EmulationState) bool {
        const base = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        self.cpu.effective_address = base +% self.cpu.x;
        self.cpu.page_crossed = (base & 0xFF00) != (self.cpu.effective_address & 0xFF00);

        // CRITICAL: Dummy read at wrong address (base_high | result_low)
        const dummy_addr = (base & 0xFF00) | (self.cpu.effective_address & 0x00FF);
        const dummy_value = self.busRead(dummy_addr);
        self.cpu.temp_value = dummy_value;
        return false;
    }

    // Calculate absolute,Y address with page crossing check
    fn calcAbsoluteY(self: *EmulationState) bool {
        const base = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        self.cpu.effective_address = base +% self.cpu.y;
        self.cpu.page_crossed = (base & 0xFF00) != (self.cpu.effective_address & 0xFF00);

        const dummy_addr = (base & 0xFF00) | (self.cpu.effective_address & 0x00FF);
        _ = self.busRead(dummy_addr);
        self.cpu.temp_value = self.bus.open_bus;
        return false;
    }

    // Fix high byte after page crossing
    // For reads: Do REAL read when page crossed (hardware behavior)
    // For RMW: This is always a dummy read before the real read cycle
    fn fixHighByte(self: *EmulationState) bool {
        if (self.cpu.page_crossed) {
            // Read the actual value at correct address
            // For read instructions: this IS the operand value (execute will use temp_value)
            // For RMW instructions: this is a dummy read (RMW will re-read in next cycle)
            self.cpu.temp_value = self.busRead(self.cpu.effective_address);
        }
        // Page not crossed: temp_value already has correct value from calcAbsolute
        return false;
    }

    // Fetch zero page base for indexed indirect
    fn fetchZpBase(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;
        return false;
    }

    // Add X to base address (with dummy read)
    fn addXToBase(self: *EmulationState) bool {
        _ = self.busRead(@as(u16, self.cpu.operand_low)); // Dummy read
        self.cpu.temp_address = @as(u16, self.cpu.operand_low +% self.cpu.x);
        return false;
    }

    // Fetch low byte of indirect address
    fn fetchIndirectLow(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.temp_address);
        return false;
    }

    // Fetch high byte of indirect address
    fn fetchIndirectHigh(self: *EmulationState) bool {
        const high_addr = @as(u16, @as(u8, @truncate(self.cpu.temp_address)) +% 1);
        self.cpu.operand_high = self.busRead(high_addr);
        self.cpu.effective_address = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        return false;
    }

    // Fetch zero page pointer for indirect indexed
    fn fetchZpPointer(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;
        return false;
    }

    // Fetch low byte of pointer
    fn fetchPointerLow(self: *EmulationState) bool {
        self.cpu.temp_value = self.busRead(@as(u16, self.cpu.operand_low));
        return false;
    }

    // Fetch high byte of pointer
    fn fetchPointerHigh(self: *EmulationState) bool {
        const high_addr = @as(u16, self.cpu.operand_low +% 1);
        self.cpu.operand_high = self.busRead(high_addr);
        return false;
    }

    // Add Y and check for page crossing
    fn addYCheckPage(self: *EmulationState) bool {
        const base = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.temp_value);
        self.cpu.effective_address = base +% self.cpu.y;
        self.cpu.page_crossed = (base & 0xFF00) != (self.cpu.effective_address & 0xFF00);

        const dummy_addr = (base & 0xFF00) | (self.cpu.effective_address & 0x00FF);
        _ = self.busRead(dummy_addr);
        self.cpu.temp_value = self.bus.open_bus;
        return false;
    }

    // Pull byte from stack (increment SP first)
    fn pullByte(self: *EmulationState) bool {
        self.cpu.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.cpu.temp_value = self.busRead(stack_addr);
        return false;
    }

    // Dummy read during stack operation
    fn stackDummyRead(self: *EmulationState) bool {
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        _ = self.busRead(stack_addr);
        return false;
    }

    // Push PC high byte to stack (for JSR/BRK)
    fn pushPch(self: *EmulationState) bool {
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.busWrite(stack_addr, @as(u8, @truncate(self.cpu.pc >> 8)));
        self.cpu.sp -%= 1;
        return false;
    }

    // Push PC low byte to stack (for JSR/BRK)
    fn pushPcl(self: *EmulationState) bool {
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.busWrite(stack_addr, @as(u8, @truncate(self.cpu.pc & 0xFF)));
        self.cpu.sp -%= 1;
        return false;
    }

    // Push status register to stack with B flag set (for BRK)
    fn pushStatusBrk(self: *EmulationState) bool {
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        const status = self.cpu.p.toByte() | 0x30; // B flag + unused flag set
        self.busWrite(stack_addr, status);
        self.cpu.sp -%= 1;
        return false;
    }

    // Pull PC low byte from stack (for RTS/RTI)
    fn pullPcl(self: *EmulationState) bool {
        self.cpu.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.cpu.operand_low = self.busRead(stack_addr);
        return false;
    }

    // Pull PC high byte from stack and reconstruct PC (for RTS/RTI)
    fn pullPch(self: *EmulationState) bool {
        self.cpu.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.cpu.operand_high = self.busRead(stack_addr);
        self.cpu.pc = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        return false;
    }

    // Pull PC high byte and signal completion (for RTI final cycle)
    fn pullPchRti(self: *EmulationState) bool {
        self.cpu.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        self.cpu.operand_high = self.busRead(stack_addr);
        self.cpu.pc = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        return true; // RTI complete
    }

    // Pull status register from stack (for RTI)
    fn pullStatus(self: *EmulationState) bool {
        self.cpu.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        const status = self.busRead(stack_addr);
        self.cpu.p = @TypeOf(self.cpu.p).fromByte(status);
        return false;
    }

    // Increment PC after RTS (PC was pushed as PC-1 by JSR)
    fn incrementPcAfterRts(self: *EmulationState) bool {
        _ = self.busRead(self.cpu.pc); // Dummy read
        self.cpu.pc +%= 1;
        return true; // RTS complete
    }

    // Stack dummy read for JSR cycle 3 (internal operation)
    fn jsrStackDummy(self: *EmulationState) bool {
        const stack_addr = 0x0100 | @as(u16, self.cpu.sp);
        _ = self.busRead(stack_addr);
        return false;
    }

    // Fetch absolute high byte for JSR and jump (final cycle)
    fn fetchAbsHighJsr(self: *EmulationState) bool {
        self.cpu.operand_high = self.busRead(self.cpu.pc);
        self.cpu.effective_address = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        self.cpu.pc = self.cpu.effective_address;
        return true; // JSR complete
    }

    // Fetch IRQ vector low byte (for BRK) and set interrupt disable flag
    fn fetchIrqVectorLow(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(0xFFFE);
        self.cpu.p.interrupt = true;
        return false;
    }

    // Fetch IRQ vector high byte and jump (completes BRK)
    fn fetchIrqVectorHigh(self: *EmulationState) bool {
        self.cpu.operand_high = self.busRead(0xFFFF);
        self.cpu.pc = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
        return true; // BRK complete
    }

    // Read operand for RMW instruction
    fn rmwRead(self: *EmulationState) bool {
        const addr = switch (self.cpu.address_mode) {
            .zero_page => @as(u16, self.cpu.operand_low),
            .zero_page_x, .absolute_x => self.cpu.effective_address,
            .absolute => (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low),
            else => unreachable,
        };

        self.cpu.effective_address = addr;
        self.cpu.temp_value = self.busRead(addr);
        return false;
    }

    // Dummy write original value (CRITICAL for hardware accuracy!)
    fn rmwDummyWrite(self: *EmulationState) bool {
        self.busWrite(self.cpu.effective_address, self.cpu.temp_value);
        return false;
    }

    // Fetch branch offset and check condition
    fn branchFetchOffset(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.pc);
        self.cpu.pc +%= 1;

        // Check branch condition based on opcode
        // If condition false, branch not taken → complete immediately (2 cycles total)
        // If condition true, branch taken → continue to branchAddOffset (3-4 cycles)
        const should_branch = switch (self.cpu.opcode) {
            0x10 => !self.cpu.p.negative,  // BPL - Branch if Plus (N=0)
            0x30 => self.cpu.p.negative,   // BMI - Branch if Minus (N=1)
            0x50 => !self.cpu.p.overflow,  // BVC - Branch if Overflow Clear (V=0)
            0x70 => self.cpu.p.overflow,   // BVS - Branch if Overflow Set (V=1)
            0x90 => !self.cpu.p.carry,     // BCC - Branch if Carry Clear (C=0)
            0xB0 => self.cpu.p.carry,      // BCS - Branch if Carry Set (C=1)
            0xD0 => !self.cpu.p.zero,      // BNE - Branch if Not Equal (Z=0)
            0xF0 => self.cpu.p.zero,       // BEQ - Branch if Equal (Z=1)
            else => unreachable,
        };

        if (!should_branch) {
            // Branch not taken - complete immediately (2 cycles total)
            // PC already advanced past offset byte, pointing to next instruction
            return true;
        }

        // Branch taken - continue to branchAddOffset (3-4 cycles total)
        // std.debug.print("[DEBUG] Branch TAKEN (opcode=0x{x:0>2}): PC=0x{x:0>4}, offset=0x{x:0>2}\n", .{ self.cpu.opcode, self.cpu.pc, self.cpu.operand_low });
        return false;
    }

    // Add offset to PC and check page crossing
    fn branchAddOffset(self: *EmulationState) bool {
        _ = self.busRead(self.cpu.pc); // Dummy read during offset calculation

        const offset = @as(i8, @bitCast(self.cpu.operand_low));
        const old_pc = self.cpu.pc;
        self.cpu.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) + offset));

        self.cpu.page_crossed = (old_pc & 0xFF00) != (self.cpu.pc & 0xFF00);

        if (!self.cpu.page_crossed) {
            return true; // Branch complete (3 cycles total)
        }
        return false; // Need page fix (4 cycles total)
    }

    // Fix PC high byte after page crossing
    fn branchFixPch(self: *EmulationState) bool {
        const dummy_addr = (self.cpu.pc & 0x00FF) | ((self.cpu.pc -% (@as(u16, self.cpu.operand_low) & 0x0100)) & 0xFF00);
        _ = self.busRead(dummy_addr);
        return true; // Branch complete
    }

    // Fetch low byte of JMP indirect target
    fn jmpIndirectFetchLow(self: *EmulationState) bool {
        self.cpu.operand_low = self.busRead(self.cpu.effective_address);
        return false;
    }

    // Fetch high byte of JMP indirect target (with page boundary bug)
    fn jmpIndirectFetchHigh(self: *EmulationState) bool {
        // 6502 bug: If pointer is at page boundary, wraps within page
        const ptr = self.cpu.effective_address;
        const high_addr = if ((ptr & 0xFF) == 0xFF)
            ptr & 0xFF00 // Wrap to start of same page
        else
            ptr + 1;

        self.cpu.operand_high = self.busRead(high_addr);
        self.cpu.effective_address = (@as(u16, self.cpu.operand_high) << 8) | self.cpu.operand_low;
        return false;
    }

    // ========================================================================
    // END PRIVATE MICROSTEP HELPERS
    // ========================================================================

    /// Tick CPU state machine (called every 3 PPU cycles)
    /// This contains all CPU side effects - pure functional helpers are in CpuLogic
    pub fn tickCpu(self: *EmulationState) void {
        self.cpu.cycle_count += 1;

        // If CPU is halted (JAM/KIL), do nothing until RESET
        if (self.cpu.halted) {
            return;
        }

        // Check for interrupts at the start of instruction fetch
        if (self.cpu.state == .fetch_opcode) {
            CpuLogic.checkInterrupts(&self.cpu);
            if (self.cpu.pending_interrupt != .none and self.cpu.pending_interrupt != .reset) {
                CpuLogic.startInterruptSequence(&self.cpu);
                return;
            }
        }

        // Cycle 1: Always fetch opcode
        if (self.cpu.state == .fetch_opcode) {
            self.cpu.opcode = self.busRead(self.cpu.pc);
            self.cpu.data_bus = self.cpu.opcode;
            self.cpu.pc +%= 1;

            const entry = CpuModule.dispatch.DISPATCH_TABLE[self.cpu.opcode];
            self.cpu.address_mode = entry.info.mode;

            // Determine if addressing cycles needed (inline logic, no arrays)
            // IMPORTANT: Control flow opcodes (JSR/RTS/RTI/BRK/PHA/PLA/PHP/PLP) have custom microstep
            // sequences even though they're marked as .implied or .absolute in the decode table
            const needs_addressing = switch (self.cpu.opcode) {
                0x20, 0x60, 0x40, 0x00, 0x48, 0x68, 0x08, 0x28 => true, // Force addressing state for control flow
                else => switch (entry.info.mode) {
                    .implied, .accumulator, .immediate => false,
                    else => true,
                },
            };

            if (needs_addressing) {
                self.cpu.state = .fetch_operand_low;
                self.cpu.instruction_cycle = 0;
            } else {
                self.cpu.state = .execute;
            }
            return;
        }

        // Handle addressing mode microsteps (inline switch logic)
        if (self.cpu.state == .fetch_operand_low) {
            const entry = CpuModule.dispatch.DISPATCH_TABLE[self.cpu.opcode];

            // Check for control flow opcodes with custom microstep sequences FIRST
            // These have special cycle patterns that don't match their addressing mode
            const is_control_flow = switch (self.cpu.opcode) {
                0x20, 0x60, 0x40, 0x00, 0x48, 0x68, 0x08, 0x28 => true, // JSR, RTS, RTI, BRK, PHA, PLA, PHP, PLP
                else => false,
            };

            // Call appropriate microstep based on mode and cycle
            // Returns true if instruction completes early (e.g., branch not taken)
            const complete = if (is_control_flow) blk: {
                // Control flow instructions with completely custom microstep sequences
                break :blk switch (self.cpu.opcode) {
                    // JSR - 6 cycles
                    0x20 => switch (self.cpu.instruction_cycle) {
                        0 => self.fetchAbsLow(),
                        1 => self.jsrStackDummy(),
                        2 => self.pushPch(),
                        3 => self.pushPcl(),
                        4 => self.fetchAbsHighJsr(),
                        else => unreachable,
                    },
                    // RTS - 6 cycles
                    0x60 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        1 => self.stackDummyRead(),
                        2 => self.pullPcl(),
                        3 => self.pullPch(),
                        4 => self.incrementPcAfterRts(),
                        else => unreachable,
                    },
                    // RTI - 6 cycles
                    0x40 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        1 => self.pullStatus(),
                        2 => self.pullPcl(),
                        3 => self.pullPch(), // Pull PC high
                        4 => blk2: { // Dummy read at new PC before completing
                            _ = self.busRead(self.cpu.pc);
                            break :blk2 true; // RTI complete
                        },
                        else => unreachable,
                    },
                    // BRK - 7 cycles
                    0x00 => switch (self.cpu.instruction_cycle) {
                        0 => self.fetchOperandLow(),
                        1 => self.pushPch(),
                        2 => self.pushPcl(),
                        3 => self.pushStatusBrk(),
                        4 => self.fetchIrqVectorLow(),
                        5 => self.fetchIrqVectorHigh(),
                        else => unreachable,
                    },
                    // PHA - 3 cycles (dummy read, then execute pushes)
                    0x48 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        else => unreachable,
                    },
                    // PHP - 3 cycles (dummy read, then execute pushes)
                    0x08 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        else => unreachable,
                    },
                    // PLA - 4 cycles (dummy read twice, then pull)
                    0x68 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        1 => self.pullByte(),
                        else => unreachable,
                    },
                    // PLP - 4 cycles
                    0x28 => switch (self.cpu.instruction_cycle) {
                        0 => self.stackDummyRead(),
                        1 => self.pullStatus(),
                        else => unreachable,
                    },
                    else => unreachable,
                };
            } else switch (entry.info.mode) {
                .zero_page => blk: {
                    if (entry.is_rmw) {
                        // RMW: 5 cycles (fetch, read, dummy write, execute)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchOperandLow(),
                            1 => self.rmwRead(),
                            2 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchOperandLow(),
                            else => unreachable,
                        };
                    }
                },
                .zero_page_x => blk: {
                    if (entry.is_rmw) {
                        // RMW: 6 cycles (fetch, add X, read, dummy write, execute)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchOperandLow(),
                            1 => self.addXToZeroPage(),
                            2 => self.rmwRead(),
                            3 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchOperandLow(),
                            1 => self.addXToZeroPage(),
                            else => unreachable,
                        };
                    }
                },
                .zero_page_y => switch (self.cpu.instruction_cycle) {
                    0 => self.fetchOperandLow(),
                    1 => self.addYToZeroPage(),
                    else => unreachable,
                },
                .absolute => blk: {
                    if (entry.is_rmw) {
                        // RMW: 6 cycles (fetch low, high, read, dummy write, execute)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            2 => self.rmwRead(),
                            3 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            else => unreachable,
                        };
                    }
                },
                .absolute_x => blk: {
                    // Read vs write have different cycle counts
                    if (entry.is_rmw) {
                        // RMW: 7 cycles (fetch low, high, calc+dummy, read, dummy write, execute)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            2 => self.calcAbsoluteX(),
                            3 => self.rmwRead(),
                            4 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        // Regular read: 4-5 cycles (4 if no page cross, 5 if page cross)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            2 => self.calcAbsoluteX(),
                            3 => self.fixHighByte(),
                            else => unreachable,
                        };
                    }
                },
                .absolute_y => blk: {
                    if (entry.is_rmw) {
                        // RMW not used with absolute_y, but handle for completeness
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            2 => self.calcAbsoluteY(),
                            3 => self.rmwRead(),
                            4 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        // Regular read: 4-5 cycles (4 if no page cross, 5 if page cross)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchAbsLow(),
                            1 => self.fetchAbsHigh(),
                            2 => self.calcAbsoluteY(),
                            3 => self.fixHighByte(),
                            else => unreachable,
                        };
                    }
                },
                .indexed_indirect => blk: {
                    if (entry.is_rmw) {
                        // RMW: 8 cycles
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchZpBase(),
                            1 => self.addXToBase(),
                            2 => self.fetchIndirectLow(),
                            3 => self.fetchIndirectHigh(),
                            4 => self.rmwRead(),
                            5 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        // Regular: 6 cycles
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchZpBase(),
                            1 => self.addXToBase(),
                            2 => self.fetchIndirectLow(),
                            3 => self.fetchIndirectHigh(),
                            else => unreachable,
                        };
                    }
                },
                .indirect_indexed => blk: {
                    if (entry.is_rmw) {
                        // RMW: 8 cycles
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchZpPointer(),
                            1 => self.fetchPointerLow(),
                            2 => self.fetchPointerHigh(),
                            3 => self.addYCheckPage(),
                            4 => self.rmwRead(),
                            5 => self.rmwDummyWrite(),
                            else => unreachable,
                        };
                    } else {
                        // Regular read: 5-6 cycles (5 if no page cross, 6 if page cross)
                        break :blk switch (self.cpu.instruction_cycle) {
                            0 => self.fetchZpPointer(),
                            1 => self.fetchPointerLow(),
                            2 => self.fetchPointerHigh(),
                            3 => self.addYCheckPage(),
                            4 => self.fixHighByte(),
                            else => unreachable,
                        };
                    }
                },
                .relative => switch (self.cpu.instruction_cycle) {
                    0 => self.branchFetchOffset(),
                    1 => self.branchAddOffset(),
                    2 => self.branchFixPch(),
                    else => unreachable,
                },
                .indirect => switch (self.cpu.instruction_cycle) {
                    0 => self.fetchAbsLow(),
                    1 => self.fetchAbsHigh(),
                    2 => self.jmpIndirectFetchLow(),
                    3 => self.jmpIndirectFetchHigh(),
                    else => unreachable,
                },
                else => unreachable, // All addressing modes should be handled above
            };

            self.cpu.instruction_cycle += 1;

            if (complete) {
                // Instruction completed early (e.g., branch not taken)
                self.cpu.state = .fetch_opcode;
                self.cpu.instruction_cycle = 0;
                return;
            }

            // Check if addressing is complete and we should move to execute
            // IMPORTANT: Check for control flow opcodes FIRST before checking addressing mode
            // These opcodes have conventional addressing modes but custom microstep sequences
            const addressing_done = if (is_control_flow) blk: {
                // Control flow instructions complete via their final microstep
                break :blk switch (self.cpu.opcode) {
                    0x20 => self.cpu.instruction_cycle >= 5, // JSR (6 cycles total)
                    0x60 => self.cpu.instruction_cycle >= 5, // RTS (6 cycles total)
                    0x40 => self.cpu.instruction_cycle >= 5, // RTI (6 cycles total)
                    0x00 => self.cpu.instruction_cycle >= 6, // BRK (7 cycles total)
                    0x48, 0x08 => self.cpu.instruction_cycle >= 1, // PHA, PHP (3 cycles total)
                    0x68, 0x28 => self.cpu.instruction_cycle >= 2, // PLA, PLP (4 cycles total)
                    else => unreachable,
                };
            } else switch (entry.info.mode) {
                .zero_page => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 3;
                    } else {
                        break :blk self.cpu.instruction_cycle >= 1;
                    }
                },
                .zero_page_x => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 4;
                    } else {
                        break :blk self.cpu.instruction_cycle >= 2;
                    }
                },
                .zero_page_y => self.cpu.instruction_cycle >= 2,
                .absolute => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 4;
                    } else {
                        break :blk self.cpu.instruction_cycle >= 2;
                    }
                },
                .absolute_x, .absolute_y => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 5;
                    } else {
                        // Non-RMW reads: 5 cycles (no page cross) or 6 cycles (page cross)
                        // After calcAbsolute sets page_crossed flag
                        const threshold: u8 = if (self.cpu.page_crossed) 4 else 3;
                        break :blk self.cpu.instruction_cycle >= threshold;
                    }
                },
                .indexed_indirect => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 6;
                    } else {
                        break :blk self.cpu.instruction_cycle >= 4;
                    }
                },
                .indirect_indexed => blk: {
                    if (entry.is_rmw) {
                        break :blk self.cpu.instruction_cycle >= 6;
                    } else {
                        // Non-RMW reads: 6 cycles (no page cross) or 7 cycles (page cross)
                        // After addYCheckPage sets page_crossed flag
                        const threshold: u8 = if (self.cpu.page_crossed) 5 else 4;
                        break :blk self.cpu.instruction_cycle >= threshold;
                    }
                },
                .relative => false, // Branches always complete via return value
                .indirect => self.cpu.instruction_cycle >= 4,
                else => true, // implied, accumulator, immediate
            };

            if (addressing_done) {
                self.cpu.state = .execute;

                // Conditional fallthrough: ONLY for indexed modes with +1 cycle deviation
                // Hardware combines final operand read + execute in same cycle for:
                // - absolute,X / absolute,Y
                // - indirect,Y (indirect indexed)
                // Other modes already have correct timing - don't fall through!
                const dispatch_entry = CpuModule.dispatch.DISPATCH_TABLE[self.cpu.opcode];
                const should_fallthrough = !dispatch_entry.is_rmw and
                    (self.cpu.address_mode == .absolute_x or
                        self.cpu.address_mode == .absolute_y or
                        self.cpu.address_mode == .indirect_indexed);

                if (should_fallthrough) {
                    // Fall through to execute state (don't return)
                    // Indexed modes complete in same tick as final addressing
                } else {
                    // All other modes: execute in separate cycle
                    return;
                }
            } else {
                return;
            }
        }

        // Execute instruction (Pure Function Architecture)
        if (self.cpu.state == .execute) {
            const entry = CpuModule.dispatch.DISPATCH_TABLE[self.cpu.opcode];

            // Extract operand value based on addressing mode (inline for bus access)
            const operand = if (entry.is_rmw or entry.is_pull)
                self.cpu.temp_value
            else switch (self.cpu.address_mode) {
                .immediate => self.busRead(self.cpu.pc),
                .accumulator => self.cpu.a,
                .implied => 0,
                .zero_page => self.busRead(@as(u16, self.cpu.operand_low)),
                .zero_page_x, .zero_page_y => self.busRead(self.cpu.effective_address),
                .absolute => blk: {
                    const addr = (@as(u16, self.cpu.operand_high) << 8) | self.cpu.operand_low;

                    // Check if this is a write-only instruction (STA, STX, STY)
                    // Real 6502 hardware doesn't read before writing for these instructions
                    const is_write_only = switch (self.cpu.opcode) {
                        0x8D, // STA absolute
                        0x8E, // STX absolute
                        0x8C, // STY absolute
                        => true,
                        else => false,
                    };

                    if (is_write_only) {
                        break :blk 0; // Operand not used for write-only instructions
                    }

                    break :blk self.busRead(addr);
                },
                // Indexed modes: Always use temp_value (already read in addressing state)
                // No page cross: calcAbsoluteX/Y read it
                // Page cross: fixHighByte read it
                .absolute_x, .absolute_y, .indirect_indexed => self.cpu.temp_value,
                .indexed_indirect => self.busRead(self.cpu.effective_address),
                .indirect => unreachable,
                .relative => self.cpu.operand_low,
            };

            // Immediate mode: Increment PC after reading operand
            if (self.cpu.address_mode == .immediate) {
                self.cpu.pc +%= 1;
            }

            // Set effective_address for modes that need it
            switch (self.cpu.address_mode) {
                .zero_page => {
                    self.cpu.effective_address = @as(u16, self.cpu.operand_low);
                },
                .absolute => {
                    self.cpu.effective_address = (@as(u16, self.cpu.operand_high) << 8) | @as(u16, self.cpu.operand_low);
                },
                else => {},
            }

            // Convert to core CPU state (6502 registers + effective address)
            const core_state = CpuLogic.toCoreState(&self.cpu);

            // Call pure opcode function (returns delta structure)
            const result = entry.operation(core_state, operand);

            // Apply result (inline for bus writes)
            if (result.a) |new_a| self.cpu.a = new_a;
            if (result.x) |new_x| self.cpu.x = new_x;
            if (result.y) |new_y| self.cpu.y = new_y;
            if (result.sp) |new_sp| self.cpu.sp = new_sp;
            if (result.pc) |new_pc| self.cpu.pc = new_pc;
            if (result.flags) |new_flags| self.cpu.p = new_flags;

            if (result.bus_write) |write| {
                self.busWrite(write.address, write.value);
                self.cpu.data_bus = write.value;
            }

            if (result.push) |value| {
                self.busWrite(0x0100 | @as(u16, self.cpu.sp), value);
                self.cpu.sp -%= 1;
                self.cpu.data_bus = value;
            }

            if (result.halt) {
                self.cpu.halted = true;
            }

            // Instruction complete
            self.cpu.state = .fetch_opcode;
            self.cpu.instruction_cycle = 0;
        }
    }

    /// Tick PPU state machine (called every PPU cycle)
    fn tickPpu(self: *EmulationState) void {
        const cart_ptr = self.cartPtr();

        // Sample A12 state before PPU tick (for MMC3 IRQ edge detection)
        const old_a12 = self.ppu_timing.a12_state;

        const flags = PpuRuntime.tick(&self.ppu, &self.ppu_timing, cart_ptr, self.framebuffer);

        // Update A12 state after PPU tick
        // A12 = bit 12 of PPU address register (v)
        const new_a12 = (self.ppu.internal.v & 0x1000) != 0;
        self.ppu_timing.a12_state = new_a12;

        // Detect A12 rising edge (0→1 transition) and notify mapper
        // MMC3 uses this to decrement its IRQ scanline counter
        if (!old_a12 and new_a12) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();
            }
        }

        self.rendering_enabled = flags.rendering_enabled;
        if (flags.frame_complete) {
            self.frame_complete = true;
        }
        self.odd_frame = (self.ppu_timing.frame & 1) == 1;
    }

    /// Tick APU state machine (called every CPU cycle)
    /// This contains all APU side effects - pure functional helpers are in ApuLogic
    fn tickApu(self: *EmulationState) void {
        // Tick frame counter
        const frame_irq = ApuLogic.tickFrameCounter(&self.apu);

        // If frame IRQ generated, assert CPU IRQ line
        if (frame_irq) {
            self.cpu.irq_line = true;
        }

        // Tick DMC timer and output unit
        // Returns true if sample buffer needs refill (trigger DMA)
        const dmc_needs_sample = ApuLogic.tickDmc(&self.apu);
        if (dmc_needs_sample) {
            const address = ApuLogic.getSampleAddress(&self.apu);
            self.dmc_dma.triggerFetch(address);
        }

        // Check DMC IRQ flag and assert CPU IRQ line if needed
        if (self.apu.dmc_irq_flag) {
            self.cpu.irq_line = true;
        }

        // TODO: Tick other channels (Phase 2: Audio Synthesis)
    }

    /// Tick DMA state machine (called every 3 PPU cycles, same as CPU)
    /// Executes OAM DMA transfer from CPU RAM ($XX00-$XXFF) to PPU OAM ($2004)
    ///
    /// Timing (hardware-accurate):
    /// - Cycle 0 (if needed): Alignment wait (odd CPU cycle start)
    /// - Cycles 1-512: 256 read/write pairs
    ///   * Even cycles: Read byte from CPU RAM
    ///   * Odd cycles: Write byte to PPU OAM
    /// - Total: 513 cycles (even start) or 514 cycles (odd start)
    ///
    /// Hardware behavior:
    /// - CPU is stalled (no instruction execution)
    /// - PPU continues running normally
    /// - Bus is monopolized by DMA controller
    fn tickDma(self: *EmulationState) void {
        // Increment CPU cycle counter (time passes even though CPU is stalled)
        self.cpu.cycle_count += 1;

        // Increment DMA cycle counter
        const cycle = self.dma.current_cycle;
        self.dma.current_cycle += 1;

        // Alignment wait cycle (if needed)
        if (self.dma.needs_alignment and cycle == 0) {
            // Wait one cycle for alignment
            // This happens when DMA is triggered on an odd CPU cycle
            return;
        }

        // Calculate effective cycle (after alignment)
        const effective_cycle = if (self.dma.needs_alignment) cycle - 1 else cycle;

        // Check if DMA is complete (512 cycles = 256 read/write pairs)
        if (effective_cycle >= 512) {
            self.dma.reset();
            return;
        }

        // DMA transfer: Alternate between read and write
        if (effective_cycle % 2 == 0) {
            // Even cycle: Read from CPU RAM
            const source_addr = (@as(u16, self.dma.source_page) << 8) | @as(u16, self.dma.current_offset);
            self.dma.temp_value = self.busRead(source_addr);
        } else {
            // Odd cycle: Write to PPU OAM
            // PPU OAM is 256 bytes at $2004 (auto-incremented by PPU)
            self.ppu.oam[self.dma.current_offset] = self.dma.temp_value;

            // Increment offset for next byte
            self.dma.current_offset +%= 1;
        }
    }

    /// Tick DMC DMA state machine (called every CPU cycle when active)
    ///
    /// Hardware behavior (NTSC 2A03 only):
    /// - CPU is stalled via RDY line for 4 cycles (3 idle + 1 fetch)
    /// - During stall, CPU repeats last read cycle
    /// - If last read was $4016/$4017 (controller), corruption occurs
    /// - If last read was $2002/$2007 (PPU), side effects repeat
    ///
    /// PAL 2A07: Bug fixed, DMA is clean (no corruption)
    ///
    /// Note: Public for testing purposes
    pub fn tickDmcDma(self: *EmulationState) void {
        // Increment CPU cycle counter (time passes even though CPU stalled)
        self.cpu.cycle_count += 1;

        const cycle = self.dmc_dma.stall_cycles_remaining;

        if (cycle == 0) {
            // DMA complete
            self.dmc_dma.rdy_low = false;
            return;
        }

        self.dmc_dma.stall_cycles_remaining -= 1;

        if (cycle == 1) {
            // Final cycle: Fetch sample byte
            const address = self.dmc_dma.sample_address;
            self.dmc_dma.sample_byte = self.busRead(address);

            // Load into APU
            ApuLogic.loadSampleByte(&self.apu, self.dmc_dma.sample_byte);

            // DMA complete - clear RDY line
            self.dmc_dma.rdy_low = false;
        } else {
            // Idle cycles (1-3): CPU repeats last read
            // This is where corruption happens on NTSC
            const has_dpcm_bug = switch (self.config.cpu.variant) {
                .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC - has bug
                .rp2a07 => false, // PAL - bug fixed
            };

            if (has_dpcm_bug) {
                // NTSC: Repeat last read (can cause corruption)
                const last_addr = self.dmc_dma.last_read_address;

                // If last read was controller, this extra read corrupts shift register
                if (last_addr == 0x4016 or last_addr == 0x4017) {
                    // Extra read advances shift register -> corruption
                    _ = self.busRead(last_addr);
                }

                // If last read was PPU status/data, side effects occur again
                if (last_addr == 0x2002 or last_addr == 0x2007) {
                    _ = self.busRead(last_addr);
                }
            }
            // PAL: Clean DMA, no repeat reads
        }
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
            // This check is RT-safe: unreachable is optimized out in ReleaseFast
            const max_cycles: u64 = 110_000;
            if (self.clock.ppu_cycles - start_cycle > max_cycles) {
                if (comptime std.debug.runtime_safety) {
                    unreachable; // Debug mode only, no allocation
                }
                break; // Release mode: exit gracefully
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

    const state = EmulationState.init(&config);

    try testing.expectEqual(@as(u64, 0), state.clock.ppu_cycles);
    try testing.expect(!state.frame_complete);
    try testing.expectEqual(@as(u8, 0), state.bus.open_bus);
    try testing.expect(!state.dma.active);
}

test "EmulationState: tick advances PPU clock" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
    state.reset();

    // Advance to scanline 241, dot 0 (just before VBlank)
    state.ppu_timing.scanline = 241;
    state.ppu_timing.dot = 0;
    try testing.expect(!state.frame_complete);

    // Tick once to reach scanline 241, dot 1 (VBlank start)
    state.tickPpu();
    try testing.expectEqual(@as(u16, 241), state.ppu_timing.scanline);
    try testing.expectEqual(@as(u16, 1), state.ppu_timing.dot);
    try testing.expect(state.frame_complete); // VBlank flag set
}

test "EmulationState: odd frame skip when rendering enabled" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
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

    var state = EmulationState.init(&config);
    state.reset();

    // Start with even frame (odd_frame = false)
    try testing.expect(!state.odd_frame);
    try testing.expectEqual(@as(u64, 0), state.ppu_timing.frame);

    // Advance to end of scanline 261 (last scanline of frame)
    state.ppu_timing.scanline = 261;
    state.ppu_timing.dot = 340;

    // Tick to cross into scanline 0 of next frame
    state.tickPpu();

    // Frame should have incremented
    try testing.expectEqual(@as(u64, 1), state.ppu_timing.frame);
    // Should now be odd frame
    try testing.expect(state.odd_frame);

    // Advance to next frame boundary
    state.ppu_timing.scanline = 261;
    state.ppu_timing.dot = 340;
    state.tickPpu();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);
}
