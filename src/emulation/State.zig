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

// Bus state
const BusState = @import("state/BusState.zig").BusState;

// Peripheral state (re-exported for tests and external use)
pub const ControllerState = @import("state/peripherals/ControllerState.zig").ControllerState;

// CPU microstep functions
const CpuMicrosteps = @import("../cpu/Microsteps.zig");

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
        self.controller.reset();

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
        self.bus.open_bus = .{};
        self.dma.reset();
        self.controller.reset();

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
        self.dma.dmc.last_read_address = address;

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

    /// Dummy read - hardware-accurate 6502 bus access where value is not used
    /// The 6502 performs reads during addressing calculations but discards the value
    pub inline fn dummyRead(self: *EmulationState, address: u16) void {
        _ = self.busRead(address);
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

        // ===================================================================
        // CPU EXECUTION (Black Box Pattern - Phase 1-5 Refactor Complete)
        // ===================================================================
        // Architecture: Signal-based coordination matching PPU pattern
        // - EmulationState computes input signals from peripheral sources
        // - EmulationState wires signals to CPU inputs (cpu.rdy_line, cpu.irq_line)
        // - CPU executes as self-contained black box
        // - EmulationState reads output signals (instruction_complete, bus_cycle_complete)
        //
        // Input Signal Sources:
        //   cpu.nmi_line: PPU (wired at end of tick - line 508)
        //   cpu.irq_line: APU frame_irq | APU dmc_irq | Mapper IRQ
        //   cpu.rdy_line: DMA coordination (DMC DMA | OAM DMA)
        //
        // Output Signals (read by debugger/DMA, not by EmulationState currently):
        //   cpu.instruction_complete: Set when instruction finishes
        //   cpu.bus_cycle_complete: Set each bus cycle
        //   cpu.halted: Set when CPU halts (JAM/KIL or DMA)
        // ===================================================================
        if (step.cpu_tick) {
            // === Peripheral Coordination ===
            self.stepApuCycle();

            // === DMA (Black Box) ===
            DmaLogic.tick(&self.dma, self.clock.master_cycles, self, &self.apu);

            // === Input Signal Wiring ===
            // Wire RDY line from DMA output (low = CPU halted)
            self.cpu.rdy_line = self.dma.rdy_line;

            // Compute IRQ line from all sources (high = interrupt requested)
            const apu_frame_irq = self.apu.frame_irq_flag;
            const apu_dmc_irq = self.apu.dmc_irq_flag;
            const mapper_irq = self.pollMapperIrq();
            self.cpu.irq_line = apu_frame_irq or apu_dmc_irq or mapper_irq;

            // === CPU Execution (Black Box) ===
            const debugger_ptr = if (self.debugger) |*dbg| dbg else null;
            CpuExecution.stepCycle(&self.cpu, self, debugger_ptr);

            // === Post-Execution Interrupt Sampling ===
            // Hardware "second-to-last cycle" rule: Sample interrupt lines AFTER execution
            // This gives instructions one cycle to complete after register writes (e.g., STA $2000)
            // Reference: nesdev.org/wiki/CPU_interrupts, Mesen2 NesCpu.cpp:311-314
            if (self.cpu.state != .interrupt_sequence) {
                CpuLogic.checkInterrupts(&self.cpu);
            }
        }

        // Advance PPU clock first (PPU owns its own timing state)
        // Hardware: PPU has independent clock counters (cycle, scanline, frame_count)
        PpuLogic.advanceClock(&self.ppu);

        // Process PPU rendering (PPU manages its own state internally)
        const cart_ptr = self.cartPtr();
        PpuLogic.tick(&self.ppu, self.clock.master_cycles, cart_ptr);

        // Wire PPU NMI output signal to CPU NMI input
        self.cpu.nmi_line = self.ppu.nmi_line;
    }

    pub fn pollMapperIrq(self: *EmulationState) bool {
        if (self.cart) |*cart| {
            return cart.tickIrq();
        }
        return false;
    }

    fn stepApuCycle(self: *EmulationState) void {
        // Tick APU frame counter (drives length counters, envelopes, sweeps at ~120Hz/~240Hz)
        // Frame IRQ flag is set internally and read at line 469-472
        ApuLogic.tickFrameCounter(&self.apu);

        // Tick DMC channel (drives sample playback and DMA triggers)
        const dmc_needs_sample = ApuLogic.tickDmc(&self.apu);
        if (dmc_needs_sample) {
            const address = ApuLogic.getSampleAddress(&self.apu);
            self.dma.dmc.triggerFetch(address);
        }
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
