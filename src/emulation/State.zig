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
    pub fn debuggerShouldHalt(self: *const EmulationState) bool {
        if (self.debugger) |*debugger| {
            return debugger.isPaused();
        }
        return false;
    }

    /// Public helper for external threads to query pause state
    pub fn debuggerIsPaused(self: *const EmulationState) bool {
        return self.debuggerShouldHalt();
    }

    /// Notify debugger about memory accesses (breakpoint/watchpoint handling)
    fn debuggerCheckMemoryAccess(self: *EmulationState, address: u16, value: u8, is_write: bool) void {
        if (self.debugger) |*debugger| {
            if (!debugger.hasMemoryTriggers()) {
                return;
            }
            const should_break = debugger.checkMemoryAccess(self, address, value, is_write) catch false;
            if (should_break) {
                self.debug_break_occurred = true;
            }
        }
    }

    /// Write to NES memory bus
    /// Routes to appropriate component and updates open bus
    pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) void {
        BusRouting.busWrite(self, address, value);
        // Refresh NMI level on $2000 (PPUCTRL) writes only
        // Writing to $2000 can change nmi_enable, which affects NMI generation
        // per nesdev.org: toggling NMI enable during VBlank can trigger NMI
        if (address >= 0x2000 and address <= 0x3FFF and (address & 0x07) == 0x00) {
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
        if (self.debuggerShouldHalt()) {
            return;
        }

        // Always advance by exactly 1 cycle
        self.clock.advance(1);

        const cpu_tick = self.clock.isCpuTick();

        // Hardware quirk: Odd frame skip
        // On odd frames with rendering enabled, scanline 0 dot 0 is skipped
        // Check AFTER advancing, and skip processing if at 0.0 on odd frame
        const skip_odd_frame = self.odd_frame and self.rendering_enabled and
            self.clock.scanline() == 0 and self.clock.dot() == 0;

        if (!skip_odd_frame) {
            // Process PPU at current clock position
            const ppu_result = self.stepPpuCycle();
            self.applyPpuCycleResult(ppu_result);
        }

        if (cpu_tick) {
            const cpu_result = self.stepCpuCycle();
            if (cpu_result.mapper_irq) {
                self.cpu.irq_line = true;
            }
            if (self.debuggerShouldHalt()) {
                return;
            }
        }

        if (cpu_tick) {
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
        }

        if (result.a12_rising) {
            if (self.cart) |*cart| {
                cart.ppuA12Rising();
            }
        }

        // Handle VBlank events and update NMI line
        // On VBlank start/end, recompute NMI level based on current PPU state
        // This ensures proper edge detection in CpuLogic.checkInterrupts()
        if (result.nmi_signal or result.vblank_clear) {
            self.refreshPpuNmiLevel();
        }
    }

    fn stepPpuCycle(self: *EmulationState) PpuCycleResult {
        var result = PpuCycleResult{};
        const cart_ptr = self.cartPtr();
        const scanline = self.clock.scanline();
        const dot = self.clock.dot();

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

    // ========================================================================
    // PRIVATE MICROSTEP HELPERS
    // ========================================================================
    // CPU MICROSTEP WRAPPERS
    // Inline delegation to cpu/microsteps.zig for all 40 atomic operations
    // ========================================================================
    pub fn fetchOperandLow(self: *EmulationState) bool {
        return CpuMicrosteps.fetchOperandLow(self);
    }

    pub fn fetchAbsLow(self: *EmulationState) bool {
        return CpuMicrosteps.fetchAbsLow(self);
    }

    pub fn fetchAbsHigh(self: *EmulationState) bool {
        return CpuMicrosteps.fetchAbsHigh(self);
    }

    pub fn addXToZeroPage(self: *EmulationState) bool {
        return CpuMicrosteps.addXToZeroPage(self);
    }

    pub fn addYToZeroPage(self: *EmulationState) bool {
        return CpuMicrosteps.addYToZeroPage(self);
    }

    pub fn calcAbsoluteX(self: *EmulationState) bool {
        return CpuMicrosteps.calcAbsoluteX(self);
    }

    pub fn calcAbsoluteY(self: *EmulationState) bool {
        return CpuMicrosteps.calcAbsoluteY(self);
    }

    pub fn fixHighByte(self: *EmulationState) bool {
        return CpuMicrosteps.fixHighByte(self);
    }

    pub fn fetchZpBase(self: *EmulationState) bool {
        return CpuMicrosteps.fetchZpBase(self);
    }

    pub fn addXToBase(self: *EmulationState) bool {
        return CpuMicrosteps.addXToBase(self);
    }

    pub fn fetchIndirectLow(self: *EmulationState) bool {
        return CpuMicrosteps.fetchIndirectLow(self);
    }

    pub fn fetchIndirectHigh(self: *EmulationState) bool {
        return CpuMicrosteps.fetchIndirectHigh(self);
    }

    pub fn fetchZpPointer(self: *EmulationState) bool {
        return CpuMicrosteps.fetchZpPointer(self);
    }

    pub fn fetchPointerLow(self: *EmulationState) bool {
        return CpuMicrosteps.fetchPointerLow(self);
    }

    pub fn fetchPointerHigh(self: *EmulationState) bool {
        return CpuMicrosteps.fetchPointerHigh(self);
    }

    pub fn addYCheckPage(self: *EmulationState) bool {
        return CpuMicrosteps.addYCheckPage(self);
    }

    pub fn pullByte(self: *EmulationState) bool {
        return CpuMicrosteps.pullByte(self);
    }

    pub fn stackDummyRead(self: *EmulationState) bool {
        return CpuMicrosteps.stackDummyRead(self);
    }

    pub fn pushPch(self: *EmulationState) bool {
        return CpuMicrosteps.pushPch(self);
    }

    pub fn pushPcl(self: *EmulationState) bool {
        return CpuMicrosteps.pushPcl(self);
    }

    pub fn pushStatusBrk(self: *EmulationState) bool {
        return CpuMicrosteps.pushStatusBrk(self);
    }

    pub fn pushStatusInterrupt(self: *EmulationState) bool {
        return CpuMicrosteps.pushStatusInterrupt(self);
    }

    pub fn pullPcl(self: *EmulationState) bool {
        return CpuMicrosteps.pullPcl(self);
    }

    pub fn pullPch(self: *EmulationState) bool {
        return CpuMicrosteps.pullPch(self);
    }

    pub fn pullPchRti(self: *EmulationState) bool {
        return CpuMicrosteps.pullPchRti(self);
    }

    pub fn pullStatus(self: *EmulationState) bool {
        return CpuMicrosteps.pullStatus(self);
    }

    pub fn incrementPcAfterRts(self: *EmulationState) bool {
        return CpuMicrosteps.incrementPcAfterRts(self);
    }

    pub fn jsrStackDummy(self: *EmulationState) bool {
        return CpuMicrosteps.jsrStackDummy(self);
    }

    pub fn fetchAbsHighJsr(self: *EmulationState) bool {
        return CpuMicrosteps.fetchAbsHighJsr(self);
    }

    pub fn fetchIrqVectorLow(self: *EmulationState) bool {
        return CpuMicrosteps.fetchIrqVectorLow(self);
    }

    pub fn fetchIrqVectorHigh(self: *EmulationState) bool {
        return CpuMicrosteps.fetchIrqVectorHigh(self);
    }

    pub fn rmwRead(self: *EmulationState) bool {
        return CpuMicrosteps.rmwRead(self);
    }

    pub fn rmwDummyWrite(self: *EmulationState) bool {
        return CpuMicrosteps.rmwDummyWrite(self);
    }

    pub fn branchFetchOffset(self: *EmulationState) bool {
        return CpuMicrosteps.branchFetchOffset(self);
    }

    pub fn branchAddOffset(self: *EmulationState) bool {
        return CpuMicrosteps.branchAddOffset(self);
    }

    pub fn branchFixPch(self: *EmulationState) bool {
        return CpuMicrosteps.branchFixPch(self);
    }

    pub fn jmpIndirectFetchLow(self: *EmulationState) bool {
        return CpuMicrosteps.jmpIndirectFetchLow(self);
    }

    pub fn jmpIndirectFetchHigh(self: *EmulationState) bool {
        return CpuMicrosteps.jmpIndirectFetchHigh(self);
    }

    // END PRIVATE MICROSTEP HELPERS
    // ========================================================================

    /// Execute CPU micro-operations for the current cycle.
    /// Caller is responsible for clock management.
    fn executeCpuCycle(self: *EmulationState) void {
        CpuExecution.executeCycle(self);
    }

    /// Test helper: Tick CPU with clock advancement
    /// Advances master clock by 3 PPU cycles (1 CPU cycle) then ticks CPU
    /// Use this in CPU-only tests instead of calling tickCpu() directly
    pub fn tickCpuWithClock(self: *EmulationState) void {
        self.clock.advance(3); // 1 CPU cycle = 3 PPU cycles
        self.tickCpu();
    }

    /// Synchronize CPU NMI input with current PPU status/CTRL configuration
    fn refreshPpuNmiLevel(self: *EmulationState) void {
        const active = self.ppu.status.vblank and self.ppu.ctrl.nmi_enable;
        self.ppu_nmi_active = active;
        self.cpu.nmi_line = active;
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
    pub fn tickDma(self: *EmulationState) void {
        // CPU cycle count removed - time tracked by MasterClock
        // No increment needed - clock is advanced in tick()

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
        // CPU cycle count removed - time tracked by MasterClock
        // No increment needed - clock is advanced in tick()

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

        if (self.debuggerShouldHalt()) {
            return 0;
        }

        // Advance until VBlank (scanline 241, dot 1)
        // NTSC: 89,342 PPU cycles per frame
        // PAL: 106,392 PPU cycles per frame
        while (!self.frame_complete) {
            self.tick();
            if (self.debuggerShouldHalt()) {
                break;
            }

            // Safety: Prevent infinite loop if something goes wrong
            // Maximum frame cycles + 1000 cycle buffer
            // This check is RT-safe: unreachable is optimized out in ReleaseFast
            const max_cycles: u64 = 110_000;
            const current_cycles = self.clock.ppu_cycles;
            const elapsed = if (current_cycles >= start_cycle)
                current_cycles - start_cycle
            else
                0;
            if (elapsed > max_cycles) {
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
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Scanline 0, dot 100
    clock.ppu_cycles = 100;
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 100), clock.dot());

    // Scanline 1, dot 0 (after 341 cycles)
    clock.ppu_cycles = 341;
    try testing.expectEqual(@as(u16, 1), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Scanline 10, dot 50
    clock.ppu_cycles = (10 * 341) + 50;
    try testing.expectEqual(@as(u16, 10), clock.scanline());
    try testing.expectEqual(@as(u16, 50), clock.dot());

    // VBlank start: Scanline 241, dot 1
    clock.ppu_cycles = (241 * 341) + 1;
    try testing.expectEqual(@as(u16, 241), clock.scanline());
    try testing.expectEqual(@as(u16, 1), clock.dot());
}

test "MasterClock: frame calculation NTSC" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Frame 0
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Still frame 0 (one cycle before frame boundary)
    clock.ppu_cycles = 89_341;
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Frame 1 (262 scanlines × 341 cycles = 89,342 cycles)
    clock.ppu_cycles = 89_342;
    try testing.expectEqual(@as(u64, 1), clock.frame());

    // Frame 10
    clock.ppu_cycles = 89_342 * 10;
    try testing.expectEqual(@as(u64, 10), clock.frame());
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

    const initial_cpu_cycles = state.clock.cpuCycles();

    // Tick 2 PPU cycles (CPU should NOT tick)
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 2), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles, state.clock.cpuCycles());

    // Tick 3rd PPU cycle (CPU SHOULD tick)
    state.tick();
    try testing.expectEqual(@as(u64, 3), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick 3 more PPU cycles (CPU should tick once more)
    state.tick();
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 6), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 2, state.clock.cpuCycles());
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
    // MasterClock: scanline 241, dot 0 = (241 * 341) + 0 PPU cycles
    state.clock.ppu_cycles = (241 * 341);
    try testing.expect(!state.frame_complete);

    // Tick once to reach scanline 241, dot 1 (VBlank start)
    state.tick();
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());
    try testing.expect(state.ppu.status.vblank); // VBlank flag set at 241.1 (NOT frame_complete)
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
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 340), state.clock.dot());

    // Tick should skip dot 0 of scanline 0, advancing by 2 PPU cycles instead of 1
    state.tick();

    // After tick: Should be at scanline 0, dot 1 (skipped dot 0)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

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
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());
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
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());
}

test "EmulationState: frame toggle at scanline boundary" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.reset();

    // Start with even frame (odd_frame = false)
    try testing.expect(!state.odd_frame);
    try testing.expectEqual(@as(u64, 0), state.clock.frame());

    // Advance to end of scanline 261 (last scanline of frame)
    state.clock.ppu_cycles = (261 * 341) + 340;

    // Tick to cross into scanline 0 of next frame
    state.tick();

    // Frame should have incremented
    try testing.expectEqual(@as(u64, 1), state.clock.frame());
    // Should now be odd frame
    try testing.expect(state.odd_frame);

    // Advance to next frame boundary
    state.clock.ppu_cycles = (261 * 341) + 340 + 89342;

    state.tick();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);
}
