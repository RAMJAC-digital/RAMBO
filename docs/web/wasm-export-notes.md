# WebAssembly Export Notes (2025-11-05)

While wiring the Phoenix front-end to the Zig wasm build we ran into a missing
symbol issue in the browser:

```
TypeError: this.exports.rambo_alloc is not a function
```

Inspecting the module shows the problem is on the Zig side rather than in the
JS shim:

```bash
$ node -e 'const fs=require("fs");const wasm=fs.readFileSync("zig-out/bin/rambo.wasm");\
           WebAssembly.instantiate(wasm,{}).then(({instance})=>console.log(Object.keys(instance.exports)))'
[ 'memory' ]
```

Even though `strings zig-out/bin/rambo.wasm` still contains symbol names like
`rambo_init`, `rambo_framebuffer_ptr`, and `rambo_alloc`, the export table only
publishes the linear memory. This means any new host API we add via
`pub export fn` will fail at runtime unless we explicitly export it.

### Current status

* The standard `std.Build` pipeline (`b.addExecutable`) does **not** emit the
  extra exports even when we set `export_symbol_names` on the module. This holds
  for Zig 0.15.2.
* Switching to a `zig build-exe` system command requires manually passing
  `--export=` for every symbol. Additionally the CLI expects the package
  arguments (`--pkg-begin` / `--pkg-end`), which complicates dependency wiring
  inside `build.zig`.
* For now the wasm artefact only exports memory. The Phoenix client therefore
  cannot call `rambo_init`, `rambo_alloc`, etc., until we add an explicit export
  step.

### Next steps

1. Hook a post-processing step (e.g. `wasm-opt --export=...`) or adjust the Zig
   command invocation so that the functions are exported.
2. Keep the export list centrally defined to ensure the Zig build and the JS
   bridge stay in sync whenever we extend the wasm API.
3. Once exports are visible, re-run the JS shim smoke test (keyboard input,
   `rambo_step_frame`, etc.) to confirm the Phoenix front-end exercises the new
   symbols correctly.

This note is meant to save time when we revisit wasm exports: the missing
functions are due to the wasm export table, not the JavaScript glue.
