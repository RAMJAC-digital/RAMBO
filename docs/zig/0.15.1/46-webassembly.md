<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: WebAssembly -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [WebAssembly](zig-0.15.1.md#toc-WebAssembly) <a href="zig-0.15.1.md#WebAssembly" class="hdr">§</a>

Zig supports building for WebAssembly out of the box.

### [Freestanding](zig-0.15.1.md#toc-Freestanding) <a href="zig-0.15.1.md#Freestanding" class="hdr">§</a>

For host environments like the web browser and nodejs, build as an executable using the freestanding
OS target. Here's an example of running Zig code compiled to WebAssembly with nodejs.

<figure>
<pre><code>extern fn print(i32) void;

export fn add(a: i32, b: i32) void {
    print(a + b);
}</code></pre>
<figcaption>math.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe math.zig -target wasm32-freestanding -fno-entry --export=add</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>const fs = require(&#39;fs&#39;);
const source = fs.readFileSync(&quot;./math.wasm&quot;);
const typedArray = new Uint8Array(source);

WebAssembly.instantiate(typedArray, {
  env: {
    print: (result) =&gt; { console.log(`The result is ${result}`); }
  }}).then(result =&gt; {
  const add = result.instance.exports.add;
  add(1, 2);
});</code></pre>
<figcaption>test.js</figcaption>
</figure>

<figure>
<pre><code>$ node test.js
The result is 3</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [WASI](zig-0.15.1.md#toc-WASI) <a href="zig-0.15.1.md#WASI" class="hdr">§</a>

Zig's support for WebAssembly System Interface (WASI) is under active development.
Example of using the standard library and reading command line arguments:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    for (args, 0..) |arg, i| {
        std.debug.print(&quot;{}: {s}\n&quot;, .{ i, arg });
    }
}</code></pre>
<figcaption>wasi_args.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe wasi_args.zig -target wasm32-wasi</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>$ wasmtime wasi_args.wasm 123 hello
0: wasi_args.wasm
1: 123
2: hello</code></pre>
<figcaption>Shell</figcaption>
</figure>

A more interesting example would be extracting the list of preopens from the runtime.
This is now supported in the standard library via `std.fs.wasi.Preopens`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const fs = std.fs;

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const preopens = try fs.wasi.preopensAlloc(arena);

    for (preopens.names, 0..) |preopen, i| {
        std.debug.print(&quot;{}: {s}\n&quot;, .{ i, preopen });
    }
}</code></pre>
<figcaption>wasi_preopens.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe wasi_preopens.zig -target wasm32-wasi</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>$ wasmtime --dir=. wasi_preopens.wasm
0: stdin
1: stdout
2: stderr
3: .</code></pre>
<figcaption>Shell</figcaption>
</figure>

