<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Slices -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Slices](zig-0.15.1.md#toc-Slices) <a href="zig-0.15.1.md#Slices" class="hdr">§</a>

A slice is a pointer and a length. The difference between an array and
a slice is that the array's length is part of the type and known at
compile-time, whereas the slice's length is known at runtime.
Both can be accessed with the `len` field.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const expectEqualSlices = @import(&quot;std&quot;).testing.expectEqualSlices;

test &quot;basic slices&quot; {
    var array = [_]i32{ 1, 2, 3, 4 };
    var known_at_runtime_zero: usize = 0;
    _ = &amp;known_at_runtime_zero;
    const slice = array[known_at_runtime_zero..array.len];

    // alternative initialization using result location
    const alt_slice: []const i32 = &amp;.{ 1, 2, 3, 4 };

    try expectEqualSlices(i32, slice, alt_slice);

    try expect(@TypeOf(slice) == []i32);
    try expect(&amp;slice[0] == &amp;array[0]);
    try expect(slice.len == array.len);

    // If you slice with comptime-known start and end positions, the result is
    // a pointer to an array, rather than a slice.
    const array_ptr = array[0..array.len];
    try expect(@TypeOf(array_ptr) == *[array.len]i32);

    // You can perform a slice-by-length by slicing twice. This allows the compiler
    // to perform some optimisations like recognising a comptime-known length when
    // the start position is only known at runtime.
    var runtime_start: usize = 1;
    _ = &amp;runtime_start;
    const length = 2;
    const array_ptr_len = array[runtime_start..][0..length];
    try expect(@TypeOf(array_ptr_len) == *[length]i32);

    // Using the address-of operator on a slice gives a single-item pointer.
    try expect(@TypeOf(&amp;slice[0]) == *i32);
    // Using the `ptr` field gives a many-item pointer.
    try expect(@TypeOf(slice.ptr) == [*]i32);
    try expect(@intFromPtr(slice.ptr) == @intFromPtr(&amp;slice[0]));

    // Slices have array bounds checking. If you try to access something out
    // of bounds, you&#39;ll get a safety check failure:
    slice[10] += 1;

    // Note that `slice.ptr` does not invoke safety checking, while `&amp;slice[0]`
    // asserts that the slice has len &gt; 0.

    // Empty slices can be created like this:
    const empty1 = &amp;[0]u8{};
    // If the type is known you can use this short hand:
    const empty2: []u8 = &amp;.{};
    try expect(empty1.len == 0);
    try expect(empty2.len == 0);

    // A zero-length initialization can always be used to create an empty slice, even if the slice is mutable.
    // This is because the pointed-to data is zero bits long, so its immutability is irrelevant.
}</code></pre>
<figcaption>test_basic_slices.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_basic_slices.zig
1/1 test_basic_slices.test.basic slices...thread 1100955 panic: index out of bounds: index 10, len 4
/home/andy/dev/zig/doc/langref/test_basic_slices.zig:41:10: 0x102e3c0 in test.basic slices (test_basic_slices.zig)
    slice[10] += 1;
         ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x1160b40 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1159d61 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x1153afd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x1153391 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/74bbaeeb0151197719152f62ae1ac340/test --seed=0xd51d6b2</code></pre>
<figcaption>Shell</figcaption>
</figure>

This is one reason we prefer slices to pointers.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;
const fmt = std.fmt;

test &quot;using slices for strings&quot; {
    // Zig has no concept of strings. String literals are const pointers
    // to null-terminated arrays of u8, and by convention parameters
    // that are &quot;strings&quot; are expected to be UTF-8 encoded slices of u8.
    // Here we coerce *const [5:0]u8 and *const [6:0]u8 to []const u8
    const hello: []const u8 = &quot;hello&quot;;
    const world: []const u8 = &quot;世界&quot;;

    var all_together: [100]u8 = undefined;
    // You can use slice syntax with at least one runtime-known index on an
    // array to convert an array into a slice.
    var start: usize = 0;
    _ = &amp;start;
    const all_together_slice = all_together[start..];
    // String concatenation example.
    const hello_world = try fmt.bufPrint(all_together_slice, &quot;{s} {s}&quot;, .{ hello, world });

    // Generally, you can use UTF-8 and not worry about whether something is a
    // string. If you don&#39;t need to deal with individual characters, no need
    // to decode.
    try expect(mem.eql(u8, hello_world, &quot;hello 世界&quot;));
}

test &quot;slice pointer&quot; {
    var array: [10]u8 = undefined;
    const ptr = &amp;array;
    try expect(@TypeOf(ptr) == *[10]u8);

    // A pointer to an array can be sliced just like an array:
    var start: usize = 0;
    var end: usize = 5;
    _ = .{ &amp;start, &amp;end };
    const slice = ptr[start..end];
    // The slice is mutable because we sliced a mutable pointer.
    try expect(@TypeOf(slice) == []u8);
    slice[2] = 3;
    try expect(array[2] == 3);

    // Again, slicing with comptime-known indexes will produce another pointer
    // to an array:
    const ptr2 = slice[2..3];
    try expect(ptr2.len == 1);
    try expect(ptr2[0] == 3);
    try expect(@TypeOf(ptr2) == *[1]u8);
}</code></pre>
<figcaption>test_slices.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_slices.zig
1/2 test_slices.test.using slices for strings...OK
2/2 test_slices.test.slice pointer...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Pointers](zig-0.15.1.md#Pointers)
- [for](zig-0.15.1.md#for)
- [Arrays](zig-0.15.1.md#Arrays)

### [Sentinel-Terminated Slices](zig-0.15.1.md#toc-Sentinel-Terminated-Slices) <a href="zig-0.15.1.md#Sentinel-Terminated-Slices" class="hdr">§</a>

The syntax `[:x]T` is a slice which has a runtime-known length
and also guarantees a sentinel value at the element indexed by the length. The type does not
guarantee that there are no sentinel elements before that. Sentinel-terminated slices allow element
access to the `len` index.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated slice&quot; {
    const slice: [:0]const u8 = &quot;hello&quot;;

    try expect(slice.len == 5);
    try expect(slice[5] == 0);
}</code></pre>
<figcaption>test_null_terminated_slice.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_slice.zig
1/1 test_null_terminated_slice.test.0-terminated slice...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Sentinel-terminated slices can also be created using a variation of the slice syntax
`data[start..end :x]`, where `data` is a many-item pointer,
array or slice and `x` is the sentinel value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated slicing&quot; {
    var array = [_]u8{ 3, 2, 1, 0, 3, 2, 1, 0 };
    var runtime_length: usize = 3;
    _ = &amp;runtime_length;
    const slice = array[0..runtime_length :0];

    try expect(@TypeOf(slice) == [:0]u8);
    try expect(slice.len == 3);
}</code></pre>
<figcaption>test_null_terminated_slicing.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_slicing.zig
1/1 test_null_terminated_slicing.test.0-terminated slicing...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Sentinel-terminated slicing asserts that the element in the sentinel position of the backing data is
actually the sentinel value. If this is not the case, safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior) results.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;sentinel mismatch&quot; {
    var array = [_]u8{ 3, 2, 1, 0 };

    // Creating a sentinel-terminated slice from the array with a length of 2
    // will result in the value `1` occupying the sentinel element position.
    // This does not match the indicated sentinel value of `0` and will lead
    // to a runtime panic.
    var runtime_length: usize = 2;
    _ = &amp;runtime_length;
    const slice = array[0..runtime_length :0];

    _ = slice;
}</code></pre>
<figcaption>test_sentinel_mismatch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_sentinel_mismatch.zig
1/1 test_sentinel_mismatch.test.sentinel mismatch...thread 1101275 panic: sentinel mismatch: expected 0, found 1
/home/andy/dev/zig/doc/langref/test_sentinel_mismatch.zig:13:24: 0x102c117 in test.sentinel mismatch (test_sentinel_mismatch.zig)
    const slice = array[0..runtime_length :0];
                       ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cc70 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155e91 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fc2d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f4c1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/f4ab327d42c7136f49bdc07a601ab333/test --seed=0xf332bd16</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Pointers](zig-0.15.1.md#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Arrays](zig-0.15.1.md#Sentinel-Terminated-Arrays)

