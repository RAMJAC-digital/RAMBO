---
index: hardware-accuracy
name: Hardware Accuracy
description: Tasks related to fixing hardware timing and behavior accuracy issues in the NES emulator
---

# Hardware Accuracy

## Active Tasks

### High Priority
- `h-fix-vblank-subcycle-timing.md` - Fix CPU/PPU sub-cycle execution order for VBlank flag timing
- `h-verify-vblank-subcycle-timing.md` - Verify RAMBO's CPU/PPU sub-cycle execution order matches Mesen2 reference implementation and hardware spec
- `h-refactor-ppu-shift-register-rewrite.md` - Rewrite PPU to model cycle-accurate shift register behavior, fixing scanline 0 crash and mid-frame register bugs
- `h-fix-oam-nmi-accuracy.md` - Fix OAM DMA, NMI, and VBlank timing accuracy (AccuracyCoin tests, hardware spec verification)
- `h-research-mesen2-design-patterns.md` - Research Mesen2 design patterns and architecture to identify improvement opportunities for RAMBO (focus: PPU/NMI/OAM patterns)
- `h-fix-oam-dma-resume-bug.md` - Fix OAM DMA resume bug (exact cycle matching failure causing AccuracyCoin OAM tests to hang)

### Medium Priority

### Low Priority

### Investigate

## Completed Tasks
<!-- Move tasks here when completed, maintaining the format -->
