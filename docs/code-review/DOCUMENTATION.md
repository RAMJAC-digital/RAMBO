# Documentation Code Review

**Audit Date:** 2025-10-11
**Status:** Good, but contains outdated information.

## 1. Overall Assessment

The project contains a wealth of high-quality documentation, including architectural diagrams, design plans, and investigation notes. This is a major strength. The use of Graphviz for diagrams is excellent for maintainability.

The primary issue is that some of the documentation, particularly in `docs/implementation/` and `docs/refactoring/`, has become outdated due to the recent, successful architectural refactorings (e.g., the new cartridge system, the flattened `EmulationState`).

The immediate priority is to archive obsolete documents and update the core architectural diagrams and descriptions to reflect the current state of the codebase.

## 2. Issues and Inconsistencies

- **Outdated Architecture Diagram:**
  - The main architecture diagram, `docs/dot/architecture.png`, is largely accurate but does not reflect the latest changes:
    - It shows the old cartridge system, not the new `AnyCartridge` tagged union.
    - It depicts a more complex component wiring model, rather than the current reality where `EmulationState` directly owns all sub-components.
    - The mailbox diagram is good but could be clarified to show the SPSC (Single-Producer, Single-Consumer) nature of the ring buffers.

- **Obsolete Design Documents:**
  - Files like `docs/implementation/INES-MODULE-PLAN.md` and `docs/refactoring/PHASE-1-MASTER-PLAN.md` describe the old architecture and the plan to migrate away from it. Now that the migration is largely complete, these documents are historical artifacts and can be confusing to new contributors.

- **Lack of a Central `ARCHITECTURE.md`:**
  - While there are many detailed documents, there isn't a single, top-level `ARCHITECTURE.md` file that provides a high-level overview of the current system design, its core principles (State/Logic separation, RT-safety, etc.), and how the major components interact. Such a document would be invaluable for onboarding.

- **Inconsistent Naming in Diagrams:**
  - The architecture diagram uses names like "Emulation Core" and "Utility Systems" which are conceptual groupings. It would be beneficial to also include the specific source file names (e.g., `EmulationState.zig`, `Config.zig`) to make it easier to map the diagram to the code.

## 3. Actionable Development Plan

1.  **Update the Core Architecture Diagram:**
    - **File:** `docs/dot/architecture.dot`
    - **Actions:**
        - Replace the old cartridge/mapper diagram elements with a new box representing the `AnyCartridge` tagged union, showing how it dispatches to different mapper implementations (e.g., `Mapper0`).
        - Simplify the main diagram to show `EmulationState` as the central owner of `CpuState`, `PpuState`, `ApuState`, `AnyCartridge`, etc. Remove the complex web of interconnecting lines and instead show that all interactions are mediated by `EmulationState`'s `tick()` method.
        - Add labels to the diagram boxes to indicate the primary source file (e.g., "CPU (cpu.zig)", "PPU (ppu.zig)").
        - Regenerate `architecture.png` from the updated `.dot` file.

2.  **Create a Central `ARCHITECTURE.md` Document:**
    - **File:** `docs/ARCHITECTURE.md` (new file)
    - **Content:**
        - A high-level overview of the 3-thread model (Main, Emulation, Render).
        - A description of the core architectural patterns: State/Logic Separation, RT-Safety (no allocations in hot path), and Comptime Polymorphism.
        - An embedded, updated `architecture.png`.
        - A brief description of each major component and its responsibility, linking to the relevant source directory.
        - A summary of the mailbox communication system.

3.  **Archive Obsolete Documents:**
    - Create a new directory: `docs/archive/pre-refactor-2025-10/`.
    - Move the following documents into the new archive directory:
        - All files in `docs/refactoring/`
        - `docs/implementation/INES-MODULE-PLAN.md`
        - `docs/implementation/MAPPER-SYSTEM-PLAN.md`
        - Any other documents that describe the now-superseded architecture.
    - Add a `README.md` to the archive directory explaining that these documents are historical and do not represent the current codebase.

4.  **Review and Update Remaining Documentation:**
    - Briefly review the remaining documents in `docs/` (e.g., `apu.md`, `threading.md`) to ensure they are still broadly accurate.
    - Update any glaring inconsistencies with the current code. For example, update `docs/architecture/apu.md` to mention the plan to refactor it to a pure State/Logic pattern, referencing the new `docs/code-review/APU.md`.
