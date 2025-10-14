<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Pointers -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Pointers](zig-0.15.1.md#toc-Pointers) <a href="zig-0.15.1.md#Pointers" class="hdr">§</a>

Zig has two kinds of pointers: single-item and many-item.

- `*T` - single-item pointer to exactly one item.
  - Supports deref syntax: `ptr.*`
  - Supports slice syntax: `ptr[`<span class="tok-number">`0`</span>`..`<span class="tok-number">`1`</span>`]`
  - Supports pointer subtraction: `ptr - ptr`
- `[*]T` - many-item pointer to unknown number of items.
  - Supports index syntax: `ptr[i]`
  - Supports slice syntax: `ptr[start..end]` and `ptr[start..]`
  - Supports pointer-integer arithmetic: `ptr + int`, `ptr - int`
  - Supports pointer subtraction: `ptr - ptr`

  `T` must have a known size, which means that it cannot be
  <span class="tok-type">`anyopaque`</span> or any other [opaque type](zig-0.15.1.md#opaque).

These types are closely related to [Arrays](zig-0.15.1.md#Arrays) and [Slices](zig-0.15.1.md#Slices):

- `*[N]T` - pointer to N items, same as single-item pointer to an array.
  - Supports index syntax: `array_ptr[i]`
  - Supports slice syntax: `array_ptr[start..end]`
  - Supports len property: `array_ptr.len`
  - Supports pointer subtraction: `array_ptr - array_ptr`

<!-- -->

- `[]T` - is a slice (a fat pointer, which contains a pointer of type `[*]T` and a length).
  - Supports index syntax: `slice[i]`
  - Supports slice syntax: `slice[start..end]`
  - Supports len property: `slice.len`

Use `&x` to obtain a single-item pointer:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;address of syntax&quot; {
    // Get the address of a variable:
    const x: i32 = 1234;
    const x_ptr = &amp;x;

    // Dereference a pointer:
    try expect(x_ptr.* == 1234);

    // When you get the address of a const variable, you get a const single-item pointer.
    try expect(@TypeOf(x_ptr) == *const i32);

    // If you want to mutate the value, you&#39;d need an address of a mutable variable:
    var y: i32 = 5678;
    const y_ptr = &amp;y;
    try expect(@TypeOf(y_ptr) == *i32);
    y_ptr.* += 1;
    try expect(y_ptr.* == 5679);
}

test &quot;pointer array access&quot; {
    // Taking an address of an individual element gives a
    // single-item pointer. This kind of pointer
    // does not support pointer arithmetic.
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const ptr = &amp;array[2];
    try expect(@TypeOf(ptr) == *u8);

    try expect(array[2] == 3);
    ptr.* += 1;
    try expect(array[2] == 4);
}

test &quot;slice syntax&quot; {
    // Get a pointer to a variable:
    var x: i32 = 1234;
    const x_ptr = &amp;x;

    // Convert to array pointer using slice syntax:
    const x_array_ptr = x_ptr[0..1];
    try expect(@TypeOf(x_array_ptr) == *[1]i32);

    // Coerce to many-item pointer:
    const x_many_ptr: [*]i32 = x_array_ptr;
    try expect(x_many_ptr[0] == 1234);
}</code></pre>
<figcaption>test_single_item_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_single_item_pointer.zig
1/3 test_single_item_pointer.test.address of syntax...OK
2/3 test_single_item_pointer.test.pointer array access...OK
3/3 test_single_item_pointer.test.slice syntax...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig supports pointer arithmetic. It's better to assign the pointer to `[*]T` and increment that variable. For example, directly incrementing the pointer from a slice will corrupt it.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pointer arithmetic with many-item pointer&quot; {
    const array = [_]i32{ 1, 2, 3, 4 };
    var ptr: [*]const i32 = &amp;array;

    try expect(ptr[0] == 1);
    ptr += 1;
    try expect(ptr[0] == 2);

    // slicing a many-item pointer without an end is equivalent to
    // pointer arithmetic: `ptr[start..] == ptr + start`
    try expect(ptr[1..] == ptr + 1);

    // subtraction between any two pointers except slices based on element size is supported
    try expect(&amp;ptr[1] - &amp;ptr[0] == 1);
}

test &quot;pointer arithmetic with slices&quot; {
    var array = [_]i32{ 1, 2, 3, 4 };
    var length: usize = 0; // var to make it runtime-known
    _ = &amp;length; // suppress &#39;var is never mutated&#39; error
    var slice = array[length..array.len];

    try expect(slice[0] == 1);
    try expect(slice.len == 4);

    slice.ptr += 1;
    // now the slice is in an bad state since len has not been updated

    try expect(slice[0] == 2);
    try expect(slice.len == 4);
}</code></pre>
<figcaption>test_pointer_arithmetic.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_arithmetic.zig
1/2 test_pointer_arithmetic.test.pointer arithmetic with many-item pointer...OK
2/2 test_pointer_arithmetic.test.pointer arithmetic with slices...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In Zig, we generally prefer [Slices](zig-0.15.1.md#Slices) rather than [Sentinel-Terminated Pointers](zig-0.15.1.md#Sentinel-Terminated-Pointers).
You can turn an array or pointer into a slice using slice syntax.

Slices have bounds checking and are therefore protected
against this kind of Illegal Behavior. This is one reason
we prefer slices to pointers.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pointer slicing&quot; {
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var start: usize = 2; // var to make it runtime-known
    _ = &amp;start; // suppress &#39;var is never mutated&#39; error
    const slice = array[start..4];
    try expect(slice.len == 2);

    try expect(array[3] == 4);
    slice[1] += 1;
    try expect(array[3] == 5);
}</code></pre>
<figcaption>test_slice_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_slice_bounds.zig
1/1 test_slice_bounds.test.pointer slicing...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Pointers work at compile-time too, as long as the code does not depend on
an undefined memory layout:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;comptime pointers&quot; {
    comptime {
        var x: i32 = 1;
        const ptr = &amp;x;
        ptr.* += 1;
        x += 1;
        try expect(ptr.* == 3);
    }
}</code></pre>
<figcaption>test_comptime_pointers.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_pointers.zig
1/1 test_comptime_pointers.test.comptime pointers...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

To convert an integer address into a pointer, use <span class="tok-builtin">`@ptrFromInt`</span>.
To convert a pointer to an integer, use <span class="tok-builtin">`@intFromPtr`</span>:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;@intFromPtr and @ptrFromInt&quot; {
    const ptr: *i32 = @ptrFromInt(0xdeadbee0);
    const addr = @intFromPtr(ptr);
    try expect(@TypeOf(addr) == usize);
    try expect(addr == 0xdeadbee0);
}</code></pre>
<figcaption>test_integer_pointer_conversion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_integer_pointer_conversion.zig
1/1 test_integer_pointer_conversion.test.@intFromPtr and @ptrFromInt...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig is able to preserve memory addresses in comptime code, as long as
the pointer is never dereferenced:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;comptime @ptrFromInt&quot; {
    comptime {
        // Zig is able to do this at compile-time, as long as
        // ptr is never dereferenced.
        const ptr: *i32 = @ptrFromInt(0xdeadbee0);
        const addr = @intFromPtr(ptr);
        try expect(@TypeOf(addr) == usize);
        try expect(addr == 0xdeadbee0);
    }
}</code></pre>
<figcaption>test_comptime_pointer_conversion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_pointer_conversion.zig
1/1 test_comptime_pointer_conversion.test.comptime @ptrFromInt...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

[@ptrCast](zig-0.15.1.md#ptrCast) converts a pointer's element type to another. This
creates a new pointer that can cause undetectable Illegal Behavior
depending on the loads and stores that pass through it. Generally, other
kinds of type conversions are preferable to
<span class="tok-builtin">`@ptrCast`</span> if possible.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;pointer casting&quot; {
    const bytes align(@alignOf(u32)) = [_]u8{ 0x12, 0x12, 0x12, 0x12 };
    const u32_ptr: *const u32 = @ptrCast(&amp;bytes);
    try expect(u32_ptr.* == 0x12121212);

    // Even this example is contrived - there are better ways to do the above than
    // pointer casting. For example, using a slice narrowing cast:
    const u32_value = std.mem.bytesAsSlice(u32, bytes[0..])[0];
    try expect(u32_value == 0x12121212);

    // And even another way, the most straightforward way to do it:
    try expect(@as(u32, @bitCast(bytes)) == 0x12121212);
}

test &quot;pointer child type&quot; {
    // pointer types have a `child` field which tells you the type they point to.
    try expect(@typeInfo(*u32).pointer.child == u32);
}</code></pre>
<figcaption>test_pointer_casting.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_casting.zig
1/2 test_pointer_casting.test.pointer casting...OK
2/2 test_pointer_casting.test.pointer child type...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optional Pointers](zig-0.15.1.md#Optional-Pointers)
- [@ptrFromInt](zig-0.15.1.md#ptrFromInt)
- [@intFromPtr](zig-0.15.1.md#intFromPtr)
- [C Pointers](zig-0.15.1.md#C-Pointers)

### [volatile](zig-0.15.1.md#toc-volatile) <a href="zig-0.15.1.md#volatile" class="hdr">§</a>

Loads and stores are assumed to not have side effects. If a given load or store
should have side effects, such as Memory Mapped Input/Output (MMIO), use <span class="tok-kw">`volatile`</span>.
In the following code, loads and stores with `mmio_ptr` are guaranteed to all happen
and in the same order as in source code:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;volatile&quot; {
    const mmio_ptr: *volatile u8 = @ptrFromInt(0x12345678);
    try expect(@TypeOf(mmio_ptr) == *volatile u8);
}</code></pre>
<figcaption>test_volatile.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_volatile.zig
1/1 test_volatile.test.volatile...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note that <span class="tok-kw">`volatile`</span> is unrelated to concurrency and [Atomics](zig-0.15.1.md#Atomics).
If you see code that is using <span class="tok-kw">`volatile`</span> for something other than Memory Mapped
Input/Output, it is probably a bug.

### [Alignment](zig-0.15.1.md#toc-Alignment) <a href="zig-0.15.1.md#Alignment" class="hdr">§</a>

Each type has an **alignment** - a number of bytes such that,
when a value of the type is loaded from or stored to memory,
the memory address must be evenly divisible by this number. You can use
[@alignOf](zig-0.15.1.md#alignOf) to find out this value for any type.

Alignment depends on the CPU architecture, but is always a power of two, and
less than <span class="tok-number">`1`</span>` << `<span class="tok-number">`29`</span>.

In Zig, a pointer type has an alignment value. If the value is equal to the
alignment of the underlying type, it can be omitted from the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;

test &quot;variable alignment&quot; {
    var x: i32 = 1234;
    const align_of_i32 = @alignOf(@TypeOf(x));
    try expect(@TypeOf(&amp;x) == *i32);
    try expect(*i32 == *align(align_of_i32) i32);
    if (builtin.target.cpu.arch == .x86_64) {
        try expect(@typeInfo(*i32).pointer.alignment == 4);
    }
}</code></pre>
<figcaption>test_variable_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_variable_alignment.zig
1/1 test_variable_alignment.test.variable alignment...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In the same way that a `*`<span class="tok-type">`i32`</span> can be [coerced](zig-0.15.1.md#Type-Coercion) to a
`*`<span class="tok-kw">`const`</span>` `<span class="tok-type">`i32`</span>, a pointer with a larger alignment can be implicitly
cast to a pointer with a smaller alignment, but not vice versa.

You can specify alignment on variables and functions. If you do this, then
pointers to them get the specified alignment:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

var foo: u8 align(4) = 100;

test &quot;global variable alignment&quot; {
    try expect(@typeInfo(@TypeOf(&amp;foo)).pointer.alignment == 4);
    try expect(@TypeOf(&amp;foo) == *align(4) u8);
    const as_pointer_to_array: *align(4) [1]u8 = &amp;foo;
    const as_slice: []align(4) u8 = as_pointer_to_array;
    const as_unaligned_slice: []u8 = as_slice;
    try expect(as_unaligned_slice[0] == 100);
}

fn derp() align(@sizeOf(usize) * 2) i32 {
    return 1234;
}
fn noop1() align(1) void {}
fn noop4() align(4) void {}

test &quot;function alignment&quot; {
    try expect(derp() == 1234);
    try expect(@TypeOf(derp) == fn () i32);
    try expect(@TypeOf(&amp;derp) == *align(@sizeOf(usize) * 2) const fn () i32);

    noop1();
    try expect(@TypeOf(noop1) == fn () void);
    try expect(@TypeOf(&amp;noop1) == *align(1) const fn () void);

    noop4();
    try expect(@TypeOf(noop4) == fn () void);
    try expect(@TypeOf(&amp;noop4) == *align(4) const fn () void);
}</code></pre>
<figcaption>test_variable_func_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_variable_func_alignment.zig
1/2 test_variable_func_alignment.test.global variable alignment...OK
2/2 test_variable_func_alignment.test.function alignment...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

If you have a pointer or a slice that has a small alignment, but you know that it actually
has a bigger alignment, use [@alignCast](zig-0.15.1.md#alignCast) to change the
pointer into a more aligned pointer. This is a no-op at runtime, but inserts a
[safety check](zig-0.15.1.md#Incorrect-Pointer-Alignment):

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;pointer alignment safety&quot; {
    var array align(4) = [_]u32{ 0x11111111, 0x11111111 };
    const bytes = std.mem.sliceAsBytes(array[0..]);
    try std.testing.expect(foo(bytes) == 0x11111111);
}
fn foo(bytes: []u8) u32 {
    const slice4 = bytes[1..5];
    const int_slice = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
    return int_slice[0];
}</code></pre>
<figcaption>test_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_incorrect_pointer_alignment.zig
1/1 test_incorrect_pointer_alignment.test.pointer alignment safety...thread 1098703 panic: incorrect alignment
/home/andy/dev/zig/doc/langref/test_incorrect_pointer_alignment.zig:10:68: 0x102c2a8 in foo (test_incorrect_pointer_alignment.zig)
    const int_slice = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                                   ^
/home/andy/dev/zig/doc/langref/test_incorrect_pointer_alignment.zig:6:31: 0x102c0d2 in test.pointer alignment safety (test_incorrect_pointer_alignment.zig)
    try std.testing.expect(foo(bytes) == 0x11111111);
                              ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cf10 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1156131 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fecd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f761 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/0b2d2bfc37e3220ff3dbb549fa094812/test --seed=0xcf0b8a3a</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [allowzero](zig-0.15.1.md#toc-allowzero) <a href="zig-0.15.1.md#allowzero" class="hdr">§</a>

This pointer attribute allows a pointer to have address zero. This is only ever needed on the
freestanding OS target, where the address zero is mappable. If you want to represent null pointers, use
[Optional Pointers](zig-0.15.1.md#Optional-Pointers) instead. [Optional Pointers](zig-0.15.1.md#Optional-Pointers) with <span class="tok-kw">`allowzero`</span>
are not the same size as pointers. In this code example, if the pointer
did not have the <span class="tok-kw">`allowzero`</span> attribute, this would be a
[Pointer Cast Invalid Null](zig-0.15.1.md#Pointer-Cast-Invalid-Null) panic:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;allowzero&quot; {
    var zero: usize = 0; // var to make to runtime-known
    _ = &amp;zero; // suppress &#39;var is never mutated&#39; error
    const ptr: *allowzero i32 = @ptrFromInt(zero);
    try expect(@intFromPtr(ptr) == 0);
}</code></pre>
<figcaption>test_allowzero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_allowzero.zig
1/1 test_allowzero.test.allowzero...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Sentinel-Terminated Pointers](zig-0.15.1.md#toc-Sentinel-Terminated-Pointers) <a href="zig-0.15.1.md#Sentinel-Terminated-Pointers" class="hdr">§</a>

The syntax `[*:x]T` describes a pointer that
has a length determined by a sentinel value. This provides protection
against buffer overflow and overreads.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

// This is also available as `std.c.printf`.
pub extern &quot;c&quot; fn printf(format: [*:0]const u8, ...) c_int;

pub fn main() anyerror!void {
    _ = printf(&quot;Hello, world!\n&quot;); // OK

    const msg = &quot;Hello, world!\n&quot;;
    const non_null_terminated_msg: [msg.len]u8 = msg.*;
    _ = printf(&amp;non_null_terminated_msg);
}</code></pre>
<figcaption>sentinel-terminated_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe sentinel-terminated_pointer.zig -lc
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:11:16: error: expected type &#39;[*:0]const u8&#39;, found &#39;*const [14]u8&#39;
    _ = printf(&amp;non_null_terminated_msg);
               ^~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:11:16: note: destination pointer requires &#39;0&#39; sentinel
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:4:34: note: parameter type declared here
pub extern &quot;c&quot; fn printf(format: [*:0]const u8, ...) c_int;
                                 ^~~~~~~~~~~~~
referenced by:
    callMain [inlined]: /home/andy/dev/zig/lib/std/start.zig:627:37
    callMainWithArgs [inlined]: /home/andy/dev/zig/lib/std/start.zig:587:20
    main: /home/andy/dev/zig/lib/std/start.zig:602:28
    1 reference(s) hidden; use &#39;-freference-trace=4&#39; to see all references
</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Slices](zig-0.15.1.md#Sentinel-Terminated-Slices)
- [Sentinel-Terminated Arrays](zig-0.15.1.md#Sentinel-Terminated-Arrays)

