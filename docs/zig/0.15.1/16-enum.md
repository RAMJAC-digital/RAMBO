<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: enum -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [enum](zig-0.15.1.md#toc-enum) <a href="zig-0.15.1.md#enum" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const mem = @import(&quot;std&quot;).mem;

// Declare an enum.
const Type = enum {
    ok,
    not_ok,
};

// Declare a specific enum field.
const c = Type.ok;

// If you want access to the ordinal value of an enum, you
// can specify the tag type.
const Value = enum(u2) {
    zero,
    one,
    two,
};
// Now you can cast between u2 and Value.
// The ordinal value starts from 0, counting up by 1 from the previous member.
test &quot;enum ordinal value&quot; {
    try expect(@intFromEnum(Value.zero) == 0);
    try expect(@intFromEnum(Value.one) == 1);
    try expect(@intFromEnum(Value.two) == 2);
}

// You can override the ordinal value for an enum.
const Value2 = enum(u32) {
    hundred = 100,
    thousand = 1000,
    million = 1000000,
};
test &quot;set enum ordinal value&quot; {
    try expect(@intFromEnum(Value2.hundred) == 100);
    try expect(@intFromEnum(Value2.thousand) == 1000);
    try expect(@intFromEnum(Value2.million) == 1000000);
}

// You can also override only some values.
const Value3 = enum(u4) {
    a,
    b = 8,
    c,
    d = 4,
    e,
};
test &quot;enum implicit ordinal values and overridden values&quot; {
    try expect(@intFromEnum(Value3.a) == 0);
    try expect(@intFromEnum(Value3.b) == 8);
    try expect(@intFromEnum(Value3.c) == 9);
    try expect(@intFromEnum(Value3.d) == 4);
    try expect(@intFromEnum(Value3.e) == 5);
}

// Enums can have methods, the same as structs and unions.
// Enum methods are not special, they are only namespaced
// functions that you can call with dot syntax.
const Suit = enum {
    clubs,
    spades,
    diamonds,
    hearts,

    pub fn isClubs(self: Suit) bool {
        return self == Suit.clubs;
    }
};
test &quot;enum method&quot; {
    const p = Suit.spades;
    try expect(!p.isClubs());
}

// An enum can be switched upon.
const Foo = enum {
    string,
    number,
    none,
};
test &quot;enum switch&quot; {
    const p = Foo.number;
    const what_is_it = switch (p) {
        Foo.string =&gt; &quot;this is a string&quot;,
        Foo.number =&gt; &quot;this is a number&quot;,
        Foo.none =&gt; &quot;this is a none&quot;,
    };
    try expect(mem.eql(u8, what_is_it, &quot;this is a number&quot;));
}

// @typeInfo can be used to access the integer tag type of an enum.
const Small = enum {
    one,
    two,
    three,
    four,
};
test &quot;std.meta.Tag&quot; {
    try expect(@typeInfo(Small).@&quot;enum&quot;.tag_type == u2);
}

// @typeInfo tells us the field count and the fields names:
test &quot;@typeInfo&quot; {
    try expect(@typeInfo(Small).@&quot;enum&quot;.fields.len == 4);
    try expect(mem.eql(u8, @typeInfo(Small).@&quot;enum&quot;.fields[1].name, &quot;two&quot;));
}

// @tagName gives a [:0]const u8 representation of an enum value:
test &quot;@tagName&quot; {
    try expect(mem.eql(u8, @tagName(Small.three), &quot;three&quot;));
}</code></pre>
<figcaption>test_enums.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_enums.zig
1/8 test_enums.test.enum ordinal value...OK
2/8 test_enums.test.set enum ordinal value...OK
3/8 test_enums.test.enum implicit ordinal values and overridden values...OK
4/8 test_enums.test.enum method...OK
5/8 test_enums.test.enum switch...OK
6/8 test_enums.test.std.meta.Tag...OK
7/8 test_enums.test.@typeInfo...OK
8/8 test_enums.test.@tagName...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@typeInfo](zig-0.15.1.md#typeInfo)
- [@tagName](zig-0.15.1.md#tagName)
- [@sizeOf](zig-0.15.1.md#sizeOf)

### [extern enum](zig-0.15.1.md#toc-extern-enum) <a href="zig-0.15.1.md#extern-enum" class="hdr">§</a>

By default, enums are not guaranteed to be compatible with the C ABI:

<figure>
<pre><code>const Foo = enum { a, b, c };
export fn entry(foo: Foo) void {
    _ = foo;
}</code></pre>
<figcaption>enum_export_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj enum_export_error.zig -target x86_64-linux
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: error: parameter of type &#39;enum_export_error.Foo&#39; not allowed in function with calling convention &#39;x86_64_sysv&#39;
export fn entry(foo: Foo) void {
                ^~~~~~~~
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: note: enum tag type &#39;u2&#39; is not extern compatible
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: note: only integers with 0, 8, 16, 32, 64 and 128 bits are extern compatible
/home/andy/dev/zig/doc/langref/enum_export_error.zig:1:13: note: enum declared here
const Foo = enum { a, b, c };
            ^~~~~~~~~~~~~~~~
referenced by:
    root: /home/andy/dev/zig/lib/std/start.zig:3:22
    comptime: /home/andy/dev/zig/lib/std/start.zig:31:9
    2 reference(s) hidden; use &#39;-freference-trace=4&#39; to see all references
</code></pre>
<figcaption>Shell</figcaption>
</figure>

For a C-ABI-compatible enum, provide an explicit tag type to
the enum:

<figure>
<pre><code>const Foo = enum(c_int) { a, b, c };
export fn entry(foo: Foo) void {
    _ = foo;
}</code></pre>
<figcaption>enum_export.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj enum_export.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Enum Literals](zig-0.15.1.md#toc-Enum-Literals) <a href="zig-0.15.1.md#Enum-Literals" class="hdr">§</a>

Enum literals allow specifying the name of an enum field without specifying the enum type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Color = enum {
    auto,
    off,
    on,
};

test &quot;enum literals&quot; {
    const color1: Color = .auto;
    const color2 = Color.auto;
    try expect(color1 == color2);
}

test &quot;switch using enum literals&quot; {
    const color = Color.on;
    const result = switch (color) {
        .auto =&gt; false,
        .on =&gt; true,
        .off =&gt; false,
    };
    try expect(result);
}</code></pre>
<figcaption>test_enum_literals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_enum_literals.zig
1/2 test_enum_literals.test.enum literals...OK
2/2 test_enum_literals.test.switch using enum literals...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Non-exhaustive enum](zig-0.15.1.md#toc-Non-exhaustive-enum) <a href="zig-0.15.1.md#Non-exhaustive-enum" class="hdr">§</a>

A non-exhaustive enum can be created by adding a trailing `_` field.
The enum must specify a tag type and cannot consume every enumeration value.

[@enumFromInt](zig-0.15.1.md#enumFromInt) on a non-exhaustive enum involves the safety semantics
of [@intCast](zig-0.15.1.md#intCast) to the integer tag type, but beyond that always results in
a well-defined enum value.

A switch on a non-exhaustive enum can include a `_` prong as an alternative to an <span class="tok-kw">`else`</span> prong.
With a `_` prong the compiler errors if all the known tag names are not handled by the switch.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Number = enum(u8) {
    one,
    two,
    three,
    _,
};

test &quot;switch on non-exhaustive enum&quot; {
    const number = Number.one;
    const result = switch (number) {
        .one =&gt; true,
        .two, .three =&gt; false,
        _ =&gt; false,
    };
    try expect(result);
    const is_one = switch (number) {
        .one =&gt; true,
        else =&gt; false,
    };
    try expect(is_one);
}</code></pre>
<figcaption>test_switch_non-exhaustive.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_non-exhaustive.zig
1/1 test_switch_non-exhaustive.test.switch on non-exhaustive enum...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

