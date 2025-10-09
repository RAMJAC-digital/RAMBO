# RAMBO Test Suite Audit - Visual Summary

## Current State (77 files, 936/956 passing)

```
┌─────────────────────────────────────────────────────────────────┐
│                    RAMBO Test Suite (77 files)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU Tests (18 files) ✅                                        │
│  ├─ opcodes/*.zig (11 files, ~150 tests)      [KEEP]           │
│  ├─ instructions_test.zig (30 tests, 698L)    [REVIEW]         │
│  ├─ rmw_test.zig, interrupt_logic_test.zig    [KEEP]           │
│  └─ page_crossing_test.zig, etc.              [KEEP]           │
│                                                                 │
│  PPU Tests (16 files) ⚠️                                        │
│  ├─ VBlank Tests (10 files)                                    │
│  │   ├─ vblank_nmi_timing_test.zig ✅         [KEEP - Core]    │
│  │   ├─ ppustatus_read_test.zig ✅            [CONSOLIDATE]    │
│  │   ├─ ppustatus_polling_test.zig ✅         [CONSOLIDATE]    │
│  │   ├─ vblank_debug_test.zig ❌              [DELETE]         │
│  │   ├─ vblank_minimal_test.zig              [DELETE]         │
│  │   ├─ vblank_tracking_test.zig             [DELETE]         │
│  │   ├─ vblank_persistence_test.zig          [DELETE]         │
│  │   ├─ vblank_polling_simple_test.zig       [DELETE]         │
│  │   └─ clock_sync_test.zig ❌               [DELETE]         │
│  │                                                              │
│  └─ Sprite Tests (6 files) ✅                 [KEEP ALL]       │
│      └─ sprite_rendering, sprite_edge_cases, etc.              │
│                                                                 │
│  APU Tests (8 files) ✅                                         │
│  └─ All comprehensive and passing             [KEEP ALL]       │
│                                                                 │
│  Integration Tests (22 files) ⚠️                               │
│  ├─ Bomberman Debug (5 files) ❌              [DELETE ALL]     │
│  │   ├─ bomberman_hang_investigation.zig                       │
│  │   ├─ bomberman_detailed_hang_analysis.zig                   │
│  │   ├─ bomberman_debug_trace_test.zig                         │
│  │   ├─ bomberman_exact_simulation.zig                         │
│  │   └─ commercial_nmi_trace_test.zig                          │
│  │                                                              │
│  ├─ VBlank Debug (3 files) ❌                 [DELETE ALL]     │
│  │   ├─ vblank_exact_trace.zig                                 │
│  │   ├─ detailed_trace.zig                                     │
│  │   └─ nmi_sequence_test.zig                                  │
│  │                                                              │
│  └─ Valid Integration Tests (14 files) ✅     [KEEP]           │
│      └─ accuracycoin, cpu_ppu_integration, oam_dma, etc.       │
│                                                                 │
│  Other Tests (13 files) ✅                                      │
│  └─ Cartridge, Debugger, Threading, Config, etc. [KEEP ALL]   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Legend:
  ✅ Passing tests    ❌ Failing tests    ⚠️ Mixed
```

## Failing Tests Breakdown (13 total)

```
┌────────────────────────────────────────────────────────────────┐
│                    13 Failing Tests                            │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Debug Artifacts (11 tests) - DELETE ❌                        │
│  ├─ vblank_debug_test.zig (1 test)                            │
│  ├─ clock_sync_test.zig (2 tests)                             │
│  ├─ bomberman_hang_investigation.zig (2 tests)                │
│  ├─ bomberman_detailed_hang_analysis.zig (3 tests)            │
│  ├─ ppustatus_polling_test.zig (1 test - "BIT timing")        │
│  └─ commercial_nmi_trace_test.zig (1 test)                    │
│                                                                │
│  Real Bugs (2 tests) - FIX 🔧                                  │
│  ├─ emulation/State.zig: "odd frame skip" ← P0 BLOCKER        │
│  └─ ppustatus_polling_test.zig: "Multiple polls" ← Regression │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Test Quality Distribution

```
┌────────────────────────────────────────────────────────────────┐
│              Test Quality: Harness Pattern Usage               │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Using Harness (13 files, 17%) ✅ GOOD                         │
│  ██░░░░░░░░░░░░░░░░                                            │
│  ├─ vblank_nmi_timing_test.zig                                │
│  ├─ ppustatus_polling_test.zig                                │
│  ├─ ppustatus_read_test.zig                                   │
│  ├─ sprite_rendering_test.zig                                 │
│  ├─ sprite_edge_cases_test.zig                                │
│  └─ ... 8 more sprite/PPU tests                               │
│                                                                │
│  Direct State Access (64 files, 83%) ⚠️ FRAGILE                │
│  ████████████████████████████████████████████████████░░░░      │
│  ├─ cpu_ppu_integration_test.zig (501 lines!)                 │
│  ├─ nmi_sequence_test.zig (200 lines)                         │
│  ├─ All CPU opcode tests                                      │
│  └─ Most integration tests                                    │
│                                                                │
│  Migration Opportunity: 51 tests (66%)                         │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Consolidation Plan

```
BEFORE (77 files)                    AFTER (51 files)
┌─────────────────────┐             ┌─────────────────────┐
│                     │             │                     │
│  VBlank Tests (10)  │──DELETE 6──▶│  VBlank Tests (3)   │
│  ├─ vblank_nmi_...  │             │  ├─ vblank_nmi_...  │
│  ├─ ppustatus_r...  │             │  ├─ ppustatus_be... │ ← Consolidated
│  ├─ ppustatus_p...  │             │  └─ vblank_integ... │ ← Consolidated
│  ├─ vblank_debu... ❌│             │                     │
│  ├─ vblank_mini...  │             │                     │
│  ├─ vblank_trac...  │             │                     │
│  ├─ vblank_pers...  │             │                     │
│  ├─ vblank_poll...  │             │                     │
│  └─ clock_sync... ❌│             │                     │
│                     │             │                     │
└─────────────────────┘             └─────────────────────┘

┌─────────────────────┐             ┌─────────────────────┐
│  Bomberman (5) ❌    │──DELETE 5──▶│  (deleted)          │
│  ├─ hang_invest...  │             │                     │
│  ├─ detailed_ha...  │             │                     │
│  ├─ debug_trace...  │             │                     │
│  ├─ exact_simul...  │             │                     │
│  └─ commercial_...  │             │                     │
└─────────────────────┘             └─────────────────────┘

┌─────────────────────┐             ┌─────────────────────┐
│  Other Debug (3) ❌  │──DELETE 3──▶│  (deleted)          │
│  ├─ vblank_exac...  │             │                     │
│  ├─ detailed_tr...  │             │                     │
│  └─ nmi_sequenc...  │             │                     │
└─────────────────────┘             └─────────────────────┘

Total Deleted: 14 files
Total Consolidated: 4 files → 2 files
Net Result: 77 → 51 files (-26 files, -34%)
```

## Effort vs. Impact Matrix

```
High Impact ▲
           │
           │  ┌──────────┐
           │  │ Phase 1  │ Delete Debug Artifacts
           │  │ 20 min   │ ← QUICK WIN
           │  └──────────┘
           │
           │  ┌──────────┐
           │  │ Phase 2  │ Fix Real Bugs
           │  │ 4 hours  │ ← HIGH PRIORITY
           │  └──────────┘
           │
           │         ┌──────────┐
           │         │ Phase 3  │ Consolidate VBlank
           │         │ 6 hours  │
           │         └──────────┘
           │
           │                ┌──────────┐
           │                │ Phase 5  │ Harness Migration
           │                │ 8 hours  │
           │                └──────────┘
           │
           │                       ┌──────────┐
           │                       │ Phase 4  │ Review CPU Tests
           │                       │ 4 hours  │
Low Impact │                       └──────────┘
           └────────────────────────────────────▶
                Low Effort          High Effort
```

## Test Count Progression

```
Phase 0: Current State
┌────────────────────────────────────────────────────────┐
│ ████████████████████████████████████████████████░░░░░░ │ 936/956 (97.9%)
└────────────────────────────────────────────────────────┘
  Passing: 936    Failing: 13    Skipped: 7

Phase 1: Delete Debug Artifacts (20 min)
┌────────────────────────────────────────────────────────┐
│ ████████████████████████████████████████████████████░░ │ ~925/930 (99.5%)
└────────────────────────────────────────────────────────┘
  Passing: 925    Failing: 2     Skipped: 3

Phase 2: Fix Real Bugs (4 hours)
┌────────────────────────────────────────────────────────┐
│ ██████████████████████████████████████████████████████ │ 925/928 (99.7%)
└────────────────────────────────────────────────────────┘
  Passing: 925    Failing: 0     Skipped: 3

Phase 3: Consolidate VBlank (6 hours)
┌────────────────────────────────────────────────────────┐
│ ███████████████████████████████████████████████████░░░ │ ~800/810 (98.8%)
└────────────────────────────────────────────────────────┘
  Passing: 800+   Failing: 0     Skipped: 3
  (Some redundant tests removed during consolidation)
```

## File Size Distribution

```
Largest Test Files (Top 10):
┌──────────────────────────────────────────────────────┐
│ debugger_test.zig          ████████████ 1849 lines  │ ← KEEP (comprehensive)
│ instructions_test.zig      ████░ 698 lines          │ ← REVIEW (redundancy?)
│ sprite_edge_cases_test.zig ███░ 611 lines           │ ← KEEP (edge cases)
│ threading_test.zig         ███░ 542 lines           │ ← KEEP (1 flaky test)
│ ines_test.zig              ███░ 529 lines           │ ← KEEP (comprehensive)
│ length_counter_test.zig    ███░ 524 lines           │ ← KEEP (APU)
│ sprite_evaluation_test.zig ███░ 517 lines           │ ← KEEP (PPU)
│ unofficial_test.zig        ███░ 516 lines           │ ← KEEP (unofficial opcodes)
│ cpu_ppu_integration_...    ███░ 501 lines           │ ← KEEP + Migrate Harness
│ prg_ram_test.zig           ███░ 480 lines           │ ← KEEP (cartridge)
└──────────────────────────────────────────────────────┘

Debug Artifact Files (To Delete):
┌──────────────────────────────────────────────────────┐
│ bomberman_hang_investigation    ██░ 262 lines       │ ← DELETE
│ bomberman_detailed_hang_...     ██░ 184 lines       │ ← DELETE
│ bomberman_debug_trace_test      ██░ ~200 lines      │ ← DELETE
│ vblank_minimal_test             █░ 131 lines        │ ← DELETE
│ clock_sync_test                 █░ 88 lines         │ ← DELETE
│ vblank_debug_test               █░ 74 lines         │ ← DELETE
└──────────────────────────────────────────────────────┘
Total to delete: ~1,834 lines
```

## Recommended Timeline

```
Week 1: Quick Wins
├─ Monday (1 hour)
│  ├─ Delete 14 debug artifact files (20 min)
│  └─ Verify tests pass (zig build test)
│
├─ Tuesday-Wednesday (4 hours)
│  ├─ Fix frame skip timing bug (2 hours)
│  ├─ Fix VBlank polling regression (2 hours)
│  └─ Verify 925/928 passing
│
└─ Friday (1 hour)
   └─ Update CLAUDE.md and commit

Week 2: Consolidation
├─ Monday-Tuesday (6 hours)
│  ├─ Create ppustatus_behavior_test.zig
│  ├─ Create vblank_integration_test.zig
│  └─ Verify no regressions
│
└─ Wednesday-Friday (4 hours)
   └─ Review cpu/instructions_test.zig for redundancy

Week 3+: Harness Migration
├─ Migrate nmi_sequence_test.zig (3 hours)
├─ Migrate cpu_ppu_integration_test.zig (4 hours)
├─ Migrate vblank_wait_test.zig (1 hour)
└─ Document Harness migration pattern (2 hours)
```

## Success Criteria

```
✅ Phase 1+2 Complete:
  ├─ 14 debug files deleted
  ├─ 2 real bugs fixed
  ├─ 0 failing tests
  ├─ 63 test files remaining
  └─ Time: 4.5 hours

✅ All Phases Complete:
  ├─ 26 files deleted/consolidated
  ├─ 51 focused test files
  ├─ >50% Harness adoption
  ├─ ~800 non-redundant tests
  └─ Time: ~30 hours total
```

---

**Next Step:** Execute Phase 1 (20 minutes) → See [test-audit-action-plan.md](./test-audit-action-plan.md)
