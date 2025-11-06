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

// DMA interaction ledger (exported for unit tests)
pub const DmaInteractionLedger = @import("DmaInteractionLedger.zig").DmaInteractionLedger;

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

    /// DMA interaction ledger for cycle-accurate DMC/OAM DMA conflict tracking
    /// Records DMC interrupt/completion timestamps, OAM pause/resume, interrupted state
    /// Enables isolated side effects pattern for complex DMA interactions
    dma_interaction_ledger: DmaInteractionLedger = .{},

    /// Memory bus state (RAM, open bus, optional test RAM)
    bus: BusState = .{},

    /// Memory handlers (embedded, zero allocation)
    /// Parameter-based pattern like mappers - handlers receive state via parameter
    handlers: struct {
        open_bus: @import("bus/handlers/OpenBusHandler.zig").OpenBusHandler = .{},
        ram: @import("bus/handlers/RamHandler.zig").RamHandler = .{},
        ppu: @import("bus/handlers/PpuHandler.zig").PpuHandler = .{},
        apu: @import("bus/handlers/ApuHandler.zig").ApuHandler = .{},
        controller: @import("bus/handlers/ControllerHandler.zig").ControllerHandler = .{},
        oam_dma: @import("bus/handlers/OamDmaHandler.zig").OamDmaHandler = .{},
        cartridge: @import("bus/handlers/CartridgeHandler.zig").CartridgeHandler = .{},
    } = .{},

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

    /// Enable verbose NMI/VBlank diagnostics (CLI --trace-nmi)
    trace_nmi: bool = false,
    trace_nmi_suppressed_logged: bool = false,

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
        self.bus.open_bus = .{};
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
        self.ppu.warmup_complete = false; // Hardware-accurate: warmup period required after power-on

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
        self.bus.open_bus = .{};
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
        // Capture last read address for DMC corruption (NTSC 2A03 bug)
        self.dmc_dma.last_read_address = address;

        // Dispatch to handlers (parameter-based pattern)
        const value = switch (address) {
            0x0000...0x1FFF => self.handlers.ram.read(self, address),
            0x2000...0x3FFF => self.handlers.ppu.read(self, address),
            0x4000...0x4013 => self.handlers.apu.read(self, address),
            0x4014 => self.handlers.oam_dma.read(self, address),
            0x4015 => self.handlers.apu.read(self, address), // Special: does NOT update open bus
            0x4016, 0x4017 => self.handlers.controller.read(self, address),
            0x4020...0xFFFF => self.handlers.cartridge.read(self, address),
            else => self.handlers.open_bus.read(self, address),
        };

        // Hardware: All reads update open bus (except $4015)
        if (address != 0x4015) {
            self.bus.open_bus.set(value);
        } else {
            self.bus.open_bus.setInternal(value);
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
        // Hardware: All writes update open bus
        self.bus.open_bus.set(value);

        // Dispatch to handlers (parameter-based pattern)
        switch (address) {
            0x0000...0x1FFF => self.handlers.ram.write(self, address, value),
            0x2000...0x3FFF => self.handlers.ppu.write(self, address, value), // NMI management now in handler
            0x4000...0x4013 => self.handlers.apu.write(self, address, value),
            0x4014 => self.handlers.oam_dma.write(self, address, value),
            0x4015 => self.handlers.apu.write(self, address, value),
            0x4016, 0x4017 => self.handlers.controller.write(self, address, value),
            0x4020...0xFFFF => {
                self.handlers.cartridge.write(self, address, value);

                // Sync PPU mirroring after cartridge write
                // Some mappers can change mirroring dynamically
                if (self.cart) |*cart| {
                    self.ppu.mirroring = cart.getMirroring();
                }
            },
            else => {}, // Unmapped - write ignored
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
    /// - Skip occurs at the transition from scanline 261 dot 339 → scanline 0 dot 0 (skips dot 340)
    /// - Hardware skips the PPU clock tick entirely (no component work for that slot)
    /// - Result: Odd frames are 89,341 cycles, even frames are 89,342 cycles
    ///
    /// Returns: TimingStep with pre-advance scanline/dot and skip flag
    ///
    /// References:
    /// - docs/code-review/clock-advance-refactor-plan.md Section 4.2
    /// - nesdev.org/wiki/PPU_frame_timing (odd frame skip)
    inline fn nextTimingStep(self: *EmulationState) TimingStep {
        // Note: Clock advancement now happens in tick() BEFORE this function is called
        // PPU clock advances via PpuLogic.advanceClock() (handles odd frame skip internally)
        // Master clock advances via self.clock.advance() (always +1, monotonic)

        // Build timing step descriptor for CPU/APU coordination
        // skip_slot is always false now (odd frame skip handled in PPU clock)
        const step = TimingStep{
            .scanline = 0, // Unused - kept for API compatibility
            .dot = 0, // Unused - kept for API compatibility
            .cpu_tick = self.clock.isCpuTick(),
            .apu_tick = self.clock.isApuTick(),
            .skip_slot = false, // Odd frame skip handled in PPU clock
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

        // Advance PPU clock first (PPU owns its own timing state)
        // Hardware: PPU has independent clock counters (cycle, scanline, frame_count)
        // Mesen2 reference: NesPpu.cpp Exec() function
        PpuLogic.advanceClock(&self.ppu, self.rendering_enabled);

        // Advance master clock (monotonic counter for timestamps)
        // Master clock always advances by 1 (no skipping - monotonic counter)
        self.clock.advance();

        // Compute next timing step (determines CPU/APU tick flags)
        const step = self.nextTimingStep();

        // HARDWARE SUB-CYCLE EXECUTION ORDER:
        // PPU rendering executes first (pixel output, sprite evaluation, etc.)
        // CPU memory operations execute second (reads/writes including $2002)
        // PPU state updates execute last (VBlank flag set, event timestamps)
        //
        // This matches NES hardware behavior where within a single PPU cycle:
        //   1. CPU Read Operations (if CPU is active this cycle)
        //   2. CPU Write Operations (if CPU is active this cycle)
        //   3. PPU Events (VBlank flag set, sprite evaluation, etc.)
        //   4. End of cycle
        //
        // Reference: https://www.nesdev.org/wiki/PPU_frame_timing

        // Process PPU rendering at the POST-advance position (current PPU clock state)
        // VBlank/frame events happen at specific scanline/dot coordinates
        // Hardware: Events trigger when clock IS AT the coordinate, not before
        // PPU processes at (241, 1) to signal VBlank, not at (241, 0)
        // Now using PPU's own clock fields instead of deriving from master clock
        const scanline = self.ppu.scanline;
        const dot = self.ppu.cycle;

        const ppu_result = self.stepPpuCycle(scanline, dot);

        // Note: Odd frame skip now handled in PPU clock (PpuLogic.advanceClock)
        // Frame completion is detected by PPU when scanline wraps to 0
        // No special handling needed here - PPU sets frame_complete flag correctly

        // Process APU if this is an APU tick (synchronized with CPU)
        // IMPORTANT: APU must tick BEFORE CPU to update IRQ state
        if (step.apu_tick) {
            const apu_result = self.stepApuCycle();
            _ = apu_result; // APU updates its own IRQ flags
        }

        // Process CPU if this is a CPU tick
        // CPU execution happens BEFORE VBlank timestamps are applied.
        // This allows CPU to set prevent_vbl_set_cycle flag via $2002 reads,
        // which is then checked when applying VBlank timestamps below.
        if (step.cpu_tick) {
            // Update IRQ line from all sources (level-triggered, reflects current state)
            // IRQ line is HIGH when ANY source is active
            // Poll mapper IRQ BEFORE CPU execution so CPU sees it this cycle
            const apu_frame_irq = self.apu.frame_irq_flag;
            const apu_dmc_irq = self.apu.dmc_irq_flag;
            const mapper_irq = self.pollMapperIrq();

            self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

            _ = self.stepCpuCycle();

            if (self.debuggerShouldHalt()) {
                return;
            }
        }

        // CRITICAL FIX: Apply VBlank timestamps AFTER CPU execution
        // This ensures prevent_vbl_set_cycle flag (set by $2002 reads) is respected.
        //
        // Mesen2 reference: NesPpu.cpp UpdateStatusFlag() (line 590-592)
        // sets _preventVblFlag when reading $2002 at cycle 0, then at cycle 1
        // checks if(!_preventVblFlag) before setting VerticalBlank flag (line 1340-1344).
        //
        // Our implementation: CPU reads $2002 and sets prevent_vbl_set_cycle,
        // then we apply VBlank timestamps which checks the prevention flag.
        //
        // Race condition timeline:
        //   dot 0: CPU reads $2002 → sets prevent_vbl_set_cycle
        //   dot 1: Apply VBlank → checks prevent_vbl_set_cycle → skip setting flag
        self.applyVBlankTimestamps(ppu_result);

        // Update NMI line EVERY cycle after VBlank flag is finalized
        // This ensures NMI line always reflects current VBlank/PPUCTRL state
        // BUG FIX: Previously only updated on CPU ticks, causing NMI line to lag
        // when VBlank sets on non-CPU-tick cycles
        // Uses isFlagVisible() because reading $2002 should keep NMI line low
        // The immediate trigger in PpuHandler uses isActive() for the enable-during-VBlank case
        const vblank_flag_visible = self.vblank_ledger.isFlagVisible();
        const nmi_line_should_assert = vblank_flag_visible and self.ppu.ctrl.nmi_enable;
        self.cpu.nmi_line = nmi_line_should_assert;

        // Sample interrupt lines ONLY on CPU ticks (not during interrupt sequence)
        // This follows the "second-to-last cycle" rule for CPU interrupt polling
        // CRITICAL: Do NOT sample during interrupt sequence!
        // The interrupt sequence (cycles 0-6) must preserve the interrupt type
        // that triggered it, even if interrupt lines change mid-sequence.
        if (step.cpu_tick and self.cpu.state != .interrupt_sequence) {
            // Sample interrupt lines for next cycle (following "second-to-last cycle" rule)
            // Mesen2 reference: EndCpuCycle() line 306-309
            // checkInterrupts() handles:
            // - NMI edge detection (0→1 transition on nmi_line)
            // - IRQ level detection (high on irq_line with I flag check)
            CpuLogic.checkInterrupts(&self.cpu);

            // Store interrupt states for next cycle
            self.cpu.nmi_pending_prev = (self.cpu.pending_interrupt == .nmi);
            self.cpu.irq_pending_prev = (self.cpu.pending_interrupt == .irq);

            // Clear pending for this cycle - will be restored from _prev next cycle
            self.cpu.pending_interrupt = .none;
        }

        // Apply remaining PPU state changes AFTER CPU execution
        // This ensures rendering_enabled and other state reflects CPU register
        // writes from this cycle (e.g., PPUMASK writes).
        self.applyPpuRenderingState(ppu_result);
    }

    /// Apply VBlank timestamps AFTER CPU execution
    /// This ensures prevention flag (set by $2002 reads) is respected.
    fn applyVBlankTimestamps(self: *EmulationState, result: PpuCycleResult) void {
        // Handle VBlank events by updating the ledger's timestamps.
        if (result.nmi_signal) {
            // VBlank flag set at scanline 241 dot 1.
            // CRITICAL: Check prevention flag before setting
            // Per Mesen2 NesPpu.cpp:1340-1344: if(!_preventVblFlag) { set flag }
            // Hardware: Read during race window (dots 0-2) prevents flag set
            //
            // PHASE-INDEPENDENT PREVENTION:
            // In different phases, CPU ticks at different dots during race window:
            // - Phase 0: CPU ticks at dot 0 (before VBlank set at dot 1)
            // - Phase 1: CPU ticks at dot 1 (AT VBlank set)
            // - Phase 2: CPU ticks at dot 2 (AFTER VBlank set at dot 1)
            //
            // Solution: Check if prevent_vbl_set_cycle is non-zero (was set this frame).
            // The flag is cleared at frame boundaries, so non-zero means CPU read during race window.
            const prevent_cycle = self.vblank_ledger.prevent_vbl_set_cycle;
            const should_prevent = prevent_cycle != 0 and prevent_cycle == self.clock.master_cycles;
            if (!should_prevent) {
                self.vblank_ledger.last_set_cycle = self.clock.master_cycles;
            }
            // One-shot: ALWAYS clear prevention flag after checking (match Mesen2 exactly)
            // Per Mesen2 NesPpu.cpp:1344: _preventVblFlag = false (unconditional)
            self.vblank_ledger.prevent_vbl_set_cycle = 0;
        }

        if (result.vblank_clear) {
            // VBlank span ends at scanline 261 dot 1 (pre-render).
            // Use master_cycles (monotonic) for timestamp
            self.vblank_ledger.last_clear_cycle = self.clock.master_cycles;
        }
    }

    /// Apply PPU rendering state AFTER CPU execution
    /// This ensures state reflects CPU register writes from this cycle.
    fn applyPpuRenderingState(self: *EmulationState, result: PpuCycleResult) void {
        self.rendering_enabled = result.rendering_enabled;

        if (result.frame_complete) {
            self.frame_complete = true;
            self.vblank_ledger.prevent_vbl_set_cycle = 0;
            // odd_frame is set in stepPpuCycle() based on frame_count (line 862)
            // Don't toggle here - it would conflict with the frame_count-based assignment
        }

        if (result.a12_rising) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();
            }
        }
    }

    /// Execute one PPU cycle at explicit scanline/dot position
    /// Post-refactor: All PPU work happens at explicit timing coordinates
    /// This decouples PPU execution from master clock state
    fn stepPpuCycle(self: *EmulationState, scanline: i16, dot: u16) PpuCycleResult {
        var result = PpuCycleResult{};
        const cart_ptr = self.cartPtr();

        const flags = PpuLogic.tick(&self.ppu, scanline, dot, cart_ptr, self.framebuffer);

        // A12 edge detection now handled by PpuLogic.tick()
        result.a12_rising = flags.a12_rising;

        result.rendering_enabled = flags.rendering_enabled;
        if (flags.frame_complete) {
            result.frame_complete = true;

            if (self.ppu.frame_count < 300 and flags.rendering_enabled and !self.ppu.rendering_was_enabled) {}
        }

        if (flags.rendering_enabled and !self.ppu.rendering_was_enabled) {
            self.ppu.rendering_was_enabled = true;
        }

        self.odd_frame = (self.ppu.frame_count & 1) == 1;

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

// Properly link tests to this module with out adding a dummy test to the count.

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
