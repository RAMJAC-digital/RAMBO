# 08 - Code Safety and Best Practices Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The RAMBO codebase is generally well-written and follows many of Zig's best practices. However, as with any complex project, there are areas where safety, clarity, and adherence to idiomatic Zig can be improved. This review focuses on identifying these areas and providing actionable recommendations.

## 2. Actionable Items

### 2.1. Replace V-Tables with Comptime Generics

*   **Action:** The `Mapper` and `ChrProvider` interfaces use vtables for polymorphism. As noted in the `architecture-review-summary.md`, this pattern is less safe than using comptime generics. Refactor these interfaces to use comptime generics (duck typing).
*   **Rationale:** Comptime generics provide compile-time polymorphism with no runtime overhead. This is safer because the compiler can verify that the types have the required functions at compile time, eliminating the risk of runtime errors due to incorrect vtable pointers.
*   **Code References:**
    *   `src/cartridge/Mapper.zig`
    *   `src/memory/ChrProvider.zig`
*   **Status:** **TODO**.

### 2.2. Eliminate `anytype` from Core Emulation Logic

*   **Action:** The `tick` and `reset` functions in `src/cpu/Cpu.zig` use `anytype` for the bus parameter. This should be replaced with a concrete type.
*   **Rationale:** Using `anytype` reduces type safety and makes the code harder to analyze. The CPU should operate on a well-defined bus interface.
*   **Code References:**
    *   `src/cpu/Cpu.zig`: The `tick` and `reset` function signatures.
*   **Status:** **TODO**.

### 2.3. Ensure Real-Time Safety

*   **Action:** The real-time (RT) emulation thread must never perform any operations that could introduce unpredictable latency, such as memory allocation, I/O, or taking locks. Audit the entire codebase to ensure that the RT thread is completely isolated from these operations.
*   **Rationale:** Real-time safety is a core requirement of the new hybrid architecture. Any violation of this principle could lead to audio stuttering, incorrect emulation timing, and other issues.
*   **Status:** **TODO**.

### 2.4. Use `std.mem.zeroes` for Initialization

*   **Action:** In many places, structs are initialized with `undefined` and then manually zeroed. This can be simplified by using `std.mem.zeroes`.
*   **Rationale:** `std.mem.zeroes` is a more concise and idiomatic way to zero-initialize a struct.
*   **Code References:**
    *   `src/io/Architecture.zig`: The `RingBuffer` struct.
*   **Status:** **TODO**.

### 2.5. Add `build.zig` Options for Enabling/Disabling Features

*   **Action:** The `build.zig` file should be updated to include options for enabling and disabling features like logging, debugging, and the different video/audio backends.
*   **Rationale:** This will make it easier to create different build configurations for development, testing, and release.
*   **Status:** **TODO**.
