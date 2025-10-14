<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Illegal Behavior -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Illegal Behavior](zig-0.15.1.md#toc-Illegal-Behavior) <a href="zig-0.15.1.md#Illegal-Behavior" class="hdr">§</a>

Many operations in Zig trigger what is known as "Illegal Behavior" (IB). If Illegal Behavior is detected at
compile-time, Zig emits a compile error and refuses to continue. Otherwise, when Illegal Behavior is not caught
at compile-time, it falls into one of two categories.

Some Illegal Behavior is *safety-checked*: this means that the compiler will insert "safety checks"
anywhere that the Illegal Behavior may occur at runtime, to determine whether it is about to happen. If it
is, the safety check "fails", which triggers a panic.

All other Illegal Behavior is *unchecked*, meaning the compiler is unable to insert safety checks for
it. If Unchecked Illegal Behavior is invoked at runtime, anything can happen: usually that will be some kind of
crash, but the optimizer is free to make Unchecked Illegal Behavior do anything, such as calling arbitrary functions
or clobbering arbitrary data. This is similar to the concept of "undefined behavior" in some other languages. Note that
Unchecked Illegal Behavior still always results in a compile error if evaluated at [comptime](zig-0.15.1.md#comptime), because the Zig
compiler is able to perform more sophisticated checks at compile-time than at runtime.

Most Illegal Behavior is safety-checked. However, to facilitate optimizations, safety checks are disabled by default
in the [ReleaseFast](zig-0.15.1.md#ReleaseFast) and [ReleaseSmall](zig-0.15.1.md#ReleaseSmall) optimization modes. Safety checks can also be enabled or disabled
on a per-block basis, overriding the default for the current optimization mode, using [@setRuntimeSafety](zig-0.15.1.md#setRuntimeSafety). When
safety checks are disabled, Safety-Checked Illegal Behavior behaves like Unchecked Illegal Behavior; that is, any behavior
may result from invoking it.

When a safety check fails, Zig's default panic handler crashes with a stack trace, like this:

<figure>
<pre><code>test &quot;safety check&quot; {
    unreachable;
}</code></pre>
<figcaption>test_illegal_behavior.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_illegal_behavior.zig
1/1 test_illegal_behavior.test.safety check...thread 1095219 panic: reached unreachable code
/home/andy/dev/zig/doc/langref/test_illegal_behavior.zig:2:5: 0x102c00c in test.safety check (test_illegal_behavior.zig)
    unreachable;
    ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cb00 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155d21 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fabd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f351 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/65a0232d3a5c4bf204eadafcbceee32c/test --seed=0xb567ab3d</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Reaching Unreachable Code](zig-0.15.1.md#toc-Reaching-Unreachable-Code) <a href="zig-0.15.1.md#Reaching-Unreachable-Code" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    assert(false);
}
fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}</code></pre>
<figcaption>test_comptime_reaching_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_reaching_unreachable.zig
/home/andy/dev/zig/doc/langref/test_comptime_reaching_unreachable.zig:5:14: error: reached unreachable code
    if (!ok) unreachable; // assertion failure
             ^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_reaching_unreachable.zig:2:11: note: called at comptime here
    assert(false);
    ~~~~~~^~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    std.debug.assert(false);
}</code></pre>
<figcaption>runtime_reaching_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_reaching_unreachable.zig
$ ./runtime_reaching_unreachable
thread 1098849 panic: reached unreachable code
/home/andy/dev/zig/lib/std/debug.zig:559:14: 0x1044179 in assert (std.zig)
    if (!ok) unreachable; // assertion failure
             ^
/home/andy/dev/zig/doc/langref/runtime_reaching_unreachable.zig:4:21: 0x113e84e in main (runtime_reaching_unreachable.zig)
    std.debug.assert(false);
                    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Index out of Bounds](zig-0.15.1.md#toc-Index-out-of-Bounds) <a href="zig-0.15.1.md#Index-out-of-Bounds" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const array: [5]u8 = &quot;hello&quot;.*;
    const garbage = array[5];
    _ = garbage;
}</code></pre>
<figcaption>test_comptime_index_out_of_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_index_out_of_bounds.zig
/home/andy/dev/zig/doc/langref/test_comptime_index_out_of_bounds.zig:3:27: error: index 5 outside array of length 5
    const garbage = array[5];
                          ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    const x = foo(&quot;hello&quot;);
    _ = x;
}

fn foo(x: []const u8) u8 {
    return x[5];
}</code></pre>
<figcaption>runtime_index_out_of_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_index_out_of_bounds.zig
$ ./runtime_index_out_of_bounds
thread 1098063 panic: index out of bounds: index 5, len 5
/home/andy/dev/zig/doc/langref/runtime_index_out_of_bounds.zig:7:13: 0x113fac6 in foo (runtime_index_out_of_bounds.zig)
    return x[5];
            ^
/home/andy/dev/zig/doc/langref/runtime_index_out_of_bounds.zig:2:18: 0x113e85a in main (runtime_index_out_of_bounds.zig)
    const x = foo(&quot;hello&quot;);
                 ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Cast Negative Number to Unsigned Integer](zig-0.15.1.md#toc-Cast-Negative-Number-to-Unsigned-Integer) <a href="zig-0.15.1.md#Cast-Negative-Number-to-Unsigned-Integer" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const value: i32 = -1;
    const unsigned: u32 = @intCast(value);
    _ = unsigned;
}</code></pre>
<figcaption>test_comptime_invalid_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_cast.zig:3:36: error: type &#39;u32&#39; cannot represent integer value &#39;-1&#39;
    const unsigned: u32 = @intCast(value);
                                   ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var value: i32 = -1; // runtime-known
    _ = &amp;value;
    const unsigned: u32 = @intCast(value);
    std.debug.print(&quot;value: {}\n&quot;, .{unsigned});
}</code></pre>
<figcaption>runtime_invalid_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_cast.zig
$ ./runtime_invalid_cast
thread 1099031 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/runtime_invalid_cast.zig:6:27: 0x113e85f in main (runtime_invalid_cast.zig)
    const unsigned: u32 = @intCast(value);
                          ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

To obtain the maximum value of an unsigned integer, use `std.math.maxInt`.

### [Cast Truncates Data](zig-0.15.1.md#toc-Cast-Truncates-Data) <a href="zig-0.15.1.md#Cast-Truncates-Data" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const spartan_count: u16 = 300;
    const byte: u8 = @intCast(spartan_count);
    _ = byte;
}</code></pre>
<figcaption>test_comptime_invalid_cast_truncate.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_cast_truncate.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_cast_truncate.zig:3:31: error: type &#39;u8&#39; cannot represent integer value &#39;300&#39;
    const byte: u8 = @intCast(spartan_count);
                              ^~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var spartan_count: u16 = 300; // runtime-known
    _ = &amp;spartan_count;
    const byte: u8 = @intCast(spartan_count);
    std.debug.print(&quot;value: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>runtime_invalid_cast_truncate.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_cast_truncate.zig
$ ./runtime_invalid_cast_truncate
thread 1101249 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/runtime_invalid_cast_truncate.zig:6:22: 0x113e860 in main (runtime_invalid_cast_truncate.zig)
    const byte: u8 = @intCast(spartan_count);
                     ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

To truncate bits, use [@truncate](zig-0.15.1.md#truncate).

### [Integer Overflow](zig-0.15.1.md#toc-Integer-Overflow) <a href="zig-0.15.1.md#Integer-Overflow" class="hdr">§</a>

#### [Default Operations](zig-0.15.1.md#toc-Default-Operations) <a href="zig-0.15.1.md#Default-Operations" class="hdr">§</a>

The following operators can cause integer overflow:

- `+` (addition)
- `-` (subtraction)
- `-` (negation)
- `*` (multiplication)
- `/` (division)
- [@divTrunc](zig-0.15.1.md#divTrunc) (division)
- [@divFloor](zig-0.15.1.md#divFloor) (division)
- [@divExact](zig-0.15.1.md#divExact) (division)

Example with addition at compile-time:

<figure>
<pre><code>comptime {
    var byte: u8 = 255;
    byte += 1;
}</code></pre>
<figcaption>test_comptime_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_overflow.zig:3:10: error: overflow of integer type &#39;u8&#39; with value &#39;256&#39;
    byte += 1;
    ~~~~~^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var byte: u8 = 255;
    byte += 1;
    std.debug.print(&quot;value: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>runtime_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_overflow.zig
$ ./runtime_overflow
thread 1095998 panic: integer overflow
/home/andy/dev/zig/doc/langref/runtime_overflow.zig:5:10: 0x113e875 in main (runtime_overflow.zig)
    byte += 1;
         ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Standard Library Math Functions](zig-0.15.1.md#toc-Standard-Library-Math-Functions) <a href="zig-0.15.1.md#Standard-Library-Math-Functions" class="hdr">§</a>

These functions provided by the standard library return possible errors.

- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.add`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.sub`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.mul`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divTrunc`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divFloor`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divExact`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.shl`

Example of catching an overflow for addition:

<figure>
<pre><code>const math = @import(&quot;std&quot;).math;
const print = @import(&quot;std&quot;).debug.print;
pub fn main() !void {
    var byte: u8 = 255;

    byte = if (math.add(u8, byte, 1)) |result| result else |err| {
        print(&quot;unable to add one: {s}\n&quot;, .{@errorName(err)});
        return err;
    };

    print(&quot;result: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>math_add.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe math_add.zig
$ ./math_add
unable to add one: Overflow
error: Overflow
/home/andy/dev/zig/lib/std/math.zig:570:21: 0x113eb8e in add__anon_22554 (std.zig)
    if (ov[1] != 0) return error.Overflow;
                    ^
/home/andy/dev/zig/doc/langref/math_add.zig:8:9: 0x113d402 in main (math_add.zig)
        return err;
        ^</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Builtin Overflow Functions](zig-0.15.1.md#toc-Builtin-Overflow-Functions) <a href="zig-0.15.1.md#Builtin-Overflow-Functions" class="hdr">§</a>

These builtins return a tuple containing whether there was an overflow
(as a <span class="tok-type">`u1`</span>) and the possibly overflowed bits of the operation:

- [@addWithOverflow](zig-0.15.1.md#addWithOverflow)
- [@subWithOverflow](zig-0.15.1.md#subWithOverflow)
- [@mulWithOverflow](zig-0.15.1.md#mulWithOverflow)
- [@shlWithOverflow](zig-0.15.1.md#shlWithOverflow)

Example of [@addWithOverflow](zig-0.15.1.md#addWithOverflow):

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;
pub fn main() void {
    const byte: u8 = 255;

    const ov = @addWithOverflow(byte, 10);
    if (ov[1] != 0) {
        print(&quot;overflowed result: {}\n&quot;, .{ov[0]});
    } else {
        print(&quot;result: {}\n&quot;, .{ov[0]});
    }
}</code></pre>
<figcaption>addWithOverflow_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe addWithOverflow_builtin.zig
$ ./addWithOverflow_builtin
overflowed result: 9</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Wrapping Operations](zig-0.15.1.md#toc-Wrapping-Operations) <a href="zig-0.15.1.md#Wrapping-Operations" class="hdr">§</a>

These operations have guaranteed wraparound semantics.

- `+%` (wraparound addition)
- `-%` (wraparound subtraction)
- `-%` (wraparound negation)
- `*%` (wraparound multiplication)

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;

test &quot;wraparound addition and subtraction&quot; {
    const x: i32 = maxInt(i32);
    const min_val = x +% 1;
    try expect(min_val == minInt(i32));
    const max_val = min_val -% 1;
    try expect(max_val == maxInt(i32));
}</code></pre>
<figcaption>test_wraparound_semantics.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wraparound_semantics.zig
1/1 test_wraparound_semantics.test.wraparound addition and subtraction...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Left Shift Overflow](zig-0.15.1.md#toc-Exact-Left-Shift-Overflow) <a href="zig-0.15.1.md#Exact-Left-Shift-Overflow" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const x = @shlExact(@as(u8, 0b01010101), 2);
    _ = x;
}</code></pre>
<figcaption>test_comptime_shlExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_shlExact_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_shlExact_overflow.zig:2:15: error: overflow of integer type &#39;u8&#39; with value &#39;340&#39;
    const x = @shlExact(@as(u8, 0b01010101), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var x: u8 = 0b01010101; // runtime-known
    _ = &amp;x;
    const y = @shlExact(x, 2);
    std.debug.print(&quot;value: {}\n&quot;, .{y});
}</code></pre>
<figcaption>runtime_shlExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_shlExact_overflow.zig
$ ./runtime_shlExact_overflow
thread 1097953 panic: left shift overflowed bits
/home/andy/dev/zig/doc/langref/runtime_shlExact_overflow.zig:6:5: 0x113e881 in main (runtime_shlExact_overflow.zig)
    const y = @shlExact(x, 2);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Right Shift Overflow](zig-0.15.1.md#toc-Exact-Right-Shift-Overflow) <a href="zig-0.15.1.md#Exact-Right-Shift-Overflow" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const x = @shrExact(@as(u8, 0b10101010), 2);
    _ = x;
}</code></pre>
<figcaption>test_comptime_shrExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_shrExact_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_shrExact_overflow.zig:2:15: error: exact shift shifted out 1 bits
    const x = @shrExact(@as(u8, 0b10101010), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const builtin = @import(&quot;builtin&quot;);
const std = @import(&quot;std&quot;);

pub fn main() void {
    var x: u8 = 0b10101010; // runtime-known
    _ = &amp;x;
    const y = @shrExact(x, 2);
    std.debug.print(&quot;value: {}\n&quot;, .{y});

    if (builtin.cpu.arch.isRISCV() and builtin.zig_backend == .stage2_llvm) @panic(&quot;https://github.com/ziglang/zig/issues/24304&quot;);
}</code></pre>
<figcaption>runtime_shrExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_shrExact_overflow.zig
$ ./runtime_shrExact_overflow
thread 1099637 panic: right shift overflowed bits
/home/andy/dev/zig/doc/langref/runtime_shrExact_overflow.zig:7:5: 0x113e86a in main (runtime_shrExact_overflow.zig)
    const y = @shrExact(x, 2);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Division by Zero](zig-0.15.1.md#toc-Division-by-Zero) <a href="zig-0.15.1.md#Division-by-Zero" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: i32 = 1;
    const b: i32 = 0;
    const c = a / b;
    _ = c;
}</code></pre>
<figcaption>test_comptime_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_division_by_zero.zig
/home/andy/dev/zig/doc/langref/test_comptime_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a / b;
                  ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 1;
    var b: u32 = 0;
    _ = .{ &amp;a, &amp;b };
    const c = a / b;
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_division_by_zero.zig
$ ./runtime_division_by_zero
thread 1091859 panic: division by zero
/home/andy/dev/zig/doc/langref/runtime_division_by_zero.zig:7:17: 0x113e870 in main (runtime_division_by_zero.zig)
    const c = a / b;
                ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Remainder Division by Zero](zig-0.15.1.md#toc-Remainder-Division-by-Zero) <a href="zig-0.15.1.md#Remainder-Division-by-Zero" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: i32 = 10;
    const b: i32 = 0;
    const c = a % b;
    _ = c;
}</code></pre>
<figcaption>test_comptime_remainder_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_remainder_division_by_zero.zig
/home/andy/dev/zig/doc/langref/test_comptime_remainder_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a % b;
                  ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 0;
    _ = .{ &amp;a, &amp;b };
    const c = a % b;
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_remainder_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_remainder_division_by_zero.zig
$ ./runtime_remainder_division_by_zero
thread 1099159 panic: division by zero
/home/andy/dev/zig/doc/langref/runtime_remainder_division_by_zero.zig:7:17: 0x113e870 in main (runtime_remainder_division_by_zero.zig)
    const c = a % b;
                ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Division Remainder](zig-0.15.1.md#toc-Exact-Division-Remainder) <a href="zig-0.15.1.md#Exact-Division-Remainder" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: u32 = 10;
    const b: u32 = 3;
    const c = @divExact(a, b);
    _ = c;
}</code></pre>
<figcaption>test_comptime_divExact_remainder.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_divExact_remainder.zig
/home/andy/dev/zig/doc/langref/test_comptime_divExact_remainder.zig:4:15: error: exact division produced remainder
    const c = @divExact(a, b);
              ^~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 3;
    _ = .{ &amp;a, &amp;b };
    const c = @divExact(a, b);
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_divExact_remainder.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_divExact_remainder.zig
$ ./runtime_divExact_remainder
thread 1093460 panic: exact division produced remainder
/home/andy/dev/zig/doc/langref/runtime_divExact_remainder.zig:7:15: 0x113e8a7 in main (runtime_divExact_remainder.zig)
    const c = @divExact(a, b);
              ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Attempt to Unwrap Null](zig-0.15.1.md#toc-Attempt-to-Unwrap-Null) <a href="zig-0.15.1.md#Attempt-to-Unwrap-Null" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const optional_number: ?i32 = null;
    const number = optional_number.?;
    _ = number;
}</code></pre>
<figcaption>test_comptime_unwrap_null.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_unwrap_null.zig
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_null.zig:3:35: error: unable to unwrap null
    const number = optional_number.?;
                   ~~~~~~~~~~~~~~~^~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var optional_number: ?i32 = null;
    _ = &amp;optional_number;
    const number = optional_number.?;
    std.debug.print(&quot;value: {}\n&quot;, .{number});
}</code></pre>
<figcaption>runtime_unwrap_null.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_unwrap_null.zig
$ ./runtime_unwrap_null
thread 1094411 panic: attempt to use null value
/home/andy/dev/zig/doc/langref/runtime_unwrap_null.zig:6:35: 0x113e894 in main (runtime_unwrap_null.zig)
    const number = optional_number.?;
                                  ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

One way to avoid this crash is to test for null instead of assuming non-null, with
the <span class="tok-kw">`if`</span> expression:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;
pub fn main() void {
    const optional_number: ?i32 = null;

    if (optional_number) |number| {
        print(&quot;got number: {}\n&quot;, .{number});
    } else {
        print(&quot;it&#39;s null\n&quot;, .{});
    }
}</code></pre>
<figcaption>testing_null_with_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe testing_null_with_if.zig
$ ./testing_null_with_if
it&#39;s null</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optionals](zig-0.15.1.md#Optionals)

### [Attempt to Unwrap Error](zig-0.15.1.md#toc-Attempt-to-Unwrap-Error) <a href="zig-0.15.1.md#Attempt-to-Unwrap-Error" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const number = getNumberOrFail() catch unreachable;
    _ = number;
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>test_comptime_unwrap_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_unwrap_error.zig
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_error.zig:2:44: error: caught unexpected error &#39;UnableToReturnNumber&#39;
    const number = getNumberOrFail() catch unreachable;
                                           ^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_error.zig:7:18: note: error returned here
    return error.UnableToReturnNumber;
                 ^~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const number = getNumberOrFail() catch unreachable;
    std.debug.print(&quot;value: {}\n&quot;, .{number});
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>runtime_unwrap_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_unwrap_error.zig
$ ./runtime_unwrap_error
thread 1091973 panic: attempt to unwrap error: UnableToReturnNumber
/home/andy/dev/zig/doc/langref/runtime_unwrap_error.zig:9:5: 0x113e84c in getNumberOrFail (runtime_unwrap_error.zig)
    return error.UnableToReturnNumber;
    ^
/home/andy/dev/zig/doc/langref/runtime_unwrap_error.zig:4:44: 0x113e8b3 in main (runtime_unwrap_error.zig)
    const number = getNumberOrFail() catch unreachable;
                                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

One way to avoid this crash is to test for an error instead of assuming a successful result, with
the <span class="tok-kw">`if`</span> expression:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    const result = getNumberOrFail();

    if (result) |number| {
        print(&quot;got number: {}\n&quot;, .{number});
    } else |err| {
        print(&quot;got error: {s}\n&quot;, .{@errorName(err)});
    }
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>testing_error_with_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe testing_error_with_if.zig
$ ./testing_error_with_if
got error: UnableToReturnNumber</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Errors](zig-0.15.1.md#Errors)

### [Invalid Error Code](zig-0.15.1.md#toc-Invalid-Error-Code) <a href="zig-0.15.1.md#Invalid-Error-Code" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const err = error.AnError;
    const number = @intFromError(err) + 10;
    const invalid_err = @errorFromInt(number);
    _ = invalid_err;
}</code></pre>
<figcaption>test_comptime_invalid_error_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_error_code.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_error_code.zig:4:39: error: integer value &#39;11&#39; represents no error
    const invalid_err = @errorFromInt(number);
                                      ^~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const err = error.AnError;
    var number = @intFromError(err) + 500;
    _ = &amp;number;
    const invalid_err = @errorFromInt(number);
    std.debug.print(&quot;value: {}\n&quot;, .{invalid_err});
}</code></pre>
<figcaption>runtime_invalid_error_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_error_code.zig
$ ./runtime_invalid_error_code
thread 1091971 panic: invalid error code
/home/andy/dev/zig/doc/langref/runtime_invalid_error_code.zig:7:5: 0x113e887 in main (runtime_invalid_error_code.zig)
    const invalid_err = @errorFromInt(number);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Invalid Enum Cast](zig-0.15.1.md#toc-Invalid-Enum-Cast) <a href="zig-0.15.1.md#Invalid-Enum-Cast" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>const Foo = enum {
    a,
    b,
    c,
};
comptime {
    const a: u2 = 3;
    const b: Foo = @enumFromInt(a);
    _ = b;
}</code></pre>
<figcaption>test_comptime_invalid_enum_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_enum_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_enum_cast.zig:8:20: error: enum &#39;test_comptime_invalid_enum_cast.Foo&#39; has no tag with value &#39;3&#39;
    const b: Foo = @enumFromInt(a);
                   ^~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_invalid_enum_cast.zig:1:13: note: enum declared here
const Foo = enum {
            ^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = enum {
    a,
    b,
    c,
};

pub fn main() void {
    var a: u2 = 3;
    _ = &amp;a;
    const b: Foo = @enumFromInt(a);
    std.debug.print(&quot;value: {s}\n&quot;, .{@tagName(b)});
}</code></pre>
<figcaption>runtime_invalid_enum_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_enum_cast.zig
$ ./runtime_invalid_enum_cast
thread 1092133 panic: invalid enum value
/home/andy/dev/zig/doc/langref/runtime_invalid_enum_cast.zig:12:20: 0x113e8d0 in main (runtime_invalid_enum_cast.zig)
    const b: Foo = @enumFromInt(a);
                   ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Invalid Error Set Cast](zig-0.15.1.md#toc-Invalid-Error-Set-Cast) <a href="zig-0.15.1.md#Invalid-Error-Set-Cast" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
comptime {
    _ = @as(Set2, @errorCast(Set1.B));
}</code></pre>
<figcaption>test_comptime_invalid_error_set_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_error_set_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_error_set_cast.zig:10:19: error: &#39;error.B&#39; not a member of error set &#39;error{A,C}&#39;
    _ = @as(Set2, @errorCast(Set1.B));
                  ^~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
pub fn main() void {
    foo(Set1.B);
}
fn foo(set1: Set1) void {
    const x: Set2 = @errorCast(set1);
    std.debug.print(&quot;value: {}\n&quot;, .{x});
}</code></pre>
<figcaption>runtime_invalid_error_set_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_error_set_cast.zig
$ ./runtime_invalid_error_set_cast
thread 1096585 panic: invalid error code
/home/andy/dev/zig/doc/langref/runtime_invalid_error_set_cast.zig:15:21: 0x113fb1c in foo (runtime_invalid_error_set_cast.zig)
    const x: Set2 = @errorCast(set1);
                    ^
/home/andy/dev/zig/doc/langref/runtime_invalid_error_set_cast.zig:12:8: 0x113e857 in main (runtime_invalid_error_set_cast.zig)
    foo(Set1.B);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Incorrect Pointer Alignment](zig-0.15.1.md#toc-Incorrect-Pointer-Alignment) <a href="zig-0.15.1.md#Incorrect-Pointer-Alignment" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const ptr: *align(1) i32 = @ptrFromInt(0x1);
    const aligned: *align(4) i32 = @alignCast(ptr);
    _ = aligned;
}</code></pre>
<figcaption>test_comptime_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_incorrect_pointer_alignment.zig
/home/andy/dev/zig/doc/langref/test_comptime_incorrect_pointer_alignment.zig:3:47: error: pointer address 0x1 is not aligned to 4 bytes
    const aligned: *align(4) i32 = @alignCast(ptr);
                                              ^~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const mem = @import(&quot;std&quot;).mem;
pub fn main() !void {
    var array align(4) = [_]u32{ 0x11111111, 0x11111111 };
    const bytes = mem.sliceAsBytes(array[0..]);
    if (foo(bytes) != 0x11111111) return error.Wrong;
}
fn foo(bytes: []u8) u32 {
    const slice4 = bytes[1..5];
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
    return int_slice[0];
}</code></pre>
<figcaption>runtime_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_incorrect_pointer_alignment.zig
$ ./runtime_incorrect_pointer_alignment
thread 1097866 panic: incorrect alignment
/home/andy/dev/zig/doc/langref/runtime_incorrect_pointer_alignment.zig:9:64: 0x113ebe8 in foo (runtime_incorrect_pointer_alignment.zig)
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                               ^
/home/andy/dev/zig/doc/langref/runtime_incorrect_pointer_alignment.zig:5:12: 0x113d3d2 in main (runtime_incorrect_pointer_alignment.zig)
    if (foo(bytes) != 0x11111111) return error.Wrong;
           ^
/home/andy/dev/zig/lib/std/start.zig:627:37: 0x113dba9 in posixCallMainAndExit (std.zig)
            const result = root.main() catch |err| {
                                    ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Wrong Union Field Access](zig-0.15.1.md#toc-Wrong-Union-Field-Access) <a href="zig-0.15.1.md#Wrong-Union-Field-Access" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    var f = Foo{ .int = 42 };
    f.float = 12.34;
}

const Foo = union {
    float: f32,
    int: u32,
};</code></pre>
<figcaption>test_comptime_wrong_union_field_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_wrong_union_field_access.zig
/home/andy/dev/zig/doc/langref/test_comptime_wrong_union_field_access.zig:3:6: error: access of union field &#39;float&#39; while field &#39;int&#39; is active
    f.float = 12.34;
    ~^~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_wrong_union_field_access.zig:6:13: note: union declared here
const Foo = union {
            ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&amp;f);
}

fn bar(f: *Foo) void {
    f.float = 12.34;
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}</code></pre>
<figcaption>runtime_wrong_union_field_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_wrong_union_field_access.zig
$ ./runtime_wrong_union_field_access
thread 1093352 panic: access of union field &#39;float&#39; while field &#39;int&#39; is active
/home/andy/dev/zig/doc/langref/runtime_wrong_union_field_access.zig:14:6: 0x113fafe in bar (runtime_wrong_union_field_access.zig)
    f.float = 12.34;
     ^
/home/andy/dev/zig/doc/langref/runtime_wrong_union_field_access.zig:10:8: 0x113e87f in main (runtime_wrong_union_field_access.zig)
    bar(&amp;f);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

This safety is not available for <span class="tok-kw">`extern`</span> or <span class="tok-kw">`packed`</span> unions.

To change the active field of a union, assign the entire union, like this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&amp;f);
}

fn bar(f: *Foo) void {
    f.* = Foo{ .float = 12.34 };
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}</code></pre>
<figcaption>change_active_union_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe change_active_union_field.zig
$ ./change_active_union_field
value: 12.34</code></pre>
<figcaption>Shell</figcaption>
</figure>

To change the active field of a union when a meaningful value for the field is not known,
use [undefined](zig-0.15.1.md#undefined), like this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    f = Foo{ .float = undefined };
    bar(&amp;f);
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}

fn bar(f: *Foo) void {
    f.float = 12.34;
}</code></pre>
<figcaption>undefined_active_union_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe undefined_active_union_field.zig
$ ./undefined_active_union_field
value: 12.34</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [union](zig-0.15.1.md#union)
- [extern union](zig-0.15.1.md#extern-union)

### [Out of Bounds Float to Integer Cast](zig-0.15.1.md#toc-Out-of-Bounds-Float-to-Integer-Cast) <a href="zig-0.15.1.md#Out-of-Bounds-Float-to-Integer-Cast" class="hdr">§</a>

This happens when casting a float to an integer where the float has a value outside the
integer type's range.

At compile-time:

<figure>
<pre><code>comptime {
    const float: f32 = 4294967296;
    const int: i32 = @intFromFloat(float);
    _ = int;
}</code></pre>
<figcaption>test_comptime_out_of_bounds_float_to_integer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_out_of_bounds_float_to_integer_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_out_of_bounds_float_to_integer_cast.zig:3:36: error: float value &#39;4294967296&#39; cannot be stored in integer type &#39;i32&#39;
    const int: i32 = @intFromFloat(float);
                                   ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    var float: f32 = 4294967296; // runtime-known
    _ = &amp;float;
    const int: i32 = @intFromFloat(float);
    _ = int;
}</code></pre>
<figcaption>runtime_out_of_bounds_float_to_integer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_out_of_bounds_float_to_integer_cast.zig
$ ./runtime_out_of_bounds_float_to_integer_cast
thread 1101276 panic: integer part of floating point value out of bounds
/home/andy/dev/zig/doc/langref/runtime_out_of_bounds_float_to_integer_cast.zig:4:22: 0x113e8b2 in main (runtime_out_of_bounds_float_to_integer_cast.zig)
    const int: i32 = @intFromFloat(float);
                     ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Pointer Cast Invalid Null](zig-0.15.1.md#toc-Pointer-Cast-Invalid-Null) <a href="zig-0.15.1.md#Pointer-Cast-Invalid-Null" class="hdr">§</a>

This happens when casting a pointer with the address 0 to a pointer which may not have the address 0.
For example, [C Pointers](zig-0.15.1.md#C-Pointers), [Optional Pointers](zig-0.15.1.md#Optional-Pointers), and [allowzero](zig-0.15.1.md#allowzero) pointers
allow address zero, but normal [Pointers](zig-0.15.1.md#Pointers) do not.

At compile-time:

<figure>
<pre><code>comptime {
    const opt_ptr: ?*i32 = null;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}</code></pre>
<figcaption>test_comptime_invalid_null_pointer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_null_pointer_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_null_pointer_cast.zig:3:32: error: null pointer casted to type &#39;*i32&#39;
    const ptr: *i32 = @ptrCast(opt_ptr);
                               ^~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    var opt_ptr: ?*i32 = null;
    _ = &amp;opt_ptr;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}</code></pre>
<figcaption>runtime_invalid_null_pointer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_null_pointer_cast.zig
$ ./runtime_invalid_null_pointer_cast
thread 1100207 panic: cast causes pointer to be null
/home/andy/dev/zig/doc/langref/runtime_invalid_null_pointer_cast.zig:4:23: 0x113e86a in main (runtime_invalid_null_pointer_cast.zig)
    const ptr: *i32 = @ptrCast(opt_ptr);
                      ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

