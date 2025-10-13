# Test Inventory - Complete Catalog

## Total Test Files: 64

### Unit Tests by Component

#### APU Tests (8 files)
1. `tests/apu/apu_test.zig` - 350 lines
2. `tests/apu/dmc_test.zig` - 413 lines
3. `tests/apu/envelope_test.zig` - 350 lines
4. `tests/apu/frame_irq_edge_test.zig`
5. `tests/apu/length_counter_test.zig` - 524 lines
6. `tests/apu/linear_counter_test.zig`
7. `tests/apu/open_bus_test.zig`
8. `tests/apu/sweep_test.zig` - 419 lines

#### CPU Tests (15 files)
1. `tests/cpu/bus_integration_test.zig`
2. `tests/cpu/diagnostics/timing_trace_test.zig`
3. `tests/cpu/dispatch_debug_test.zig`
4. `tests/cpu/instructions_test.zig` - 698 lines ⚠️ (LARGE)
5. `tests/cpu/interrupt_logic_test.zig`
6. `tests/cpu/interrupt_timing_test.zig`
7. `tests/cpu/opcodes/arithmetic_test.zig`
8. `tests/cpu/opcodes/branch_test.zig`
9. `tests/cpu/opcodes/compare_test.zig`
10. `tests/cpu/opcodes/control_flow_test.zig`
11. `tests/cpu/opcodes/helpers.zig` (not a test file - helpers)
12. `tests/cpu/opcodes/incdec_test.zig`
13. `tests/cpu/opcodes/jumps_test.zig`
14. `tests/cpu/opcodes/loadstore_test.zig`
15. `tests/cpu/opcodes/logical_test.zig`
16. `tests/cpu/opcodes/shifts_test.zig`
17. `tests/cpu/opcodes/stack_test.zig`
18. `tests/cpu/opcodes/transfer_test.zig`
19. `tests/cpu/opcodes/unofficial_test.zig` - 516 lines
20. `tests/cpu/page_crossing_test.zig`
21. `tests/cpu/rmw_test.zig` - 345 lines

#### PPU Tests (11 files)
1. `tests/ppu/chr_integration_test.zig`
2. `tests/ppu/ppustatus_polling_test.zig` - 443 lines
3. `tests/ppu/seek_behavior_test.zig`
4. `tests/ppu/simple_vblank_test.zig`
5. `tests/ppu/sprite_edge_cases_test.zig` - 611 lines ⚠️ (LARGE)
6. `tests/ppu/sprite_evaluation_test.zig` - 517 lines
7. `tests/ppu/sprite_rendering_test.zig` - 452 lines
8. `tests/ppu/status_bit_test.zig`
9. `tests/ppu/vblank_behavior_test.zig`
10. `tests/ppu/vblank_nmi_timing_test.zig`

#### Other Unit Tests
1. `tests/bus/bus_integration_test.zig` - 397 lines
2. `tests/cartridge/accuracycoin_test.zig`
3. `tests/cartridge/prg_ram_test.zig` - 480 lines
4. `tests/comptime/poc_mapper_generics.zig`
5. `tests/config/parser_test.zig`
6. `tests/debugger/debugger_test.zig` - 1849 lines ⚠️ (VERY LARGE)
7. `tests/emulation/state_test.zig`
8. `tests/helpers/FramebufferValidator.zig` (not a test - helper)
9. `tests/input/button_state_test.zig`
10. `tests/input/keyboard_mapper_test.zig`
11. `tests/snapshot/snapshot_integration_test.zig` - 462 lines

### Integration Tests (14 files)
1. `tests/integration/accuracycoin_execution_test.zig`
2. `tests/integration/accuracycoin_prg_ram_test.zig`
3. `tests/integration/benchmark_test.zig`
4. `tests/integration/bit_ppustatus_test.zig`
5. `tests/integration/commercial_rom_test.zig`
6. `tests/integration/controller_test.zig`
7. `tests/integration/cpu_ppu_integration_test.zig` - 521 lines
8. `tests/integration/dpcm_dma_test.zig`
9. `tests/integration/input_integration_test.zig`
10. `tests/integration/interrupt_execution_test.zig`
11. `tests/integration/nmi_sequence_test.zig`
12. `tests/integration/oam_dma_test.zig` - 418 lines
13. `tests/integration/ppu_register_absolute_test.zig`
14. `tests/integration/rom_test_runner.zig` - 357 lines (helper module)
15. `tests/integration/smb_vblank_reproduction_test.zig`
16. `tests/integration/vblank_wait_test.zig`

### Threading Tests (1 file)
1. `tests/threads/threading_test.zig` - 542 lines

---

## Analysis Priority

### High Priority (Integration Tests - Harness Usage)
These tests are most likely to have harness misuse issues based on the user's concerns:
- All 14 integration test files
- Focus on VBlank-related tests first

### Medium Priority (Large Unit Tests)
These files are complex and may have duplication:
- `tests/debugger/debugger_test.zig` (1849 lines)
- `tests/cpu/instructions_test.zig` (698 lines)
- `tests/ppu/sprite_edge_cases_test.zig` (611 lines)

### Lower Priority (Smaller Unit Tests)
These are more likely to be correct but need verification:
- All other unit tests

---

## Next Steps

1. Delegate integration test analysis to specialized agents
2. Check for compatibility shims (old API usage)
3. Verify harness usage patterns
4. Document test intent categories
5. Identify duplication
