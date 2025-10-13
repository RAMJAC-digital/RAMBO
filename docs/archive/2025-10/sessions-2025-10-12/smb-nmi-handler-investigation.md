# Super Mario Bros NMI Handler Investigation

**Date:** 2025-10-10
**Status:** NMI mechanism fixed and verified via trace logging, SMB still blank screen (NMI handler stuck in loop)

## Summary

The NMI interrupt mechanism is now working correctly. Super Mario Bros successfully:

1. Sets up the game loop at `0x8057` (infinite `JMP $8057`)
2. Enables NMI by writing `0x90` to PPUCTRL
3. VBlank occurs at scanline 241 dot 1
4. NMI edge pending is set in VBlankLedger
5. **NMI FIRES** - interrupt sequence executes
6. Jumps to NMI handler at `0x8082`
7. Handler executes and eventually gets stuck in internal loop at `0x8E6C-0x8E79`

## Key Findings

### NMI Mechanism Works

The interrupt timing and edge persistence fixes resolved the core NMI issues:

- **NMI Edge Persistence:** Once `nmi_edge_pending = true`, NMI fires even after NMI_enable is disabled
- **Interrupt Timing:** Interrupt check happens in current cycle (no +1 delay)
- **Acknowledgment:** `acknowledgeCpu()` properly clears the edge after interrupt completes

Proof from trace:
```
[VBlankLedger] NMI EDGE PENDING SET!
[NMI LINE] changed false -> true at scanline=241, dot=1, ppu_cycle=350208, PC=0x8059
[PPUCTRL] Write 0x10, NMI: true -> false    # Handler DISABLES NMI
[acknowledgeCpu] Clearing nmi_edge_pending at cycle=350232   # NMI STILL FIRED!
```

### SMB NMI Handler Behavior

**NMI Vector:** `$FFFA-FFFB` = `$1615` (little endian) maps to handler at `0x8082`

**Handler Execution:**
1. Starts at `0x8082`
2. Reads and processes PPU state
3. Writes `0x10` to PPUCTRL (disables NMI)
4. Reads `$2002` (clears VBlank flag)
5. Calls subroutines
6. **Gets stuck in loop at `0x8E6C-0x8E79`**

**Loop at 0x8E6C-0x8E79:**
```
[CPU] PC=0x8E6C opcode=0x48  # PHA
[CPU] PC=0x8E6D opcode=0xBD  # LDA abs,X
[CPU] PC=0x8E70 opcode=0x85  # STA zp
[CPU] PC=0x8E72 opcode=0x4A  # LSR
[CPU] PC=0x8E73 opcode=0x05  # ORA zp
[CPU] PC=0x8E75 opcode=0x4A  # LSR
[CPU] PC=0x8E76 opcode=0x68  # PLA
[CPU] PC=0x8E77 opcode=0x2A  # ROL
[CPU] PC=0x8E78 opcode=0x88  # DEY
[CPU] PC=0x8E79 opcode=0xD0  # BNE (branches back to 0x8E6C)
```

This is a countdown loop (DEY + BNE). The handler is waiting for Y register to reach zero,
but something is preventing the loop from terminating.

## Actual Game Status

**SMB Still Shows Blank Screen:** Running `./zig-out/bin/RAMBO "Super Mario Bros. (World).nes"`
still produces a blank screen. The NMI mechanism works (verified via trace logging), but the
NMI handler gets stuck in an internal loop and never completes initialization.

## Next Steps

**NOT an NMI timing issue** - The NMI fires correctly. The problem is the NMI handler itself gets stuck.

Possible causes:
1. **PPU Rendering State:** Handler may be waiting for PPU to be in a specific state
2. **Sprite DMA:** Handler may be setting up OAM DMA that's not completing
3. **Timing:** Handler may be counting PPU cycles/scanlines incorrectly
4. **Missing Initialization:** Some game state may not be initialized correctly

## Investigation Tools Used

1. **Debug Logging:** Added trace logging for CPU execution, NMI line, VBlankLedger
2. **Pattern Matching:** Used grep to filter relevant events from trace output
3. **ROM Analysis:** Used `xxd` to inspect ROM contents and verify opcodes

## Code Changes

See commit `3540396`:
- Fixed NMI edge persistence in `VBlankLedger.shouldNmiEdge()`
- Fixed +1 cycle interrupt timing bug in `execution.zig`
- Updated test expectations in `interrupt_execution_test.zig`

## References

- NES Dev Wiki: https://www.nesdev.org/wiki/NMI
- Audit Document: docs/dot/irq-nmi-audit-2025-10-09.md
- VBlank Architecture: docs/code-review/vblank-nmi-architecture-review-2025-10-09.md
