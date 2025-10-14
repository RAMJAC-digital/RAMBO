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
pub const MasterClock = @import("MasterClock.zig").MasterClock;
const CpuModule = @import("../cpu/Cpu.zig");
const CpuState = CpuModule.State.CpuState;
const CpuLogic = CpuModule.Logic;
const PpuModule = @import("../ppu/Ppu.zig");
const PpuState = PpuModule.State.PpuState;
const PpuLogic = PpuModule.Logic;
const ApuModule = @import("../apu/Apu.zig");
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;
const CartridgeModule = @import("../cartridge/Cartridge.zig");
const RegistryModule = @import("../cartridge/mappers/registry.zig");
const AnyCartridge = RegistryModule.AnyCartridge;
const Debugger = @import("../debugger/Debugger.zig");
const CpuExecution = @import("cpu/execution.zig");

// Cycle result structures
const CycleResults = @import("state/CycleResults.zig");
const PpuCycleResult = CycleResults.PpuCycleResult;
const CpuCycleResult = CycleResults.CpuCycleResult;
const ApuCycleResult = CycleResults.ApuCycleResult;

// Bus state
const BusState = @import("state/BusState.zig").BusState;

// Peripheral state (re-exported for tests and external use)
pub const OamDma = @import("state/peripherals/OamDma.zig").OamDma;
pub const DmcDma = @import("state/peripherals/DmcDma.zig").DmcDma;
pub const ControllerState = @import("state/peripherals/ControllerState.zig").ControllerState;

// CPU microstep functions
const CpuMicrosteps = @import("cpu/microsteps.zig");

// DMA logic
const DmaLogic = @import("dma/logic.zig");

// Bus inspection (debugger-safe memory reads)
const BusInspection = @import("bus/inspection.zig");

// Debugger integration (breakpoints, watchpoints, pause management)
const DebugIntegration = @import("debug/integration.zig");

// Emulation helpers (convenience wrappers for testing/benchmarking)
const Helpers = @import("helpers.zig");

// Timing structures and helpers
const Timing = @import("state/Timing.zig");
const TimingStep = Timing.TimingStep;
const TimingHelpers = Timing.TimingHelpers;

// VBlank timing ledger (exported for unit tests)
pub const VBlankLedger = @import("VBlankLedger.zig").VBlankLedger;

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

    /// VBlank timestamp ledger for cycle-accurate NMI edge detection
    /// Records VBlank set/clear, $2002 reads, PPUCTRL writes with master clock timestamps
    /// Decouples CPU NMI latch from readable PPU status flag
    vblank_ledger: VBlankLedger = .{},

    /// Memory bus state (RAM, open bus, optional test RAM)
    bus: BusState = .{},

    /// Cartridge (direct ownership)
    /// Supports all mappers via tagged union dispatch
    cart: ?AnyCartridge = null,

    /// DMA state machine
    dma: OamDma = .{},

    /// DMC DMA state machine (RDY line / DPCM sample fetch)
    dmc_dma: DmcDma = .{},

    /// Controller state (shift registers, strobe, buttons)
    controller: ControllerState = .{},

    /// Optional debugger for breakpoints/watchpoints (RT-safe, zero allocations in hot path)
    debugger: ?Debugger.Debugger = null,

    /// Debug break occurred flag (checked by EmulationThread to post events)
    debug_break_occurred: bool = false,

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
    pub fn power_on(self: *EmulationState) void {
        self.clock.reset();
        self.frame_complete = false;
        self.odd_frame = false;
        self.rendering_enabled = false;
        self.bus.open_bus = 0;
        self.dma.reset();
        self.dmc_dma.reset();
        self.controller.reset();
        self.vblank_ledger.reset();

        const reset_vector = self.busRead16(0xFFFC);
        self.cpu.pc = reset_vector;
        self.cpu.sp = 0xFD;
        self.cpu.p.interrupt = true;
        self.cpu.state = .fetch_opcode;
        self.cpu.instruction_cycle = 0;
        self.cpu.pending_interrupt = .none;
        self.cpu.halted = false;

        PpuLogic.reset(&self.ppu);
        self.ppu.warmup_complete = false;  // Hardware-accurate: warmup period required after power-on

        ApuLogic.reset(&self.apu);
        self.cpu.nmi_line = false;
        self.cpu.irq_line = false; // Hardware-accurate: IRQ line low after power-on
    }

    /// Reset emulation to reset state
    /// Loads PC from RESET vector ($FFFC-$FFFD)
    pub fn reset(self: *EmulationState) void {
        self.clock.reset();
        self.frame_complete = false;
        self.odd_frame = false;
        self.rendering_enabled = false;
        self.bus.open_bus = 0;
        self.dma.reset();
        self.dmc_dma.reset();
        self.controller.reset();
        self.vblank_ledger.reset();

        const reset_vector = self.busRead16(0xFFFC);
        self.cpu.pc = reset_vector;
        self.cpu.sp = 0xFD;
        self.cpu.p.interrupt = true;
        self.cpu.state = .fetch_opcode;
        self.cpu.instruction_cycle = 0;
        self.cpu.pending_interrupt = .none;
        self.cpu.halted = false;

        PpuLogic.reset(&self.ppu);
        self.ppu.warmup_complete = true;

        ApuLogic.reset(&self.apu);
        self.cpu.nmi_line = false;
        self.cpu.irq_line = false; // Hardware-accurate: IRQ line low after reset
    }

    // =========================================================================
    // Test Helper Functions
    // =========================================================================
    // These functions coordinate VBlank flag changes with the VBlankLedger
    // to ensure tests properly simulate hardware behavior

    /// TEST HELPER: Set PPUCTRL NMI enable
    pub fn testSetNmiEnable(self: *EmulationState, enabled: bool) void {
        self.ppu.ctrl.nmi_enable = enabled;
    }

    // =========================================================================
    // Bus Routing (inline logic - no separate abstraction)
    // =========================================================================

    /// Read from NES memory bus
    /// Routes to appropriate component and updates open bus
    pub inline fn busRead(self: *EmulationState, address: u16) u8 {
        const cart_ptr = self.cartPtr();

        // The result of the read. For PPU reads, this will be a struct.
        var ppu_read_result: ?PpuLogic.PpuReadResult = null;
        var update_open_bus: bool = true;

        const value = switch (address) {
            // RAM + mirrors ($0000-$1FFF)
            0x0000...0x1FFF => self.bus.ram[address & 0x7FF],

            // PPU registers + mirrors ($2000-$3FFF)
            0x2000...0x3FFF => blk: {
                // Check if this is a $2002 read (PPUSTATUS) for race condition handling
                const is_status_read = (address & 0x0007) == 0x0002;

                // Race condition: If reading $2002 on the exact cycle VBlank is set,
                // set race_hold BEFORE computing vblank_active in readRegister()
                if (is_status_read) {
                    const now = self.clock.ppu_cycles;
                    if (now == self.vblank_ledger.last_set_cycle and
                        self.vblank_ledger.last_set_cycle > self.vblank_ledger.last_clear_cycle)
                    {
                        self.vblank_ledger.race_hold = true;
                    }
                }

                const result = PpuLogic.readRegister(
                    &self.ppu,
                    cart_ptr,
                    address,
                    self.vblank_ledger,
                );
                ppu_read_result = result;
                break :blk result.value;
            },

            // APU and I/O registers ($4000-$4017)
            0x4000...0x4013 => self.bus.open_bus, // APU channels write-only
            0x4014 => self.bus.open_bus, // OAMDMA write-only
            0x4015 => blk: {
                const status = ApuLogic.readStatus(&self.apu);
                ApuLogic.clearFrameIrq(&self.apu);
                // Open bus behavior: reading $4015 should NOT update open_bus
                update_open_bus = false;
                break :blk status;
            },
            0x4016 => self.controller.read1() | (self.bus.open_bus & 0xE0),
            0x4017 => self.controller.read2() | (self.bus.open_bus & 0xE0),

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => blk: {
                if (self.cart) |*cart| {
                    break :blk cart.cpuRead(address);
                }
                if (self.bus.test_ram) |test_ram| {
                    if (address >= 0x8000) {
                        break :blk test_ram[address - 0x8000];
                    }
                }
                break :blk self.bus.open_bus;
            },

            else => self.bus.open_bus,
        };

        // If a PPU read occurred, update the read cycle timestamp
        if (ppu_read_result) |result| {
            if (result.read_2002) {
                const now = self.clock.ppu_cycles;
                self.vblank_ledger.last_read_cycle = now;

                // Note: race_hold is now set BEFORE readRegister() is called above,
                // so the VBlank flag computation sees the correct race condition state
            }
        }

        // All reads update the open bus.
        if (update_open_bus) {
            self.bus.open_bus = value;
        }

        self.debuggerCheckMemoryAccess(address, value, false);
        return value;
    }

    /// Helper to obtain pointer to owned cartridge (if any)
    fn cartPtr(self: *EmulationState) ?*AnyCartridge {
        if (self.cart) |*cart_ref| {
            return cart_ref;
        }
        return null;
    }

    /// Determine if debugger is attached and currently holding execution
    /// Delegates to DebugIntegration.shouldHalt()
    pub fn debuggerShouldHalt(self: *const EmulationState) bool {
        return DebugIntegration.shouldHalt(self);
    }

    /// Public helper for external threads to query pause state
    /// Delegates to DebugIntegration.isPaused()
    pub fn debuggerIsPaused(self: *const EmulationState) bool {
        return DebugIntegration.isPaused(self);
    }

    /// Notify debugger about memory accesses (breakpoint/watchpoint handling)
    /// Delegates to DebugIntegration.checkMemoryAccess()
    fn debuggerCheckMemoryAccess(self: *EmulationState, address: u16, value: u8, is_write: bool) void {
        DebugIntegration.checkMemoryAccess(self, address, value, is_write);
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
            0x2000...0x3FFF => |addr| {
                const reg = addr & 0x07;
                PpuLogic.writeRegister(&self.ppu, cart_ptr, reg, value);
            },

            // APU and I/O registers ($4000-$4017)
            0x4000...0x4003 => |addr| ApuLogic.writePulse1(&self.apu, @intCast(addr & 0x03), value),
            0x4004...0x4007 => |addr| ApuLogic.writePulse2(&self.apu, @intCast(addr & 0x03), value),
            0x4008...0x400B => |addr| ApuLogic.writeTriangle(&self.apu, @intCast(addr & 0x03), value),
            0x400C...0x400F => |addr| ApuLogic.writeNoise(&self.apu, @intCast(addr & 0x03), value),
            0x4010...0x4013 => |addr| ApuLogic.writeDmc(&self.apu, @intCast(addr & 0x03), value),

            0x4014 => {
                const cpu_cycle = self.clock.ppu_cycles / 3;
                const on_odd_cycle = (cpu_cycle & 1) != 0;
                self.dma.trigger(value, on_odd_cycle);
            },

            0x4015 => ApuLogic.writeControl(&self.apu, value),

            0x4016 => {
                self.controller.writeStrobe(value);
            },

            0x4017 => ApuLogic.writeFrameCounter(&self.apu, value),

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => {
                if (self.cart) |*cart| {
                    cart.cpuWrite(address, value);
                } else if (self.bus.test_ram) |test_ram| {
                    if (address >= 0x8000) {
                        test_ram[address - 0x8000] = value;
                    }
                }
            },

            else => {},
        }

        self.debuggerCheckMemoryAccess(address, value, true);
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
    ///
    /// Delegates to BusInspection.peekMemory()
    pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
        return BusInspection.peekMemory(self, address);
    }

    /// Compute next timing step and advance master clock
    /// This is the ONLY function that advances timing in the emulator
    ///
    /// Architecture:
    /// - Captures current timing state BEFORE advancing clock
    /// - Decides how much to advance (1 or 2 cycles for odd frame skip)
    /// - Returns timing metadata for component coordination
    ///
    /// Odd Frame Skip Hardware Behavior:
    /// - On odd frames with rendering enabled, the PPU skips one cycle
    /// - Skip occurs at the transition from scanline 261 dot 340 → scanline 0 dot 0
    /// - Hardware skips the PPU clock tick entirely (no component work for that slot)
    /// - Result: Odd frames are 89,341 cycles, even frames are 89,342 cycles
    ///
    /// Returns: TimingStep with pre-advance scanline/dot and skip flag
    ///
    /// References:
    /// - docs/code-review/clock-advance-refactor-plan.md Section 4.2
    /// - nesdev.org/wiki/PPU_frame_timing (odd frame skip)
    inline fn nextTimingStep(self: *EmulationState) TimingStep {
        // Capture timing state BEFORE clock advancement
        const current_scanline = self.clock.scanline();
        const current_dot = self.clock.dot();

        // Check if this is the odd-frame skip point
        // Hardware: At scanline 261 dot 340, if odd frame + rendering enabled,
        // the NEXT tick skips dot 0 of scanline 0
        const skip_slot = TimingHelpers.shouldSkipOddFrame(
            self.odd_frame,
            self.rendering_enabled,
            current_scanline,
            current_dot,
        );

        // Advance clock by 1 PPU cycle (always happens)
        self.clock.advance(1);

        // If skip condition met, advance by additional 1 cycle
        // This simulates the skipped PPU clock tick
        if (skip_slot) {
            self.clock.advance(1);
        }

        // Build timing step descriptor with PRE-advance position
        // but POST-advance CPU/APU tick flags (since they depend on new clock position)
        const step = TimingStep{
            .scanline = current_scanline,
            .dot = current_dot,
            .cpu_tick = self.clock.isCpuTick(), // ← Checked AFTER advance
            .apu_tick = self.clock.isApuTick(), // ← Checked AFTER advance
            .skip_slot = skip_slot,
        };

        return step;
    }

    /// RT emulation loop - advances state by exactly 1 PPU cycle
    /// This is the core tick function for cycle-accurate emulation
    ///
    /// Architecture (Post-Refactor):
    /// - Delegates timing decisions to nextTimingStep() scheduler
    /// - Early returns on skip_slot (no component work for skipped cycles)
    /// - Components receive already-advanced clock position
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
    ///
    /// References:
    /// - docs/code-review/clock-advance-refactor-plan.md Section 4.3
    pub fn tick(self: *EmulationState) void {
        if (self.debuggerShouldHalt()) {
            return;
        }

        // Compute next timing step and advance clock
        // This is the ONLY place clock advancement happens
        const step = self.nextTimingStep();

        // Process PPU at the POST-advance position (current clock state)
        // VBlank/frame events happen at specific scanline/dot coordinates
        // Hardware: Events trigger when clock IS AT the coordinate, not before
        // PPU processes at (241, 1) to SET VBlank, not at (241, 0)
        const scanline = self.clock.scanline();
        const dot = self.clock.dot();

        var ppu_result = self.stepPpuCycle(scanline, dot);

        // Special handling for odd frame skip:
        // Frame completion happened at (261, 340) but we skipped to (0, 1)
        // Manually set frame_complete flag since PPU didn't see (261, 340)
        if (step.skip_slot) {
            ppu_result.frame_complete = true;
        }

        self.applyPpuCycleResult(ppu_result);

        // Process APU if this is an APU tick (synchronized with CPU)
        // IMPORTANT: APU must tick BEFORE CPU to update IRQ state
        if (step.apu_tick) {
            const apu_result = self.stepApuCycle();
            _ = apu_result; // APU updates its own IRQ flags
        }

        // Process CPU if this is a CPU tick
        if (step.cpu_tick) {
            // Update IRQ line from all sources (level-triggered, reflects current state)
            // IRQ line is HIGH when ANY source is active
            // Note: mapper_irq is polled AFTER CPU execution and updates IRQ state for next cycle
            const apu_frame_irq = self.apu.frame_irq_flag;
            const apu_dmc_irq = self.apu.dmc_irq_flag;

            self.cpu.irq_line = apu_frame_irq or apu_dmc_irq;

            const cpu_result = self.stepCpuCycle();
            // Mapper IRQ is polled after CPU tick and updates IRQ line for next cycle
            if (cpu_result.mapper_irq) {
                self.cpu.irq_line = true;
            }

            if (self.debuggerShouldHalt()) {
                return;
            }
        }
    }

    fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void {
        self.rendering_enabled = result.rendering_enabled;

        if (result.frame_complete) {
            self.frame_complete = true;
            self.odd_frame = !self.odd_frame; // Toggle odd/even frame flag
        }

        if (result.a12_rising) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();
            }
        }

        // Handle VBlank events by updating the ledger's timestamps.
        if (result.nmi_signal) {
            // VBlank flag set at scanline 241 dot 1.
            self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
        }

        if (result.vblank_clear) {
            // VBlank span ends at scanline 261 dot 1 (pre-render).
            self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
            self.vblank_ledger.race_hold = false;
        }
    }

    /// Execute one PPU cycle at explicit scanline/dot position
    /// Post-refactor: All PPU work happens at explicit timing coordinates
    /// This decouples PPU execution from master clock state
    fn stepPpuCycle(self: *EmulationState, scanline: u16, dot: u16) PpuCycleResult {
        var result = PpuCycleResult{};
        const cart_ptr = self.cartPtr();

        const flags = PpuLogic.tick(&self.ppu, scanline, dot, cart_ptr, self.framebuffer);

        // A12 edge detection now handled by PpuLogic.tick()
        result.a12_rising = flags.a12_rising;

        result.rendering_enabled = flags.rendering_enabled;
        if (flags.frame_complete) {
            result.frame_complete = true;

            if (self.clock.frame() < 300 and flags.rendering_enabled and !self.ppu.rendering_was_enabled) {}
        }

        if (flags.rendering_enabled and !self.ppu.rendering_was_enabled) {
            self.ppu.rendering_was_enabled = true;
        }

        self.odd_frame = self.clock.isOddFrame();

        // Pass through PPU event signals to emulation state
        result.nmi_signal = flags.nmi_signal;
        result.vblank_clear = flags.vblank_clear;

        return result;
    }

    fn stepCpuCycle(self: *EmulationState) CpuCycleResult {
        return CpuExecution.stepCycle(self);
    }

    pub fn pollMapperIrq(self: *EmulationState) bool {
        if (self.cart) |*cart| {
            return cart.tickIrq();
        }
        return false;
    }

    /// Test helper: execute a single CPU cycle without advancing the master clock.
    pub fn tickCpu(self: *EmulationState) void {
        _ = self.stepCpuCycle();
    }

    fn stepApuCycle(self: *EmulationState) ApuCycleResult {
        var result = ApuCycleResult{};

        if (ApuLogic.tickFrameCounter(&self.apu)) {
            result.frame_irq = true;
        }

        const dmc_needs_sample = ApuLogic.tickDmc(&self.apu);
        if (dmc_needs_sample) {
            const address = ApuLogic.getSampleAddress(&self.apu);
            self.dmc_dma.triggerFetch(address);
        }

        if (self.apu.dmc_irq_flag) {
            result.dmc_irq = true;
        }

        return result;
    }

    /// Execute CPU micro-operations for the current cycle.
    /// Caller is responsible for clock management.
    fn executeCpuCycle(self: *EmulationState) void {
        CpuExecution.executeCycle(self);
    }

    /// Test helper: Tick CPU with clock advancement
    /// Advances master clock by 3 PPU cycles (1 CPU cycle) then ticks CPU
    /// Use this in CPU-only tests instead of calling tickCpu() directly
    /// Delegates to Helpers.tickCpuWithClock()
    pub fn tickCpuWithClock(self: *EmulationState) void {
        Helpers.tickCpuWithClock(self);
    }

    /// REMOVED: Legacy function that bypassed VBlankLedger
    ///
    /// This function was setting cpu.nmi_line directly, bypassing the VBlankLedger's
    /// edge detection logic. This caused ROMs to never see VBlank because the level
    /// signal would overwrite the latched edge.
    ///
    /// The VBlankLedger is now the ONLY source of truth for NMI state.
    /// Only stepCycle() (via VBlankLedger.shouldAssertNmiLine()) should set cpu.nmi_line.
    /// Tick DMA state machine (called every 3 PPU cycles, same as CPU)
    /// Delegates to DmaLogic.tickOamDma()
    pub fn tickDma(self: *EmulationState) void {
        DmaLogic.tickOamDma(self);
    }

    /// Tick DMC DMA state machine (called every CPU cycle when active)
    /// Delegates to DmaLogic.tickDmcDma()
    ///
    /// Note: Public for testing purposes
    pub fn tickDmcDma(self: *EmulationState) void {
        DmaLogic.tickDmcDma(self);
    }

    /// Emulate a complete frame (convenience wrapper)
    /// Advances emulation until frame_complete flag is set
    /// Returns number of PPU cycles elapsed
    /// Delegates to Helpers.emulateFrame()
    pub fn emulateFrame(self: *EmulationState) u64 {
        return Helpers.emulateFrame(self);
    }

    /// Emulate N CPU cycles (convenience wrapper)
    /// Returns actual PPU cycles elapsed (N × 3)
    /// Delegates to Helpers.emulateCpuCycles()
    pub fn emulateCpuCycles(self: *EmulationState, cpu_cycles: u64) u64 {
        return Helpers.emulateCpuCycles(self, cpu_cycles);
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
