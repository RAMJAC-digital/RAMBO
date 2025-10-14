<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Arrays -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Arrays](zig-0.15.1.md#toc-Arrays) <a href="zig-0.15.1.md#Arrays" class="hdr">§</a>

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

- [for](zig-0.15.1.md#for)
- [Slices](zig-0.15.1.md#Slices)

### [Multidimensional Arrays](zig-0.15.1.md#toc-Multidimensional-Arrays) <a href="zig-0.15.1.md#Multidimensional-Arrays" class="hdr">§</a>

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

### [Sentinel-Terminated Arrays](zig-0.15.1.md#toc-Sentinel-Terminated-Arrays) <a href="zig-0.15.1.md#Sentinel-Terminated-Arrays" class="hdr">§</a>

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

- [Sentinel-Terminated Pointers](zig-0.15.1.md#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Slices](zig-0.15.1.md#Sentinel-Terminated-Slices)

### [Destructuring Arrays](zig-0.15.1.md#toc-Destructuring-Arrays) <a href="zig-0.15.1.md#Destructuring-Arrays" class="hdr">§</a>

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

- [Destructuring](zig-0.15.1.md#Destructuring)
- [Destructuring Tuples](zig-0.15.1.md#Destructuring-Tuples)
- [Destructuring Vectors](zig-0.15.1.md#Destructuring-Vectors)

