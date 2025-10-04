# Phase 4.3: Snapshot + Debugger System Architecture

**Visual Reference:** Architecture diagrams and data flow for Phase 4.3 implementation

---

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAMBO Emulator                            │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              EmulationState (Pure Data)                  │    │
│  │                                                           │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │    │
│  │  │  Clock   │  │   CPU    │  │   PPU    │  │   Bus   │  │    │
│  │  │ (8 bytes)│  │(44 bytes)│  │(2.6 KB)  │  │ (2 KB)  │  │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │    │
│  │                                                           │    │
│  │  Total Core State: ~5.2 KB (without framebuffer)         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              ▲                                    │
│                              │                                    │
│                              ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           External Tools (Phase 4.3)                     │    │
│  │                                                           │    │
│  │  ┌──────────────────┐        ┌──────────────────────┐   │    │
│  │  │ Snapshot System  │        │  Debugger System     │   │    │
│  │  │                  │        │                      │   │    │
│  │  │ ┌──────────────┐ │        │ ┌──────────────────┐│   │    │
│  │  │ │ Binary Save  │ │        │ │  Breakpoints    ││   │    │
│  │  │ │ Binary Load  │ │        │ │  Watchpoints    ││   │    │
│  │  │ └──────────────┘ │        │ │  Step Execution ││   │    │
│  │  │                  │        │ │  History Buffer ││   │    │
│  │  │ ┌──────────────┐ │        │ │  Callbacks      ││   │    │
│  │  │ │ JSON Save    │ │        │ │  Disassembler   ││   │    │
│  │  │ │ JSON Load    │ │        │ └──────────────────┘│   │    │
│  │  │ └──────────────┘ │        │                      │   │    │
│  │  │                  │        │  Wraps EmulationState│   │    │
│  │  │ ┌──────────────┐ │        │  (No modifications)  │   │    │
│  │  │ │ Checksum     │ │        └──────────────────────┘   │    │
│  │  │ │ Validation   │ │                                    │    │
│  │  │ └──────────────┘ │                                    │    │
│  │  └──────────────────┘                                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Snapshot Data Flow

### Save Operation

```
EmulationState
      │
      ▼
┌─────────────────┐
│ Snapshot.save() │
└─────────────────┘
      │
      ▼
┌─────────────────────────────────────────┐
│  Serialize Components                   │
│                                         │
│  1. Serialize Config values (no arena)  │
│  2. Serialize MasterClock (8 bytes)     │
│  3. Serialize CpuState (44 bytes)       │
│  4. Serialize PpuState (2.6 KB)         │
│  5. Serialize BusState.ram (2 KB)       │
│  6. Handle Cartridge:                   │
│     ├─ Reference mode: ROM path/hash    │
│     └─ Embed mode: Full ROM data        │
│  7. Optional: Framebuffer (245 KB)      │
└─────────────────────────────────────────┘
      │
      ▼
┌─────────────────┐
│ Add Header      │
│ - Magic         │
│ - Version       │
│ - Timestamp     │
│ - Size info     │
│ - Flags         │
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Calculate CRC32 │
│ Checksum        │
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Binary Format:  │
│ ~5 KB core      │
│ ~250 KB w/FB    │
│                 │
│ JSON Format:    │
│ ~8 KB core      │
│ ~400 KB w/FB    │
└─────────────────┘
```

### Load Operation

```
Binary/JSON Data
      │
      ▼
┌─────────────────┐
│ Verify Header   │
│ - Magic check   │
│ - Version check │
│ - CRC32 verify  │
└─────────────────┘
      │
      ▼
┌────────────────────────────────────────┐
│  Deserialize Components                │
│                                        │
│  1. Parse Config values                │
│  2. Reconstruct MasterClock            │
│  3. Reconstruct CpuState               │
│  4. Reconstruct PpuState               │
│  5. Reconstruct BusState               │
│  6. Handle Cartridge:                  │
│     ├─ Reference: Load from ROM path   │
│     └─ Embed: Reconstruct from data    │
│  7. Optional: Restore framebuffer      │
└────────────────────────────────────────┘
      │
      ▼
┌─────────────────┐
│ Connect Pointers│
│ via connect     │
│ Components()    │
└─────────────────┘
      │
      ▼
EmulationState
(Fully Restored)
```

---

## Debugger Architecture

### Wrapper Pattern

```
┌──────────────────────────────────────────────────────┐
│                   Debugger                           │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │      EmulationState* (borrowed)            │    │
│  │                                            │    │
│  │  No modifications to EmulationState        │    │
│  │  Read-only inspection + controlled writes  │    │
│  └────────────────────────────────────────────┘    │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │      Debugger-Owned Data                   │    │
│  │                                            │    │
│  │  ┌──────────────────────────────────────┐ │    │
│  │  │  BreakpointManager                   │ │    │
│  │  │  - ArrayList<Breakpoint>             │ │    │
│  │  │  - Next ID counter                   │ │    │
│  │  └──────────────────────────────────────┘ │    │
│  │                                            │    │
│  │  ┌──────────────────────────────────────┐ │    │
│  │  │  WatchpointManager                   │ │    │
│  │  │  - ArrayList<Watchpoint>             │ │    │
│  │  │  - Access logging                    │ │    │
│  │  └──────────────────────────────────────┘ │    │
│  │                                            │    │
│  │  ┌──────────────────────────────────────┐ │    │
│  │  │  ExecutionHistory                    │ │    │
│  │  │  - Circular buffer (512 entries)     │ │    │
│  │  │  - ~16 KB memory                     │ │    │
│  │  └──────────────────────────────────────┘ │    │
│  │                                            │    │
│  │  ┌──────────────────────────────────────┐ │    │
│  │  │  CallbackManager                     │ │    │
│  │  │  - Event → Callback mapping          │ │    │
│  │  └──────────────────────────────────────┘ │    │
│  │                                            │    │
│  │  ┌──────────────────────────────────────┐ │    │
│  │  │  StepState                           │ │    │
│  │  │  - Current step mode                 │ │    │
│  │  │  - Target values                     │ │    │
│  │  └──────────────────────────────────────┘ │    │
│  └────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Debugger Execution Flow

```
┌─────────────┐
│ debugger.   │
│ run()       │
└─────────────┘
      │
      ▼
┌─────────────────────────────────┐
│ Loop: Until break condition     │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 1. Check breakpoints       │ │
│  │    - PC match?             │ │
│  │    - Opcode match?         │ │
│  │    - Condition met?        │ │
│  └────────────────────────────┘ │
│          │                       │
│          │ No match              │
│          ▼                       │
│  ┌────────────────────────────┐ │
│  │ 2. Tick EmulationState     │ │
│  │    state.tick()            │ │
│  └────────────────────────────┘ │
│          │                       │
│          ▼                       │
│  ┌────────────────────────────┐ │
│  │ 3. Check watchpoints       │ │
│  │    - Memory access?        │ │
│  │    - Address in range?     │ │
│  └────────────────────────────┘ │
│          │                       │
│          │ No match              │
│          ▼                       │
│  ┌────────────────────────────┐ │
│  │ 4. Record history          │ │
│  │    - Push to circular buf  │ │
│  └────────────────────────────┘ │
│          │                       │
│          ▼                       │
│  ┌────────────────────────────┐ │
│  │ 5. Check step mode         │ │
│  │    - Step complete?        │ │
│  │    - Target reached?       │ │
│  └────────────────────────────┘ │
│          │                       │
└──────────┼───────────────────────┘
           │
           ▼
    ┌──────────────┐
    │ Breakpoint   │
    │ hit?         │
    └──────────────┘
           │
           ▼
    ┌──────────────┐
    │ Trigger      │
    │ callbacks    │
    └──────────────┘
           │
           ▼
    ┌──────────────┐
    │ Return       │
    │ StopReason   │
    └──────────────┘
```

---

## Memory Layout

### EmulationState Memory Map

```
┌─────────────────────────────────────────────┐
│ EmulationState                              │
│                                             │
│  Offset  │ Size   │ Component              │
│ ─────────┼────────┼───────────────────────  │
│  0       │ 8      │ MasterClock            │
│          │        │   ppu_cycles: u64      │
│ ─────────┼────────┼───────────────────────  │
│  8       │ 44     │ CpuState               │
│          │        │   registers: 7 bytes   │
│          │        │   cycle info: 17 bytes │
│          │        │   instruction: 10 bytes│
│          │        │   misc: 10 bytes       │
│ ─────────┼────────┼───────────────────────  │
│  52      │ 2,659  │ PpuState               │
│          │        │   registers: 18 bytes  │
│          │        │   oam: 256 bytes       │
│          │        │   secondary_oam: 32 B  │
│          │        │   vram: 2,048 bytes    │
│          │        │   palette: 32 bytes    │
│          │        │   bg_state: 28 bytes   │
│          │        │   metadata: 19 bytes   │
│ ─────────┼────────┼───────────────────────  │
│  2,711   │ 2,104  │ BusState               │
│          │        │   ram: 2,048 bytes     │
│          │        │   cycle: 8 bytes       │
│          │        │   open_bus: 16 bytes   │
│          │        │   pointers: 32 bytes   │
│ ─────────┼────────┼───────────────────────  │
│  4,815   │ 8      │ config: *const Config  │
│ ─────────┼────────┼───────────────────────  │
│  4,823   │ 3      │ frame flags            │
│          │        │   frame_complete: bool │
│          │        │   odd_frame: bool      │
│          │        │   rendering_enabled    │
│ ─────────┴────────┴───────────────────────  │
│                                             │
│  Total: ~4,826 bytes (~4.7 KB)              │
└─────────────────────────────────────────────┘
```

### Snapshot Binary Format

```
┌─────────────────────────────────────────────┐
│ Binary Snapshot Format                      │
│                                             │
│  Offset  │ Size     │ Section               │
│ ─────────┼──────────┼──────────────────────  │
│  0       │ 64       │ Header                │
│          │          │   magic: [8]u8        │
│          │          │   version: u32        │
│          │          │   timestamp: i64      │
│          │          │   emulator_ver: [16]  │
│          │          │   total_size: u64     │
│          │          │   state_size: u32     │
│          │          │   cart_size: u32      │
│          │          │   fb_size: u32        │
│          │          │   flags: u32          │
│          │          │   checksum: u32       │
│          │          │   reserved: [8]u8     │
│ ─────────┼──────────┼──────────────────────  │
│  64      │ Variable │ Config values         │
│          │          │   (enums, ints, bools)│
│ ─────────┼──────────┼──────────────────────  │
│  ~100    │ 8        │ MasterClock           │
│ ─────────┼──────────┼──────────────────────  │
│  ~108    │ 44       │ CpuState              │
│ ─────────┼──────────┼──────────────────────  │
│  ~152    │ 2,659    │ PpuState              │
│ ─────────┼──────────┼──────────────────────  │
│  ~2,811  │ 2,088    │ BusState (ram + meta) │
│ ─────────┼──────────┼──────────────────────  │
│  ~4,899  │ Variable │ Cartridge             │
│          │          │   mode: enum          │
│          │          │   Reference mode:     │
│          │          │     - ROM path        │
│          │          │     - SHA-256 hash    │
│          │          │   Embed mode:         │
│          │          │     - iNES header     │
│          │          │     - PRG ROM data    │
│          │          │     - CHR data        │
│          │          │     - Mapper state    │
│ ─────────┼──────────┼──────────────────────  │
│  Variable│ 245,760  │ Optional Framebuffer  │
│          │          │   (256×240×4 bytes)   │
│ ─────────┴──────────┴──────────────────────  │
│                                             │
│  Total (no FB): ~5 KB                       │
│  Total (with FB): ~250 KB                   │
│  Total (embed cart): +32 KB typical         │
└─────────────────────────────────────────────┘
```

---

## Debugger State Diagram

```
                    ┌─────────────┐
                    │   CREATED   │
                    └─────────────┘
                          │
                    init(allocator, &state)
                          │
                          ▼
                    ┌─────────────┐
                    │   READY     │◄────────┐
                    └─────────────┘         │
                          │                 │
                    ┌─────┴─────┐           │
                    │           │           │
              run() │           │ step*()   │
                    ▼           ▼           │
            ┌─────────────┬─────────────┐   │
            │  RUNNING    │  STEPPING   │   │
            └─────────────┴─────────────┘   │
                    │           │           │
           ┌────────┼───────────┼────────┐  │
           │        │           │        │  │
    Breakpoint  Watchpoint   Step    Error │
      hit         hit      complete       │  │
           │        │           │        │  │
           └────────┴───────────┴────────┘  │
                          │                 │
                          ▼                 │
                    ┌─────────────┐         │
                    │  STOPPED    │─────────┘
                    └─────────────┘
                          │
                    callbacks triggered
                          │
                          ▼
                    ┌─────────────┐
                    │   READY     │
                    └─────────────┘
                          │
                      deinit()
                          │
                          ▼
                    ┌─────────────┐
                    │ DESTROYED   │
                    └─────────────┘
```

---

## Breakpoint Check Flow

```
                    ┌─────────────────┐
                    │ Before tick()   │
                    └─────────────────┘
                            │
                            ▼
                    ┌─────────────────┐
                    │ Check PC        │
                    │ breakpoints     │
                    └─────────────────┘
                            │
                    ┌───────┴───────┐
                    │               │
                Match?          No match
                    │               │
                    ▼               ▼
            ┌─────────────┐  ┌─────────────────┐
            │ Return      │  │ Check opcode    │
            │ breakpoint  │  │ breakpoints     │
            │ hit         │  └─────────────────┘
            └─────────────┘          │
                                ┌────┴────┐
                                │         │
                            Match?    No match
                                │         │
                                ▼         ▼
                        ┌─────────────┐  │
                        │ Return      │  │
                        │ breakpoint  │  │
                        │ hit         │  │
                        └─────────────┘  │
                                         │
                                         ▼
                                ┌─────────────────┐
                                │ Execute tick()  │
                                └─────────────────┘
                                         │
                                         ▼
                                ┌─────────────────┐
                                │ Check memory    │
                                │ breakpoints     │
                                └─────────────────┘
                                         │
                                ┌────────┴────────┐
                                │                 │
                            Match?            No match
                                │                 │
                                ▼                 ▼
                        ┌─────────────┐   ┌─────────────┐
                        │ Return      │   │ Continue    │
                        │ breakpoint  │   │ execution   │
                        │ hit         │   └─────────────┘
                        └─────────────┘
```

---

## File Structure

```
rambo/
├── src/
│   ├── snapshot/
│   │   ├── Snapshot.zig          # Main API
│   │   │   ├── saveBinary()      # Binary serialization
│   │   │   ├── loadBinary()      # Binary deserialization
│   │   │   ├── saveJson()        # JSON serialization
│   │   │   ├── loadJson()        # JSON deserialization
│   │   │   ├── verify()          # Checksum validation
│   │   │   └── getMetadata()     # Header parsing
│   │   │
│   │   ├── binary.zig            # Binary format implementation
│   │   │   ├── writeHeader()
│   │   │   ├── writeState()
│   │   │   ├── writeCartridge()
│   │   │   ├── readHeader()
│   │   │   ├── readState()
│   │   │   └── readCartridge()
│   │   │
│   │   ├── json.zig              # JSON format implementation
│   │   │   ├── serializeState()
│   │   │   ├── deserializeState()
│   │   │   └── base64Encode/Decode()
│   │   │
│   │   ├── cartridge.zig         # Cartridge snapshot handling
│   │   │   ├── saveReference()   # ROM path/hash
│   │   │   ├── saveEmbed()       # Full ROM data
│   │   │   ├── loadReference()   # Load from ROM file
│   │   │   └── loadEmbed()       # Reconstruct from data
│   │   │
│   │   └── checksum.zig          # CRC32 implementation
│   │       ├── calculate()
│   │       └── verify()
│   │
│   ├── debugger/
│   │   ├── Debugger.zig          # Main API
│   │   │   ├── init()
│   │   │   ├── deinit()
│   │   │   ├── run()
│   │   │   ├── step*()
│   │   │   ├── addBreakpoint*()
│   │   │   ├── addWatchpoint()
│   │   │   ├── set*()
│   │   │   └── get*()
│   │   │
│   │   ├── breakpoints.zig       # Breakpoint manager
│   │   │   ├── BreakpointManager
│   │   │   ├── add()
│   │   │   ├── remove()
│   │   │   ├── check()
│   │   │   └── checkMemory()
│   │   │
│   │   ├── watchpoints.zig       # Watchpoint manager
│   │   │   ├── WatchpointManager
│   │   │   ├── add()
│   │   │   ├── remove()
│   │   │   └── check()
│   │   │
│   │   ├── history.zig           # Execution history
│   │   │   ├── ExecutionHistory
│   │   │   ├── push()
│   │   │   ├── get()
│   │   │   └── clear()
│   │   │
│   │   ├── callbacks.zig         # Callback system
│   │   │   ├── CallbackManager
│   │   │   ├── register()
│   │   │   ├── unregister()
│   │   │   └── trigger()
│   │   │
│   │   └── disassembler.zig      # Disassembly utilities
│   │       ├── disassemble()
│   │       └── disassembleRange()
│   │
│   └── root.zig                  # Export snapshot & debugger
│
├── tests/
│   ├── snapshot/
│   │   ├── binary_test.zig       # Binary format tests
│   │   ├── json_test.zig         # JSON format tests
│   │   ├── cartridge_test.zig    # Cartridge tests
│   │   └── integration_test.zig  # Integration tests
│   │
│   └── debugger/
│       ├── breakpoint_test.zig   # Breakpoint tests
│       ├── watchpoint_test.zig   # Watchpoint tests
│       ├── step_test.zig         # Step execution tests
│       ├── history_test.zig      # History tests
│       └── integration_test.zig  # Integration tests
│
└── docs/
    ├── PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md    # Full specification
    ├── PHASE-4-3-SUMMARY.md                    # Executive summary
    └── PHASE-4-3-ARCHITECTURE.md               # This file
```

---

## API Call Hierarchy

### Snapshot Save Call Chain

```
User Code
    │
    └── Snapshot.saveBinary(allocator, &state, &config, cart, mode, fb)
            │
            ├── binary.writeHeader(writer, metadata)
            │       └── Writes 64-byte header
            │
            ├── binary.writeConfig(writer, config)
            │       └── Serializes config values only
            │
            ├── binary.writeState(writer, state)
            │       ├── Write MasterClock (8 bytes)
            │       ├── Write CpuState (44 bytes)
            │       ├── Write PpuState (2,659 bytes)
            │       └── Write BusState (2,088 bytes)
            │
            ├── cartridge.saveSnapshot(writer, cart, mode)
            │       ├── Reference mode:
            │       │   ├── Write ROM path string
            │       │   └── Write SHA-256 hash
            │       └── Embed mode:
            │           ├── Write iNES header
            │           ├── Write PRG ROM data
            │           ├── Write CHR data
            │           └── Write mapper state
            │
            ├── Optional: binary.writeFramebuffer(writer, fb)
            │       └── Write 245,760 bytes
            │
            └── checksum.calculate(data)
                    └── Return CRC32 checksum
```

### Debugger Run Call Chain

```
User Code
    │
    └── debugger.run()
            │
            └── Loop:
                    │
                    ├── breakpoints.check(&state)
                    │       ├── Check PC breakpoints
                    │       ├── Check opcode breakpoints
                    │       └── Check register breakpoints
                    │
                    ├── If breakpoint: Return DebugStopReason.breakpoint
                    │
                    ├── state.tick()  # Execute one PPU cycle
                    │
                    ├── watchpoints.check(&state, bus_access)
                    │       ├── Check read watchpoints
                    │       ├── Check write watchpoints
                    │       └── Log access if enabled
                    │
                    ├── If watchpoint: Return DebugStopReason.watchpoint
                    │
                    ├── history.push(entry)
                    │       └── Record instruction in circular buffer
                    │
                    ├── Check step mode
                    │       ├── instruction: Check if instruction complete
                    │       ├── cycle_cpu: Check if CPU cycle complete
                    │       ├── cycle_ppu: Always complete (tick() = 1 PPU cycle)
                    │       ├── scanline: Check scanline change
                    │       └── frame: Check frame_complete flag
                    │
                    └── If step complete: Return DebugStopReason.step_complete
```

---

## Performance Considerations

### Snapshot Performance

**Binary Save (5 KB state):**
```
Header write:          ~100 ns
Config serialize:      ~500 ns
State serialize:       ~2 μs
Cartridge (reference): ~200 ns
Cartridge (embed):     ~50 μs (32 KB ROM)
Checksum:              ~3 μs
─────────────────────────────
Total (reference):     ~6 μs
Total (embed):         ~56 μs
Total (with FB):       ~1.5 ms (245 KB)
```

**Binary Load (5 KB state):**
```
Header parse:          ~100 ns
Verify checksum:       ~3 μs
Config parse:          ~500 ns
State deserialize:     ~2 μs
Cartridge (reference): ~200 μs (load ROM file)
Cartridge (embed):     ~50 μs (reconstruct)
Connect pointers:      ~100 ns
─────────────────────────────
Total (reference):     ~206 μs
Total (embed):         ~56 μs
Total (with FB):       ~1.5 ms (245 KB)
```

### Debugger Performance

**Per-tick Overhead:**
```
Breakpoint check:      ~500 ns (10 breakpoints)
Watchpoint check:      ~300 ns (5 watchpoints)
History record:        ~100 ns (push to buffer)
─────────────────────────────
Total overhead:        ~900 ns per tick

Acceptable: <1 μs overhead per instruction (typically 2-7 cycles)
```

**Memory Overhead:**
```
BreakpointManager:     ~1 KB (20 breakpoints × 48 bytes)
WatchpointManager:     ~500 bytes (10 watchpoints × 48 bytes)
ExecutionHistory:      ~16 KB (512 entries × 32 bytes)
CallbackManager:       ~1 KB (10 callbacks × 96 bytes)
─────────────────────────────
Total:                 ~18.5 KB
```

---

## Cross-Platform Compatibility

### Endianness Handling

```zig
// Write multi-byte values in little-endian
fn writeU16LE(writer: anytype, value: u16) !void {
    try writer.writeByte(@truncate(value & 0xFF));
    try writer.writeByte(@truncate((value >> 8) & 0xFF));
}

fn writeU32LE(writer: anytype, value: u32) !void {
    try writer.writeByte(@truncate(value & 0xFF));
    try writer.writeByte(@truncate((value >> 8) & 0xFF));
    try writer.writeByte(@truncate((value >> 16) & 0xFF));
    try writer.writeByte(@truncate((value >> 24) & 0xFF));
}

fn writeU64LE(writer: anytype, value: u64) !void {
    try writer.writeByte(@truncate(value & 0xFF));
    try writer.writeByte(@truncate((value >> 8) & 0xFF));
    try writer.writeByte(@truncate((value >> 16) & 0xFF));
    try writer.writeByte(@truncate((value >> 24) & 0xFF));
    try writer.writeByte(@truncate((value >> 32) & 0xFF));
    try writer.writeByte(@truncate((value >> 40) & 0xFF));
    try writer.writeByte(@truncate((value >> 48) & 0xFF));
    try writer.writeByte(@truncate((value >> 56) & 0xFF));
}

// Read multi-byte values from little-endian
fn readU16LE(reader: anytype) !u16 {
    const lo = try reader.readByte();
    const hi = try reader.readByte();
    return @as(u16, hi) << 8 | lo;
}

fn readU32LE(reader: anytype) !u32 {
    const b0 = try reader.readByte();
    const b1 = try reader.readByte();
    const b2 = try reader.readByte();
    const b3 = try reader.readByte();
    return @as(u32, b3) << 24 |
           @as(u32, b2) << 16 |
           @as(u32, b1) << 8 |
           @as(u32, b0);
}

fn readU64LE(reader: anytype) !u64 {
    const b0 = try reader.readByte();
    const b1 = try reader.readByte();
    const b2 = try reader.readByte();
    const b3 = try reader.readByte();
    const b4 = try reader.readByte();
    const b5 = try reader.readByte();
    const b6 = try reader.readByte();
    const b7 = try reader.readByte();
    return @as(u64, b7) << 56 |
           @as(u64, b6) << 48 |
           @as(u64, b5) << 40 |
           @as(u64, b4) << 32 |
           @as(u64, b3) << 24 |
           @as(u64, b2) << 16 |
           @as(u64, b1) << 8 |
           @as(u64, b0);
}
```

---

## Summary

This architecture document provides visual references for:

1. **System Overview** - How snapshot/debugger fit into RAMBO architecture
2. **Data Flow** - Save/load operations step-by-step
3. **Memory Layout** - Exact byte-level structure of state and snapshots
4. **Debugger Flow** - Execution control and breakpoint checking
5. **File Structure** - Complete organization of implementation files
6. **API Hierarchy** - Call chains for major operations
7. **Performance** - Expected timing and memory overhead
8. **Cross-Platform** - Endianness handling for compatibility

**Status:** ✅ Architecture design complete and ready for implementation

**See Also:**
- [Full Specification](./PHASE-4-3-SNAPSHOT-DEBUGGER-SPEC.md)
- [Executive Summary](./PHASE-4-3-SUMMARY.md)
