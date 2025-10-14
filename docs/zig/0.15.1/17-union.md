<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: union -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [union](zig-0.15.1.md#toc-union) <a href="zig-0.15.1.md#union" class="hdr">§</a>

A bare <span class="tok-kw">`union`</span> defines a set of possible types that a value
can be as a list of fields. Only one field can be active at a time.
The in-memory representation of bare unions is not guaranteed.
Bare unions cannot be used to reinterpret memory. For that, use [@ptrCast](zig-0.15.1.md#ptrCast),
or use an [extern union](zig-0.15.1.md#extern-union) or a [packed union](zig-0.15.1.md#packed-union) which have
guaranteed in-memory layout.
[Accessing the non-active field](zig-0.15.1.md#Wrong-Union-Field-Access) is
safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior):

<figure>
<pre><code>const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test &quot;simple union&quot; {
    var payload = Payload{ .int = 1234 };
    payload.float = 12.34;
}</code></pre>
<figcaption>test_wrong_union_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wrong_union_access.zig
1/1 test_wrong_union_access.test.simple union...thread 1095042 panic: access of union field &#39;float&#39; while field &#39;int&#39; is active
/home/andy/dev/zig/doc/langref/test_wrong_union_access.zig:8:12: 0x102c083 in test.simple union (test_wrong_union_access.zig)
    payload.float = 12.34;
           ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cd90 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155fb1 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fd4d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f5e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/ba4ad6352a6237c381e8f15c2b46bcd6/test --seed=0x8b6eed28</code></pre>
<figcaption>Shell</figcaption>
</figure>

You can activate another field by assigning the entire union:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test &quot;simple union&quot; {
    var payload = Payload{ .int = 1234 };
    try expect(payload.int == 1234);
    payload = Payload{ .float = 12.34 };
    try expect(payload.float == 12.34);
}</code></pre>
<figcaption>test_simple_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_simple_union.zig
1/1 test_simple_union.test.simple union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In order to use [switch](zig-0.15.1.md#switch) with a union, it must be a [Tagged union](zig-0.15.1.md#Tagged-union).

To initialize a union when the tag is a [comptime](zig-0.15.1.md#comptime)-known name, see [@unionInit](zig-0.15.1.md#unionInit).

### [Tagged union](zig-0.15.1.md#toc-Tagged-union) <a href="zig-0.15.1.md#Tagged-union" class="hdr">§</a>

Unions can be declared with an enum tag type.
This turns the union into a *tagged* union, which makes it eligible
to use with [switch](zig-0.15.1.md#switch) expressions.
Tagged unions coerce to their tag type: [Type Coercion: Unions and Enums](zig-0.15.1.md#Type-Coercion-Unions-and-Enums).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test &quot;switch on tagged union&quot; {
    const c = ComplexType{ .ok = 42 };
    try expect(@as(ComplexTypeTag, c) == ComplexTypeTag.ok);

    switch (c) {
        .ok =&gt; |value| try expect(value == 42),
        .not_ok =&gt; unreachable,
    }
}

test &quot;get tag type&quot; {
    try expect(std.meta.Tag(ComplexType) == ComplexTypeTag);
}</code></pre>
<figcaption>test_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagged_union.zig
1/2 test_tagged_union.test.switch on tagged union...OK
2/2 test_tagged_union.test.get tag type...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In order to modify the payload of a tagged union in a switch expression,
place a `*` before the variable name to make it a pointer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test &quot;modify tagged union in switch&quot; {
    var c = ComplexType{ .ok = 42 };

    switch (c) {
        ComplexTypeTag.ok =&gt; |*value| value.* += 1,
        ComplexTypeTag.not_ok =&gt; unreachable,
    }

    try expect(c.ok == 43);
}</code></pre>
<figcaption>test_switch_modify_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_modify_tagged_union.zig
1/1 test_switch_modify_tagged_union.test.modify tagged union in switch...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Unions can be made to infer the enum tag type.
Further, unions can have methods just like structs and enums.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Variant = union(enum) {
    int: i32,
    boolean: bool,

    // void can be omitted when inferring enum tag type.
    none,

    fn truthy(self: Variant) bool {
        return switch (self) {
            Variant.int =&gt; |x_int| x_int != 0,
            Variant.boolean =&gt; |x_bool| x_bool,
            Variant.none =&gt; false,
        };
    }
};

test &quot;union method&quot; {
    var v1: Variant = .{ .int = 1 };
    var v2: Variant = .{ .boolean = false };
    var v3: Variant = .none;

    try expect(v1.truthy());
    try expect(!v2.truthy());
    try expect(!v3.truthy());
}</code></pre>
<figcaption>test_union_method.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_union_method.zig
1/1 test_union_method.test.union method...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Unions with inferred enum tag types can also assign ordinal values to their inferred tag.
This requires the tag to specify an explicit integer type.
[@intFromEnum](zig-0.15.1.md#intFromEnum) can be used to access the ordinal value corresponding to the active field.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Tagged = union(enum(u32)) {
    int: i64 = 123,
    boolean: bool = 67,
};

test &quot;tag values&quot; {
    const int: Tagged = .{ .int = -40 };
    try expect(@intFromEnum(int) == 123);

    const boolean: Tagged = .{ .boolean = false };
    try expect(@intFromEnum(boolean) == 67);
}</code></pre>
<figcaption>test_tagged_union_with_tag_values.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagged_union_with_tag_values.zig
1/1 test_tagged_union_with_tag_values.test.tag values...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

[@tagName](zig-0.15.1.md#tagName) can be used to return a [comptime](zig-0.15.1.md#comptime)
`[:`<span class="tok-number">`0`</span>`]`<span class="tok-kw">`const`</span>` `<span class="tok-type">`u8`</span> value representing the field name:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Small2 = union(enum) {
    a: i32,
    b: bool,
    c: u8,
};
test &quot;@tagName&quot; {
    try expect(std.mem.eql(u8, @tagName(Small2.a), &quot;a&quot;));
}</code></pre>
<figcaption>test_tagName.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagName.zig
1/1 test_tagName.test.@tagName...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [extern union](zig-0.15.1.md#toc-extern-union) <a href="zig-0.15.1.md#extern-union" class="hdr">§</a>

An <span class="tok-kw">`extern`</span>` `<span class="tok-kw">`union`</span> has memory layout guaranteed to be compatible with
the target C ABI.

See also:

- [extern struct](zig-0.15.1.md#extern-struct)

### [packed union](zig-0.15.1.md#toc-packed-union) <a href="zig-0.15.1.md#packed-union" class="hdr">§</a>

A <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`union`</span> has well-defined in-memory layout and is eligible
to be in a [packed struct](zig-0.15.1.md#packed-struct).

### [Anonymous Union Literals](zig-0.15.1.md#toc-Anonymous-Union-Literals) <a href="zig-0.15.1.md#Anonymous-Union-Literals" class="hdr">§</a>

[Anonymous Struct Literals](zig-0.15.1.md#Anonymous-Struct-Literals) syntax can be used to initialize unions without specifying
the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Number = union {
    int: i32,
    float: f64,
};

test &quot;anonymous union literal syntax&quot; {
    const i: Number = .{ .int = 42 };
    const f = makeNumber();
    try expect(i.int == 42);
    try expect(f.float == 12.34);
}

fn makeNumber() Number {
    return .{ .float = 12.34 };
}</code></pre>
<figcaption>test_anonymous_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_anonymous_union.zig
1/1 test_anonymous_union.test.anonymous union literal syntax...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

