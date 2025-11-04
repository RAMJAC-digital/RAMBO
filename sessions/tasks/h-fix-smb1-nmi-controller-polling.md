---
name: h-fix-smb1-nmi-controller-polling
branch: fix/h-fix-smb1-nmi-controller-polling
status: pending
created: 2025-11-04
---

# Fix SMB1 NMI Controller Polling

## Problem/Goal

Super Mario Bros 1 does not respond to controller input, making the game unplayable. Other ROMs (Castlevania, Mega Man, Kid Icarus, etc.) respond correctly to controller input, indicating this is SMB1-specific behavior.

**Root Cause:** SMB1 reads controller input in its NMI handler during VBlank. If NMI timing is incorrect for SMB1's specific expectations, the NMI handler never executes, and controller polling never happens.

This task builds on the NMI/VBlank/OAM accuracy work in `fix/h-fix-oam-nmi-accuracy`, leveraging the refactoring and improvements already made to the bus handler architecture and timing systems.

**Reference:** SMB1 disassembly available at https://gist.github.com/1wErt3r/4048722

## Success Criteria

- [ ] **SMB1 controller input responsive** - Mario moves and jumps in response to D-pad and button input
- [ ] **NMI fires correctly for SMB1** - NMI handler executes every frame at expected timing
- [ ] **Test coverage for SMB1 NMI flow** - Tests written based on SMB1 disassembly to capture NMI/controller polling sequence
- [ ] **No regressions** - Other working ROMs (Castlevania, Mega Man, Kid Icarus, etc.) continue to work
- [ ] **Controller polling in NMI verified** - Confirm SMB1's controller read happens in NMI handler as expected

## Context Manifest

### Hardware Specification: NMI/VBlank Timing and Controller Polling

**ALWAYS START WITH HARDWARE DOCUMENTATION**

[VERBOSE HARDWARE DESCRIPTION with nesdev.org citations:]

According to the NES hardware documentation (https://www.nesdev.org/wiki/NMI), the Non-Maskable Interrupt (NMI) is triggered when the PPU enters VBlank period at scanline 241, dot 1. Games rely on NMI to perform frame-synchronized operations like controller polling, sprite updates, and sound processing.

**VBlank/NMI Timing Sequence:**
- **Scanline 241, dot 0:** CPU read of $2002 during this cycle can prevent VBlank flag from being set (race condition window)
- **Scanline 241, dot 1:** VBlank flag set, NMI triggered if PPUCTRL bit 7 enabled (citation: nesdev.org/wiki/PPU_frame_timing)
- **NMI Handler Execution:** CPU vectors to address at $FFFA-$FFFB (NMI vector), executes game's VBlank handler
- **Scanline -1 (261), dot 1:** VBlank flag cleared at start of pre-render scanline

**NMI Edge Detection (CPU Side):**
- NMI is **edge-triggered** (falling edge: high → low transition)
- CPU samples NMI line at **end of each cycle**, checks at **start of next cycle** ("second-to-last cycle" rule)
- Citation: https://www.nesdev.org/wiki/CPU_interrupts
- NMI cannot be masked by I flag (unlike IRQ)
- NMI has priority over IRQ during interrupt sequences

**Controller Hardware Timing:**
- Controllers are 8-bit shift registers (4021 chip) accessed via $4016/$4017
- Strobe bit (write $01 to $4016) latches current button state into shift register
- Strobe clear (write $00 to $4016) enables serial read mode
- Reading $4016 returns bit 0 (current button) and shifts register right
- Button order: A, B, Select, Start, Up, Down, Left, Right (LSB to MSB)
- Citation: https://www.nesdev.org/wiki/Standard_controller

**Why the Hardware Works This Way:**
The NMI timing exists because NTSC CRT displays require VBlank period for electron beam retrace. The PPU provides a fixed 20 scanline VBlank window (scanlines 241-260, ~2273 CPU cycles) for games to perform updates without visual artifacts. Games universally use NMI handlers for controller polling because it's the only guaranteed frame-synchronization mechanism.

**Edge Cases & Boundary Conditions:**
- **Race condition at 241:0-2:** Reading $2002 during race window prevents VBlank flag set (hardware quirk)
- **NMI suppression:** Reading $2002 at exactly dot 1 reads VBlank as set then immediately clears it, suppressing NMI
- **Multiple NMI per VBlank:** Toggling PPUCTRL bit 7 (0→1→0→1) during VBlank triggers multiple NMIs (hardware allows this)
- **Controller strobe timing:** Must strobe THEN clear before reading (some games poll multiple times per frame)

### SMB1 Disassembly Analysis: NMI and Controller Polling Flow

[VERBOSE NARRATIVE explaining SMB1's specific implementation:]

Super Mario Bros reads controller input **exclusively in its NMI handler**. The game does NOT poll controllers anywhere else in its code. This is verified by the SMB1 disassembly at https://gist.github.com/1wErt3r/4048722.

**SMB1 NMI Handler Location:**
- NMI vector at $FFFA-$FFFB points to `NonMaskableInterrupt` routine
- NMI handler is the ONLY place SMB1 reads controllers

**SMB1 NMI Handler Execution Flow:**

```assembly
NonMaskableInterrupt:
    ; 1. Disable NMI to prevent nested interrupts
    lda Mirror_PPU_CTRL_REG1     ; Load mirror of PPUCTRL
    and #%01111111               ; Clear bit 7 (NMI enable)
    sta Mirror_PPU_CTRL_REG1     ; Update mirror

    ; 2. Configure PPU for VRAM updates
    and #%01111110               ; Set nametable to $2800 (effectively $2000)
    sta PPU_CTRL_REG1            ; Write to $2000

    ; 3. Disable rendering temporarily
    lda Mirror_PPU_CTRL_REG2     ; Load PPUMASK mirror
    and #%11100110               ; Disable BG and sprite rendering
    ldy DisableScreenFlag
    bne ScreenOff
    lda Mirror_PPU_CTRL_REG2     ; Re-enable if flag clear
    ora #%00011110
ScreenOff:
    sta Mirror_PPU_CTRL_REG2
    and #%11100111
    sta PPU_CTRL_REG2            ; Write to $2001

    ; 4. Reset PPU scroll
    ldx PPU_STATUS               ; Read $2002 to reset PPU address latch
    lda #$00
    jsr InitScroll

    ; 5. Perform OAM DMA
    sta PPU_SPR_ADDR             ; Reset sprite address to $00
    lda #$02
    sta SPR_DMA                  ; Trigger DMA from $0200-$02FF

    ; 6. Update VRAM buffers
    ldx VRAM_Buffer_AddrCtrl
    lda VRAM_AddrTable_Low,x
    sta $00
    lda VRAM_AddrTable_High,x
    sta $01
    jsr UpdateScreen

    ; 7. Clear VRAM buffers
    ldy #$00
    ldx VRAM_Buffer_AddrCtrl
    cpx #$06
    bne InitBuffer
    iny
InitBuffer:
    ldx VRAM_Buffer_Offset,y
    lda #$00
    sta VRAM_Buffer1_Offset,x
    sta VRAM_Buffer1,x
    sta VRAM_Buffer_AddrCtrl

    ; 8. Re-enable rendering
    lda Mirror_PPU_CTRL_REG2
    sta PPU_CTRL_REG2

    ; 9. Handle audio
    jsr SoundEngine

    ; 10. **CONTROLLER POLLING** - THIS IS WHERE INPUT IS READ
    jsr ReadJoypads              ; <-- CRITICAL: Only controller read in entire game!

    ; 11. Handle pause
    jsr PauseRoutine

    ; 12. Update score display
    jsr UpdateTopScore

    ; 13. Decrement timers if not paused
    lda GamePauseStatus
    lsr
    bcs PauseSkip
    lda TimerControl
    beq DecTimers
    dec TimerControl
    bne NoDecTimers
DecTimers:
    ldx #$14
    ; ... timer decrement loop ...
```

**ReadJoypads Subroutine (Line 10 above):**

```assembly
ReadJoypads:
    lda #$01                ; Strobe high
    sta JOYPAD_PORT         ; Write to $4016 - latch buttons
    lsr                     ; A = $00
    tax                     ; X = 0 (controller 1 index)
    sta JOYPAD_PORT         ; Write $00 to $4016 - clear strobe, enable shifting
    jsr ReadPortBits        ; Read 8 bits from controller 1
    inx                     ; X = 1 (controller 2 index)
ReadPortBits:
    ldy #$08                ; 8 bits to read
PortLoop:
    pha                     ; Save accumulator
    lda JOYPAD_PORT,x       ; Read from $4016 or $4017
    sta $00                 ; Famicom-specific: check d1 and d0
    lsr                     ; Shift right to get bit 0
    ora $00                 ; OR with original (handles Famicom expansion port)
    lsr                     ; Shift again
    pla                     ; Restore accumulator
    rol                     ; Rotate carry into accumulator
    dey
    bne PortLoop            ; Loop for all 8 buttons
    sta SavedJoypadBits,x   ; Store final button state
    ; ... additional filtering for Select/Start ...
    rts
```

**Critical SMB1 Behavior:**
1. **NMI Handler is ONLY controller read location** - If NMI doesn't fire, SMB1 NEVER sees controller input
2. **NMI runs EVERY frame** - SMB1 expects 60 Hz NMI for responsive controls
3. **Controller polling happens mid-NMI** - After OAM DMA, before game logic
4. **No polling outside NMI** - Main game loop never reads $4016/$4017 directly

**Why SMB1 Doesn't Respond to Input:**
If RAMBO's NMI timing is incorrect for SMB1's specific expectations:
- NMI handler never executes → `ReadJoypads` never called → buttons never read
- Even if controller mailbox updates work perfectly, SMB1 never reads the hardware registers
- Game main loop continues but with stale/zero controller data in `SavedJoypadBits`

**Contrast with Working Games (Castlevania, Mega Man):**
These games likely have more robust NMI handling or poll controllers outside NMI as fallback. SMB1 is a "canary" - its strict NMI-only polling exposes timing bugs that other games tolerate.

### Current NMI Implementation (fix/h-fix-oam-nmi-accuracy Branch)

[VERBOSE NARRATIVE explaining current codebase implementation:]

RAMBO's NMI implementation is currently undergoing refactoring on the `fix/h-fix-oam-nmi-accuracy` branch. This branch has already completed the bus handler architecture migration (2025-11-04) with zero compilation errors and 98.1% test pass rate (1162/1184 tests).

**Recent Investigation (2025-11-04):**
The file `docs/investigation/vblank-nmi-remediation-2025-11-04.md` contains a comprehensive analysis comparing RAMBO's VBlank/NMI timing against Mesen2 (hardware-accurate reference emulator). Key finding:

**ONE CRITICAL BUG IDENTIFIED:**
- **Location:** `src/emulation/bus/handlers/PpuHandler.zig:72`
- **Bug:** Prevention window uses `dot <= 2` instead of `dot == 0`
- **Impact:** VBlank incorrectly suppressed in 2/3 CPU/PPU phase alignments (66.7% failure rate)
- **Expected after fix:** +3 to +8 tests passing, grey screen games (Paperboy, Tetris) should boot

**VBlank/NMI Architecture:**

RAMBO uses a **timestamp-based VBlank ledger** pattern (functionally equivalent to Mesen2's flag-based approach):

**State Organization:**
- VBlank timestamps stored in `src/emulation/VBlankLedger.zig`:
  - `last_set_cycle: u64` - When VBlank flag was set (scanline 241 dot 1)
  - `last_clear_cycle: u64` - When VBlank flag was cleared (scanline -1 dot 1 OR $2002 read)
  - `last_read_cycle: u64` - When $2002 (PPUSTATUS) was last read
  - `prevent_vbl_set_cycle: u64` - Prevention flag for race condition (dot 0 reads)

**Logic Flow (Execution Order CRITICAL):**

From `src/emulation/State.zig:tick()` lines 500-580:

```
1. PPU Tick (advance PPU state machine)
   - Scanline/dot advancement
   - Rendering operations
   - A12 edge detection
   - Signal VBlank events (nmi_signal, vblank_clear flags)

2. APU Tick (if aligned - synchronized with CPU)
   - Frame counter
   - DMC DMA triggers
   - IRQ generation

3. CPU Execution (BEFORE VBlank timestamp application)
   - CPU microstep execution
   - Can read $2002 and set prevent_vbl_set_cycle flag
   - THIS ORDERING IS CRITICAL for prevention mechanism

4. Apply VBlank Timestamps (AFTER CPU execution)
   - Check prevent_vbl_set_cycle flag
   - Set last_set_cycle if not prevented
   - Clear prevent_vbl_set_cycle (one-shot flag)
   - Handle last_clear_cycle updates

5. Update NMI Line (AFTER VBlank timestamps finalized)
   - nmi_line = vblank_visible && nmi_enable
   - Continuous update every cycle
   - Reflects final VBlank state

6. Sample Interrupt Lines (ONLY on CPU ticks)
   - Call CpuLogic.checkInterrupts()
   - NMI edge detection: if (nmi_line && !nmi_prev) -> pending_interrupt = .nmi
   - IRQ level detection: if (irq_line && !p.interrupt && pending == .none)
   - Store nmi_pending_prev, irq_pending_prev for next cycle
   - Clear pending_interrupt (restored next cycle via _prev)
```

**Critical Implementation Detail (2025-11-03 Fix):**
CPU execution happens BEFORE VBlank timestamps are applied. This allows the prevention mechanism to work correctly:
- CPU reads $2002 at dot 0 → sets `prevent_vbl_set_cycle = master_cycles`
- VBlank timestamp application at dot 1 checks `if (prevent_vbl_set_cycle != 0)` → skips setting flag
- Interrupt sampling happens AFTER VBlank state finalized → ensures correct NMI line state

**Hardware Citations:**
- Primary: https://www.nesdev.org/wiki/PPU_frame_timing (VBlank timing)
- NMI: https://www.nesdev.org/wiki/NMI (edge detection, priority)
- CPU interrupts: https://www.nesdev.org/wiki/CPU_interrupts (second-to-last cycle rule)
- Reference: Mesen2 NesPpu.cpp:590-592 (prevention flag), 1340-1344 (VBlank set with check)
- Reference: Mesen2 NesCpu.cpp:294-314 (NMI edge detection)

### Controller Input System: Mailbox to Hardware Flow

[VERBOSE NARRATIVE explaining controller input architecture:]

RAMBO uses a **lock-free mailbox pattern** to communicate controller input from the main thread (XDG input events) to the emulation thread (hardware register emulation).

**Data Flow Architecture:**

```
Main Thread → ControllerInputMailbox → Emulation Thread → ControllerState → $4016/$4017 Hardware Registers
```

**Step-by-Step Flow:**

**1. Input Capture (Main Thread or Backend):**
- **Wayland/Vulkan backend:** `src/video/backends/VulkanBackend.zig` (XDG input events)
- **Terminal backend:** `src/video/backends/MovyBackend.zig` (raw terminal input)
- Keyboard events mapped to NES buttons via `src/input/KeyboardMapper.zig`
- `ButtonState` packed struct (8 bools → u8) - matches NES shift register order

**2. Mailbox Post:**
```zig
// From src/main.zig:323 or MovyBackend.zig:425
mailboxes.controller_input.postController1(button_state);
```

**3. Mailbox Implementation:**
- File: `src/mailboxes/ControllerInputMailbox.zig`
- Type: Atomic lock-free double-buffered mailbox
- `postController1(ButtonState)` - Write button state atomically
- `getInput() ControllerInput` - Read current state (non-blocking)

**4. Emulation Thread Poll (Every Frame):**
From `src/threads/EmulationThread.zig:94-96`:
```zig
// Poll controller input mailbox and update controller state
const input = ctx.mailboxes.controller_input.getInput();
ctx.state.controller.updateButtons(
    input.controller1.toByte(),
    input.controller2.toByte()
);
```

**5. ControllerState Update:**
File: `src/emulation/state/peripherals/ControllerState.zig`
```zig
pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
    self.buttons1 = buttons1;  // Store current button state
    self.buttons2 = buttons2;
    // If strobe is high, immediately reload shift registers
    if (self.strobe) {
        self.latch();  // shift1 = buttons1, shift2 = buttons2
    }
}
```

**6. Hardware Register Emulation:**
File: `src/emulation/bus/handlers/ControllerHandler.zig`

**Write to $4016 (strobe control):**
```zig
pub fn write(_: *ControllerHandler, state: anytype, address: u16, value: u8) void {
    const reg = address & 0x01;
    if (reg == 0) {
        // $4016: Controller strobe
        state.controller.writeStrobe(value);  // Latch if bit 0 set
    }
    // $4017 writes go to APU frame counter
}
```

**Read from $4016/$4017 (button data):**
```zig
pub fn read(_: *const ControllerHandler, state: anytype, address: u16) u8 {
    const reg = address & 0x01;

    const controller_bit = if (reg == 0)
        state.controller.read1()  // Read bit 0, shift right
    else
        state.controller.read2();

    // Hardware behavior: bits 1-4 always 0, bits 5-7 from open bus
    return controller_bit | (state.bus.open_bus & 0xE0);
}
```

**7. ControllerState Shift Register Behavior:**
```zig
pub fn read1(self: *ControllerState) u8 {
    if (self.strobe) {
        // Strobe high: continuously return current A button state
        return self.buttons1 & 0x01;
    } else {
        // Strobe low: shift mode
        const bit = self.shift1 & 0x01;
        self.shift1 = (self.shift1 >> 1) | 0x80;  // Shift right, fill with 1s
        return bit;
    }
}
```

**Critical Timing Behavior:**
- `updateButtons()` called ONCE per frame at start of emulation thread tick
- Games can read $4016 MULTIPLE times per frame (SMB1 reads 8 times in NMI)
- Strobe must be written HIGH then LOW before reading (hardware requirement)
- If strobe stays HIGH, reads return current A button continuously (hardware behavior)
- After 8 reads with strobe LOW, shift register fills with 1s (hardware behavior)

**Integration Points:**
- **EmulationState.controller:** `ControllerState` instance (line 122 of State.zig)
- **EmulationState.handlers.controller:** `ControllerHandler` instance (line 106)
- **Bus routing:** $4016-$4017 → ControllerHandler.read/write

**Why This Works for Most Games:**
- Mailbox updates happen BEFORE frame emulation starts
- Controller state persists for entire frame
- Games read during NMI (mid-frame) see consistent button state
- No race conditions - atomic mailbox ensures clean reads

**Why This Might Fail for SMB1:**
If NMI doesn't fire, SMB1 never reads $4016/$4017, so mailbox updates are irrelevant. The problem is NOT the controller input system - it's the NMI timing that prevents SMB1's handler from executing.

### Bus Handler Architecture: PpuHandler and ControllerHandler

[VERBOSE NARRATIVE explaining bus handler pattern:]

RAMBO recently migrated (2025-11-04) from monolithic bus routing to a **stateless handler delegation pattern** that mirrors the cartridge mapper architecture.

**Handler Pattern Characteristics:**

**Zero-Size Handlers:**
```zig
pub const PpuHandler = struct {
    // NO fields - completely stateless!
    // @sizeOf(PpuHandler) == 0
};
```

**Interface (all handlers implement):**
```zig
pub fn read(_: *const Handler, state: anytype, address: u16) u8
pub fn write(_: *Handler, state: anytype, address: u16, value: u8) void
pub fn peek(_: *const Handler, state: anytype, address: u16) u8  // debugger-safe
```

**State Access via Parameter:**
Handlers are completely stateless - they access emulation state via the `state` parameter:
- `state.ppu` - PPU registers and rendering state
- `state.vblank_ledger` - VBlank timing ledger
- `state.cpu` - CPU state (NMI line, etc.)
- `state.clock` - Master clock (cycle counts)
- `state.controller` - Controller shift registers
- `state.bus` - Open bus value

**PpuHandler ($2000-$3FFF) - Most Complex:**

File: `src/emulation/bus/handlers/PpuHandler.zig`

**Complexity: ⭐⭐⭐⭐⭐ (5/5)** - Timing-sensitive, NMI coordination, race conditions

**Critical Behaviors:**

**1. VBlank Race Detection (read() lines 63-77):**
```zig
if (reg == 0x02) {  // $2002 PPUSTATUS
    const scanline = state.ppu.scanline;
    const dot = state.ppu.cycle;

    // Prevention window: scanline 241, dot 0 ONLY
    // BUG (TO BE FIXED): Currently uses dot <= 2 (incorrect)
    if (scanline == 241 and dot == 0) {
        state.vblank_ledger.prevent_vbl_set_cycle = state.clock.master_cycles;
    }
}
```

**2. $2002 Read Side Effects (read() lines 89-98):**
```zig
if (result.read_2002) {
    // ALWAYS record timestamp (hardware behavior)
    state.vblank_ledger.last_read_cycle = state.clock.master_cycles;

    // ALWAYS clear NMI line (per Mesen2)
    state.cpu.nmi_line = false;
}
```

**3. PPUCTRL NMI Line Management (write() lines 122-136):**
```zig
if (reg == 0x00) {  // $2000 PPUCTRL
    const old_nmi_enable = state.ppu.ctrl.nmi_enable;
    const new_nmi_enable = (value & 0x80) != 0;
    const vblank_active = state.vblank_ledger.isFlagVisible();

    // Edge trigger: 0→1 transition while VBlank active
    if (!old_nmi_enable and new_nmi_enable and vblank_active) {
        state.cpu.nmi_line = true;  // Immediate NMI trigger
    }

    // Disable: 1→0 transition clears NMI
    if (old_nmi_enable and !new_nmi_enable) {
        state.cpu.nmi_line = false;
    }
}
```

**ControllerHandler ($4016-$4017) - Medium Complexity:**

File: `src/emulation/bus/handlers/ControllerHandler.zig`

**Complexity: ⭐⭐ (2/5)** - Shift registers + open bus masking

**Key Behaviors:**

**1. Read with Open Bus Masking (read() lines 50-62):**
```zig
const controller_bit = if (reg == 0)
    state.controller.read1()  // Returns bit 0, shifts register
else
    state.controller.read2();

// Hardware: bits 1-4 always 0, bits 5-7 from open bus
return controller_bit | (state.bus.open_bus & 0xE0);
```

**2. Strobe Control (write() lines 80-90):**
```zig
if (reg == 0) {
    // $4016: Controller strobe
    state.controller.writeStrobe(value);  // Bit 0 controls strobe
} else {
    // $4017: APU frame counter
    ApuLogic.writeFrameCounter(&state.apu, value);
}
```

**Benefits of Handler Architecture:**
- Clear separation: Each handler owns its address space (mirrors hardware chips)
- Independently testable: Handlers unit-tested with real state
- Debugger-safe: `peek()` allows inspection without side effects
- Zero overhead: Handlers are zero-size, all inlined by compiler
- Hardware-accurate: Handler boundaries match NES chip architecture

**Integration in EmulationState:**
From `src/emulation/State.zig:99-109`:
```zig
handlers: struct {
    open_bus: OpenBusHandler = .{},
    ram: RamHandler = .{},
    ppu: PpuHandler = .{},         // <-- VBlank/NMI coordination
    apu: ApuHandler = .{},
    controller: ControllerHandler = .{},  // <-- Controller I/O
    oam_dma: OamDmaHandler = .{},
    cartridge: CartridgeHandler = .{},
} = .{},
```

**Bus Routing Dispatch:**
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    const value = switch (address) {
        0x2000...0x3FFF => self.handlers.ppu.read(self, address),
        0x4016, 0x4017 => self.handlers.controller.read(self, address),
        // ... other handlers ...
    };

    // Open bus capture (hardware behavior)
    if (address != 0x4015) {
        self.bus.open_bus = value;
    }

    return value;
}
```

### State/Logic Abstraction Plan

**State Changes Required:**

**No new state fields anticipated.** The NMI/controller system already has all necessary state:

**Existing State (Sufficient):**
- `src/emulation/VBlankLedger.zig` - VBlank timestamp tracking (complete)
- `src/emulation/state/peripherals/ControllerState.zig` - Controller shift registers (complete)
- `src/cpu/State.zig` - NMI line, edge detector, pending interrupts (complete)
- `src/ppu/State.zig` - PPUCTRL.nmi_enable, scanline/dot (complete)

**Potential Bug Fix Location:**
- `src/emulation/bus/handlers/PpuHandler.zig:72` - Prevention window timing (dot <= 2 → dot == 0)

**Logic Implementation Locations:**

**Primary logic (already implemented, may need adjustment):**
- `src/emulation/State.zig:tick()` - Main emulation loop (CPU/PPU/NMI coordination)
- `src/emulation/State.zig:applyVBlankTimestamps()` - VBlank timestamp application
- `src/cpu/Logic.zig:checkInterrupts()` - NMI edge detection
- `src/emulation/bus/handlers/PpuHandler.zig` - PPU register I/O with NMI side effects
- `src/emulation/bus/handlers/ControllerHandler.zig` - Controller register I/O

**Helper functions (existing, pure):**
- `src/emulation/VBlankLedger.zig:isFlagVisible()` - Check if VBlank readable
- `src/emulation/VBlankLedger.zig:isActive()` - Check if in VBlank span
- `src/emulation/state/peripherals/ControllerState.zig:updateButtons()` - Update from mailbox
- `src/emulation/state/peripherals/ControllerState.zig:read1/read2()` - Shift register reads

**Maintaining Purity:**

All logic functions maintain pure function pattern:
- State passed via explicit parameters (cpu: *CpuState, state: *EmulationState)
- No global variables or hidden mutations
- Side effects limited to mutations of passed pointers
- Cycle timing tracked explicitly in parameters and ledgers

**Example (existing pattern to follow):**
```zig
// Pure function - all state explicit
pub fn checkInterrupts(state: *CpuState) void {
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        state.pending_interrupt = .nmi;  // Explicit mutation
    }
    // ... IRQ check ...
}
```

### Readability Guidelines

**For This Investigation:**

The task is NOT to implement new functionality - it's to **diagnose why SMB1's NMI handler never executes**.

**Prioritize:**
1. **Diagnostic clarity:** Add extensive tracing/logging to understand NMI firing patterns
2. **Test-driven debugging:** Create SMB1-specific NMI test based on disassembly analysis
3. **Minimal code changes:** Only fix what's broken (likely single-line fix per investigation doc)
4. **Hardware citations:** Every change must cite nesdev.org or Mesen2 reference

**Code Structure Principles:**
- If adding debug output, use conditional compilation or runtime flags
- Extensive comments explaining SMB1's specific NMI/controller expectations
- Break complex NMI timing logic into well-named helper functions if needed
- Example: `isSmbNmiTimingCorrect()` more readable than inline boolean maze

**Investigation Strategy:**
1. Verify prevention window fix (dot <= 2 → dot == 0) resolves issue
2. If not, add cycle-accurate NMI trace comparing RAMBO vs Mesen2
3. Create SMB1-specific test that reproduces NMI handler execution
4. Verify `ReadJoypads` actually gets called (controller reads at $4016)

### Technical Reference

#### Hardware Citations

**Primary References:**
- NMI timing: https://www.nesdev.org/wiki/NMI
- PPU frame timing: https://www.nesdev.org/wiki/PPU_frame_timing
- CPU interrupts: https://www.nesdev.org/wiki/CPU_interrupts (second-to-last cycle rule)
- Controller hardware: https://www.nesdev.org/wiki/Standard_controller
- VBlank race condition: https://www.nesdev.org/wiki/PPU_frame_timing ("Reading one PPU clock before")

**Mesen2 Reference Implementation:**
- VBlank prevention: NesPpu.cpp:590-592 (sets _preventVblFlag at cycle 0)
- VBlank set with check: NesPpu.cpp:1340-1344 (checks !_preventVblFlag before setting)
- NMI edge detection: NesCpu.cpp:294-314 (EndCpuCycle), lines 306-309 (edge trigger)
- PPUSTATUS read: NesPpu.cpp:587-588 (clears VBlank flag + NMI line unconditionally)
- PPUCTRL write: NesPpu.cpp:543-560 (updates NMI flag based on new state)

**SMB1 Disassembly:**
- Full disassembly: https://gist.github.com/1wErt3r/4048722
- NMI handler: `NonMaskableInterrupt` label (vectors from $FFFA)
- Controller polling: `ReadJoypads` subroutine (called from NMI handler only)
- NMI vector: $FFFA-$FFFB → `NonMaskableInterrupt` address

#### Related State Structures

```zig
// src/emulation/VBlankLedger.zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,      // VBlank set at scanline 241 dot 1
    last_clear_cycle: u64 = 0,    // VBlank clear at scanline -1 dot 1 OR $2002 read
    last_read_cycle: u64 = 0,     // Last $2002 read timestamp
    prevent_vbl_set_cycle: u64 = 0,  // Prevention flag (dot 0 read)

    pub fn isFlagVisible(self: VBlankLedger) bool;  // VBlank readable?
    pub fn isActive(self: VBlankLedger) bool;       // In VBlank span?
};

// src/emulation/state/peripherals/ControllerState.zig
pub const ControllerState = struct {
    shift1: u8 = 0,       // Controller 1 shift register
    shift2: u8 = 0,       // Controller 2 shift register
    strobe: bool = false, // Strobe state (latch vs shift mode)
    buttons1: u8 = 0,     // Button data for controller 1 (from mailbox)
    buttons2: u8 = 0,     // Button data for controller 2

    pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void;
    pub fn read1(self: *ControllerState) u8;  // Read bit 0, shift register
    pub fn read2(self: *ControllerState) u8;
    pub fn writeStrobe(self: *ControllerState, value: u8) void;
};

// src/cpu/State.zig (relevant NMI fields)
pub const CpuState = struct {
    nmi_line: bool = false,              // NMI line state (active low in hardware)
    nmi_edge_detected: bool = false,     // Edge detector state (prev cycle)
    pending_interrupt: InterruptType = .none,  // .nmi, .irq, or .none
    nmi_pending_prev: bool = false,      // Stored for "second-to-last cycle" rule
    irq_pending_prev: bool = false,
    // ... other CPU registers ...
};

// src/ppu/State.zig (relevant PPUCTRL field)
pub const PpuCtrl = packed struct(u8) {
    // ... other fields ...
    nmi_enable: bool,  // Bit 7: Enable NMI on VBlank
};
```

#### Related Logic Functions

```zig
// src/cpu/Logic.zig
pub fn checkInterrupts(state: *CpuState) void
// NMI edge detection: if (nmi_line && !nmi_prev) -> pending_interrupt = .nmi
// IRQ level detection: if (irq_line && !p.interrupt && pending == .none)

// src/emulation/State.zig
pub fn tick(self: *EmulationState) void
// Main emulation loop - coordinates CPU/PPU/APU/DMA
// Lines 500-580: Critical execution ordering for NMI timing

fn applyVBlankTimestamps(self: *EmulationState, result: PpuCycleResult) void
// Lines 582-614: Apply VBlank events with prevention check

// src/emulation/bus/handlers/PpuHandler.zig
pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8
// Lines 59-101: $2002 read with VBlank race detection + NMI clear

pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void
// Lines 116-141: $2000 write with immediate NMI trigger on 0→1 edge

// src/emulation/bus/handlers/ControllerHandler.zig
pub fn read(_: *const ControllerHandler, state: anytype, address: u16) u8
// Lines 50-62: $4016/$4017 read with open bus masking

pub fn write(_: *ControllerHandler, state: anytype, address: u16, value: u8) void
// Lines 80-90: $4016 strobe control, $4017 APU frame counter

// src/emulation/VBlankLedger.zig
pub fn isFlagVisible(self: VBlankLedger) bool
// Returns true if VBlank flag readable on PPU bus (active && not read)

pub fn isActive(self: VBlankLedger) bool
// Returns true if in VBlank span (between set and clear)
```

#### File Locations

**Primary investigation targets:**
- Prevention window bug: `src/emulation/bus/handlers/PpuHandler.zig:72`
- NMI timing coordination: `src/emulation/State.zig:tick()` lines 500-580
- VBlank timestamp application: `src/emulation/State.zig:applyVBlankTimestamps()` lines 582-614
- NMI edge detection: `src/cpu/Logic.zig:checkInterrupts()` lines 59-76

**Controller system (likely working correctly):**
- Mailbox integration: `src/threads/EmulationThread.zig:94-96`
- Button state update: `src/emulation/state/peripherals/ControllerState.zig:35-42`
- Hardware register I/O: `src/emulation/bus/handlers/ControllerHandler.zig`

**Test coverage (for verification):**
- NMI edge trigger: `tests/integration/nmi_edge_trigger_test.zig`
- NMI control: `tests/integration/accuracy/nmi_control_test.zig`
- VBlank behavior: `tests/ppu/vblank_behavior_test.zig`
- VBlank/NMI timing: `tests/ppu/vblank_nmi_timing_test.zig`
- SMB VBlank repro: `tests/integration/smb_vblank_reproduction_test.zig`
- ⚠️ **Need to create:** SMB1-specific NMI handler execution test

**Investigation documentation:**
- VBlank/NMI timing analysis: `docs/investigation/vblank-nmi-remediation-2025-11-04.md`
- Current issues: `docs/CURRENT-ISSUES.md` (SMB1 status: controller not responding)
- Test status: `docs/STATUS.md` (1162/1184 passing, 98.1%)

#### Expected Changes

**Most Likely Fix (per investigation doc):**
```zig
// File: src/emulation/bus/handlers/PpuHandler.zig:72
// Current (BUG):
if (scanline == 241 and dot <= 2 and state.clock.isCpuTick()) {

// Fixed:
if (scanline == 241 and dot == 0 and state.clock.isCpuTick()) {
```

**Test Creation (new file):**
```zig
// File: tests/integration/smb1_nmi_controller_test.zig
// Reproduce SMB1 NMI handler execution and controller polling
// Based on disassembly analysis:
// 1. Load SMB1 ROM
// 2. Run to first NMI (frame 1-3)
// 3. Verify NMI handler PC reached (NonMaskableInterrupt address)
// 4. Verify ReadJoypads called (check $4016 read count)
// 5. Inject controller input via mailbox
// 6. Verify SavedJoypadBits updated with button data
```

**Potential Additional Fixes (if prevention window fix insufficient):**
- NMI sampling timing adjustment (unlikely - already verified correct)
- VBlank ledger state machine edge case (unlikely - comprehensive investigation found none)
- Phase alignment issue (unlikely - investigation covered all 3 phases)

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
