# Microsoft BASIC → NES Port Plan

## 1. Source Overview

The repository includes the original `m6502.asm` for Microsoft BASIC 1.1 (circa 1978). Important traits:

- **Assembler dialect:** MACRO-11 style with `DEFINE`, `IRPC`, `IF*` directives, and pseudo-ops such as `XWD`, `PRINTX`, `PAGE`, `SUBTTL`.
- **Conditional configuration:** Dozens of `IF`/`IFE` branches switch between target platforms (`REALIO` values 0–5, `ROMSW`, `ADDPRC`, etc.).
- **Macro-heavy zero-page access:** Helpers like `LDWD`, `STWD`, `PSHWD`, `JEQ`, etc., expand to 6502 instructions and hide two-byte accesses.
- **Memory model:** Original build expects 8 KiB ROM mapped with symbolic `ROMLOC`/`RAMLOC`. No iNES header or NES-specific vectors are provided.
- **I/O hooks:** Uses platform-dependent routines for console input/output, cassette/disk I/O, and KIM-1 style monitor entry points.

To produce a NES-compatible ROM we must eliminate dialect-specific constructs, select a deterministic configuration, provide an iNES header, and replace I/O vectors with NES host shims.

## 2. Target Requirements

- **Assembler:** `nesasm` v3.x (same tool we use for AccuracyCoin). Supports `.ines*`, `.org`, `.db`, `.dw`, `.macro`, but *not* MACRO-11 directives.
- **Memory map:**
  - PRG ROM at `$8000-$FFFF` (NROM-128 or NROM-256 depending on final size).
  - Zero page / stack identical to original BASIC expectations, but must avoid clashes with NES hardware registers.
  - PPU/APU register space must be guarded.
- **Entry points:** NES reset/NMI/IRQ vectors, optional stub for waiting on PPU warm-up.
- **Host services:** Console input/output via controller + PPU text rendering, persistent storage optional.

## 3. Conversion Strategy

### Stage A — Static Analysis

1. **Macro inventory:**
   - 32 `DEFINE` macros, majority of which wrap two-byte load/store patterns or branch helpers.
   - Special cases: `IRPC` usage inside `DT` macro, branch macros (`BCCA`, `BPLA`, etc.), `INCW` with generated labels (`%Q`).
2. **Conditional tree:** Identify required symbol values for NES target (`REALIO`, `ROMSW`, etc.) and freeze non-relevant branches.
3. **Pseudo-op catalogue:** List unsupported directives (`PAGE`, `SUBTTL`, `PRINTX`, `COMMENT`, `XWD`, `TITLE`, `IRPC`, `IRPS`, `IF1`/`IF2`).

Deliverable: machine-readable manifest describing macros, directives, and conditional symbols. Macro manifest now produced by `uv run compiler analyze-basic` → `compiler/docs/microsoft-basic-macro-manifest.json`.

### Stage B — Preprocessor Implementation (Python)

Goal: transform `m6502.asm` into plain `nesasm`-compatible assembly `m6502.nesasm.asm`.

1. **Parser skeleton:**
   - Tokenise line-by-line, preserving labels/comments.
   - Recognise `DEFINE NAME(args),<body>` blocks, capture body text until matching `>` with nesting support.
   - Store macros with metadata (parameter list, body, local labels like `%Q`).
2. **Macro expansion:**
   - Replace macro invocations with inline body.
   - Implement argument substitution for `WD`, `Q`, etc., converting `<ARG>`/`<<ARG>>` numeric operators into equivalent NESASM expressions (`LOW(ARG)`, `HIGH(ARG)` or explicit bit math).
   - Handle `%` local label pattern by generating unique labels per expansion.
   - Emulate `IRPC` (character iteration) inside `DT` by expanding to repeated `EXP` lines or equivalent `.db`.
3. **Directive translation:**
   - Drop documentation directives (`PAGE`, `SUBTTL`, `COMMENT`, `TITLE`) or convert to `;` comments.
   - Convert `XWD a,b` to two `.dw` or `.db` statements depending on usage (macro expands to pair of bytes).
   - Replace `PRINTX` with comments or remove.
   - Evaluate `IF*` conditionals using chosen symbol table and only emit selected branches.
4. **Expression rewrite:**
   - Replace octal notation (`^O377`) with decimal/hex (`$FF`).
   - Convert shift/divide operations (`<<WD>&^O377`) to NESASM-friendly forms using `AND`, `>>`, `& $FF`, etc.

5. **Output:** emit fully expanded assembly with macros removed, standard `.org` directives, ready for manual NES adjustments.

### Stage C — NES Integration Layer

1. **Header & vectors:** Prepend `.inesprg`, `.ineschr`, `.inesmap`, `.inesmir` directives and place reset/NMI/IRQ vectors at `$FFFA-$FFFF`. *(Implemented: reset stub performs minimal PPU init and jumps into the BASIC entry point.)*
2. **Memory mapping:**
   - Set `.org $8000` for PRG.
   - Ensure zero-page definitions (`ZP`, `STK`, etc.) remain below `$0100`.
   - Audit usage of `$2000+` addresses to avoid accidental PPU/APU writes.
3. **Host routines:**
   - Provide scaffolding for character output (likely tile-based text renderer) and input (controller-driven line editor).
   - Replace cassette/disk routines with no-ops or RAM stubs.
   - Map BASIC’s warm start / cold start entry points to NES reset vector.
4. **Testing harness:**
   - Build minimal ROM to boot, run memory diagnostics, output “READY”.
   - Integrate with RAMBO emulator test harness (new CLI command `build-basic` once stable).

## 4. Task Breakdown

| Milestone | Deliverable | Status | Notes |
| --- | --- | --- | --- |
| A1 | Macro manifest (`compiler/docs/microsoft-basic-macro-manifest.json`) | ✅ Complete | Generated via `uv run compiler analyze-basic` |
| A2 | Conditional symbol map (`compiler/docs/basic-configurations.md`) | ✅ Complete | NES defaults captured in configuration matrix |
| B1 | Preprocessor MVP (`compiler/src/compiler/basic_preprocessor.py`) | ✅ Complete | Macro expansion, `REPEAT`, `ADR`, `DT`/`IRPC`, and `IF*` evaluation implemented with `--verify` guard |
| B1.1 | Macro expander design doc | ✅ Complete | Documented in `docs/macro-expansion-design.md` |
| B2 | Expression normaliser | ⏳ Pending | Convert octal/bit ops to hex |
| B3 | Conditional evaluator | ⏳ Pending | Python evaluation of `IF*` tree |
| C1 | NES header shim (`compiler/templates/basic_header.asm`) | ⏳ Pending | Include `.ines*` + vector table |
| C2 | I/O stub design doc | ⏳ Pending | Plan for text output/input |
| C3 | End-to-end build command (`compiler build-basic`) | ⏳ Pending | Produces `compiler/dist/basic/basic.nes` |
| C4 | Emulator smoke test | ⏳ Pending | Boot ROM inside RAMBO, snapshot results |

## 5. Open Questions

- **Target configuration:** Which historic variant best matches NES constraints? (Apple II vs. Commodore vs. ROM-only.)
- **CHR data:** Text renderer likely needs custom CHR ROM; decide between tiles baked alongside BASIC or reused from AccuracyCoin.
- **RAM footprint:** Determine whether interpreter plus NES host routines fits in 16 KiB PRG; may need NROM-256 (32 KiB).
- **I/O semantics:** Map BASIC’s concept of console, timing, and cassette to NES controller/PPU without diverging from original behaviour.

## 6. Next Steps

1. **Complete** – Macro manifest (A1) generated; keep current via `uv run compiler analyze-basic`.
2. Lock in NES memory map decisions (C1) and start designing the PPU text renderer (C2) in parallel.
3. Wire the `compiler build-basic` command to call the preprocessor + nesasm once the translation path is reliable.
4. Expand testing harness to boot the generated ROM inside RAMBO and capture smoke-test output (C4).

All updates should be tracked in this document as milestones complete.
