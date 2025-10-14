<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: struct -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [struct](zig-0.15.1.md#toc-struct) <a href="zig-0.15.1.md#struct" class="hdr">§</a>

<figure>
<pre><code>// Declare a struct.
// Zig gives no guarantees about the order of fields and the size of
// the struct but the fields are guaranteed to be ABI-aligned.
const Point = struct {
    x: f32,
    y: f32,
};

// Declare an instance of a struct.
const p: Point = .{
    .x = 0.12,
    .y = 0.34,
};

// Functions in the struct&#39;s namespace can be called with dot syntax.
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};

test &quot;dot product&quot; {
    const v1 = Vec3.init(1.0, 0.0, 0.0);
    const v2 = Vec3.init(0.0, 1.0, 0.0);
    try expect(v1.dot(v2) == 0.0);

    // Other than being available to call with dot syntax, struct methods are
    // not special. You can reference them as any other declaration inside
    // the struct:
    try expect(Vec3.dot(v1, v2) == 0.0);
}

// Structs can have declarations.
// Structs can have 0 fields.
const Empty = struct {
    pub const PI = 3.14;
};
test &quot;struct namespaced variable&quot; {
    try expect(Empty.PI == 3.14);
    try expect(@sizeOf(Empty) == 0);

    // Empty structs can be instantiated the same as usual.
    const does_nothing: Empty = .{};

    _ = does_nothing;
}

// Struct field order is determined by the compiler, however, a base pointer
// can be computed from a field pointer:
fn setYBasedOnX(x: *f32, y: f32) void {
    const point: *Point = @fieldParentPtr(&quot;x&quot;, x);
    point.y = y;
}
test &quot;field parent pointer&quot; {
    var point = Point{
        .x = 0.1234,
        .y = 0.5678,
    };
    setYBasedOnX(&amp;point.x, 0.9);
    try expect(point.y == 0.9);
}

// Structs can be returned from functions.
fn LinkedList(comptime T: type) type {
    return struct {
        pub const Node = struct {
            prev: ?*Node,
            next: ?*Node,
            data: T,
        };

        first: ?*Node,
        last: ?*Node,
        len: usize,
    };
}

test &quot;linked list&quot; {
    // Functions called at compile-time are memoized.
    try expect(LinkedList(i32) == LinkedList(i32));

    const list = LinkedList(i32){
        .first = null,
        .last = null,
        .len = 0,
    };
    try expect(list.len == 0);

    // Since types are first class values you can instantiate the type
    // by assigning it to a variable:
    const ListOfInts = LinkedList(i32);
    try expect(ListOfInts == LinkedList(i32));

    var node = ListOfInts.Node{
        .prev = null,
        .next = null,
        .data = 1234,
    };
    const list2 = LinkedList(i32){
        .first = &amp;node,
        .last = &amp;node,
        .len = 1,
    };

    // When using a pointer to a struct, fields can be accessed directly,
    // without explicitly dereferencing the pointer.
    // So you can do
    try expect(list2.first.?.data == 1234);
    // instead of try expect(list2.first.?.*.data == 1234);
}

const expect = @import(&quot;std&quot;).testing.expect;</code></pre>
<figcaption>test_structs.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_structs.zig
1/4 test_structs.test.dot product...OK
2/4 test_structs.test.struct namespaced variable...OK
3/4 test_structs.test.field parent pointer...OK
4/4 test_structs.test.linked list...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Default Field Values](zig-0.15.1.md#toc-Default-Field-Values) <a href="zig-0.15.1.md#Default-Field-Values" class="hdr">§</a>

Each struct field may have an expression indicating the default field
value. Such expressions are executed at [comptime](zig-0.15.1.md#comptime), and allow the
field to be omitted in a struct literal expression:

<figure>
<pre><code>const Foo = struct {
    a: i32 = 1234,
    b: i32,
};

test &quot;default struct initialization fields&quot; {
    const x: Foo = .{
        .b = 5,
    };
    if (x.a + x.b != 1239) {
        comptime unreachable;
    }
}</code></pre>
<figcaption>struct_default_field_values.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test struct_default_field_values.zig
1/1 struct_default_field_values.test.default struct initialization fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Faulty Default Field Values](zig-0.15.1.md#toc-Faulty-Default-Field-Values) <a href="zig-0.15.1.md#Faulty-Default-Field-Values" class="hdr">§</a>

Default field values are only appropriate when the data invariants of a struct
cannot be violated by omitting that field from an initialization.

For example, here is an inappropriate use of default struct field initialization:

<figure>
<pre><code>const Threshold = struct {
    minimum: f32 = 0.25,
    maximum: f32 = 0.75,

    const Category = enum { low, medium, high };

    fn categorize(t: Threshold, value: f32) Category {
        assert(t.maximum &gt;= t.minimum);
        if (value &lt; t.minimum) return .low;
        if (value &gt; t.maximum) return .high;
        return .medium;
    }
};

pub fn main() !void {
    var threshold: Threshold = .{
        .maximum = 0.20,
    };
    const category = threshold.categorize(0.90);
    try std.fs.File.stdout().writeAll(@tagName(category));
}

const std = @import(&quot;std&quot;);
const assert = std.debug.assert;</code></pre>
<figcaption>bad_default_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe bad_default_value.zig
$ ./bad_default_value
thread 1093499 panic: reached unreachable code
/home/andy/dev/zig/lib/std/debug.zig:559:14: 0x1044179 in assert (std.zig)
    if (!ok) unreachable; // assertion failure
             ^
/home/andy/dev/zig/doc/langref/bad_default_value.zig:8:15: 0x113ec34 in categorize (bad_default_value.zig)
        assert(t.maximum &gt;= t.minimum);
              ^
/home/andy/dev/zig/doc/langref/bad_default_value.zig:19:42: 0x113d424 in main (bad_default_value.zig)
    const category = threshold.categorize(0.90);
                                         ^
/home/andy/dev/zig/lib/std/start.zig:627:37: 0x113dc89 in posixCallMainAndExit (std.zig)
            const result = root.main() catch |err| {
                                    ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

Above you can see the danger of ignoring this principle. The default
field values caused the data invariant to be violated, causing illegal
behavior.

To fix this, remove the default values from all the struct fields, and provide
a named default value:

<figure>
<pre><code>const Threshold = struct {
    minimum: f32,
    maximum: f32,

    const default: Threshold = .{
        .minimum = 0.25,
        .maximum = 0.75,
    };
};</code></pre>
<figcaption>struct_default_value.zig</figcaption>
</figure>

If a struct value requires a runtime-known value in order to be initialized
without violating data invariants, then use an initialization method that accepts
those runtime values, and populates the remaining fields.

### [extern struct](zig-0.15.1.md#toc-extern-struct) <a href="zig-0.15.1.md#extern-struct" class="hdr">§</a>

An <span class="tok-kw">`extern`</span>` `<span class="tok-kw">`struct`</span> has in-memory layout matching
the C ABI for the target.

If well-defined in-memory layout is not required, [struct](zig-0.15.1.md#struct) is a better choice
because it places fewer restrictions on the compiler.

See [packed struct](zig-0.15.1.md#packed-struct) for a struct that has the ABI of its backing integer,
which can be useful for modeling flags.

See also:

- [extern union](zig-0.15.1.md#extern-union)
- [extern enum](zig-0.15.1.md#extern-enum)

### [packed struct](zig-0.15.1.md#toc-packed-struct) <a href="zig-0.15.1.md#packed-struct" class="hdr">§</a>

<span class="tok-kw">`packed`</span> structs, like <span class="tok-kw">`enum`</span>, are based on the concept
of interpreting integers differently. All packed structs have a **backing integer**,
which is implicitly determined by the total bit count of fields, or explicitly specified.
Packed structs have well-defined memory layout - exactly the same ABI as their backing integer.

Each field of a packed struct is interpreted as a logical sequence of bits, arranged from
least to most significant. Allowed field types:

- An [integer](zig-0.15.1.md#Integers) field uses exactly as many bits as its
  bit width. For example, a <span class="tok-type">`u5`</span> will use 5 bits of
  the backing integer.
- A [bool](zig-0.15.1.md#Primitive-Types) field uses exactly 1 bit.
- An [enum](zig-0.15.1.md#enum) field uses exactly the bit width of its integer tag type.
- A [packed union](zig-0.15.1.md#packed-union) field uses exactly the bit width of the union field with
  the largest bit width.
- A <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`struct`</span> field uses the bits of its backing integer.

This means that a <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`struct`</span> can participate
in a [@bitCast](zig-0.15.1.md#bitCast) or a [@ptrCast](zig-0.15.1.md#ptrCast) to reinterpret memory.
This even works at [comptime](zig-0.15.1.md#comptime):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const native_endian = @import(&quot;builtin&quot;).target.cpu.arch.endian();
const expect = std.testing.expect;

const Full = packed struct {
    number: u16,
};
const Divided = packed struct {
    half1: u8,
    quarter3: u4,
    quarter4: u4,
};

test &quot;@bitCast between packed structs&quot; {
    try doTheTest();
    try comptime doTheTest();
}

fn doTheTest() !void {
    try expect(@sizeOf(Full) == 2);
    try expect(@sizeOf(Divided) == 2);
    const full = Full{ .number = 0x1234 };
    const divided: Divided = @bitCast(full);
    try expect(divided.half1 == 0x34);
    try expect(divided.quarter3 == 0x2);
    try expect(divided.quarter4 == 0x1);

    const ordered: [2]u8 = @bitCast(full);
    switch (native_endian) {
        .big =&gt; {
            try expect(ordered[0] == 0x12);
            try expect(ordered[1] == 0x34);
        },
        .little =&gt; {
            try expect(ordered[0] == 0x34);
            try expect(ordered[1] == 0x12);
        },
    }
}</code></pre>
<figcaption>test_packed_structs.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_structs.zig
1/1 test_packed_structs.test.@bitCast between packed structs...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The backing integer can be inferred or explicitly provided. When
inferred, it will be unsigned. When explicitly provided, its bit width
will be enforced at compile time to exactly match the total bit width of
the fields:

<figure>
<pre><code>test &quot;missized packed struct&quot; {
    const S = packed struct(u32) { a: u16, b: u8 };
    _ = S{ .a = 4, .b = 2 };
}</code></pre>
<figcaption>test_missized_packed_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_missized_packed_struct.zig
/home/andy/dev/zig/doc/langref/test_missized_packed_struct.zig:2:29: error: backing integer type &#39;u32&#39; has bit size 32 but the struct fields have a total bit size of 24
    const S = packed struct(u32) { a: u16, b: u8 };
                            ^~~
referenced by:
    test.missized packed struct: /home/andy/dev/zig/doc/langref/test_missized_packed_struct.zig:2:22
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig allows the address to be taken of a non-byte-aligned field:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var foo = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointer to non-byte-aligned field&quot; {
    const ptr = &amp;foo.b;
    try expect(ptr.* == 2);
}</code></pre>
<figcaption>test_pointer_to_non-byte_aligned_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_to_non-byte_aligned_field.zig
1/1 test_pointer_to_non-byte_aligned_field.test.pointer to non-byte-aligned field...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

However, the pointer to a non-byte-aligned field has special properties and cannot
be passed when a normal pointer is expected:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var bit_field = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointer to non-byte-aligned field&quot; {
    try expect(bar(&amp;bit_field.b) == 2);
}

fn bar(x: *const u3) u3 {
    return x.*;
}</code></pre>
<figcaption>test_misaligned_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_misaligned_pointer.zig
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: error: expected type &#39;*const u3&#39;, found &#39;*align(1:3:1) u3&#39;
    try expect(bar(&amp;bit_field.b) == 2);
                   ^~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: note: pointer host size &#39;1&#39; cannot cast into pointer host size &#39;0&#39;
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: note: pointer bit offset &#39;3&#39; cannot cast into pointer bit offset &#39;0&#39;
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:20:11: note: parameter type declared here
fn bar(x: *const u3) u3 {
          ^~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

In this case, the function `bar` cannot be called because the pointer
to the non-ABI-aligned field mentions the bit offset, but the function expects an ABI-aligned pointer.

Pointers to non-ABI-aligned fields share the same address as the other fields within their host integer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var bit_field = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointers of sub-byte-aligned fields share addresses&quot; {
    try expect(@intFromPtr(&amp;bit_field.a) == @intFromPtr(&amp;bit_field.b));
    try expect(@intFromPtr(&amp;bit_field.a) == @intFromPtr(&amp;bit_field.c));
}</code></pre>
<figcaption>test_packed_struct_field_address.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_struct_field_address.zig
1/1 test_packed_struct_field_address.test.pointers of sub-byte-aligned fields share addresses...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This can be observed with [@bitOffsetOf](zig-0.15.1.md#bitOffsetOf) and [offsetOf](zig-0.15.1.md#offsetOf):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

test &quot;offsets of non-byte-aligned fields&quot; {
    comptime {
        try expect(@bitOffsetOf(BitField, &quot;a&quot;) == 0);
        try expect(@bitOffsetOf(BitField, &quot;b&quot;) == 3);
        try expect(@bitOffsetOf(BitField, &quot;c&quot;) == 6);

        try expect(@offsetOf(BitField, &quot;a&quot;) == 0);
        try expect(@offsetOf(BitField, &quot;b&quot;) == 0);
        try expect(@offsetOf(BitField, &quot;c&quot;) == 0);
    }
}</code></pre>
<figcaption>test_bitOffsetOf_offsetOf.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_bitOffsetOf_offsetOf.zig
1/1 test_bitOffsetOf_offsetOf.test.offsets of non-byte-aligned fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Packed structs have the same alignment as their backing integer, however, overaligned
pointers to packed structs can override this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const S = packed struct {
    a: u32,
    b: u32,
};
test &quot;overaligned pointer to packed struct&quot; {
    var foo: S align(4) = .{ .a = 1, .b = 2 };
    const ptr: *align(4) S = &amp;foo;
    const ptr_to_b: *u32 = &amp;ptr.b;
    try expect(ptr_to_b.* == 2);
}</code></pre>
<figcaption>test_overaligned_packed_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_overaligned_packed_struct.zig
1/1 test_overaligned_packed_struct.test.overaligned pointer to packed struct...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It's also possible to set alignment of struct fields:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

test &quot;aligned struct fields&quot; {
    const S = struct {
        a: u32 align(2),
        b: u32 align(64),
    };
    var foo = S{ .a = 1, .b = 2 };

    try expectEqual(64, @alignOf(S));
    try expectEqual(*align(2) u32, @TypeOf(&amp;foo.a));
    try expectEqual(*align(64) u32, @TypeOf(&amp;foo.b));
}</code></pre>
<figcaption>test_aligned_struct_fields.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_aligned_struct_fields.zig
1/1 test_aligned_struct_fields.test.aligned struct fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Equating packed structs results in a comparison of the backing integer,
and only works for the `==` and `!=` [Operators](zig-0.15.1.md#Operators).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;packed struct equality&quot; {
    const S = packed struct {
        a: u4,
        b: u4,
    };
    const x: S = .{ .a = 1, .b = 2 };
    const y: S = .{ .b = 2, .a = 1 };
    try expect(x == y);
}</code></pre>
<figcaption>test_packed_struct_equality.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_struct_equality.zig
1/1 test_packed_struct_equality.test.packed struct equality...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Field access and assignment can be understood as shorthand for bitshifts
on the backing integer. These operations are not [atomic](zig-0.15.1.md#Atomics),
so beware using field access syntax when combined with memory-mapped
input-output (MMIO). Instead of field access on [volatile](zig-0.15.1.md#volatile) [Pointers](zig-0.15.1.md#Pointers),
construct a fully-formed new value first, then write that value to the volatile pointer.

<figure>
<pre><code>pub const GpioRegister = packed struct(u8) {
    GPIO0: bool,
    GPIO1: bool,
    GPIO2: bool,
    GPIO3: bool,
    reserved: u4 = 0,
};

const gpio: *volatile GpioRegister = @ptrFromInt(0x0123);

pub fn writeToGpio(new_states: GpioRegister) void {
    // Example of what not to do:
    // BAD! gpio.GPIO0 = true; BAD!

    // Instead, do this:
    gpio.* = new_states;
}</code></pre>
<figcaption>packed_struct_mmio.zig</figcaption>
</figure>

### [Struct Naming](zig-0.15.1.md#toc-Struct-Naming) <a href="zig-0.15.1.md#Struct-Naming" class="hdr">§</a>

Since all structs are anonymous, Zig infers the type name based on a few rules.

- If the struct is in the initialization expression of a variable, it gets named after
  that variable.
- If the struct is in the <span class="tok-kw">`return`</span> expression, it gets named after
  the function it is returning from, with the parameter values serialized.
- Otherwise, the struct gets a name such as `(filename.funcname__struct_ID)`.
- If the struct is declared inside another struct, it gets named after both the parent
  struct and the name inferred by the previous rules, separated by a dot.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const Foo = struct {};
    std.debug.print(&quot;variable: {s}\n&quot;, .{@typeName(Foo)});
    std.debug.print(&quot;anonymous: {s}\n&quot;, .{@typeName(struct {})});
    std.debug.print(&quot;function: {s}\n&quot;, .{@typeName(List(i32))});
}

fn List(comptime T: type) type {
    return struct {
        x: T,
    };
}</code></pre>
<figcaption>struct_name.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe struct_name.zig
$ ./struct_name
variable: struct_name.main.Foo
anonymous: struct_name.main__struct_22696
function: struct_name.List(i32)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Anonymous Struct Literals](zig-0.15.1.md#toc-Anonymous-Struct-Literals) <a href="zig-0.15.1.md#Anonymous-Struct-Literals" class="hdr">§</a>

Zig allows omitting the struct type of a literal. When the result is [coerced](zig-0.15.1.md#Type-Coercion),
the struct literal will directly instantiate the [result location](zig-0.15.1.md#Result-Location-Semantics),
with no copy:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Point = struct { x: i32, y: i32 };

test &quot;anonymous struct literal&quot; {
    const pt: Point = .{
        .x = 13,
        .y = 67,
    };
    try expect(pt.x == 13);
    try expect(pt.y == 67);
}</code></pre>
<figcaption>test_struct_result.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_struct_result.zig
1/1 test_struct_result.test.anonymous struct literal...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The struct type can be inferred. Here the [result location](zig-0.15.1.md#Result-Location-Semantics)
does not include a type, and so Zig infers the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;fully anonymous struct&quot; {
    try check(.{
        .int = @as(u32, 1234),
        .float = @as(f64, 12.34),
        .b = true,
        .s = &quot;hi&quot;,
    });
}

fn check(args: anytype) !void {
    try expect(args.int == 1234);
    try expect(args.float == 12.34);
    try expect(args.b);
    try expect(args.s[0] == &#39;h&#39;);
    try expect(args.s[1] == &#39;i&#39;);
}</code></pre>
<figcaption>test_anonymous_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_anonymous_struct.zig
1/1 test_anonymous_struct.test.fully anonymous struct...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Tuples](zig-0.15.1.md#toc-Tuples) <a href="zig-0.15.1.md#Tuples" class="hdr">§</a>

Anonymous structs can be created without specifying field names, and are referred to as "tuples". An empty tuple looks like `.{}` and can be seen in one of the [Hello World examples](zig-0.15.1.md#Hello-World).

The fields are implicitly named using numbers starting from 0. Because their names are integers,
they cannot be accessed with `.` syntax without also wrapping them in
`@""`. Names inside `@""` are always recognised as
[identifiers](zig-0.15.1.md#Identifiers).

Like arrays, tuples have a .len field, can be indexed (provided the index is comptime-known)
and work with the ++ and \*\* operators. They can also be iterated over with [inline for](zig-0.15.1.md#inline-for).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;tuple&quot; {
    const values = .{
        @as(u32, 1234),
        @as(f64, 12.34),
        true,
        &quot;hi&quot;,
    } ++ .{false} ** 2;
    try expect(values[0] == 1234);
    try expect(values[4] == false);
    inline for (values, 0..) |v, i| {
        if (i != 2) continue;
        try expect(v);
    }
    try expect(values.len == 6);
    try expect(values.@&quot;3&quot;[0] == &#39;h&#39;);
}</code></pre>
<figcaption>test_tuples.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tuples.zig
1/1 test_tuples.test.tuple...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Destructuring Tuples](zig-0.15.1.md#toc-Destructuring-Tuples) <a href="zig-0.15.1.md#Destructuring-Tuples" class="hdr">§</a>

Tuples can be [destructured](zig-0.15.1.md#Destructuring).

Tuple destructuring is helpful for returning multiple values from a block:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    const digits = [_]i8 { 3, 8, 9, 0, 7, 4, 1 };

    const min, const max = blk: {
        var min: i8 = 127;
        var max: i8 = -128;

        for (digits) |digit| {
            if (digit &lt; min) min = digit;
            if (digit &gt; max) max = digit;
        }

        break :blk .{ min, max };
    };

    print(&quot;min = {}&quot;, .{ min });
    print(&quot;max = {}&quot;, .{ max });
}</code></pre>
<figcaption>destructuring_block.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_block.zig
$ ./destructuring_block
min = 0max = 9</code></pre>
<figcaption>Shell</figcaption>
</figure>

Tuple destructuring is helpful for dealing with functions and built-ins that return multiple values
as a tuple:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

fn divmod(numerator: u32, denominator: u32) struct { u32, u32 } {
    return .{ numerator / denominator, numerator % denominator };
}

pub fn main() void {
    const div, const mod = divmod(10, 3);

    print(&quot;10 / 3 = {}\n&quot;, .{div});
    print(&quot;10 % 3 = {}\n&quot;, .{mod});
}</code></pre>
<figcaption>destructuring_return_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_return_value.zig
$ ./destructuring_return_value
10 / 3 = 3
10 % 3 = 1</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](zig-0.15.1.md#Destructuring)
- [Destructuring Arrays](zig-0.15.1.md#Destructuring-Arrays)
- [Destructuring Vectors](zig-0.15.1.md#Destructuring-Vectors)

See also:

- [comptime](zig-0.15.1.md#comptime)
- [@fieldParentPtr](zig-0.15.1.md#fieldParentPtr)

