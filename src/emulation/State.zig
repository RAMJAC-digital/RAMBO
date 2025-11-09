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
const CpuExecution = @import("../cpu/Execution.zig");

// DMA subsystem (black box pattern - consolidated module)
const DmaModule = @import("../dma/Dma.zig");
const DmaState = DmaModule.State.DmaState;
const DmaLogic = DmaModule.Logic;

// Bus module (black box pattern - consolidated module)
const BusModule = @import("../bus/Bus.zig");
const BusState = BusModule.State.State;
const BusLogic = BusModule.Logic;
const BusInspection = BusModule.Inspection;

// Controller module (black box pattern - consolidated module)
const ControllerModule = @import("../controller/Controller.zig");
const ControllerState = ControllerModule.State.ControllerState;
const ControllerLogic = ControllerModule.Logic;

// CPU microstep functions
const CpuMicrosteps = @import("../cpu/Microsteps.zig");

// Debugger integration (breakpoints, watchpoints, pause management)
const DebugIntegration = @import("debug/integration.zig");

// Emulation helpers (convenience wrappers for testing/benchmarking)
const Helpers = @import("helpers.zig");

// Timing structures and helpers
const Timing = @import("state/Timing.zig");
const TimingStep = Timing.TimingStep;
const TimingHelpers = Timing.TimingHelpers;

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

    /// DMA state (OAM DMA + DMC DMA + interaction tracking + RDY line output)
    /// Consolidated DMA subsystem following PPU black box pattern
    dma: DmaState = .{},

    /// Memory bus state (RAM, open bus, handlers, optional test RAM)
    /// Bus module owns routing logic following black box pattern
    bus: BusState = .{},

    /// Cartridge (direct ownership)
    /// Supports all mappers via tagged union dispatch
    cart: ?AnyCartridge = null,

    /// Controller state (shift registers, strobe, buttons)
    controller: ControllerState = .{},

    /// Optional debugger for breakpoints/watchpoints (RT-safe, zero allocations in hot path)
    debugger: ?Debugger.Debugger = null,

    /// Debug break occurred flag (checked by EmulationThread to post events)
    debug_break_occurred: bool = false,

    /// Hardware configuration (immutable during emulation)
    config: *const Config.Config,

    /// Enable verbose NMI/VBlank diagnostics (CLI --trace-nmi)
    trace_nmi: bool = false,
    trace_nmi_suppressed_logged: bool = false,

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
        self.bus.open_bus = .{};
        self.dma.reset();
        ControllerLogic.power_on(&self.controller);

        const reset_vector = self.busRead16(0xFFFC);
        CpuLogic.power_on(&self.cpu, reset_vector);

        PpuLogic.power_on(&self.ppu);

        ApuLogic.reset(&self.apu);
        self.cpu.nmi_line = false;
        self.cpu.irq_line = false; // Hardware-accurate: IRQ line low after power-on
    }

    /// Reset emulation to reset state
    /// Loads PC from RESET vector ($FFFC-$FFFD)
    pub fn reset(self: *EmulationState) void {
        self.clock.reset();
        self.bus.open_bus = .{};
        self.dma.reset();
        ControllerLogic.reset(&self.controller);

        const reset_vector = self.busRead16(0xFFFC);
        CpuLogic.reset(&self.cpu, reset_vector);

        PpuLogic.reset(&self.ppu);

        ApuLogic.reset(&self.apu);
        self.cpu.nmi_line = false;
        self.cpu.irq_line = false; // Hardware-accurate: IRQ line low after reset
    }

    // =========================================================================
    // Bus Routing (inline logic - no separate abstraction)
    // =========================================================================

    /// Read from NES memory bus
    /// Delegates to Bus module
    pub inline fn busRead(self: *EmulationState, address: u16) u8 {
        return BusLogic.read(&self.bus, self, address);
    }

    /// Dummy read - hardware-accurate 6502 bus access where value is not used
    /// Delegates to Bus module
    pub inline fn dummyRead(self: *EmulationState, address: u16) void {
        BusLogic.dummyRead(&self.bus, self, address);
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
    /// Delegates to Bus module
    pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) void {
        BusLogic.write(&self.bus, self, address, value);
    }

    /// Read 16-bit value (little-endian)
    /// Delegates to Bus module
    pub inline fn busRead16(self: *EmulationState, address: u16) u16 {
        return BusLogic.read16(&self.bus, self, address);
    }

    /// Peek memory without side effects (for debugging/inspection)
    /// Delegates to Bus module
    pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
        return BusInspection.peek(&self.bus, self, address);
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
    /// - Skip occurs at the transition from scanline 261 dot 339 → scanline 0 dot 0 (skips dot 340)
    /// - Hardware skips the PPU clock tick entirely (no component work for that slot)
    /// - Result: Odd frames are 89,341 cycles, even frames are 89,342 cycles
    ///
    /// Returns: TimingStep with pre-advance scanline/dot and skip flag
    ///
    /// References:
    /// - [PPU Odd Frame Skip](https://nesdev.org/wiki/PPU_frame_timing)
    inline fn nextTimingStep(self: *EmulationState) TimingStep {
        // Note: Clock advancement now happens in tick() BEFORE this function is called
        // PPU clock advances via PpuLogic.advanceClock() (handles odd frame skip internally)
        // Master clock advances via self.clock.advance() (always +1, monotonic)

        // Build timing step descriptor for CPU/APU coordination
        // skip_slot is always false now (odd frame skip handled in PPU clock)
        const step = TimingStep{ .cpu_tick = self.clock.isCpuTick() };

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
            return {};
        }
        PpuLogic.advanceClock(&self.ppu, self.clock.master_cycles);
        // Compute timing step (determines CPU/APU tick flags)
        const step = self.nextTimingStep();

        // HARDWARE SUB-CYCLE EXECUTION ORDER:
        // Components execute on current cycle before clock advances
        // This matches NES hardware behavior where within a single PPU cycle:
        //   1. CPU Read Operations (if CPU is active this cycle)
        //   2. CPU Write Operations (if CPU is active this cycle)
        //   3. PPU Events (VBlank flag set, sprite evaluation, etc.)
        //   4. End of cycle (clock advances)
        //
        // Reference: https://www.nesdev.org/wiki/PPU_frame_timing

        // CPU coordination (APU, DMA, signal wiring, CPU execution)
        if (step.cpu_tick) {
            self.tickCpu();
        }

        // Process PPU rendering (PPU manages its own state internally)
        const cart_ptr = self.cartPtr();
        PpuLogic.updatePPU(&self.ppu, self.clock.master_cycles, cart_ptr);

        // Signal routing (updates NMI from PPU output)
        self.wireSignals();

        // Advance master clock last (components execute on current cycle, then advance)
        self.clock.advance();
    }

    /// CPU coordination: APU, DMA, signal wiring, and CPU execution
    fn tickCpu(self: *EmulationState) void {
        // APU frame counter and DMC
        self.tickApu();

        // DMA coordination
        self.tickDma();

        // Signal routing (RDY, IRQ, NMI)
        self.wireSignals();

        // CPU execution (handles interrupt sampling internally)
        const debugger_ptr = if (self.debugger) |*dbg| dbg else null;
        CpuExecution.stepCycle(&self.cpu, self, debugger_ptr);
    }

    pub fn pollMapperIrq(self: *EmulationState) bool {
        if (self.cart) |*cart| {
            return cart.tickIrq();
        }
        return false;
    }

    /// APU frame counter and DMC coordination
    fn tickApu(self: *EmulationState) void {
        // Tick APU frame counter (drives length counters, envelopes, sweeps at ~120Hz/~240Hz)
        ApuLogic.tickFrameCounter(&self.apu);

        // Tick DMC channel (drives sample playback and DMA triggers)
        const dmc_needs_sample = ApuLogic.tickDmc(&self.apu);
        if (dmc_needs_sample) {
            const address = ApuLogic.getSampleAddress(&self.apu);
            self.dma.dmc.triggerFetch(address);
        }
    }

    /// DMA coordination (OAM DMA and DMC DMA)
    fn tickDma(self: *EmulationState) void {
        DmaLogic.tick(&self.dma, self.clock.master_cycles, self, &self.apu);
    }

    /// Signal routing between subsystems
    fn wireSignals(self: *EmulationState) void {
        // Wire RDY line from DMA output (low = CPU halted)
        self.cpu.rdy_line = self.dma.rdy_line;

        // Compute and wire IRQ line from all sources (high = interrupt requested)
        const apu_frame_irq = self.apu.frame_irq_flag;
        const apu_dmc_irq = self.apu.dmc_irq_flag;
        const mapper_irq = self.pollMapperIrq();
        self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

        // Wire NMI line from PPU output
        self.cpu.nmi_line = self.ppu.nmi_line;
    }

    /// Test helper: Tick CPU with clock advancement
    /// Advances master clock by 3 PPU cycles (1 CPU cycle) then ticks CPU
    /// Use this in CPU-only tests instead of calling tickCpu() directly
    /// Delegates to Helpers.tickCpuWithClock()
    pub fn tickCpuWithClock(self: *EmulationState) void {
        Helpers.tickCpuWithClock(self);
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

// Properly link tests to this module with out adding a dummy test to the count.

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
