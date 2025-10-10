# RAMBO NES Emulator - Complete Codebase Inventory

**Generated:** 2025-10-09
**Purpose:** Comprehensive module mapping for GraphViz diagram generation
**Accuracy:** 100% - All data extracted from actual source files

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Emulation](#core-emulation)
3. [CPU Subsystem](#cpu-subsystem)
4. [PPU Subsystem](#ppu-subsystem)
5. [APU Subsystem](#apu-subsystem)
6. [Cartridge System](#cartridge-system)
7. [Debugging System](#debugging-system)
8. [Threading System](#threading-system)
9. [Mailbox Communication](#mailbox-communication)
10. [Video Rendering](#video-rendering)
11. [Input System](#input-system)
12. [Data Flow Analysis](#data-flow-analysis)
13. [Memory Ownership](#memory-ownership)
14. [Side Effect Catalog](#side-effect-catalog)

---

## Architecture Overview

### Design Pattern: State/Logic Separation

**Pattern Definition:**
- **State modules (`State.zig`):** Pure data structures with optional convenience methods
- **Logic modules (`Logic.zig`):** Pure functions operating on State pointers
- **No hidden state:** All data explicitly passed through function parameters
- **RT-safety:** Zero heap allocations in hot paths (emulation loop)

### Thread Architecture

**3-Thread Mailbox Pattern:**
1. **Main Thread:** Coordinator (libxev loop, input routing, minimal work)
2. **Emulation Thread:** RT-safe CPU/PPU/APU emulation (timer-driven, 60 FPS)
3. **Render Thread:** Wayland + Vulkan rendering (double-buffered frame output)

**Communication:**
- Lock-free SPSC mailboxes for inter-thread messaging
- Double-buffered frame data (FrameMailbox)
- Event-driven command/response pattern

---

## Core Emulation

### EmulationState (`src/emulation/State.zig`)

**Type:** Monolithic state container with direct ownership
**Ownership:** All components owned directly (no pointer wiring)
**Thread Safety:** Single-threaded (emulation thread exclusive access)

#### Public Types

```zig
pub const EmulationState = struct {
    // Core Components (Direct Ownership)
    clock: MasterClock,           // PPU cycle granularity timing
    cpu: CpuState,                // 6502 CPU registers + state machine
    ppu: PpuState,                // 2C02 PPU registers + VRAM + rendering state
    apu: ApuState,                // APU channels + frame counter

    // Memory & I/O
    bus: BusState,                // 2KB RAM + open bus tracking
    cart: ?AnyCartridge,          // Optional cartridge (tagged union)

    // Peripheral State Machines
    dma: OamDma,                  // OAM DMA (512-cycle transfer)
    dmc_dma: DmcDma,              // DMC DMA (RDY line control)
    controller: ControllerState,   // NES controller shift registers

    // Debug & Synchronization
    vblank_ledger: VBlankLedger,  // Cycle-accurate NMI edge detection
    debugger: ?Debugger,          // Optional RT-safe debugger

    // Configuration
    config: *const Config,        // Immutable hardware config

    // Frame State
    frame_complete: bool,
    odd_frame: bool,
    rendering_enabled: bool,
    framebuffer: ?[]u32,          // Optional RGBA output buffer
}
```

#### Public Functions

**Lifecycle:**
- `init(config: *const Config) EmulationState` - Initialize power-on state
- `deinit(self: *EmulationState) void` - Cleanup resources (cartridge)
- `reset(self: *EmulationState) void` - RESET button (load vector from $FFFC)

**Cartridge Management:**
- `loadCartridge(self: *EmulationState, cart: AnyCartridge) void` - Take ownership
- `unloadCartridge(self: *EmulationState) void` - Unload and cleanup

**Bus Routing (Inline):**
- `busRead(self: *EmulationState, address: u16) u8` - CPU memory read with routing
- `busWrite(self: *EmulationState, address: u16, value: u8) void` - CPU memory write
- `busRead16(self: *EmulationState, address: u16) u16` - 16-bit little-endian read
- `busRead16Bug(self: *EmulationState, address: u16) u16` - JMP indirect page wrap bug
- `peekMemory(self: *const EmulationState, address: u16) u8` - Debugger read (no side effects)

**Emulation Loop:**
- `tick(self: *EmulationState) void` - **Main emulation entry point** (1 PPU cycle)
  - Calls `nextTimingStep()` to advance clock
  - Processes PPU, APU (if tick), CPU (if tick)
  - Handles odd-frame skip (rendering enabled)
  - Updates NMI line via VBlankLedger

**Helper Functions:**
- `emulateFrame(self: *EmulationState) u64` - Run until frame_complete (returns PPU cycles)
- `emulateCpuCycles(self: *EmulationState, n: u64) u64` - Run N CPU cycles

**Test Helpers:**
- `testSetVBlank(self: *EmulationState) void` - Set VBlank flag with ledger sync
- `testClearVBlank(self: *EmulationState) void` - Clear VBlank flag
- `testSetNmiEnable(self: *EmulationState, enabled: bool) void` - Toggle NMI enable

#### Side Effects

**Memory Mutations:**
- `bus.ram[2048]` - Internal RAM writes via busWrite()
- `ppu.*` - PPU state updates (registers, VRAM, OAM, shift registers)
- `cpu.*` - CPU state updates (registers, flags, state machine)
- `apu.*` - APU state updates (channels, IRQ flags)

**I/O Effects:**
- Cartridge writes (mapper state, PRG RAM, CHR RAM)
- Controller latch/shift operations
- DMA transfers (OAM DMA, DMC DMA)

**Timing Mutations:**
- `clock.advance(cycles)` - Master clock progression
- Frame counter increments

#### Dependencies

**Internal Modules:**
- `MasterClock` - Timing coordination (PPU cycles, CPU cycles, frame number)
- `CpuExecution` - CPU microstep execution (`src/emulation/cpu/execution.zig`)
- `BusRouting` - Memory-mapped I/O routing (`src/emulation/bus/routing.zig`)
- `DmaLogic` - DMA state machines (`src/emulation/dma/logic.zig`)
- `DebugIntegration` - Debugger coordination (`src/emulation/debug/integration.zig`)
- `PpuRuntime` - PPU tick orchestration (`src/emulation/Ppu.zig`)

**Component Modules:**
- `CpuState`, `CpuLogic` - CPU subsystem
- `PpuState`, `PpuLogic` - PPU subsystem
- `ApuState`, `ApuLogic` - APU subsystem
- `AnyCartridge` - Cartridge tagged union
- `Debugger` - Debug system

---

### MasterClock (`src/emulation/MasterClock.zig`)

**Type:** Timing coordinator (PPU cycle granularity)
**Thread Safety:** Single-threaded (owned by EmulationState)

#### Public Types

```zig
pub const MasterClock = struct {
    ppu_cycles: u64 = 0,  // PPU cycles since power-on (finest granularity)

    // Derived via computation (not stored):
    // - CPU cycles = ppu_cycles / 3
    // - APU cycles = ppu_cycles / 3 (same as CPU)
    // - Scanline = (ppu_cycles % 89342) / 341
    // - Dot = (ppu_cycles % 89342) % 341
    // - Frame = ppu_cycles / 89342
}
```

#### Public Functions

**Clock Operations:**
- `advance(self: *MasterClock, cycles: u64) void` - Advance PPU cycles
- `reset(self: *MasterClock) void` - Reset to power-on state

**Query Functions (Computed):**
- `cpuCycles(self: *const MasterClock) u64` - CPU cycles (ppu_cycles / 3)
- `apuCycles(self: *const MasterClock) u64` - APU cycles (ppu_cycles / 3)
- `scanline(self: *const MasterClock) u16` - Current scanline (0-261)
- `dot(self: *const MasterClock) u16` - Current dot (0-340)
- `frame(self: *const MasterClock) u64` - Frame number

**Tick Checks:**
- `isCpuTick(self: *const MasterClock) bool` - True if ppu_cycles % 3 == 0
- `isApuTick(self: *const MasterClock) bool` - True if ppu_cycles % 3 == 0
- `isOddFrame(self: *const MasterClock) bool` - Odd frame flag

#### Side Effects

- **Mutations:** Only `ppu_cycles` field (via `advance()`)
- **No I/O:** Pure timing state

---

### BusRouting (`src/emulation/bus/routing.zig`)

**Type:** Pure routing logic (inline functions)
**Side Effects:** Via EmulationState mutations

#### Public Functions

```zig
pub inline fn busRead(state: anytype, address: u16) u8;
pub inline fn busWrite(state: anytype, address: u16, value: u8) void;
pub inline fn busRead16(state: anytype, address: u16) u16;
pub inline fn busRead16Bug(state: anytype, address: u16) u16;
```

#### Memory Map (NES Architecture)

**RAM & Mirrors ($0000-$1FFF):**
- `$0000-$07FF`: 2KB internal RAM
- `$0800-$1FFF`: Mirrors of $0000-$07FF (repeat 3x)

**PPU Registers ($2000-$3FFF):**
- `$2000`: PPUCTRL (write-only)
- `$2001`: PPUMASK (write-only)
- `$2002`: PPUSTATUS (read-only, clears VBlank flag + write toggle)
- `$2003`: OAMADDR (write-only)
- `$2004`: OAMDATA (read/write)
- `$2005`: PPUSCROLL (write-only, 2 writes)
- `$2006`: PPUADDR (write-only, 2 writes)
- `$2007`: PPUDATA (read/write with buffer)
- `$2008-$3FFF`: Mirrors of $2000-$2007

**APU & I/O Registers ($4000-$4017):**
- `$4000-$4003`: Pulse 1 (write-only)
- `$4004-$4007`: Pulse 2 (write-only)
- `$4008-$400B`: Triangle (write-only)
- `$400C-$400F`: Noise (write-only)
- `$4010-$4013`: DMC (write-only)
- `$4014`: OAMDMA (write-only trigger)
- `$4015`: APU Status (read clears frame IRQ, write enables channels)
- `$4016`: Controller 1 (read/write strobe)
- `$4017`: Controller 2 / Frame Counter (read controller, write frame counter mode)

**Cartridge Space ($4020-$FFFF):**
- `$4020-$5FFF`: Expansion ROM (mapper-dependent)
- `$6000-$7FFF`: PRG RAM (8KB, battery-backed)
- `$8000-$FFFF`: PRG ROM (32KB, mapper-dependent)

#### Side Effects

**Read Side Effects:**
- `$2002` read: Clears VBlank flag, resets write toggle (w=0)
- `$2007` read: Updates read buffer, increments VRAM address
- `$4015` read: Clears frame IRQ flag
- `$4016/$4017` read: Shifts controller data

**Write Side Effects:**
- PPU register writes: Update PPU internal state
- `$2000` write: May trigger NMI if VBlank flag already set
- `$4014` write: Triggers OAM DMA (512 cycles)
- `$4016` write: Latches controller state
- Cartridge writes: Mapper state changes (banking, IRQ counters)

---

## CPU Subsystem

### CpuState (`src/cpu/State.zig`)

**Type:** Pure data structure (6502 architectural state + microstep machine)
**Size:** ~48 bytes (registers + context)

#### Public Types

```zig
pub const StatusFlags = packed struct(u8) {
    carry: bool,        // C (bit 0)
    zero: bool,         // Z (bit 1)
    interrupt: bool,    // I (bit 2) - IRQ disable
    decimal: bool,      // D (bit 3) - not used on NES
    break_flag: bool,   // B (bit 4) - software vs hardware interrupt
    unused: bool,       // - (bit 5) - always 1
    overflow: bool,     // V (bit 6)
    negative: bool,     // N (bit 7)
}

pub const AddressingMode = enum(u8) {
    implied, accumulator, immediate,
    zero_page, zero_page_x, zero_page_y,
    absolute, absolute_x, absolute_y,
    indirect, indexed_indirect, indirect_indexed,
    relative,
}

pub const ExecutionState = enum(u8) {
    fetch_opcode, fetch_operand_low, fetch_operand_high,
    calc_address_low, calc_address_high,
    dummy_read, dummy_write, execute, write_result,
    push_high, push_low, pull,
    interrupt_sequence,
    branch_taken, branch_page_cross,
}

pub const InterruptType = enum(u8) {
    none, nmi, irq, reset, brk,
}

pub const CpuState = struct {
    // 6502 Registers
    a: u8,           // Accumulator
    x: u8,           // X index
    y: u8,           // Y index
    sp: u8,          // Stack pointer (starts at $FD)
    pc: u16,         // Program counter
    p: StatusFlags,  // Status register

    // Microstep State Machine
    instruction_cycle: u8,
    state: ExecutionState,

    // Current Instruction Context
    opcode: u8,
    operand_low: u8,
    operand_high: u8,
    effective_address: u16,
    address_mode: AddressingMode,
    page_crossed: bool,

    // Open Bus Simulation
    data_bus: u8,

    // Interrupt State
    pending_interrupt: InterruptType,
    nmi_line: bool,           // Level
    nmi_edge_detected: bool,  // Edge latch
    irq_line: bool,           // Level-triggered

    // CPU Halt (JAM/KIL opcodes)
    halted: bool,

    // Temporary Storage
    temp_value: u8,      // RMW operations, indexed modes
    temp_address: u16,   // Indirect modes
}

pub const CpuCoreState = struct {
    // Pure 6502 state (for opcode functions)
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    p: StatusFlags,
    effective_address: u16,
}

pub const OpcodeResult = struct {
    // Delta structure (null = no change)
    a: ?u8, x: ?u8, y: ?u8, sp: ?u8, pc: ?u16,
    flags: ?StatusFlags,
    bus_write: ?BusWrite,
    push: ?u8,
    pull: bool,
    halt: bool,
}
```

#### Public Functions (StatusFlags)

- `toByte(self: StatusFlags) u8` - Pack to byte for stack push
- `fromByte(byte: u8) StatusFlags` - Unpack from stack (ensures unused=1)
- `setZN(self: StatusFlags, value: u8) StatusFlags` - Update zero/negative (pure)
- `setCarry(self: StatusFlags, carry: bool) StatusFlags` - Set carry flag (pure)
- `setOverflow(self: StatusFlags, overflow: bool) StatusFlags` - Set overflow (pure)

---

### CpuLogic (`src/cpu/Logic.zig`)

**Type:** Pure helper functions (no state mutation)

#### Public Functions

```zig
pub fn init() CpuState;
pub fn reset(cpu: *CpuState, reset_vector: u16) void;
pub fn toCoreState(state: *const CpuState) CpuCoreState;
pub fn checkInterrupts(state: *CpuState) void;
pub fn startInterruptSequence(state: *CpuState) void;
```

#### Side Effects

- Mutations only to passed `*CpuState` parameter
- No I/O, no heap allocations

---

### CpuExecution (`src/emulation/cpu/execution.zig`)

**Type:** Microstep state machine executor
**Critical Path:** RT-safe (zero allocations)

#### Public Functions

```zig
pub fn stepCycle(state: anytype) CpuCycleResult;
pub fn executeCycle(state: anytype) void;
```

#### Execution Flow

**stepCycle() - Entry Point:**
1. Query VBlankLedger for NMI line state
2. Check PPU warmup period (29,658 CPU cycles)
3. Handle CPU halted state (JAM/KIL)
4. Check debugger breakpoints/watchpoints
5. Handle DMC DMA stall (RDY line low)
6. Handle OAM DMA active (512 cycles)
7. Call executeCycle() for normal execution
8. Poll mapper IRQ counter

**executeCycle() - State Machine:**
1. **Interrupt Sequence** (7 cycles): Hardware interrupts (NMI/IRQ/RESET)
2. **Fetch Opcode** (1 cycle): Read next instruction at PC
3. **Addressing Microsteps** (0-8 cycles): Mode-dependent operand fetch
4. **Execute** (1 cycle): Pure opcode function + apply result

#### Side Effects

**Memory:**
- All via EmulationState.busRead/busWrite
- CPU register updates via executeCycle()

**Control Flow:**
- PC mutations (jumps, branches, interrupts)
- Stack operations (push/pull PC, P register)

**Hardware Accuracy:**
- Read-Modify-Write dummy writes (original value written before modified)
- Dummy reads on page crossings (wrong address before fix)
- Interrupt vector fetches (7-cycle sequence)

---

### CPU Microsteps (`src/emulation/cpu/microsteps.zig`)

**Type:** Atomic hardware operations
**Pattern:** Each function = 1 CPU cycle

#### Public Functions (Addressing Modes)

**Immediate/Zero Page:**
- `fetchOperandLow(state) bool` - Fetch byte at PC, increment PC
- `addXToZeroPage(state) bool` - Add X with zero page wrap
- `addYToZeroPage(state) bool` - Add Y with zero page wrap

**Absolute:**
- `fetchAbsLow(state) bool` - Fetch low byte at PC
- `fetchAbsHigh(state) bool` - Fetch high byte at PC
- `calcAbsoluteX(state) bool` - Add X, dummy read at wrong address
- `calcAbsoluteY(state) bool` - Add Y, dummy read at wrong address
- `fixHighByte(state) bool` - Read correct address if page crossed

**Indexed Indirect (ind,X):**
- `fetchZpBase(state) bool` - Fetch zero page pointer base
- `addXToBase(state) bool` - Add X to base (zero page wrap)
- `fetchIndirectLow(state) bool` - Read pointer low byte
- `fetchIndirectHigh(state) bool` - Read pointer high byte (wrap)

**Indirect Indexed (ind),Y:**
- `fetchZpPointer(state) bool` - Fetch zero page pointer
- `fetchPointerLow(state) bool` - Read pointer low byte
- `fetchPointerHigh(state) bool` - Read pointer high byte
- `addYCheckPage(state) bool` - Add Y, check page crossing

**Stack Operations:**
- `pushPch(state) bool` - Push PC high byte
- `pushPcl(state) bool` - Push PC low byte
- `pushStatusBrk(state) bool` - Push P with B=1 (BRK)
- `pushStatusInterrupt(state) bool` - Push P with B=0 (NMI/IRQ)
- `pullPcl(state) bool` - Pull PC low byte
- `pullPch(state) bool` - Pull PC high byte
- `pullStatus(state) bool` - Pull P register
- `pullByte(state) bool` - Pull generic byte
- `stackDummyRead(state) bool` - Dummy read at current SP

**Read-Modify-Write:**
- `rmwRead(state) bool` - Read operand from effective address
- `rmwDummyWrite(state) bool` - **CRITICAL:** Write original value back

**Branches:**
- `branchFetchOffset(state) bool` - Fetch signed offset, check condition
- `branchAddOffset(state) bool` - Add offset to PC
- `branchFixPch(state) bool` - Fix PC high byte if page crossed

**Control Flow:**
- `jsrStackDummy(state) bool` - JSR cycle 3 dummy read
- `fetchAbsHighJsr(state) bool` - JSR final cycle (jump)
- `fetchIrqVectorLow(state) bool` - BRK cycle 5
- `fetchIrqVectorHigh(state) bool` - BRK cycle 6 (jump)
- `incrementPcAfterRts(state) bool` - RTS final cycle

**JMP Indirect:**
- `jmpIndirectFetchLow(state) bool` - Read pointer low byte
- `jmpIndirectFetchHigh(state) bool` - Read pointer high byte (page wrap bug!)

#### Side Effects

- All via EmulationState.busRead/busWrite
- CPU state updates (registers, flags, effective_address)
- **Return Value:** `true` if instruction completes early (e.g., branch not taken)

---

### CPU Dispatch (`src/cpu/dispatch.zig`)

**Type:** Comptime-generated dispatch table
**Size:** 256 entries (one per opcode)

#### Public Types

```zig
pub const OpcodeFn = *const fn(CpuCoreState, u8) OpcodeResult;

pub const DispatchEntry = struct {
    operation: OpcodeFn,        // Pure opcode function
    info: decode.OpcodeInfo,    // Metadata (mnemonic, mode, cycles)
    is_rmw: bool,               // Read-Modify-Write flag
    is_pull: bool,              // Stack pull flag
}

pub const DISPATCH_TABLE: [256]DispatchEntry = buildDispatchTable();
```

#### Opcode Categories

**Load/Store:** LDA, LDX, LDY, STA, STX, STY
**Arithmetic:** ADC, SBC
**Logical:** AND, ORA, EOR
**Compare:** CMP, CPX, CPY, BIT
**Shift/Rotate:** ASL, LSR, ROL, ROR
**Inc/Dec:** INC, DEC, INX, INY, DEX, DEY
**Transfer:** TAX, TAY, TXA, TYA, TSX, TXS
**Flags:** CLC, CLD, CLI, CLV, SEC, SED, SEI
**Stack:** PHA, PHP, PLA, PLP
**Branches:** BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS
**Control:** JMP, JSR, RTS, RTI, BRK, NOP
**Unofficial:** LAX, SAX, SLO, RLA, SRE, RRA, DCP, ISC, ANC, ALR, ARR, XAA, LXA, AXS, SHA, SHX, SHY, TAS, LAE, JAM

#### Build Process

**Comptime Generation:**
1. Initialize all 256 entries with NOP
2. Populate official opcodes by category
3. Add unofficial opcodes (RP2A03G variant)
4. Mark RMW operations (is_rmw flag)
5. Mark pull operations (is_pull flag)

---

## PPU Subsystem

### PpuState (`src/ppu/State.zig`)

**Type:** Pure data structure (2C02 PPU state)
**Size:** ~2.5KB (VRAM + OAM + registers)

#### Public Types

```zig
pub const PpuCtrl = packed struct(u8) {
    nametable_x: bool,        // Bit 0
    nametable_y: bool,        // Bit 1
    vram_increment: bool,     // Bit 2 (0=+1, 1=+32)
    sprite_pattern: bool,     // Bit 3 (0=$0000, 1=$1000)
    bg_pattern: bool,         // Bit 4 (0=$0000, 1=$1000)
    sprite_size: bool,        // Bit 5 (0=8x8, 1=8x16)
    master_slave: bool,       // Bit 6
    nmi_enable: bool,         // Bit 7
}

pub const PpuMask = packed struct(u8) {
    greyscale: bool,          // Bit 0
    show_bg_left: bool,       // Bit 1 (leftmost 8 pixels)
    show_sprites_left: bool,  // Bit 2 (leftmost 8 pixels)
    show_bg: bool,            // Bit 3
    show_sprites: bool,       // Bit 4
    emphasize_red: bool,      // Bit 5
    emphasize_green: bool,    // Bit 6
    emphasize_blue: bool,     // Bit 7
}

pub const PpuStatus = packed struct(u8) {
    open_bus: u5,             // Bits 0-4
    sprite_overflow: bool,    // Bit 5
    sprite_0_hit: bool,       // Bit 6
    vblank: bool,             // Bit 7
}

pub const OpenBus = struct {
    value: u8,
    decay_timer: u16,  // Frames until decay
}

pub const InternalRegisters = struct {
    v: u16,              // Current VRAM address (15 bits)
    t: u16,              // Temporary VRAM address
    x: u3,               // Fine X scroll (3 bits)
    w: bool,             // Write toggle (0 or 1)
    read_buffer: u8,     // PPUDATA read buffer
}

pub const BackgroundState = struct {
    pattern_shift_lo: u16,   // 16-bit shift registers
    pattern_shift_hi: u16,
    attribute_shift_lo: u8,
    attribute_shift_hi: u8,

    nametable_latch: u8,     // Tile data latches
    attribute_latch: u8,
    pattern_latch_lo: u8,
    pattern_latch_hi: u8,
}

pub const SpriteState = struct {
    pattern_shift_lo: [8]u8,   // 8 sprites
    pattern_shift_hi: [8]u8,
    attributes: [8]u8,         // Palette + priority + flip
    x_counters: [8]u8,         // Countdown to sprite activation
    oam_source_index: [8]u8,   // Primary OAM index (for sprite 0)
    sprite_count: u8,
    sprite_0_present: bool,
    sprite_0_index: u8,
}

pub const PpuState = struct {
    // Registers
    ctrl: PpuCtrl,
    mask: PpuMask,
    status: PpuStatus,
    oam_addr: u8,
    open_bus: OpenBus,
    internal: InternalRegisters,

    // Memory
    oam: [256]u8,              // Object Attribute Memory
    secondary_oam: [32]u8,     // Sprite evaluation buffer
    vram: [2048]u8,            // Nametable storage (2KB)
    palette_ram: [32]u8,       // Palette RAM

    // Configuration
    mirroring: Mirroring,      // Horizontal/Vertical/Four-screen
    warmup_complete: bool,     // PPU warm-up period (29,658 CPU cycles)

    // Rendering State
    bg_state: BackgroundState,
    sprite_state: SpriteState,

    // Debug
    rendering_was_enabled: bool,
}
```

#### Public Functions (Register Helpers)

**PpuCtrl:**
- `nametableAddress(self) u16` - Base nametable ($2000/$2400/$2800/$2C00)
- `vramIncrementAmount(self) u16` - 1 or 32

**PpuMask:**
- `renderingEnabled(self) bool` - True if show_bg OR show_sprites

**PpuStatus:**
- `toByte(self, data_bus: u8) u8` - Merge with open bus bits

**BackgroundState:**
- `loadShiftRegisters(self) void` - Load latches into shift registers (every 8 pixels)
- `shift(self) void` - Shift by 1 pixel

---

### PpuLogic (`src/ppu/Logic.zig`)

**Type:** Facade module delegating to specialized logic

#### Public Functions (Delegates)

**Memory Access (`logic/memory.zig`):**
- `readVram(state, cart, address: u16) u8` - VRAM read ($0000-$3FFF)
- `writeVram(state, cart, address: u16, value: u8) void` - VRAM write

**Register I/O (`logic/registers.zig`):**
- `readRegister(state, cart, address: u16) u8` - CPU reads ($2000-$2007)
- `writeRegister(state, cart, address: u16, value: u8) void` - CPU writes

**Scrolling (`logic/scrolling.zig`):**
- `incrementScrollX(state) void` - Increment coarse X (every 8 pixels)
- `incrementScrollY(state) void` - Increment Y (end of scanline)
- `copyScrollX(state) void` - Copy t→v horizontal bits (dot 257)
- `copyScrollY(state) void` - Copy t→v vertical bits (pre-render scanline)

**Background (`logic/background.zig`):**
- `fetchBackgroundTile(state, cart, dot: u16) void` - 4-step tile fetch
- `getBackgroundPixel(state, pixel_x: u16) u8` - Extract from shift registers
- `getPaletteColor(state, palette_index: u8) u32` - RGBA color lookup

**Sprites (`logic/sprites.zig`):**
- `evaluateSprites(state, scanline: u16) void` - Secondary OAM population (64 cycles)
- `fetchSprites(state, cart, scanline: u16, dot: u16) void` - Load sprite shift registers
- `getSpritePixel(state, pixel_x: u16) SpritePixel` - Active sprite pixel
- `getSpritePatternAddress(...) u16` - 8x8 sprite pattern address
- `getSprite16PatternAddress(...) u16` - 8x16 sprite pattern address
- `reverseBits(byte: u8) u8` - Horizontal flip helper

#### Side Effects

**Memory Mutations:**
- VRAM writes (nametables, CHR RAM)
- OAM writes (sprite data)
- Palette RAM writes
- Internal register updates (v, t, x, w, read_buffer)

**Hardware Interactions:**
- Cartridge CHR access (pattern tables)
- Cartridge nametable access (if mapped)

---

### PPU Runtime (`src/emulation/Ppu.zig`)

**Type:** Timing-driven PPU orchestrator
**Entry Point:** `tick(state, scanline, dot, cart, framebuffer)`

#### Public Types

```zig
pub const TickFlags = struct {
    frame_complete: bool,
    rendering_enabled: bool,
    nmi_signal: bool,      // VBlank starts (scanline 241, dot 1)
    vblank_clear: bool,    // VBlank ends (scanline 261, dot 1)
}
```

#### Public Functions

```zig
pub fn tick(
    state: *PpuState,
    scanline: u16,        // 0-261
    dot: u16,             // 0-340
    cart: ?*AnyCartridge,
    framebuffer: ?[]u32   // Optional RGBA output
) TickFlags;
```

#### Timing Breakdown (Per Scanline)

**Visible Scanlines (0-239):**
- **Dots 1-256:** Pixel output + background/sprite fetching
- **Dots 257-320:** Sprite fetching for next scanline
- **Dots 321-336:** Prefetch next scanline tiles
- **Dots 337-340:** Dummy nametable reads

**Post-Render (240):**
- Idle scanline

**VBlank (241-260):**
- **Scanline 241, Dot 1:** Set VBlank flag, trigger NMI if enabled
- Idle period for CPU work

**Pre-Render (261):**
- **Dot 1:** Clear VBlank, sprite 0 hit, sprite overflow flags
- **Dots 280-304:** Copy vertical scroll (t→v)
- **Dots 321-340:** Same as visible scanlines

**Frame Complete:** Scanline 261, Dot 340

#### Side Effects

**Memory Mutations:**
- Background shift register updates (every cycle)
- Sprite shift register updates (every cycle)
- Secondary OAM population (dots 1-64)
- VRAM address increments (scrolling)

**Flag Updates:**
- VBlank flag (set at 241/1, clear at 261/1, clear on $2002 read)
- Sprite 0 hit flag (background/sprite overlap)
- Sprite overflow flag (>8 sprites on scanline)

**Output:**
- Framebuffer writes (256x240 RGBA pixels)

---

## APU Subsystem

### ApuState (`src/apu/State.zig`)

**Type:** Pure data structure (APU channels + frame counter)
**Size:** ~256 bytes

#### Public Types

```zig
pub const ApuState = struct {
    // Frame Counter
    frame_counter_mode: bool,    // 0=4-step, 1=5-step
    irq_inhibit: bool,
    frame_irq_flag: bool,
    frame_counter_cycles: u32,

    // Channel Enables
    pulse1_enabled: bool,
    pulse2_enabled: bool,
    triangle_enabled: bool,
    noise_enabled: bool,
    dmc_enabled: bool,

    // Length Counters
    pulse1_length: u8,
    pulse2_length: u8,
    triangle_length: u8,
    noise_length: u8,

    // Length Counter Halt Flags
    pulse1_halt: bool,
    pulse2_halt: bool,
    triangle_halt: bool,
    noise_halt: bool,

    // Envelopes (Pulse 1, Pulse 2, Noise)
    pulse1_envelope: Envelope,
    pulse2_envelope: Envelope,
    noise_envelope: Envelope,

    // Triangle Linear Counter
    triangle_linear_counter: u7,
    triangle_linear_reload: u7,
    triangle_linear_reload_flag: bool,

    // Sweep Units (Pulse channels)
    pulse1_sweep: Sweep,
    pulse2_sweep: Sweep,

    // Pulse Periods
    pulse1_period: u11,
    pulse2_period: u11,

    // DMC Channel
    dmc_active: bool,
    dmc_irq_flag: bool,
    dmc_irq_enabled: bool,
    dmc_loop_flag: bool,
    dmc_sample_address: u8,
    dmc_sample_length: u8,
    dmc_bytes_remaining: u16,
    dmc_current_address: u16,
    dmc_sample_buffer: u8,
    dmc_sample_buffer_empty: bool,
    dmc_shift_register: u8,
    dmc_bits_remaining: u4,
    dmc_silence_flag: bool,
    dmc_output: u7,
    dmc_timer: u16,
    dmc_timer_period: u16,

    // Channel Register Storage (write-only for Phase 1)
    pulse1_regs: [4]u8,
    pulse2_regs: [4]u8,
    triangle_regs: [4]u8,
    noise_regs: [4]u8,
    dmc_regs: [4]u8,
}
```

#### Public Functions

- `init() ApuState` - Initialize to power-on state
- `reset(self: *ApuState) void` - RESET button (clears channels, preserves mode)

---

### ApuLogic (`src/apu/Logic.zig`)

**Type:** Facade delegating to specialized logic

#### Public Functions (Delegates)

**Register Writes (`logic/registers.zig`):**
- `writePulse1(state, offset: u2, value: u8) void` - $4000-$4003
- `writePulse2(state, offset: u2, value: u8) void` - $4004-$4007
- `writeTriangle(state, offset: u2, value: u8) void` - $4008-$400B
- `writeNoise(state, offset: u2, value: u8) void` - $400C-$400F
- `writeDmc(state, offset: u2, value: u8) void` - $4010-$4013
- `writeControl(state, value: u8) void` - $4015 (channel enables)
- `writeFrameCounter(state, value: u8) void` - $4017 (mode, IRQ inhibit)

**Register Reads:**
- `readStatus(state: *const ApuState) u8` - $4015 read (channel lengths, IRQ flags)
- `clearFrameIrq(state: *ApuState) void` - Side effect of $4015 read

**Frame Counter (`logic/frame_counter.zig`):**
- `tickFrameCounter(state: *ApuState) bool` - Tick frame counter (returns true if IRQ)
- `clockLinearCounter(state: *ApuState) void` - Quarter-frame clock (triangle)

**DMC (`Dmc.zig`):**
- `getSampleAddress(state: *const ApuState) u16` - Current DMA address
- `loadSampleByte(state: *ApuState, value: u8) void` - DMA callback
- `tickDmc(state: *ApuState) bool` - Tick DMC (returns true if DMA needed)

#### Side Effects

**Memory Mutations:**
- All register state updates
- Channel timers, counters, envelopes
- IRQ flag updates

**DMA Triggers:**
- DMC sample fetch (via DmcDma state machine)

---

## Cartridge System

### Cartridge(MapperType) (`src/cartridge/Cartridge.zig`)

**Type:** Comptime generic factory (zero-cost polymorphism)
**Pattern:** Duck-typed mapper interface (no VTable)

#### Public Types

```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,      // Concrete mapper instance
        prg_rom: []const u8,     // 16KB or 32KB
        chr_data: []u8,          // CHR ROM or CHR RAM
        prg_ram: ?[]u8,          // 8KB battery-backed RAM
        header: InesHeader,      // ROM metadata
        mirroring: Mirroring,    // Nametable mirroring mode
        allocator: std.mem.Allocator,

        // Required Mapper Interface (duck typing):
        // - cpuRead(self, cart, address: u16) u8
        // - cpuWrite(self, cart, address: u16, value: u8) void
        // - ppuRead(self, cart, address: u16) u8
        // - ppuWrite(self, cart, address: u16, value: u8) void
        // - reset(self, cart) void
        // - tickIrq(self) bool
        // - ppuA12Rising(self) void
        // - acknowledgeIrq(self) void
    }
}

pub const NromCart = Cartridge(Mapper0);
```

#### Public Functions

**Lifecycle:**
- `loadFromData(allocator, data: []const u8) !Self` - Parse iNES ROM
- `load(allocator, path: []const u8) !Self` - Load from file
- `deinit(self: *Self) void` - Cleanup (frees PRG ROM, CHR, PRG RAM)

**CPU Interface:**
- `cpuRead(self: *const Self, address: u16) u8` - Read $4020-$FFFF
- `cpuWrite(self: *Self, address: u16, value: u8) void` - Write (mapper registers, PRG RAM)

**PPU Interface:**
- `ppuRead(self: *const Self, address: u16) u8` - Read CHR $0000-$1FFF
- `ppuWrite(self: *Self, address: u16, value: u8) void` - Write CHR RAM

**Control:**
- `reset(self: *Self) void` - RESET button (mapper state reset)

#### Memory Layout

**PRG ROM ($8000-$FFFF):**
- **NROM-128:** 16KB ROM mirrored at $8000 and $C000
- **NROM-256:** 32KB ROM at $8000-$FFFF

**PRG RAM ($6000-$7FFF):**
- 8KB battery-backed RAM (always allocated for Mapper 0)

**CHR ($0000-$1FFF):**
- **CHR ROM:** 8KB read-only pattern tables
- **CHR RAM:** 8KB read/write (if header chr_rom_size == 0)

#### Side Effects

**Memory Mutations:**
- PRG RAM writes ($6000-$7FFF)
- CHR RAM writes ($0000-$1FFF, if CHR RAM mode)

**No Mapper State (NROM):**
- Mapper 0 has no banking or IRQ features

---

### AnyCartridge (`src/cartridge/mappers/registry.zig`)

**Type:** Tagged union for runtime mapper dispatch
**Pattern:** `inline else` for zero-overhead switch

#### Public Types

```zig
pub const MapperId = enum(u8) {
    nrom = 0,
    // Future: mmc1 = 1, uxrom = 2, cnrom = 3, mmc3 = 4
}

pub const AnyCartridge = union(MapperId) {
    nrom: Cartridge(Mapper0),
    // Future mapper variants
}
```

#### Public Functions

**CPU Interface:**
- `cpuRead(self: *const AnyCartridge, address: u16) u8`
- `cpuWrite(self: *AnyCartridge, address: u16, value: u8) void`

**PPU Interface:**
- `ppuRead(self: *const AnyCartridge, address: u16) u8`
- `ppuWrite(self: *AnyCartridge, address: u16, value: u8) void`

**IRQ Interface:**
- `tickIrq(self: *AnyCartridge) bool` - Poll IRQ (returns false for NROM)
- `ppuA12Rising(self: *AnyCartridge) void` - Notify A12 edge (no-op for NROM)
- `acknowledgeIrq(self: *AnyCartridge) void` - Acknowledge IRQ (no-op for NROM)

**Control:**
- `reset(self: *AnyCartridge) void`
- `getMirroring(self: *const AnyCartridge) Mirroring`
- `deinit(self: *AnyCartridge) void`

**Metadata:**
- `getMapperId(self: *const AnyCartridge) MapperId`
- `getMetadata(self: *const AnyCartridge) MapperMetadata`

**ROM Data (for snapshot system):**
- `getPrgRom(self: *const AnyCartridge) []const u8`
- `getChrData(self: *const AnyCartridge) []u8`
- `getPrgRam(self: *const AnyCartridge) ?[]u8`
- `getHeader(self: *const AnyCartridge) InesHeader`

#### Side Effects

- Delegates all side effects to concrete cartridge type
- Zero overhead due to `inline else` comptime dispatch

---

## Debugging System

### Debugger (`src/debugger/Debugger.zig`)

**Type:** External wrapper for EmulationState
**Pattern:** Delegate pattern (inline functions to submodules)
**Thread Safety:** RT-safe (zero heap allocations in hot path)

#### Public Types

```zig
pub const Debugger = struct {
    state: DebuggerState,

    // DebuggerState contains:
    // - mode: DebugMode (running, paused, step_*)
    // - breakpoints: [256]?Breakpoint
    // - watchpoints: [256]?Watchpoint
    // - callbacks: [8]?DebugCallback
    // - step_state: StepState
    // - break_reason_buffer: [256]u8
    // - stats: DebugStats
    // - modification_history: [256]StateModification
}

pub const BreakpointType = enum {
    execute, read, write, access
}

pub const Breakpoint = struct {
    address: u16,
    type: BreakpointType,
    enabled: bool,
    hit_count: u64,
    condition: ?BreakCondition,
}

pub const Watchpoint = struct {
    address: u16,
    size: u16,
    type: WatchType,  // read, write, change
    enabled: bool,
    hit_count: u64,
    old_value: ?u8,
}

pub const DebugMode = enum {
    running, paused,
    step_instruction, step_over, step_out,
    step_scanline, step_frame,
}

pub const DebugCallback = struct {
    userdata: *anyopaque,
    onBeforeInstruction: ?*const fn(*anyopaque, *const EmulationState) bool,
    onMemoryAccess: ?*const fn(*anyopaque, u16, u8, bool) bool,
}
```

#### Public Functions

**Lifecycle:**
- `init(allocator, config: *const Config) Debugger`
- `deinit(self: *Debugger) void`

**Breakpoints (`breakpoints.zig`):**
- `addBreakpoint(self, address: u16, type: BreakpointType) !void`
- `removeBreakpoint(self, address: u16, type: BreakpointType) bool`
- `setBreakpointEnabled(self, address: u16, type: BreakpointType, enabled: bool) bool`
- `clearBreakpoints(self) void`

**Watchpoints (`watchpoints.zig`):**
- `addWatchpoint(self, address: u16, size: u16, type: WatchType) !void`
- `removeWatchpoint(self, address: u16, type: WatchType) bool`
- `clearWatchpoints(self) void`

**Execution Control (`stepping.zig`):**
- `continue_(self) void` - Resume execution
- `pause(self) void` - Pause execution
- `stepInstruction(self) void` - Execute one instruction
- `stepOver(self, state: *const EmulationState) void` - Step over subroutines
- `stepOut(self, state: *const EmulationState) void` - Step out of subroutine
- `stepScanline(self, state: *const EmulationState) void` - Step one scanline
- `stepFrame(self, state: *const EmulationState) void` - Step one frame

**Callbacks:**
- `registerCallback(self, callback: DebugCallback) !void` - Max 8 callbacks
- `unregisterCallback(self, userdata: *anyopaque) bool`
- `clearCallbacks(self) void`

**Execution Hooks:**
- `shouldBreak(self, state: *const EmulationState) !bool` - Check before instruction
- `checkMemoryAccess(self, state: *const EmulationState, address: u16, value: u8, is_write: bool) !bool`

**History (`history.zig`):**
- `captureHistory(self, state: *const EmulationState) !void`
- `restoreFromHistory(self, index: usize, cartridge: ?AnyCartridge) !EmulationState`
- `clearHistory(self) void`

**State Manipulation (`modification.zig`):**
- `setRegisterA(self, state: *EmulationState, value: u8) void`
- `setRegisterX/Y(self, state, value) void`
- `setStackPointer(self, state, value) void`
- `setProgramCounter(self, state, value: u16) void`
- `setStatusFlag(self, state, flag: StatusFlag, value: bool) void`
- `setStatusRegister(self, state, value: u8) void`
- `writeMemory(self, state, address: u16, value: u8) void`
- `writeMemoryRange(self, state, address: u16, data: []const u8) void`
- `setPpuScanline(self, state, scanline: u16) void`
- `setPpuFrame(self, state, frame: u64) void`

**Inspection (`inspection.zig`):**
- `readMemory(self, state: *const EmulationState, address: u16) u8` - No side effects
- `readMemoryRange(self, allocator, state, address: u16, length: u16) ![]u8`
- `getModifications(self) []const StateModification`
- `clearModifications(self) void`
- `getBreakReason(self) ?[]const u8`
- `isPaused(self) bool`
- `hasMemoryTriggers(self) bool`

#### Side Effects

**Memory Mutations:**
- CPU register modifications (via modification.zig)
- Memory writes (via modification.zig)
- Debugger state updates (breakpoints, watchpoints, mode)

**No I/O in Hot Path:**
- All breakpoint/watchpoint checks use stack buffers (no heap)
- Pre-allocated arrays for breakpoints (256), watchpoints (256)

**Control Flow:**
- Can pause execution (mode = .paused)
- Break reason stored in fixed buffer (256 bytes)

---

## Threading System

### EmulationThread (`src/threads/EmulationThread.zig`)

**Type:** Timer-driven RT-safe emulation loop
**Threading:** Dedicated thread with libxev event loop
**Timing:** 60.0988 Hz NTSC (16.639 ms/frame)

#### Public Types

```zig
pub const EmulationContext = struct {
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    frame_count: u64,
    total_frames: u64,
    total_cycles: u64,
    last_report_time: i128,
    shutdown_printed: bool,
}

pub const ThreadConfig = struct {
    frame_duration_ns: u64,  // 16,639,267 ns
    report_interval_ns: i128, // 1 second
    verbose: bool,
}
```

#### Public Functions

**Thread Entry:**
- `threadMain(state: *EmulationState, mailboxes: *Mailboxes, running: *std.atomic.Value(bool)) void`
- `spawn(state, mailboxes, running) !std.Thread` - Helper to spawn thread

**Internal Functions:**
- `timerCallback(ctx: ?*EmulationContext, loop: *xev.Loop, ...) xev.CallbackAction` - libxev timer callback
- `handleCommand(ctx: *EmulationContext, command: EmulationCommand) void`
- `handleDebugCommand(ctx: *EmulationContext, command: DebugCommand) void`
- `captureSnapshot(ctx: *EmulationContext) CpuSnapshot`
- `reportProgress(ctx: *EmulationContext) void`

#### Execution Flow

**Timer Callback (Every Frame):**
1. Check shutdown signal (atomic load)
2. Poll emulation commands (non-blocking)
3. Poll debug commands (non-blocking)
4. Poll controller input (non-blocking)
5. Get write buffer from FrameMailbox (may be null if full)
6. Emulate one frame (cycle-accurate)
7. Check for debug breaks (post events if triggered)
8. Swap frame buffers (if rendered)
9. Report progress (periodic FPS logging)
10. Rearm timer for next frame

#### Side Effects

**Memory Mutations:**
- EmulationState mutations via tick() loop
- Mailbox writes (frame data, debug events)

**Thread Synchronization:**
- Atomic running flag (acquire/release semantics)
- Lock-free SPSC mailboxes (single producer side)

**Timing:**
- libxev timer rearms (17ms rounded from 16.639ms)

---

### RenderThread (`src/threads/RenderThread.zig`)

**Type:** Wayland + Vulkan rendering thread
**Threading:** Dedicated thread with Wayland event loop
**Frame Rate:** 60 FPS (synchronized with emulation via mailbox)

#### Public Functions

**Thread Entry:**
- `threadMain(mailboxes: *Mailboxes, running: *std.atomic.Value(bool), config: RenderConfig) void`
- `spawn(mailboxes, running, config) !std.Thread`

#### Execution Flow

**Main Loop:**
1. Check shutdown signal
2. Poll read buffer from FrameMailbox (non-blocking)
3. If frame available:
   - Upload to Vulkan texture (staging buffer)
   - Render quad with texture
   - Present to Wayland surface
4. Process Wayland events (keyboard, mouse, window)
5. Post events to mailboxes (XdgWindowEventMailbox, XdgInputEventMailbox)
6. Run Wayland event loop (no_wait)
7. Small sleep to avoid busy-wait

#### Side Effects

**GPU Operations:**
- Vulkan texture uploads
- Command buffer recording
- Swapchain presentation

**Window Events:**
- Wayland protocol messages (window close, resize, keyboard, mouse)
- Event mailbox writes

---

## Mailbox Communication

### Mailboxes Container (`src/mailboxes/Mailboxes.zig`)

**Type:** Dependency injection container
**Ownership:** By-value ownership (prevents leaks)

#### Public Types

```zig
pub const Mailboxes = struct {
    // Emulation Input (Main → Emulation)
    controller_input: ControllerInputMailbox,
    emulation_command: EmulationCommandMailbox,
    debug_command: DebugCommandMailbox,

    // Emulation Output (Emulation → Render/Main)
    frame: FrameMailbox,
    debug_event: DebugEventMailbox,

    // Render Thread (Render ↔ Main)
    xdg_window_event: XdgWindowEventMailbox,
    xdg_input_event: XdgInputEventMailbox,
}
```

#### Public Functions

- `init(allocator: std.mem.Allocator) Mailboxes`
- `deinit(self: *Mailboxes) void`

---

### FrameMailbox (`src/mailboxes/FrameMailbox.zig`)

**Type:** Double-buffered frame data (pure atomic)
**Size:** 2 × 256×240 RGBA buffers (492 KB)

#### Public Functions

**Producer (Emulation Thread):**
- `getWriteBuffer(self: *FrameMailbox) ?[]u32` - Get buffer for writing (may be null)
- `swapBuffers(self: *FrameMailbox) void` - Atomically swap write/read buffers

**Consumer (Render Thread):**
- `getReadBuffer(self: *FrameMailbox) ?[]const u32` - Get buffer for reading (may be null)

**Metrics:**
- `getFramesDropped(self: *FrameMailbox) u64` - Increment and return drop counter

#### Side Effects

- **Atomic Operations:** Buffer index swaps (acquire/release semantics)
- **Memory Writes:** Framebuffer pixel updates (producer only)

---

### ControllerInputMailbox

**Type:** Atomic button state
**Size:** 2 bytes (2 controllers)

#### Public Functions

**Producer (Main Thread):**
- `postController1(self, state: ButtonState) void` - Update controller 1 (atomic)
- `postController2(self, state: ButtonState) void` - Update controller 2 (atomic)

**Consumer (Emulation Thread):**
- `getInput(self: *const ControllerInputMailbox) ControllerInput` - Read both controllers (atomic)

---

### DebugCommandMailbox

**Type:** Lock-free SPSC ring buffer
**Capacity:** 256 commands

#### Public Types

```zig
pub const DebugCommand = union(enum) {
    add_breakpoint: struct { address: u16, bp_type: BreakpointType },
    remove_breakpoint: struct { address: u16, bp_type: BreakpointType },
    add_watchpoint: struct { address: u16, size: u16, watch_type: WatchType },
    remove_watchpoint: struct { address: u16, watch_type: WatchType },
    pause,
    resume_execution,
    step_instruction,
    step_frame,
    inspect,
    clear_breakpoints,
    clear_watchpoints,
    set_breakpoint_enabled: struct { address: u16, bp_type: BreakpointType, enabled: bool },
}
```

#### Public Functions

**Producer (Main Thread):**
- `postCommand(self, command: DebugCommand) !void` - Enqueue command

**Consumer (Emulation Thread):**
- `pollCommand(self: *DebugCommandMailbox) ?DebugCommand` - Dequeue (non-blocking)

---

### DebugEventMailbox

**Type:** Lock-free SPSC ring buffer
**Capacity:** 256 events

#### Public Types

```zig
pub const DebugEvent = union(enum) {
    breakpoint_hit: struct { reason: [128]u8, reason_len: usize, snapshot: CpuSnapshot },
    watchpoint_hit: struct { reason: [128]u8, reason_len: usize, snapshot: CpuSnapshot },
    inspect_response: struct { snapshot: CpuSnapshot },
    paused: struct { snapshot: CpuSnapshot },
    resumed,
    breakpoint_added: struct { address: u16 },
    breakpoint_removed: struct { address: u16 },
    error_occurred: struct { message: [128]u8, message_len: usize },
}

pub const CpuSnapshot = struct {
    a: u8, x: u8, y: u8, sp: u8, pc: u16, p: u8,
    cycle: u64, frame: u64,
}
```

#### Public Functions

**Producer (Emulation Thread):**
- `postEvent(self, event: DebugEvent) !void` - Enqueue event

**Consumer (Main Thread):**
- `drainEvents(self: *DebugEventMailbox, buffer: []DebugEvent) usize` - Drain up to N events

---

## Video Rendering

### WaylandState (`src/video/WaylandState.zig`)

**Type:** Pure data structure (Wayland window state)
**Thread Safety:** Render thread exclusive

#### Public Types

```zig
pub const WaylandState = struct {
    // Core Wayland Objects
    display: ?*wl.Display,
    registry: ?*wl.Registry,
    compositor: ?*wl.Compositor,
    wm_base: ?*xdg.WmBase,

    // Window Surface
    surface: ?*wl.Surface,
    xdg_surface: ?*xdg.Surface,
    toplevel: ?*xdg.Toplevel,

    // Input Devices
    seat: ?*wl.Seat,
    keyboard: ?*wl.Keyboard,
    pointer: ?*wl.Pointer,

    // Window State
    current_width: u32,
    current_height: u32,
    closed: bool,
    is_fullscreen: bool,
    is_maximized: bool,
    is_activated: bool,

    // Pending Resize
    pending_width: ?u32,
    pending_height: ?u32,

    // Mouse State
    last_x: f32,
    last_y: f32,

    // Keyboard Modifiers
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    mods_group: u32,

    // Dependency Injection
    window_mailbox: *XdgWindowEventMailbox,
    input_mailbox: *XdgInputEventMailbox,
    allocator: std.mem.Allocator,
}
```

---

### VulkanState (`src/video/VulkanState.zig`)

**Type:** Pure data structure (Vulkan rendering state)
**Thread Safety:** Render thread exclusive

#### Public Types

```zig
pub const VulkanState = struct {
    // Core Vulkan
    instance: c.VkInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,

    // Queues
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    graphics_queue_family: u32,
    present_queue_family: u32,

    // Surface & Swapchain
    surface: c.VkSurfaceKHR,
    swapchain: c.VkSwapchainKHR,
    swapchain_images: []c.VkImage,
    swapchain_image_views: []c.VkImageView,
    swapchain_extent: c.VkExtent2D,
    swapchain_format: c.VkFormat,

    // Render Pass
    render_pass: c.VkRenderPass,
    framebuffers: []c.VkFramebuffer,

    // Pipeline
    pipeline_layout: c.VkPipelineLayout,
    graphics_pipeline: c.VkPipeline,

    // Descriptor Sets (Texture Binding)
    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_sets: []c.VkDescriptorSet,

    // NES Frame Texture (256×240 RGBA)
    texture_image: c.VkImage,
    texture_memory: c.VkDeviceMemory,
    texture_image_view: c.VkImageView,
    texture_sampler: c.VkSampler,

    // Staging Buffer (Texture Upload)
    staging_buffer: c.VkBuffer,
    staging_buffer_memory: c.VkDeviceMemory,

    // Command Buffers
    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,

    // Synchronization
    image_available_semaphores: []c.VkSemaphore,
    render_finished_semaphores: []c.VkSemaphore,
    in_flight_fences: []c.VkFence,
    current_frame: u32,

    // Debug
    debug_messenger: c.VkDebugUtilsMessengerEXT,

    // Config
    allocator: std.mem.Allocator,
    max_frames_in_flight: u32,  // 2 (double-buffering)
    enable_validation: bool,
}
```

---

## Input System

### ButtonState (`src/input/ButtonState.zig`)

**Type:** Packed struct (8 NES buttons)
**Size:** 1 byte

#### Public Types

```zig
pub const ButtonState = packed struct(u8) {
    a: bool,      // Bit 0
    b: bool,      // Bit 1
    select: bool, // Bit 2
    start: bool,  // Bit 3
    up: bool,     // Bit 4
    down: bool,   // Bit 5
    left: bool,   // Bit 6
    right: bool,  // Bit 7
}
```

#### Public Functions

- `toByte(self: ButtonState) u8` - Pack to byte
- `fromByte(byte: u8) ButtonState` - Unpack from byte

---

### KeyboardMapper (`src/input/KeyboardMapper.zig`)

**Type:** Stateful keyboard → NES button mapper
**Mapping:** Wayland keycodes → ButtonState

#### Default Mapping

```
Arrow Keys → D-Pad
Z → B
X → A
Enter → Start
Shift → Select
```

#### Public Functions

- `keyPress(self: *KeyboardMapper, keycode: u32) void`
- `keyRelease(self: *KeyboardMapper, keycode: u32) void`
- `getState(self: *const KeyboardMapper) ButtonState`
- `reset(self: *KeyboardMapper) void`

---

## Data Flow Analysis

### Main Emulation Loop (tick())

**Call Chain:**
1. **EmulationState.tick()**
   - Calls `nextTimingStep()` → advances MasterClock
   - Calls `stepPpuCycle()` → PPU work
   - Calls `stepApuCycle()` (if APU tick) → APU work
   - Calls `stepCpuCycle()` (if CPU tick) → CPU work

2. **stepPpuCycle(scanline, dot)**
   - Calls `PpuRuntime.tick()` → PPU rendering + flag updates
   - Returns `PpuCycleResult` (frame_complete, nmi_signal, vblank_clear, a12_rising)
   - Updates `rendering_enabled`, toggles `odd_frame`
   - Records VBlank events in `vblank_ledger`

3. **stepCpuCycle()**
   - Queries `vblank_ledger.shouldAssertNmiLine()` → updates `cpu.nmi_line`
   - Checks PPU warmup (29,658 CPU cycles)
   - Handles CPU halted state (JAM/KIL)
   - Checks debugger (if attached)
   - Handles DMC DMA (RDY line low)
   - Handles OAM DMA (512 cycles)
   - Calls `executeCycle()` → CPU state machine
   - Polls mapper IRQ counter

4. **executeCycle()**
   - Implements 6502 state machine:
     - `.interrupt_sequence` → hardware interrupt (7 cycles)
     - `.fetch_opcode` → read instruction at PC
     - `.fetch_operand_low` → addressing mode microsteps
     - `.execute` → pure opcode function + apply result

5. **Opcode Execution (Pure Function Pattern)**
   - Extract `CpuCoreState` from `CpuState`
   - Extract operand value (bus read or temp_value)
   - Call `DispatchEntry.operation(core_state, operand)` → returns `OpcodeResult`
   - Apply delta: registers, flags, bus writes, stack ops

### Frame Generation Flow

**Emulation Thread:**
1. Timer fires (every 16.639 ms)
2. Get write buffer from FrameMailbox
3. Set `emulation_state.framebuffer = write_buffer`
4. Call `emulation_state.emulateFrame()` → loops `tick()` until frame_complete
5. PPU writes pixels to framebuffer during visible scanlines
6. Call `frame_mailbox.swapBuffers()` (atomic)
7. Clear framebuffer reference

**Render Thread:**
1. Get read buffer from FrameMailbox (non-blocking)
2. If buffer available:
   - Copy to Vulkan staging buffer
   - Record command buffer (texture upload + quad render)
   - Submit to GPU
   - Present to Wayland surface
3. Process Wayland events (keyboard, mouse)
4. Post events to input mailbox

**Main Thread:**
1. Poll input events from mailbox
2. Update KeyboardMapper state
3. Post ButtonState to controller input mailbox
4. Small sleep (100ms coordinator)

---

## Memory Ownership

### Direct Ownership (No Pointers)

**EmulationState Owns:**
- `MasterClock` (by value)
- `CpuState` (by value)
- `PpuState` (by value)
- `ApuState` (by value)
- `BusState` (by value, includes 2KB RAM)
- `?AnyCartridge` (optional by value, cartridge owns ROM/RAM slices)
- `OamDma`, `DmcDma`, `ControllerState` (by value)
- `VBlankLedger` (by value)
- `?Debugger` (optional by value, debugger owns history/breakpoints)

**No Pointer Wiring:**
- All component access via `state.cpu`, `state.ppu`, `state.apu`
- Bus routing via inline functions (no abstraction layer)
- Cartridge access via `state.cart` (optional reference)

### Heap Allocations

**EmulationState:**
- Cartridge ROM/RAM (allocated by loader, owned by cartridge)
- Debugger history (if enabled, bounded to 256 entries)

**Threads:**
- Thread stack (OS-managed)
- libxev event loop (thread-local)

**Mailboxes:**
- SpscRingBuffer backing storage (bounded to capacity)
- FrameMailbox pixel buffers (2 × 256×240 RGBA = 492 KB)

**Video:**
- Vulkan GPU buffers (swapchain images, staging buffer)
- Wayland protocol objects (compositor allocations)

### RT-Safety (Emulation Thread)

**Zero Allocations in Hot Path:**
- `tick()` loop uses only stack
- Opcodes use delta structures (stack-allocated)
- DMA state machines use fixed state (no allocations)
- Debugger uses pre-allocated arrays (256 breakpoints, 256 watchpoints)

**Bounded Memory:**
- Framebuffer double-buffering (fixed 492 KB)
- SPSC ring buffers (fixed capacity)
- Debug events (stack buffers, 128-byte reason strings)

---

## Side Effect Catalog

### Memory Mutations

**CPU State:**
- Registers: A, X, Y, SP, PC, P
- State machine: instruction_cycle, state, opcode, operand_low/high
- Flags: page_crossed, halted
- Temp: temp_value, temp_address, effective_address

**PPU State:**
- Registers: ctrl, mask, status, oam_addr
- VRAM: vram[2048], palette_ram[32], oam[256], secondary_oam[32]
- Internal: v, t, x, w, read_buffer
- Shift registers: bg_state, sprite_state
- Open bus: value, decay_timer

**APU State:**
- Frame counter: mode, cycles, irq_flag
- Channels: enabled flags, length counters, envelopes, periods
- DMC: active, irq_flag, buffer, shift_register, timer

**Bus State:**
- RAM: ram[2048]
- Open bus: open_bus value

**Cartridge State:**
- PRG RAM writes ($6000-$7FFF)
- CHR RAM writes ($0000-$1FFF)
- Mapper state (banking, IRQ counters) - future

**Timing:**
- MasterClock: ppu_cycles increment
- VBlankLedger: span tracking, NMI edge latching

**Debugger State:**
- Breakpoint hit counts
- Watchpoint hit counts
- Mode changes (running ↔ paused)
- Break reason buffer
- Modification history

### I/O Effects

**Bus Reads:**
- Open bus update (all reads except $4015)
- PPU buffer update ($2007)
- VBlank flag clear ($2002)
- Write toggle reset ($2002)
- Frame IRQ clear ($4015)
- Controller shift ($4016/$4017)

**Bus Writes:**
- Open bus update (all writes)
- PPU register updates ($2000-$2007)
- APU register updates ($4000-$4017)
- OAM DMA trigger ($4014)
- Controller latch ($4016)
- Cartridge writes (mapper state)

**DMA Operations:**
- OAM DMA: 512 CPU cycles, copies $XX00-$XXFF → OAM
- DMC DMA: Stalls CPU (RDY line low) for sample fetch

**GPU Operations:**
- Texture uploads (256×240 RGBA per frame)
- Command buffer recording
- Swapchain presentation

**Window Events:**
- Wayland protocol messages
- Keyboard/mouse events
- Window close/resize

### Control Flow

**Jumps/Branches:**
- PC mutations (JMP, JSR, RTS, RTI, BRK, branches)
- Conditional branches (8 opcodes)

**Interrupts:**
- Hardware: NMI (edge-triggered), IRQ (level-triggered), RESET
- Software: BRK
- 7-cycle sequence (push PC, push P, load vector, jump)

**DMA:**
- OAM DMA: CPU frozen for 512 cycles
- DMC DMA: CPU stalled until sample fetched

**Debugger:**
- Pause execution (mode = .paused)
- Step execution (single instruction, scanline, frame)
- Breakpoint hit (execution halts)

### Timing Mutations

**Clock Advancement:**
- `MasterClock.advance(cycles)` - Only call site: `EmulationState.nextTimingStep()`
- PPU cycles increment by 1 or 2 (odd frame skip)
- CPU cycles = ppu_cycles / 3 (computed)

**Frame Boundary:**
- `frame_complete` flag set at scanline 261, dot 340
- `odd_frame` toggle on frame completion

**VBlank Window:**
- VBlank flag set at scanline 241, dot 1
- VBlank flag clear at scanline 261, dot 1 (or $2002 read)
- NMI edge detection via VBlankLedger

---

## File Path Reference

### Core Emulation
- `/home/colin/Development/RAMBO/src/emulation/State.zig` - Main emulation state
- `/home/colin/Development/RAMBO/src/emulation/MasterClock.zig` - Timing coordinator
- `/home/colin/Development/RAMBO/src/emulation/bus/routing.zig` - Memory-mapped I/O
- `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` - CPU state machine
- `/home/colin/Development/RAMBO/src/emulation/cpu/microsteps.zig` - Atomic CPU ops
- `/home/colin/Development/RAMBO/src/emulation/Ppu.zig` - PPU orchestrator
- `/home/colin/Development/RAMBO/src/emulation/state/BusState.zig` - Bus data

### CPU
- `/home/colin/Development/RAMBO/src/cpu/State.zig` - CPU state + types
- `/home/colin/Development/RAMBO/src/cpu/Logic.zig` - CPU helpers
- `/home/colin/Development/RAMBO/src/cpu/dispatch.zig` - Dispatch table (256 opcodes)
- `/home/colin/Development/RAMBO/src/cpu/opcodes/*.zig` - Opcode implementations (14 modules)

### PPU
- `/home/colin/Development/RAMBO/src/ppu/State.zig` - PPU state + registers
- `/home/colin/Development/RAMBO/src/ppu/Logic.zig` - PPU facade
- `/home/colin/Development/RAMBO/src/ppu/logic/*.zig` - Specialized logic (5 modules)
- `/home/colin/Development/RAMBO/src/ppu/palette.zig` - NES color palette
- `/home/colin/Development/RAMBO/src/ppu/timing.zig` - Timing constants

### APU
- `/home/colin/Development/RAMBO/src/apu/State.zig` - APU channels + frame counter
- `/home/colin/Development/RAMBO/src/apu/Logic.zig` - APU facade
- `/home/colin/Development/RAMBO/src/apu/logic/*.zig` - Specialized logic (3 modules)
- `/home/colin/Development/RAMBO/src/apu/Envelope.zig` - Envelope generator
- `/home/colin/Development/RAMBO/src/apu/Sweep.zig` - Sweep unit
- `/home/colin/Development/RAMBO/src/apu/Dmc.zig` - DMC channel

### Cartridge
- `/home/colin/Development/RAMBO/src/cartridge/Cartridge.zig` - Generic factory
- `/home/colin/Development/RAMBO/src/cartridge/mappers/Mapper0.zig` - NROM mapper
- `/home/colin/Development/RAMBO/src/cartridge/mappers/registry.zig` - Tagged union
- `/home/colin/Development/RAMBO/src/cartridge/ines.zig` - iNES parser
- `/home/colin/Development/RAMBO/src/cartridge/loader.zig` - File loader

### Debugging
- `/home/colin/Development/RAMBO/src/debugger/Debugger.zig` - Main facade
- `/home/colin/Development/RAMBO/src/debugger/State.zig` - Debugger state
- `/home/colin/Development/RAMBO/src/debugger/*.zig` - Submodules (8 files)

### Threading
- `/home/colin/Development/RAMBO/src/threads/EmulationThread.zig` - Emulation loop
- `/home/colin/Development/RAMBO/src/threads/RenderThread.zig` - Render loop

### Mailboxes
- `/home/colin/Development/RAMBO/src/mailboxes/Mailboxes.zig` - Container
- `/home/colin/Development/RAMBO/src/mailboxes/FrameMailbox.zig` - Frame data
- `/home/colin/Development/RAMBO/src/mailboxes/ControllerInputMailbox.zig` - Input
- `/home/colin/Development/RAMBO/src/mailboxes/DebugCommandMailbox.zig` - Debug commands
- `/home/colin/Development/RAMBO/src/mailboxes/DebugEventMailbox.zig` - Debug events
- `/home/colin/Development/RAMBO/src/mailboxes/SpscRingBuffer.zig` - Generic ring buffer

### Video
- `/home/colin/Development/RAMBO/src/video/WaylandState.zig` - Wayland state
- `/home/colin/Development/RAMBO/src/video/WaylandLogic.zig` - Wayland logic
- `/home/colin/Development/RAMBO/src/video/VulkanState.zig` - Vulkan state
- `/home/colin/Development/RAMBO/src/video/VulkanLogic.zig` - Vulkan logic
- `/home/colin/Development/RAMBO/src/video/VulkanBindings.zig` - Vulkan C bindings

### Input
- `/home/colin/Development/RAMBO/src/input/ButtonState.zig` - NES button state
- `/home/colin/Development/RAMBO/src/input/KeyboardMapper.zig` - Keyboard mapping

### Main
- `/home/colin/Development/RAMBO/src/main.zig` - Entry point + CLI
- `/home/colin/Development/RAMBO/src/root.zig` - Library root (public API)

---

## Notes for GraphViz Diagrams

### Recommended Diagram Types

1. **Module Dependency Graph** - All modules with import edges
2. **Emulation State Machine** - CPU execution states + transitions
3. **Data Flow Diagram** - tick() → components → results
4. **Thread Communication** - Mailbox producer/consumer relationships
5. **Memory Map** - NES address space routing
6. **Ownership Tree** - EmulationState direct ownership hierarchy

### Key Relationships

**Ownership (Solid Lines):**
- EmulationState → CpuState, PpuState, ApuState, BusState, MasterClock
- Cartridge → PRG ROM, CHR data, PRG RAM
- Debugger → Breakpoints, Watchpoints, History

**Function Calls (Dotted Lines):**
- EmulationState.tick() → PpuRuntime.tick(), CpuExecution.stepCycle()
- CpuExecution.executeCycle() → Microsteps, Dispatch table
- BusRouting → PpuLogic, ApuLogic, Cartridge

**Data Flow (Arrows):**
- Main Thread → ControllerInputMailbox → Emulation Thread
- Emulation Thread → FrameMailbox → Render Thread
- Render Thread → XdgInputEventMailbox → Main Thread

### Legend

- **State Module:** Rectangle (blue) - Pure data structures
- **Logic Module:** Ellipse (green) - Pure functions
- **Facade Module:** Diamond (yellow) - Delegation pattern
- **Thread:** Parallelogram (red) - Execution context
- **Mailbox:** Cylinder (purple) - Communication channel

---

**END OF INVENTORY**

This document provides complete coverage of the RAMBO codebase with precise function signatures, type definitions, side effect annotations, and file path references for GraphViz diagram generation.
