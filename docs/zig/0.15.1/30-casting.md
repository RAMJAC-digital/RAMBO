<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Casting -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Casting](zig-0.15.1.md#toc-Casting) <a href="zig-0.15.1.md#Casting" class="hdr">§</a>

A **type cast** converts a value of one type to another.
Zig has [Type Coercion](zig-0.15.1.md#Type-Coercion) for conversions that are known to be completely safe and unambiguous,
and [Explicit Casts](zig-0.15.1.md#Explicit-Casts) for conversions that one would not want to happen on accident.
There is also a third kind of type conversion called [Peer Type Resolution](zig-0.15.1.md#Peer-Type-Resolution) for
the case when a result type must be decided given multiple operand types.

### [Type Coercion](zig-0.15.1.md#toc-Type-Coercion) <a href="zig-0.15.1.md#Type-Coercion" class="hdr">§</a>

Type coercion occurs when one type is expected, but different type is provided:

<figure>
<pre><code>test &quot;type coercion - variable declaration&quot; {
    const a: u8 = 1;
    const b: u16 = a;
    _ = b;
}

test &quot;type coercion - function call&quot; {
    const a: u8 = 1;
    foo(a);
}

fn foo(b: u16) void {
    _ = b;
}

test &quot;type coercion - @as builtin&quot; {
    const a: u8 = 1;
    const b = @as(u16, a);
    _ = b;
}</code></pre>
<figcaption>test_type_coercion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_type_coercion.zig
1/3 test_type_coercion.test.type coercion - variable declaration...OK
2/3 test_type_coercion.test.type coercion - function call...OK
3/3 test_type_coercion.test.type coercion - @as builtin...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Type coercions are only allowed when it is completely unambiguous how to get from one type to another,
and the transformation is guaranteed to be safe. There is one exception, which is [C Pointers](zig-0.15.1.md#C-Pointers).

#### [Type Coercion: Stricter Qualification](zig-0.15.1.md#toc-Type-Coercion-Stricter-Qualification) <a href="zig-0.15.1.md#Type-Coercion-Stricter-Qualification" class="hdr">§</a>

Values which have the same representation at runtime can be cast to increase the strictness
of the qualifiers, no matter how nested the qualifiers are:

- <span class="tok-kw">`const`</span> - non-const to const is allowed
- <span class="tok-kw">`volatile`</span> - non-volatile to volatile is allowed
- <span class="tok-kw">`align`</span> - bigger to smaller alignment is allowed
- [error sets](zig-0.15.1.md#Error-Set-Type) to supersets is allowed

These casts are no-ops at runtime since the value representation does not change.

<figure>
<pre><code>test &quot;type coercion - const qualification&quot; {
    var a: i32 = 1;
    const b: *i32 = &amp;a;
    foo(b);
}

fn foo(_: *const i32) void {}</code></pre>
<figcaption>test_no_op_casts.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_no_op_casts.zig
1/1 test_no_op_casts.test.type coercion - const qualification...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In addition, pointers coerce to const optional pointers:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;cast *[1][*:0]const u8 to []const ?[*:0]const u8&quot; {
    const window_name = [1][*:0]const u8{&quot;window name&quot;};
    const x: []const ?[*:0]const u8 = &amp;window_name;
    try expect(mem.eql(u8, mem.span(x[0].?), &quot;window name&quot;));
}</code></pre>
<figcaption>test_pointer_coerce_const_optional.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_coerce_const_optional.zig
1/1 test_pointer_coerce_const_optional.test.cast *[1][*:0]const u8 to []const ?[*:0]const u8...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Integer and Float Widening](zig-0.15.1.md#toc-Type-Coercion-Integer-and-Float-Widening) <a href="zig-0.15.1.md#Type-Coercion-Integer-and-Float-Widening" class="hdr">§</a>

[Integers](zig-0.15.1.md#Integers) coerce to integer types which can represent every value of the old type, and likewise
[Floats](zig-0.15.1.md#Floats) coerce to float types which can represent every value of the old type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;integer widening&quot; {
    const a: u8 = 250;
    const b: u16 = a;
    const c: u32 = b;
    const d: u64 = c;
    const e: u64 = d;
    const f: u128 = e;
    try expect(f == a);
}

test &quot;implicit unsigned integer to signed integer&quot; {
    const a: u8 = 250;
    const b: i16 = a;
    try expect(b == 250);
}

test &quot;float widening&quot; {
    const a: f16 = 12.34;
    const b: f32 = a;
    const c: f64 = b;
    const d: f128 = c;
    try expect(d == a);
}</code></pre>
<figcaption>test_integer_widening.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_integer_widening.zig
1/3 test_integer_widening.test.integer widening...OK
2/3 test_integer_widening.test.implicit unsigned integer to signed integer...OK
3/3 test_integer_widening.test.float widening...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Float to Int](zig-0.15.1.md#toc-Type-Coercion-Float-to-Int) <a href="zig-0.15.1.md#Type-Coercion-Float-to-Int" class="hdr">§</a>

A compiler error is appropriate because this ambiguous expression leaves the compiler
two choices about the coercion.

- Cast <span class="tok-number">`54.0`</span> to <span class="tok-type">`comptime_int`</span> resulting in <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`comptime_int`</span>`, `<span class="tok-number">`10`</span>`)`, which is casted to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`f32`</span>`, `<span class="tok-number">`10`</span>`)`
- Cast <span class="tok-number">`5`</span> to <span class="tok-type">`comptime_float`</span> resulting in <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`comptime_float`</span>`, `<span class="tok-number">`10.8`</span>`)`, which is casted to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`f32`</span>`, `<span class="tok-number">`10.8`</span>`)`

<figure>
<pre><code>// Compile time coercion of float to int
test &quot;implicit cast to comptime_int&quot; {
    const f: f32 = 54.0 / 5;
    _ = f;
}</code></pre>
<figcaption>test_ambiguous_coercion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_ambiguous_coercion.zig
/home/andy/dev/zig/doc/langref/test_ambiguous_coercion.zig:3:25: error: ambiguous coercion of division operands &#39;comptime_float&#39; and &#39;comptime_int&#39;; non-zero remainder &#39;4&#39;
    const f: f32 = 54.0 / 5;
                   ~~~~~^~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Slices, Arrays and Pointers](zig-0.15.1.md#toc-Type-Coercion-Slices-Arrays-and-Pointers) <a href="zig-0.15.1.md#Type-Coercion-Slices-Arrays-and-Pointers" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

// You can assign constant pointers to arrays to a slice with
// const modifier on the element type. Useful in particular for
// String literals.
test &quot;*const [N]T to []const T&quot; {
    const x1: []const u8 = &quot;hello&quot;;
    const x2: []const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, x1, x2));

    const y: []const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect(y[0] == 1.2);
}

// Likewise, it works when the destination type is an error union.
test &quot;*const [N]T to E![]const T&quot; {
    const x1: anyerror![]const u8 = &quot;hello&quot;;
    const x2: anyerror![]const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, try x1, try x2));

    const y: anyerror![]const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect((try y)[0] == 1.2);
}

// Likewise, it works when the destination type is an optional.
test &quot;*const [N]T to ?[]const T&quot; {
    const x1: ?[]const u8 = &quot;hello&quot;;
    const x2: ?[]const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, x1.?, x2.?));

    const y: ?[]const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect(y.?[0] == 1.2);
}

// In this cast, the array length becomes the slice length.
test &quot;*[N]T to []T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: []u8 = &amp;buf;
    try expect(std.mem.eql(u8, x, &quot;hello&quot;));

    const buf2 = [2]f32{ 1.2, 3.4 };
    const x2: []const f32 = &amp;buf2;
    try expect(std.mem.eql(f32, x2, &amp;[2]f32{ 1.2, 3.4 }));
}

// Single-item pointers to arrays can be coerced to many-item pointers.
test &quot;*[N]T to [*]T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: [*]u8 = &amp;buf;
    try expect(x[4] == &#39;o&#39;);
    // x[5] would be an uncaught out of bounds pointer dereference!
}

// Likewise, it works when the destination type is an optional.
test &quot;*[N]T to ?[*]T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: ?[*]u8 = &amp;buf;
    try expect(x.?[4] == &#39;o&#39;);
}

// Single-item pointers can be cast to len-1 single-item arrays.
test &quot;*T to *[1]T&quot; {
    var x: i32 = 1234;
    const y: *[1]i32 = &amp;x;
    const z: [*]i32 = y;
    try expect(z[0] == 1234);
}

// Sentinel-terminated slices can be coerced into sentinel-terminated pointers
test &quot;[:x]T to [*:x]T&quot; {
    const buf: [:0]const u8 = &quot;hello&quot;;
    const buf2: [*:0]const u8 = buf;
    try expect(buf2[4] == &#39;o&#39;);
}</code></pre>
<figcaption>test_coerce_slices_arrays_and_pointers.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_slices_arrays_and_pointers.zig
1/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to []const T...OK
2/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to E![]const T...OK
3/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to ?[]const T...OK
4/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to []T...OK
5/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to [*]T...OK
6/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to ?[*]T...OK
7/8 test_coerce_slices_arrays_and_pointers.test.*T to *[1]T...OK
8/8 test_coerce_slices_arrays_and_pointers.test.[:x]T to [*:x]T...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [C Pointers](zig-0.15.1.md#C-Pointers)

#### [Type Coercion: Optionals](zig-0.15.1.md#toc-Type-Coercion-Optionals) <a href="zig-0.15.1.md#Type-Coercion-Optionals" class="hdr">§</a>

The payload type of [Optionals](zig-0.15.1.md#Optionals), as well as [null](zig-0.15.1.md#null), coerce to the optional type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coerce to optionals&quot; {
    const x: ?i32 = 1234;
    const y: ?i32 = null;

    try expect(x.? == 1234);
    try expect(y == null);
}</code></pre>
<figcaption>test_coerce_optionals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_optionals.zig
1/1 test_coerce_optionals.test.coerce to optionals...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Optionals work nested inside the [Error Union Type](zig-0.15.1.md#Error-Union-Type), too:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coerce to optionals wrapped in error union&quot; {
    const x: anyerror!?i32 = 1234;
    const y: anyerror!?i32 = null;

    try expect((try x).? == 1234);
    try expect((try y) == null);
}</code></pre>
<figcaption>test_coerce_optional_wrapped_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_optional_wrapped_error_union.zig
1/1 test_coerce_optional_wrapped_error_union.test.coerce to optionals wrapped in error union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Error Unions](zig-0.15.1.md#toc-Type-Coercion-Error-Unions) <a href="zig-0.15.1.md#Type-Coercion-Error-Unions" class="hdr">§</a>

The payload type of an [Error Union Type](zig-0.15.1.md#Error-Union-Type) as well as the [Error Set Type](zig-0.15.1.md#Error-Set-Type)
coerce to the error union type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coercion to error unions&quot; {
    const x: anyerror!i32 = 1234;
    const y: anyerror!i32 = error.Failure;

    try expect((try x) == 1234);
    try std.testing.expectError(error.Failure, y);
}</code></pre>
<figcaption>test_coerce_to_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_to_error_union.zig
1/1 test_coerce_to_error_union.test.coercion to error unions...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Compile-Time Known Numbers](zig-0.15.1.md#toc-Type-Coercion-Compile-Time-Known-Numbers) <a href="zig-0.15.1.md#Type-Coercion-Compile-Time-Known-Numbers" class="hdr">§</a>

When a number is [comptime](zig-0.15.1.md#comptime)-known to be representable in the destination type,
it may be coerced:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coercing large integer type to smaller one when value is comptime-known to fit&quot; {
    const x: u64 = 255;
    const y: u8 = x;
    try expect(y == 255);
}</code></pre>
<figcaption>test_coerce_large_to_small.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_large_to_small.zig
1/1 test_coerce_large_to_small.test.coercing large integer type to smaller one when value is comptime-known to fit...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Unions and Enums](zig-0.15.1.md#toc-Type-Coercion-Unions-and-Enums) <a href="zig-0.15.1.md#Type-Coercion-Unions-and-Enums" class="hdr">§</a>

Tagged unions can be coerced to enums, and enums can be coerced to tagged unions
when they are [comptime](zig-0.15.1.md#comptime)-known to be a field of the union that has only one possible value, such as
[void](zig-0.15.1.md#void):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const E = enum {
    one,
    two,
    three,
};

const U = union(E) {
    one: i32,
    two: f32,
    three,
};

const U2 = union(enum) {
    a: void,
    b: f32,

    fn tag(self: U2) usize {
        switch (self) {
            .a =&gt; return 1,
            .b =&gt; return 2,
        }
    }
};

test &quot;coercion between unions and enums&quot; {
    const u = U{ .two = 12.34 };
    const e: E = u; // coerce union to enum
    try expect(e == E.two);

    const three = E.three;
    const u_2: U = three; // coerce enum to union
    try expect(u_2 == E.three);

    const u_3: U = .three; // coerce enum literal to union
    try expect(u_3 == E.three);

    const u_4: U2 = .a; // coerce enum literal to union with inferred enum tag type.
    try expect(u_4.tag() == 1);

    // The following example is invalid.
    // error: coercion from enum &#39;@TypeOf(.enum_literal)&#39; to union &#39;test_coerce_unions_enum.U2&#39; must initialize &#39;f32&#39; field &#39;b&#39;
    //var u_5: U2 = .b;
    //try expect(u_5.tag() == 2);
}</code></pre>
<figcaption>test_coerce_unions_enums.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_unions_enums.zig
1/1 test_coerce_unions_enums.test.coercion between unions and enums...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [union](zig-0.15.1.md#union)
- [enum](zig-0.15.1.md#enum)

#### [Type Coercion: undefined](zig-0.15.1.md#toc-Type-Coercion-undefined) <a href="zig-0.15.1.md#Type-Coercion-undefined" class="hdr">§</a>

[undefined](zig-0.15.1.md#undefined) can be coerced to any type.

#### [Type Coercion: Tuples to Arrays](zig-0.15.1.md#toc-Type-Coercion-Tuples-to-Arrays) <a href="zig-0.15.1.md#Type-Coercion-Tuples-to-Arrays" class="hdr">§</a>

[Tuples](zig-0.15.1.md#Tuples) can be coerced to arrays, if all of the fields have the same type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Tuple = struct { u8, u8 };
test &quot;coercion from homogeneous tuple to array&quot; {
    const tuple: Tuple = .{ 5, 6 };
    const array: [2]u8 = tuple;
    _ = array;
}</code></pre>
<figcaption>test_coerce_tuples_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_tuples_arrays.zig
1/1 test_coerce_tuples_arrays.test.coercion from homogeneous tuple to array...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Explicit Casts](zig-0.15.1.md#toc-Explicit-Casts) <a href="zig-0.15.1.md#Explicit-Casts" class="hdr">§</a>

Explicit casts are performed via [Builtin Functions](zig-0.15.1.md#Builtin-Functions).
Some explicit casts are safe; some are not.
Some explicit casts perform language-level assertions; some do not.
Some explicit casts are no-ops at runtime; some are not.

- [@bitCast](zig-0.15.1.md#bitCast) - change type but maintain bit representation
- [@alignCast](zig-0.15.1.md#alignCast) - make a pointer have more alignment
- [@enumFromInt](zig-0.15.1.md#enumFromInt) - obtain an enum value based on its integer tag value
- [@errorFromInt](zig-0.15.1.md#errorFromInt) - obtain an error code based on its integer value
- [@errorCast](zig-0.15.1.md#errorCast) - convert to a smaller error set
- [@floatCast](zig-0.15.1.md#floatCast) - convert a larger float to a smaller float
- [@floatFromInt](zig-0.15.1.md#floatFromInt) - convert an integer to a float value
- [@intCast](zig-0.15.1.md#intCast) - convert between integer types
- [@intFromBool](zig-0.15.1.md#intFromBool) - convert true to 1 and false to 0
- [@intFromEnum](zig-0.15.1.md#intFromEnum) - obtain the integer tag value of an enum or tagged union
- [@intFromError](zig-0.15.1.md#intFromError) - obtain the integer value of an error code
- [@intFromFloat](zig-0.15.1.md#intFromFloat) - obtain the integer part of a float value
- [@intFromPtr](zig-0.15.1.md#intFromPtr) - obtain the address of a pointer
- [@ptrFromInt](zig-0.15.1.md#ptrFromInt) - convert an address to a pointer
- [@ptrCast](zig-0.15.1.md#ptrCast) - convert between pointer types
- [@truncate](zig-0.15.1.md#truncate) - convert between integer types, chopping off bits

### [Peer Type Resolution](zig-0.15.1.md#toc-Peer-Type-Resolution) <a href="zig-0.15.1.md#Peer-Type-Resolution" class="hdr">§</a>

Peer Type Resolution occurs in these places:

- [switch](zig-0.15.1.md#switch) expressions
- [if](zig-0.15.1.md#if) expressions
- [while](zig-0.15.1.md#while) expressions
- [for](zig-0.15.1.md#for) expressions
- Multiple break statements in a block
- Some [binary operations](zig-0.15.1.md#Table-of-Operators)

This kind of type resolution chooses a type that all peer types can coerce into. Here are
some examples:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;peer resolve int widening&quot; {
    const a: i8 = 12;
    const b: i16 = 34;
    const c = a + b;
    try expect(c == 46);
    try expect(@TypeOf(c) == i16);
}

test &quot;peer resolve arrays of different size to const slice&quot; {
    try expect(mem.eql(u8, boolToStr(true), &quot;true&quot;));
    try expect(mem.eql(u8, boolToStr(false), &quot;false&quot;));
    try comptime expect(mem.eql(u8, boolToStr(true), &quot;true&quot;));
    try comptime expect(mem.eql(u8, boolToStr(false), &quot;false&quot;));
}
fn boolToStr(b: bool) []const u8 {
    return if (b) &quot;true&quot; else &quot;false&quot;;
}

test &quot;peer resolve array and const slice&quot; {
    try testPeerResolveArrayConstSlice(true);
    try comptime testPeerResolveArrayConstSlice(true);
}
fn testPeerResolveArrayConstSlice(b: bool) !void {
    const value1 = if (b) &quot;aoeu&quot; else @as([]const u8, &quot;zz&quot;);
    const value2 = if (b) @as([]const u8, &quot;zz&quot;) else &quot;aoeu&quot;;
    try expect(mem.eql(u8, value1, &quot;aoeu&quot;));
    try expect(mem.eql(u8, value2, &quot;zz&quot;));
}

test &quot;peer type resolution: ?T and T&quot; {
    try expect(peerTypeTAndOptionalT(true, false).? == 0);
    try expect(peerTypeTAndOptionalT(false, false).? == 3);
    comptime {
        try expect(peerTypeTAndOptionalT(true, false).? == 0);
        try expect(peerTypeTAndOptionalT(false, false).? == 3);
    }
}
fn peerTypeTAndOptionalT(c: bool, b: bool) ?usize {
    if (c) {
        return if (b) null else @as(usize, 0);
    }

    return @as(usize, 3);
}

test &quot;peer type resolution: *[0]u8 and []const u8&quot; {
    try expect(peerTypeEmptyArrayAndSlice(true, &quot;hi&quot;).len == 0);
    try expect(peerTypeEmptyArrayAndSlice(false, &quot;hi&quot;).len == 1);
    comptime {
        try expect(peerTypeEmptyArrayAndSlice(true, &quot;hi&quot;).len == 0);
        try expect(peerTypeEmptyArrayAndSlice(false, &quot;hi&quot;).len == 1);
    }
}
fn peerTypeEmptyArrayAndSlice(a: bool, slice: []const u8) []const u8 {
    if (a) {
        return &amp;[_]u8{};
    }

    return slice[0..1];
}
test &quot;peer type resolution: *[0]u8, []const u8, and anyerror![]u8&quot; {
    {
        var data = &quot;hi&quot;.*;
        const slice = data[0..];
        try expect((try peerTypeEmptyArrayAndSliceAndError(true, slice)).len == 0);
        try expect((try peerTypeEmptyArrayAndSliceAndError(false, slice)).len == 1);
    }
    comptime {
        var data = &quot;hi&quot;.*;
        const slice = data[0..];
        try expect((try peerTypeEmptyArrayAndSliceAndError(true, slice)).len == 0);
        try expect((try peerTypeEmptyArrayAndSliceAndError(false, slice)).len == 1);
    }
}
fn peerTypeEmptyArrayAndSliceAndError(a: bool, slice: []u8) anyerror![]u8 {
    if (a) {
        return &amp;[_]u8{};
    }

    return slice[0..1];
}

test &quot;peer type resolution: *const T and ?*T&quot; {
    const a: *const usize = @ptrFromInt(0x123456780);
    const b: ?*usize = @ptrFromInt(0x123456780);
    try expect(a == b);
    try expect(b == a);
}

test &quot;peer type resolution: error union switch&quot; {
    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `if (x) {...} else |err| blk: { switch (err) {...} }` does not consider the
    // non-error and error case to be peers.
    var a: error{ A, B, C }!u32 = 0;
    _ = &amp;a;
    const b = if (a) |x|
        x + 3
    else |err| switch (err) {
        error.A =&gt; 0,
        error.B =&gt; 1,
        error.C =&gt; null,
    };
    try expect(@TypeOf(b) == ?u32);

    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `x catch |err| blk: { switch (err) {...} }` does not consider the unwrapped `x`
    // and error case to be peers.
    const c = a catch |err| switch (err) {
        error.A =&gt; 0,
        error.B =&gt; 1,
        error.C =&gt; null,
    };
    try expect(@TypeOf(c) == ?u32);
}</code></pre>
<figcaption>test_peer_type_resolution.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_peer_type_resolution.zig
1/8 test_peer_type_resolution.test.peer resolve int widening...OK
2/8 test_peer_type_resolution.test.peer resolve arrays of different size to const slice...OK
3/8 test_peer_type_resolution.test.peer resolve array and const slice...OK
4/8 test_peer_type_resolution.test.peer type resolution: ?T and T...OK
5/8 test_peer_type_resolution.test.peer type resolution: *[0]u8 and []const u8...OK
6/8 test_peer_type_resolution.test.peer type resolution: *[0]u8, []const u8, and anyerror![]u8...OK
7/8 test_peer_type_resolution.test.peer type resolution: *const T and ?*T...OK
8/8 test_peer_type_resolution.test.peer type resolution: error union switch...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

