<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Arrays, Pointers & Slices

Included sections:
- Arrays
- Vectors
- Pointers
- Slices

## [Arrays](../zig-0.15.1.md#toc-Arrays) <a href="../zig-0.15.1.md#Arrays" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const assert = @import(&quot;std&quot;).debug.assert;
const mem = @import(&quot;std&quot;).mem;

// array literal
const message = [_]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, &#39;o&#39; };

// alternative initialization using result location
const alt_message: [5]u8 = .{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, &#39;o&#39; };

comptime {
    assert(mem.eql(u8, &amp;message, &amp;alt_message));
}

// get the size of an array
comptime {
    assert(message.len == 5);
}

// A string literal is a single-item pointer to an array.
const same_message = &quot;hello&quot;;

comptime {
    assert(mem.eql(u8, &amp;message, same_message));
}

test &quot;iterate over an array&quot; {
    var sum: usize = 0;
    for (message) |byte| {
        sum += byte;
    }
    try expect(sum == &#39;h&#39; + &#39;e&#39; + &#39;l&#39; * 2 + &#39;o&#39;);
}

// modifiable array
var some_integers: [100]i32 = undefined;

test &quot;modify an array&quot; {
    for (&amp;some_integers, 0..) |*item, i| {
        item.* = @intCast(i);
    }
    try expect(some_integers[10] == 10);
    try expect(some_integers[99] == 99);
}

// array concatenation works if the values are known
// at compile time
const part_one = [_]i32{ 1, 2, 3, 4 };
const part_two = [_]i32{ 5, 6, 7, 8 };
const all_of_it = part_one ++ part_two;
comptime {
    assert(mem.eql(i32, &amp;all_of_it, &amp;[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 }));
}

// remember that string literals are arrays
const hello = &quot;hello&quot;;
const world = &quot;world&quot;;
const hello_world = hello ++ &quot; &quot; ++ world;
comptime {
    assert(mem.eql(u8, hello_world, &quot;hello world&quot;));
}

// ** does repeating patterns
const pattern = &quot;ab&quot; ** 3;
comptime {
    assert(mem.eql(u8, pattern, &quot;ababab&quot;));
}

// initialize an array to zero
const all_zero = [_]u16{0} ** 10;

comptime {
    assert(all_zero.len == 10);
    assert(all_zero[5] == 0);
}

// use compile-time code to initialize an array
var fancy_array = init: {
    var initial_value: [10]Point = undefined;
    for (&amp;initial_value, 0..) |*pt, i| {
        pt.* = Point{
            .x = @intCast(i),
            .y = @intCast(i * 2),
        };
    }
    break :init initial_value;
};
const Point = struct {
    x: i32,
    y: i32,
};

test &quot;compile-time array initialization&quot; {
    try expect(fancy_array[4].x == 4);
    try expect(fancy_array[4].y == 8);
}

// call a function to initialize an array
var more_points = [_]Point{makePoint(3)} ** 10;
fn makePoint(x: i32) Point {
    return Point{
        .x = x,
        .y = x * 2,
    };
}
test &quot;array initialization with function calls&quot; {
    try expect(more_points[4].x == 3);
    try expect(more_points[4].y == 6);
    try expect(more_points.len == 10);
}</code></pre>
<figcaption>test_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_arrays.zig
1/4 test_arrays.test.iterate over an array...OK
2/4 test_arrays.test.modify an array...OK
3/4 test_arrays.test.compile-time array initialization...OK
4/4 test_arrays.test.array initialization with function calls...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [for](../zig-0.15.1.md#for)
- [Slices](../zig-0.15.1.md#Slices)

### [Multidimensional Arrays](../zig-0.15.1.md#toc-Multidimensional-Arrays) <a href="../zig-0.15.1.md#Multidimensional-Arrays" class="hdr">§</a>

Multidimensional arrays can be created by nesting arrays:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const mat4x5 = [4][5]f32{
    [_]f32{ 1.0, 0.0, 0.0, 0.0, 0.0 },
    [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 },
    [_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0 },
    [_]f32{ 0.0, 0.0, 0.0, 1.0, 9.9 },
};
test &quot;multidimensional arrays&quot; {
    // mat4x5 itself is a one-dimensional array of arrays.
    try expectEqual(mat4x5[1], [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 });

    // Access the 2D array by indexing the outer array, and then the inner array.
    try expect(mat4x5[3][4] == 9.9);

    // Here we iterate with for loops.
    for (mat4x5, 0..) |row, row_index| {
        for (row, 0..) |cell, column_index| {
            if (row_index == column_index) {
                try expect(cell == 1.0);
            }
        }
    }

    // Initialize a multidimensional array to zeros.
    const all_zero: [4][5]f32 = .{.{0} ** 5} ** 4;
    try expect(all_zero[0][0] == 0);
}</code></pre>
<figcaption>test_multidimensional_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_multidimensional_arrays.zig
1/1 test_multidimensional_arrays.test.multidimensional arrays...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Sentinel-Terminated Arrays](../zig-0.15.1.md#toc-Sentinel-Terminated-Arrays) <a href="../zig-0.15.1.md#Sentinel-Terminated-Arrays" class="hdr">§</a>

The syntax `[N:x]T` describes an array which has a sentinel element of value `x` at the
index corresponding to the length `N`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated sentinel array&quot; {
    const array = [_:0]u8{ 1, 2, 3, 4 };

    try expect(@TypeOf(array) == [4:0]u8);
    try expect(array.len == 4);
    try expect(array[4] == 0);
}

test &quot;extra 0s in 0-terminated sentinel array&quot; {
    // The sentinel value may appear earlier, but does not influence the compile-time &#39;len&#39;.
    const array = [_:0]u8{ 1, 0, 0, 4 };

    try expect(@TypeOf(array) == [4:0]u8);
    try expect(array.len == 4);
    try expect(array[4] == 0);
}</code></pre>
<figcaption>test_null_terminated_array.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_array.zig
1/2 test_null_terminated_array.test.0-terminated sentinel array...OK
2/2 test_null_terminated_array.test.extra 0s in 0-terminated sentinel array...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Pointers](../zig-0.15.1.md#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Slices](../zig-0.15.1.md#Sentinel-Terminated-Slices)

### [Destructuring Arrays](../zig-0.15.1.md#toc-Destructuring-Arrays) <a href="../zig-0.15.1.md#Destructuring-Arrays" class="hdr">§</a>

Arrays can be destructured:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

fn swizzleRgbaToBgra(rgba: [4]u8) [4]u8 {
    // readable swizzling by destructuring
    const r, const g, const b, const a = rgba;
    return .{ b, g, r, a };
}

pub fn main() void {
    const pos = [_]i32{ 1, 2 };
    const x, const y = pos;
    print(&quot;x = {}, y = {}\n&quot;, .{x, y});

    const orange: [4]u8 = .{ 255, 165, 0, 255 };
    print(&quot;{any}\n&quot;, .{swizzleRgbaToBgra(orange)});
}</code></pre>
<figcaption>destructuring_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_arrays.zig
$ ./destructuring_arrays
x = 1, y = 2
{ 0, 165, 255, 255 }</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](../zig-0.15.1.md#Destructuring)
- [Destructuring Tuples](../zig-0.15.1.md#Destructuring-Tuples)
- [Destructuring Vectors](../zig-0.15.1.md#Destructuring-Vectors)

## [Vectors](../zig-0.15.1.md#toc-Vectors) <a href="../zig-0.15.1.md#Vectors" class="hdr">§</a>

A vector is a group of booleans, [Integers](../zig-0.15.1.md#Integers), [Floats](../zig-0.15.1.md#Floats), or
[Pointers](../zig-0.15.1.md#Pointers) which are operated on in parallel, using SIMD instructions if possible.
Vector types are created with the builtin function [@Vector](../zig-0.15.1.md#Vector).

Vectors generally support the same builtin operators as their underlying base types.
The only exception to this is the keywords \`and\` and \`or\` on vectors of bools, since
these operators affect control flow, which is not allowed for vectors.
All other operations are performed element-wise, and return a vector of the same length
as the input vectors. This includes:

- Arithmetic (`+`, `-`, `/`, `*`,
  <span class="tok-builtin">`@divFloor`</span>, <span class="tok-builtin">`@sqrt`</span>, <span class="tok-builtin">`@ceil`</span>,
  <span class="tok-builtin">`@log`</span>, etc.)
- Bitwise operators (`>>`, `<<`, `&`,
  `|`, `~`, etc.)
- Comparison operators (`<`, `>`, `==`, etc.)
- Boolean not (`!`)

It is prohibited to use a math operator on a mixture of scalars (individual numbers)
and vectors. Zig provides the [@splat](../zig-0.15.1.md#splat) builtin to easily convert from scalars
to vectors, and it supports [@reduce](../zig-0.15.1.md#reduce) and array indexing syntax to convert
from vectors to scalars. Vectors also support assignment to and from fixed-length
arrays with comptime-known length.

For rearranging elements within and between vectors, Zig provides the [@shuffle](../zig-0.15.1.md#shuffle) and [@select](../zig-0.15.1.md#select) functions.

Operations on vectors shorter than the target machine's native SIMD size will typically compile to single SIMD
instructions, while vectors longer than the target machine's native SIMD size will compile to multiple SIMD
instructions. If a given operation doesn't have SIMD support on the target architecture, the compiler will default
to operating on each vector element one at a time. Zig supports any comptime-known vector length up to 2^32-1,
although small powers of two (2-64) are most typical. Note that excessively long vector lengths (e.g. 2^20) may
result in compiler crashes on current versions of Zig.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

test &quot;Basic vector usage&quot; {
    // Vectors have a compile-time known length and base type.
    const a = @Vector(4, i32){ 1, 2, 3, 4 };
    const b = @Vector(4, i32){ 5, 6, 7, 8 };

    // Math operations take place element-wise.
    const c = a + b;

    // Individual vector elements can be accessed using array indexing syntax.
    try expectEqual(6, c[0]);
    try expectEqual(8, c[1]);
    try expectEqual(10, c[2]);
    try expectEqual(12, c[3]);
}

test &quot;Conversion between vectors, arrays, and slices&quot; {
    // Vectors and fixed-length arrays can be automatically assigned back and forth
    const arr1: [4]f32 = [_]f32{ 1.1, 3.2, 4.5, 5.6 };
    const vec: @Vector(4, f32) = arr1;
    const arr2: [4]f32 = vec;
    try expectEqual(arr1, arr2);

    // You can also assign from a slice with comptime-known length to a vector using .*
    const vec2: @Vector(2, f32) = arr1[1..3].*;

    const slice: []const f32 = &amp;arr1;
    var offset: u32 = 1; // var to make it runtime-known
    _ = &amp;offset; // suppress &#39;var is never mutated&#39; error
    // To extract a comptime-known length from a runtime-known offset,
    // first extract a new slice from the starting offset, then an array of
    // comptime-known length
    const vec3: @Vector(2, f32) = slice[offset..][0..2].*;
    try expectEqual(slice[offset], vec2[0]);
    try expectEqual(slice[offset + 1], vec2[1]);
    try expectEqual(vec2, vec3);
}</code></pre>
<figcaption>test_vector.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_vector.zig
1/2 test_vector.test.Basic vector usage...OK
2/2 test_vector.test.Conversion between vectors, arrays, and slices...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

TODO talk about C ABI interop  
TODO consider suggesting std.MultiArrayList

See also:

- [@splat](../zig-0.15.1.md#splat)
- [@shuffle](../zig-0.15.1.md#shuffle)
- [@select](../zig-0.15.1.md#select)
- [@reduce](../zig-0.15.1.md#reduce)

### [Destructuring Vectors](../zig-0.15.1.md#toc-Destructuring-Vectors) <a href="../zig-0.15.1.md#Destructuring-Vectors" class="hdr">§</a>

Vectors can be destructured:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

// emulate punpckldq
pub fn unpack(x: @Vector(4, f32), y: @Vector(4, f32)) @Vector(4, f32) {
    const a, const c, _, _ = x;
    const b, const d, _, _ = y;
    return .{ a, b, c, d };
}

pub fn main() void {
    const x: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
    const y: @Vector(4, f32) = .{ 5.0, 6.0, 7.0, 8.0 };
    print(&quot;{}&quot;, .{unpack(x, y)});
}</code></pre>
<figcaption>destructuring_vectors.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_vectors.zig
$ ./destructuring_vectors
{ 1, 5, 2, 6 }</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](../zig-0.15.1.md#Destructuring)
- [Destructuring Tuples](../zig-0.15.1.md#Destructuring-Tuples)
- [Destructuring Arrays](../zig-0.15.1.md#Destructuring-Arrays)

## [Pointers](../zig-0.15.1.md#toc-Pointers) <a href="../zig-0.15.1.md#Pointers" class="hdr">§</a>

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
  <span class="tok-type">`anyopaque`</span> or any other [opaque type](../zig-0.15.1.md#opaque).

These types are closely related to [Arrays](../zig-0.15.1.md#Arrays) and [Slices](../zig-0.15.1.md#Slices):

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

In Zig, we generally prefer [Slices](../zig-0.15.1.md#Slices) rather than [Sentinel-Terminated Pointers](../zig-0.15.1.md#Sentinel-Terminated-Pointers).
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

[@ptrCast](../zig-0.15.1.md#ptrCast) converts a pointer's element type to another. This
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

- [Optional Pointers](../zig-0.15.1.md#Optional-Pointers)
- [@ptrFromInt](../zig-0.15.1.md#ptrFromInt)
- [@intFromPtr](../zig-0.15.1.md#intFromPtr)
- [C Pointers](../zig-0.15.1.md#C-Pointers)

### [volatile](../zig-0.15.1.md#toc-volatile) <a href="../zig-0.15.1.md#volatile" class="hdr">§</a>

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

Note that <span class="tok-kw">`volatile`</span> is unrelated to concurrency and [Atomics](../zig-0.15.1.md#Atomics).
If you see code that is using <span class="tok-kw">`volatile`</span> for something other than Memory Mapped
Input/Output, it is probably a bug.

### [Alignment](../zig-0.15.1.md#toc-Alignment) <a href="../zig-0.15.1.md#Alignment" class="hdr">§</a>

Each type has an **alignment** - a number of bytes such that,
when a value of the type is loaded from or stored to memory,
the memory address must be evenly divisible by this number. You can use
[@alignOf](../zig-0.15.1.md#alignOf) to find out this value for any type.

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

In the same way that a `*`<span class="tok-type">`i32`</span> can be [coerced](../zig-0.15.1.md#Type-Coercion) to a
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
has a bigger alignment, use [@alignCast](../zig-0.15.1.md#alignCast) to change the
pointer into a more aligned pointer. This is a no-op at runtime, but inserts a
[safety check](../zig-0.15.1.md#Incorrect-Pointer-Alignment):

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

### [allowzero](../zig-0.15.1.md#toc-allowzero) <a href="../zig-0.15.1.md#allowzero" class="hdr">§</a>

This pointer attribute allows a pointer to have address zero. This is only ever needed on the
freestanding OS target, where the address zero is mappable. If you want to represent null pointers, use
[Optional Pointers](../zig-0.15.1.md#Optional-Pointers) instead. [Optional Pointers](../zig-0.15.1.md#Optional-Pointers) with <span class="tok-kw">`allowzero`</span>
are not the same size as pointers. In this code example, if the pointer
did not have the <span class="tok-kw">`allowzero`</span> attribute, this would be a
[Pointer Cast Invalid Null](../zig-0.15.1.md#Pointer-Cast-Invalid-Null) panic:

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

### [Sentinel-Terminated Pointers](../zig-0.15.1.md#toc-Sentinel-Terminated-Pointers) <a href="../zig-0.15.1.md#Sentinel-Terminated-Pointers" class="hdr">§</a>

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

- [Sentinel-Terminated Slices](../zig-0.15.1.md#Sentinel-Terminated-Slices)
- [Sentinel-Terminated Arrays](../zig-0.15.1.md#Sentinel-Terminated-Arrays)

## [Slices](../zig-0.15.1.md#toc-Slices) <a href="../zig-0.15.1.md#Slices" class="hdr">§</a>

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

- [Pointers](../zig-0.15.1.md#Pointers)
- [for](../zig-0.15.1.md#for)
- [Arrays](../zig-0.15.1.md#Arrays)

### [Sentinel-Terminated Slices](../zig-0.15.1.md#toc-Sentinel-Terminated-Slices) <a href="../zig-0.15.1.md#Sentinel-Terminated-Slices" class="hdr">§</a>

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
actually the sentinel value. If this is not the case, safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) results.

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

- [Sentinel-Terminated Pointers](../zig-0.15.1.md#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Arrays](../zig-0.15.1.md#Sentinel-Terminated-Arrays)


