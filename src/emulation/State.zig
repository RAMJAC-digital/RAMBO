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
const PpuRuntime = @import("Ppu.zig");
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

// Bus routing logic
const BusRouting = @import("bus/routing.zig");

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

// VBlank timing ledger
const VBlankLedger = @import("state/VBlankLedger.zig").VBlankLedger;

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

    /// Latched PPU NMI level (asserted while VBlank active and enabled)
    ppu_nmi_active: bool = false,

    /// VBlank timestamp ledger for cycle-accurate NMI edge detection
    /// Records VBlank set/clear, $2002 reads, PPUCTRL writes with master clock timestamps
    /// Decouples CPU NMI latch from readable PPU status flag
    vblank_ledger: VBlankLedger = .{},

    /// PPU A12 state (for MMC3 IRQ detection)
    /// Bit 12 of PPU address - transitions during tile fetches
    /// MMC3 IRQ counter decrements on rising edge (0→1)
    /// Moved here from old ppu_timing struct (timing now in MasterClock)
    ppu_a12_state: bool = false,

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
    pub fn reset(self: *EmulationState) void {
        self.clock.reset();
        self.frame_complete = false;
        self.odd_frame = false;
        self.rendering_enabled = false;
        self.ppu_a12_state = false;
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
        self.apu.reset();
        self.ppu_nmi_active = false;
        self.cpu.nmi_line = false;
    }

    /// Recompute derived signal lines after manual state mutation (testing/debug)
    pub fn syncDerivedSignals(self: *EmulationState) void {
        self.refreshPpuNmiLevel();
    }

    // =========================================================================
    // Bus Routing (inline logic - no separate abstraction)
    // =========================================================================

    /// Read from NES memory bus
    /// Routes to appropriate component and updates open bus
    pub inline fn busRead(self: *EmulationState, address: u16) u8 {
        const value = BusRouting.busRead(self, address);
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
        BusRouting.busWrite(self, address, value);

        // Track PPUCTRL writes for VBlank ledger
        // Writing to $2000 can change nmi_enable, which affects NMI generation
        // per nesdev.org: toggling NMI enable during VBlank can trigger NMI
        if (address >= 0x2000 and address <= 0x3FFF and (address & 0x07) == 0x00) {
            const old_enabled = self.ppu.ctrl.nmi_enable;
            const new_enabled = (value & 0x80) != 0;
            self.vblank_ledger.recordCtrlToggle(self.clock.ppu_cycles, old_enabled, new_enabled);
            self.refreshPpuNmiLevel();
        }

        self.debuggerCheckMemoryAccess(address, value, true);
    }

    /// Read 16-bit value (little-endian)
    /// Used for reading interrupt vectors and 16-bit operands
    pub inline fn busRead16(self: *EmulationState, address: u16) u16 {
        return BusRouting.busRead16(self, address);
    }

    /// Read 16-bit value with JMP indirect page wrap bug
    /// The 6502 has a bug where JMP ($xxFF) wraps within the page
    pub inline fn busRead16Bug(self: *EmulationState, address: u16) u16 {
        return BusRouting.busRead16Bug(self, address);
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
        var ppu_result = self.stepPpuCycle(self.clock.scanline(), self.clock.dot());

        // Special handling for odd frame skip:
        // Frame completion happened at (261, 340) but we skipped to (0, 1)
        // Manually set frame_complete flag since PPU didn't see (261, 340)
        if (step.skip_slot) {
            ppu_result.frame_complete = true;
        }

        self.applyPpuCycleResult(ppu_result);

        // Process CPU if this is a CPU tick
        if (step.cpu_tick) {
            const cpu_result = self.stepCpuCycle();
            if (cpu_result.mapper_irq) {
                self.cpu.irq_line = true;
            }
            if (self.debuggerShouldHalt()) {
                return;
            }
        }

        // Process APU if this is an APU tick (synchronized with CPU)
        if (step.apu_tick) {
            const apu_result = self.stepApuCycle();
            if (apu_result.frame_irq or apu_result.dmc_irq) {
                self.cpu.irq_line = true;
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

        // Handle VBlank events with timestamp ledger
        // Post-refactor: Record events with master clock cycles for deterministic NMI
        // Ledger is single source of truth - no local nmi_latched flag
        if (result.nmi_signal) {
            // VBlank flag set at scanline 241 dot 1
            // Pass current NMI enable state for edge detection
            // Ledger internally manages nmi_edge_pending flag
            const nmi_enabled = self.ppu.ctrl.nmi_enable;
            self.vblank_ledger.recordVBlankSet(self.clock.ppu_cycles, nmi_enabled);
        }

        if (result.vblank_clear) {
            // VBlank span ends at scanline 261 dot 1 (pre-render)
            self.vblank_ledger.recordVBlankSpanEnd(self.clock.ppu_cycles);
            self.refreshPpuNmiLevel();
        }
    }

    /// Execute one PPU cycle at explicit scanline/dot position
    /// Post-refactor: All PPU work happens at explicit timing coordinates
    /// This decouples PPU execution from master clock state
    fn stepPpuCycle(self: *EmulationState, scanline: u16, dot: u16) PpuCycleResult {
        var result = PpuCycleResult{};
        const cart_ptr = self.cartPtr();

        const old_a12 = self.ppu_a12_state;
        const flags = PpuRuntime.tick(&self.ppu, scanline, dot, cart_ptr, self.framebuffer);

        const new_a12 = (self.ppu.internal.v & 0x1000) != 0;
        self.ppu_a12_state = new_a12;
        if (!old_a12 and new_a12) {
            result.a12_rising = true;
        }

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

    /// Synchronize CPU NMI input with current PPU status/CTRL configuration
    /// Hardware: NMI line is a LEVEL signal (high when vblank AND nmi_enable)
    /// The CPU latches the falling EDGE separately (handled by nmi_latched flag)
    fn refreshPpuNmiLevel(self: *EmulationState) void {
        // NMI line reflects current hardware state (level signal)
        const active = self.ppu.status.vblank and self.ppu.ctrl.nmi_enable;
        self.ppu_nmi_active = active;
        self.cpu.nmi_line = active;

        // Edge detection is handled separately by VBlankLedger and nmi_latched flag
        // Reading $2002 clears the level but not the latched edge
    }

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
