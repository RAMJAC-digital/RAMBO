---
name: m-fix-wasm-export-visibility
branch: fix/m-fix-wasm-export-visibility
status: pending
created: 2025-11-05
---

# Fix WebAssembly Export Visibility

## Problem/Goal

The RAMBO WebAssembly build compiles successfully and contains all exported function symbols in the binary, but the WASM export table only publishes `memory`. This prevents the Phoenix LiveView frontend from calling any of the 12 exported API functions (`rambo_init`, `rambo_alloc`, `rambo_step_frame`, etc.), making the web emulator non-functional.

**Root Cause**: Zig 0.15.2's `std.Build` pipeline does not emit WASM exports even when `export_symbol_names` is set on the module. The symbols exist in the binary (visible via `strings`) but are not published in the WASM export table that JavaScript can access.

**Current State**:
- ✅ WASM build target works (`zig build wasm`)
- ✅ Single-threaded emulation core (`src/wasm.zig` with 12 exported functions)
- ✅ Phoenix LiveView frontend (`rambo_web/`)
- ✅ JavaScript client with canvas rendering
- ❌ Export table only contains `memory` (verified via `WebAssembly.instantiate`)

**Reference**: See `docs/web/wasm-export-notes.md` for detailed investigation.

## Success Criteria

- [ ] **Refactor build system** - Extract WASM build logic from `build.zig:77-121` into new `build/wasm.zig` module (follows existing pattern: `build/wayland.zig`, `build/graphics.zig`, etc.)
- [ ] **Fix export visibility** - All 12 exported functions appear in WASM export table and are callable from JavaScript
- [ ] **Centralized export list** - Export symbol names defined in one location, shared between Zig build and JavaScript client
- [ ] **Verify integration** - Phoenix frontend can successfully call all WASM API functions (init, shutdown, reset, step_frame, controller I/O, framebuffer access, alloc/free)
- [ ] **Test with commercial ROM** - Load a test ROM through the web UI, verify frame rendering and keyboard input work end-to-end
- [ ] **Cross-browser compatibility** - Verify functionality in Firefox (Linux), Chrome (macOS), and Safari (macOS)
- [ ] **Frame rate target** - Achieve reasonable performance (target ~60 FPS, baseline from 100+ native FPS without debug symbols)
- [ ] **Audio stub** - Add Web Audio API stub for future audio implementation (non-functional but architecture in place)
- [ ] **Document solution** - Update `docs/web/wasm-export-notes.md` with final approach and rationale

## Context Manifest
<!-- Added by context-gathering agent -->

## User Notes

**Testing Environment**:
- Linux machine: Firefox (development/testing)
- macOS machine: Chrome + Safari (cross-browser validation)
- Mobile support: Not a priority

**Performance Baseline**:
### The Core Problem

**Root Cause:** Zig 0.15.2's `std.Build.addExecutable()` does NOT emit WASM exports automatically, even with `pub export fn` declarations. The symbols exist in the binary but aren't published in the WebAssembly export table that JavaScript accesses.

**Current State:** 
- `build.zig` lines 76-121 contain inline WASM build logic
- Only `memory` appears in export table (verified via Node.js test in `docs/web/wasm-export-notes.md`)
- All 12 functions fail at runtime: `TypeError: this.exports.rambo_alloc is not a function`

**Technical Details:**
- Symbols visible via `strings zig-out/bin/rambo.wasm` (contains `rambo_init`, `rambo_alloc`, etc.)
- Export table empty: `WebAssembly.instantiate()` only shows `['memory']`
- Setting `export_symbol_names` on module has no effect in Zig 0.15.2

### Build System Patterns to Follow

All build modules in `build/*.zig` follow consistent structure:

**Pattern Example** (`build/graphics.zig`):
```zig
pub const Shaders = struct {
    install_vertex: *std.Build.Step.InstallFile,
    install_fragment: *std.Build.Step.InstallFile,
};

pub fn setup(b: *std.Build) Shaders {
    const glslc = b.addSystemCommand(&.{"glslc"});
    // ... configure compilation ...
    const install_step = b.addInstallFile(artifact, dest);
    return Shaders{ .install_vertex = ..., .install_fragment = ... };
}
```

**Integration in `build.zig`:**
```zig
const Graphics = @import("build/graphics.zig");
const shaders = Graphics.setup(b);
b.getInstallStep().dependOn(&shaders.install_vertex.step);
```

**Key Characteristics:**
- Public struct for return artifacts
- Factory function `setup()` with explicit parameters
- Returns configured build steps ready to wire into dependency graph
- Zero hidden state - all configuration explicit

### Solution: Direct zig build-exe Approach

According to Zig's WebAssembly documentation, WASM exports require explicit `--export=` flags:

```bash
zig build-exe src/wasm.zig \
    -target wasm32-freestanding \
    -fno-entry \
    --export=rambo_init \
    --export=rambo_alloc \
    --export=rambo_step_frame \
    # ... (11 total functions)
```

**Implementation Strategy:**

1. **Create `build/wasm.zig`** following `build/graphics.zig` pattern:
   - Define export list as constant
   - Use `b.addSystemCommand()` to invoke `zig build-exe`
   - Programmatically add `--export=` flags for each function
   - Handle module dependencies (`--dep`, `-M` flags)

2. **Centralize export list:**
```zig
pub const EXPORT_SYMBOLS = [_][]const u8{
    "rambo_get_error",
    "rambo_init",
    "rambo_shutdown",
    "rambo_reset",
    "rambo_set_controller_state",
    "rambo_step_frame",
    "rambo_framebuffer_ptr",
    "rambo_framebuffer_size",
    "rambo_frame_dimensions",
    "rambo_alloc",
    "rambo_free",
};
```

3. **Return artifacts struct:**
```zig
pub const WasmBuild = struct {
    exe: *std.Build.Step.Compile,
    install: *std.Build.Step.InstallArtifact,
};

pub fn setup(b: *std.Build, config: WasmConfig) WasmBuild
```

### Current WASM Build Configuration

**Location:** `build.zig:76-121`

**Key Elements to Preserve:**
- Target: `wasm32-freestanding` (lines 86-89)
- Entry point disabled: `wasm_exe.entry = .disabled` (line 115)
- Single-threaded build options (lines 80-84)
- Module imports: `RAMBO` + `build_options` (lines 100-107)
- Install artifact to `zig-out/bin/rambo.wasm` (line 117)

**To Be Refactored:**
- Lines 91-108: Module creation (move to `build/wasm.zig`)
- Lines 110-117: Executable creation + installation
- Line 119-120: Build step registration

### WASM API Surface (src/wasm.zig)

**Complete Function List (11 exports + memory):**

| Function | Signature | Purpose |
|----------|-----------|---------|
| `rambo_get_error` | `() → u32` | Get last error code (ErrorCode enum) |
| `rambo_init` | `([*]const u8, usize) → u32` | Initialize emulator with ROM data |
| `rambo_shutdown` | `() → void` | Cleanup and free resources |
| `rambo_reset` | `() → u32` | Power cycle (reset CPU/PPU state) |
| `rambo_set_controller_state` | `(u32, u8) → void` | Update controller buttons (port + mask) |
| `rambo_step_frame` | `() → u32` | Execute one frame (~29780 CPU cycles) |
| `rambo_framebuffer_ptr` | `() → usize` | Get pointer to 256×240 RGBA framebuffer |
| `rambo_framebuffer_size` | `() → usize` | Get framebuffer size (61440 pixels) |
| `rambo_frame_dimensions` | `(*u32, *u32) → void` | Get width/height (256, 240) |
| `rambo_alloc` | `(usize) → usize` | Allocate WASM memory, return pointer |
| `rambo_free` | `(usize, usize) → void` | Free WASM memory (pointer + size) |
| `memory` | (implicit) | Linear memory (exported automatically) |

**Dependencies:**
- `RAMBO` module (src/root.zig) - Core emulation (`EmulationState`, `ButtonState`, `Config`, `CartridgeLoader`)
- `build_options` - Single-threaded configuration
- `std.heap.wasm_allocator` - WASM memory management

### Phoenix Frontend Integration

**JavaScript Client:** `rambo_web/assets/js/rambo_emulator.js`

**Initialization Flow:**
```javascript
// 1. Load WASM module
const { instance } = await WebAssembly.instantiate(bytes, {});
this.exports = instance.exports;  // Expects all 11 functions here!

// 2. Load ROM
const ptr = this.exports.rambo_alloc(bytes.length);  // Allocate
wasmView.set(bytes);                                  // Copy ROM
const result = this.exports.rambo_init(ptr, bytes.length);  // Initialize
this.exports.rambo_free(ptr, bytes.length);          // Free temp buffer

// 3. Get framebuffer
this.framePtr = this.exports.rambo_framebuffer_ptr();
this.framePixels = this.exports.rambo_framebuffer_size();
```

**Render Loop (60 FPS):**
```javascript
renderLoop() {
    const result = this.exports.rambo_step_frame();  // Emulate one frame
    this.drawFrame();  // Copy framebuffer to canvas
    requestAnimationFrame(this.raf);  // Next frame
}
```

**Input Handling:**
```javascript
handleKey(code, pressed) {
    const mask = KEY_BINDINGS.get(code);  // Arrow keys, Z/X, Enter, Shift
    if (pressed) this.controllerMask |= mask;
    else this.controllerMask &= ~mask;
    this.exports.rambo_set_controller_state(0, this.controllerMask);
}
```

**Critical Dependencies:**
- All 11 functions must be in `instance.exports` or client crashes
- Memory management: JavaScript owns ROM copy, WASM owns emulator state
- Framebuffer: Zero-copy (JavaScript views WASM memory directly)

### Verification Test

**After fix, this should succeed:**
```bash
# Build WASM
zig build wasm

# Verify exports (should show all 11 functions + memory)
node -e 'const fs=require("fs"); \
         const wasm=fs.readFileSync("zig-out/bin/rambo.wasm"); \
         WebAssembly.instantiate(wasm,{}).then(({instance})=> \
         console.log(Object.keys(instance.exports).sort()))'
```

**Expected Output:**
```javascript
[
  'memory',
  'rambo_alloc',
  'rambo_frame_dimensions',
  'rambo_framebuffer_ptr',
  'rambo_framebuffer_size',
  'rambo_free',
  'rambo_get_error',
  'rambo_init',
  'rambo_reset',
  'rambo_set_controller_state',
  'rambo_shutdown',
  'rambo_step_frame'
]
```

**Integration Test:**
```bash
cd rambo_web
mix phx.server  # Start Phoenix server
# Open http://localhost:5000
# Upload test ROM (e.g., nestest.nes)
# Verify: ROM loads, frames render, keyboard controls work
```

### File Locations Summary

**To Create:**
- `build/wasm.zig` - New build module (follow `build/graphics.zig` pattern)

**To Modify:**
- `build.zig` - Replace lines 76-121 with `Wasm.setup()` call
- Add import: `const Wasm = @import("build/wasm.zig");` (line 8)

**Reference Files:**
- `build/graphics.zig` - Pattern for `addSystemCommand()` usage
- `build/modules.zig` - Pattern for module factory functions
- `src/wasm.zig` - Source of all export functions (no changes needed)
- `docs/web/wasm-export-notes.md` - Investigation findings (update after fix)

**Testing:**
- `rambo_web/assets/js/rambo_emulator.js` - JavaScript client expectations
- `rambo_web/mix.exs` - Phoenix server configuration
- Node.js one-liner (see Verification Test above)

### Alternative Approach: wasm-opt Post-Processing

**If zig build-exe proves complex**, alternative using Binaryen tools:

```zig
// In build/wasm.zig
pub fn setup(b: *std.Build, config: WasmConfig) WasmBuild {
    // 1. Build normally with addExecutable
    const wasm_exe = b.addExecutable(.{ ... });
    
    // 2. Post-process with wasm-opt
    const wasm_opt = b.addSystemCommand(&.{"wasm-opt"});
    for (EXPORT_SYMBOLS) |symbol| {
        wasm_opt.addArg("--export=" ++ symbol);
    }
    wasm_opt.addFileArg(wasm_exe.getEmittedBin());
    wasm_opt.addArg("-o");
    const output = wasm_opt.addOutputFileArg("rambo.wasm");
    
    const install = b.addInstallFile(output, "bin/rambo.wasm");
    return WasmBuild{ .exe = wasm_exe, .install = install };
}
```

**Trade-offs:**
- **Pro:** Simpler build logic, standard WebAssembly tooling
- **Con:** Requires `wasm-opt` installed (not currently a dependency)
- **Con:** Extra build step (compile → post-process → install)

Recommend: Try `zig build-exe` approach first (zero external dependencies).
- Native emulation: 100+ FPS (release build without debug symbols)
- Target: ~60 FPS in browser (acceptable, will measure actual performance)

**Audio**:
- APU emulation logic exists but audio output not fully implemented
- Web side: Stub out Web Audio API integration for future work
- Not a blocker for this task

**Implementation Approaches** (choose during implementation):

1. **Option A: wasm-opt post-processing** (recommended)
   - Add `wasm-opt --export=rambo_init --export=rambo_alloc ...` step after `zig build wasm`
   - Cleanest solution, standard WebAssembly tooling
   - Requires `wasm-opt` as build dependency

2. **Option B: Custom zig build-exe**
   - Replace `b.addExecutable()` with manual `zig build-exe` command
   - Pass `--export=` flags for each function
   - More complex, requires manual dependency wiring (`--pkg-begin`/`--pkg-end`)
   - No additional dependencies

3. **Option C: Zig 0.16.0 upgrade**
   - Check if Zig 0.16.0+ fixes export emission
   - May require migration effort if breaking changes exist

**Export List** (12 functions from `src/wasm.zig`):
- `rambo_get_error`
- `rambo_init`
- `rambo_shutdown`
- `rambo_reset`
- `rambo_set_controller_state`
- `rambo_step_frame`
- `rambo_framebuffer_ptr`
- `rambo_framebuffer_size`
- `rambo_frame_dimensions`
- `rambo_alloc`
- `rambo_free`
- `memory` (implicit, already exported)

## Work Log
<!-- Updated as work progresses -->
