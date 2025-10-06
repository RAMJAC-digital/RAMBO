# Mapper & PRG RAM Implementation Plan

**Last Updated:** 2025-10-06  
**Status:** READY FOR IMPLEMENTATION  
**Priority:** HIGH – required for AccuracyCoin test extraction and mapper roadmap

---

## 1. Objectives
- Enable fully functional PRG RAM at CPU $6000-$7FFF for all cartridges that declare it.  
- Generalise the cartridge runtime to load mapper variants at comptime while selecting them deterministically at runtime.  
- Preserve emulator determinism: all mapper state stays owned by the cartridge, with IRQ signalling routed through existing CPU/APU hooks.  
- Deliver a low-friction developer workflow: clear tasks, predictable testing, and documentation that removes guesswork.

Success Criteria:
1. AccuracyCoin ROM returns non-`0xFF` status bytes and strings through $6000-$7FFF.  
2. All tests (`zig build --summary all test`) pass with new mapper scaffolding.  
3. Snapshot save/restore preserves PRG RAM and mapper state blobs.  
4. No new allocations or locks in the hot tick path; `EmulationState.tick` remains non-blocking.

---

## 2. Hardware References
- [NES CPU Memory Map – nesdev.org](https://www.nesdev.org/wiki/CPU_memory_map) (PRG RAM behaviour, open bus expectations).  
- [Mapper 0 (NROM) – nesdev.org](https://www.nesdev.org/wiki/NROM) (baseline PRG bank rules).  
- [MMC1 – nesdev.org](https://www.nesdev.org/wiki/MMC1) and [MMC3](https://www.nesdev.org/wiki/MMC3) (upcoming mapper requirements; informs interface design).

Key Requirements:
- PRG RAM is battery-backed RAM at $6000-$7FFF when enabled by iNES header (Flags 6 bit 1); returns open bus otherwise.  
- Mapper IRQs must assert the CPU IRQ line without bypassing `CpuLogic.checkInterrupts`.  
- Bank switching and IRQ counters may run each CPU cycle but must not use global state or blocking calls.

---

## 3. Architecture Decisions
- **Comptime Cartridge Factory:** Introduce `MapperId` enum and `pub fn CartridgeFor(comptime id: MapperId) type` so each mapper compiles into a specialised cartridge type (pattern mirrors `src/cpu/variants.zig`).  
- **Tagged Union Runtime Dispatch:** Replace `EmulationState.cart: ?NromCart` with `?AnyCart`, a tagged union wrapping supported cartridge types. Inline helper methods perform a `switch` per access (predictable, branch-friendly).  
- **Mapper Ownership:** Each mapper struct holds only its own registers/counters. IRQ requests expose a boolean accessor; `EmulationState.tick` samples it and updates `cpu.irq_line` (same pattern used for APU DMC).  
- **PRG RAM Storage:** `Cartridge` gains optional `prg_ram` buffer allocated at load time based on iNES size hints (default 8 KB). Open bus semantics handled inside mapper logic.  
- **Snapshot Hooks:** Extend cartridge snapshot data with mapper ID and serialized state; each mapper implements `serializeState`/`deserializeState` returning a small blob (empty for Mapper0).  
- **No Hot-Path Allocation:** Cartridge loading allocates all ROM/RAM up front. Runtime switches and mapper ticks are allocation-free and do not touch external mutexes.

---

## 4. Implementation Tasks

### 4.1 Documentation & Design
- `docs/implementation/mapper-architecture.md` (NEW): Summarise mapper factory, union dispatch, IRQ routing, and PRG RAM rules. Include links to nesdev sources and examples for future mappers.

### 4.2 Cartridge Core
- `src/cartridge/Cartridge.zig`
  - Add `prg_ram: ?[]u8`, `battery_backed: bool`, helper `hasPrgRam()`.  
  - Update `loadFromData` to allocate/zero PRG RAM based on header (`flags6` & `flags7`, `prg_ram_size`).  
  - Update `deinit` to free PRG RAM when present.  
  - Provide accessors used by mappers (`readPrgRam`, `writePrgRam`).
- `src/cartridge/loader.zig`
  - Parse mapper number into `MapperId`.  
  - Instantiate `CartridgeFor(id)` and wrap result in `AnyCart`.  
  - Validate file size expectations with PRG RAM logic (open bus when absent).
- `src/cartridge/mappers/Mapper0.zig`
  - Route $6000-$7FFF reads/writes through `cart.prg_ram` when available; return `0xFF` otherwise.  
  - Add unit tests covering presence/absence cases and reset behaviour (PRG RAM remains dirty unless explicitly cleared).
- `src/cartridge/mappers/registry.zig` (NEW)
  - Define `MapperId` enum and compile-time metadata (name, description, nesdev link).  
  - Provide `initCartridge(allocator, data, MapperId)` factory returning `AnyCart` variant.  
  - Stub entries for future mappers (Mapper0 implemented immediately; markers for Mapper1/MMC1, Mapper2/UxROM, Mapper4/MMC3).

### 4.3 Emulator Runtime
- `src/emulation/State.zig`
  - Introduce `const AnyCart = union(enum) { mapper0: CartridgeFor(.mapper0), ... }`.  
  - Replace `cartPtr()` helpers with `cartCpuRead/Write`, `cartPpuRead/Write`, `cartHasIrq`.  
  - Update bus routing (`busRead`/`busWrite`) to call union dispatch, keeping open-bus semantics identical.  
  - Add `tickMapperIrq` hook (called each CPU tick) that sets `cpu.irq_line` if the active mapper asserts IRQ (no effect for Mapper0).  
  - Ensure DMA code keeps logging last read address for DMC corruption; union dispatch must not alter timing.
- `src/root.zig`
  - Export `MapperId`, `AnyCart`, and `CartridgeFor` for tests/tooling.

### 4.4 Snapshot System
- `src/snapshot/cartridge.zig`
  - Embed mapper ID, PRG RAM size, and serialized mapper blob in both reference and embed snapshots.  
  - Update `writeCartridgeSnapshot`/`readCartridgeSnapshot` to delegate to mapper-specific serializers.  
  - Add tests ensuring PRG RAM contents survive save/load.
- `src/snapshot/Snapshot.zig`
  - Thread mapper state through snapshot creation and restoration.  
  - Validate mapper ID compatibility during load; return descriptive error if ROM uses unsupported mapper.

### 4.5 Testing
- `tests/cartridge/prg_ram_test.zig` (NEW): Unit tests for PRG RAM read/write, reset invariants, and open-bus fallback.  
- `tests/cartridge/mapper_union_test.zig` (NEW): Validate union dispatch for Mapper0 and smoke-test factory.  
- `tests/integration/accuracycoin_results.zig` (NEW): Drive AccuracyCoin ROM, read status bytes/strings from PRG RAM, assert they’re not `0xFF` (skip if ROM absent).  
- `tests/snapshot/cartridge_prg_ram_test.zig` (NEW): Save snapshot with written PRG RAM; reload and confirm contents.  
- Update existing suites (`tests/bus/bus_integration_test.zig`, `tests/comptime/poc_mapper_generics.zig`) to reference new API where needed.

### 4.6 Future Mapper Hooks (Plan-Only)
- Stubs for Mapper1, Mapper2, Mapper4 with TODO comments referencing nesdev articles and outlining state fields required (shift register, PRG/CHR bank registers, IRQ counter).  
- Add placeholder tests that `@compileLog` if mapper not yet implemented—keeps coverage expectations visible without blocking current work.

---

## 5. Development Notes & Constraints
- **Determinism:** All mapper state transitions must occur inside cartridge methods. IRQ flags are sampled in `EmulationState.tick` and cleared according to mapper spec (e.g., MMC3 IRQ acknowledge on CPU read).  
- **Thread Safety:** No locks or dynamic allocations in `tick` or bus handlers. All buffers allocated during cartridge load; map releases happen in `deinit`.  
- **Battery Handling:** For now, persist battery flag in cartridge struct. Actual battery-backed persistence (disk IO) is a separate task; document TODO in loader.  
- **Error Surfaces:** Loader must return `UnsupportedMapper` for unknown mapper numbers, now surfaced via `MapperId` enum. Include mapper number in error message for clarity.  
- **Open Bus Semantics:** When PRG RAM is absent, reads still return previous open bus value (currently `0xFF`). Ensure union dispatch does not overwrite `bus.open_bus` prematurely.

---

## 6. Verification Checklist
- [ ] `zig fmt src tests docs`  
- [ ] `zig build --summary all test`  
- [ ] Manual run: load AccuracyCoin ROM, confirm PRG RAM status bytes decode.  
- [ ] Snapshot round-trip preserving PRG RAM.  
- [ ] Review union dispatch assembly (optional `zig build --verbose-cimport`) to confirm no unexpected indirection.

---

## 7. Risk Mitigation
- **Mapper Explosion:** Keep `MapperId` list deliberate; start with Mapper0 only and add others when ready. The union scales predictably.  
- **Snapshot Size Growth:** Mapper blob size is small (8 KB PRG RAM max + mapper registers). Document size expectations to avoid surprises.  
- **IRQ Handling Mistakes:** Use unit tests per mapper to simulate IRQ trigger/ack cycles and ensure `cpu.irq_line` clears correctly.  
- **Accuracy Regression:** Add integration tests for DMC + PRG RAM interplay to confirm DMC DMA logic unaffected by union dispatch.

---

With the above plan, developers can proceed sequentially or in parallel (documentation, cartridge core, runtime, snapshot). Each task points to the exact files and desired outcomes, with external references for hardware correctness. No open questions remain; all identified gaps have explicit steps and safeguards.
