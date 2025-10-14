<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: switch -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [switch](zig-0.15.1.md#toc-switch) <a href="zig-0.15.1.md#switch" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;

test &quot;switch simple&quot; {
    const a: u64 = 10;
    const zz: u64 = 103;

    // All branches of a switch expression must be able to be coerced to a
    // common type.
    //
    // Branches cannot fallthrough. If fallthrough behavior is desired, combine
    // the cases and use an if.
    const b = switch (a) {
        // Multiple cases can be combined via a &#39;,&#39;
        1, 2, 3 =&gt; 0,

        // Ranges can be specified using the ... syntax. These are inclusive
        // of both ends.
        5...100 =&gt; 1,

        // Branches can be arbitrarily complex.
        101 =&gt; blk: {
            const c: u64 = 5;
            break :blk c * 2 + 1;
        },

        // Switching on arbitrary expressions is allowed as long as the
        // expression is known at compile-time.
        zz =&gt; zz,
        blk: {
            const d: u32 = 5;
            const e: u32 = 100;
            break :blk d + e;
        } =&gt; 107,

        // The else branch catches everything not already captured.
        // Else branches are mandatory unless the entire range of values
        // is handled.
        else =&gt; 9,
    };

    try expect(b == 1);
}

// Switch expressions can be used outside a function:
const os_msg = switch (builtin.target.os.tag) {
    .linux =&gt; &quot;we found a linux user&quot;,
    else =&gt; &quot;not a linux user&quot;,
};

// Inside a function, switch statements implicitly are compile-time
// evaluated if the target expression is compile-time known.
test &quot;switch inside function&quot; {
    switch (builtin.target.os.tag) {
        .fuchsia =&gt; {
            // On an OS other than fuchsia, block is not even analyzed,
            // so this compile error is not triggered.
            // On fuchsia this compile error would be triggered.
            @compileError(&quot;fuchsia not supported&quot;);
        },
        else =&gt; {},
    }
}</code></pre>
<figcaption>test_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch.zig
1/2 test_switch.test.switch simple...OK
2/2 test_switch.test.switch inside function...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-kw">`switch`</span> can be used to capture the field values
of a [Tagged union](zig-0.15.1.md#Tagged-union). Modifications to the field values can be
done by placing a `*` before the capture variable name,
turning it into a pointer.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;switch on tagged union&quot; {
    const Point = struct {
        x: u8,
        y: u8,
    };
    const Item = union(enum) {
        a: u32,
        c: Point,
        d,
        e: u32,
    };

    var a = Item{ .c = Point{ .x = 1, .y = 2 } };

    // Switching on more complex enums is allowed.
    const b = switch (a) {
        // A capture group is allowed on a match, and will return the enum
        // value matched. If the payload types of both cases are the same
        // they can be put into the same switch prong.
        Item.a, Item.e =&gt; |item| item,

        // A reference to the matched value can be obtained using `*` syntax.
        Item.c =&gt; |*item| blk: {
            item.*.x += 1;
            break :blk 6;
        },

        // No else is required if the types cases was exhaustively handled
        Item.d =&gt; 8,
    };

    try expect(b == 6);
    try expect(a.c.x == 2);
}</code></pre>
<figcaption>test_switch_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_tagged_union.zig
1/1 test_switch_tagged_union.test.switch on tagged union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [comptime](zig-0.15.1.md#comptime)
- [enum](zig-0.15.1.md#enum)
- [@compileError](zig-0.15.1.md#compileError)
- [Compile Variables](zig-0.15.1.md#Compile-Variables)

### [Exhaustive Switching](zig-0.15.1.md#toc-Exhaustive-Switching) <a href="zig-0.15.1.md#Exhaustive-Switching" class="hdr">§</a>

When a <span class="tok-kw">`switch`</span> expression does not have an <span class="tok-kw">`else`</span> clause,
it must exhaustively list all the possible values. Failure to do so is a compile error:

<figure>
<pre><code>const Color = enum {
    auto,
    off,
    on,
};

test &quot;exhaustive switching&quot; {
    const color = Color.off;
    switch (color) {
        Color.auto =&gt; {},
        Color.on =&gt; {},
    }
}</code></pre>
<figcaption>test_unhandled_enumeration_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_unhandled_enumeration_value.zig
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:9:5: error: switch must handle all possibilities
    switch (color) {
    ^~~~~~
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:3:5: note: unhandled enumeration value: &#39;off&#39;
    off,
    ^~~
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:1:15: note: enum &#39;test_unhandled_enumeration_value.Color&#39; declared here
const Color = enum {
              ^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Switching with Enum Literals](zig-0.15.1.md#toc-Switching-with-Enum-Literals) <a href="zig-0.15.1.md#Switching-with-Enum-Literals" class="hdr">§</a>

[Enum Literals](zig-0.15.1.md#Enum-Literals) can be useful to use with <span class="tok-kw">`switch`</span> to avoid
repetitively specifying [enum](zig-0.15.1.md#enum) or [union](zig-0.15.1.md#union) types:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Color = enum {
    auto,
    off,
    on,
};

test &quot;enum literals with switch&quot; {
    const color = Color.off;
    const result = switch (color) {
        .auto =&gt; false,
        .on =&gt; false,
        .off =&gt; true,
    };
    try expect(result);
}</code></pre>
<figcaption>test_exhaustive_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_exhaustive_switch.zig
1/1 test_exhaustive_switch.test.enum literals with switch...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled switch](zig-0.15.1.md#toc-Labeled-switch) <a href="zig-0.15.1.md#Labeled-switch" class="hdr">§</a>

When a switch statement is labeled, it can be referenced from a
<span class="tok-kw">`break`</span> or <span class="tok-kw">`continue`</span>.
<span class="tok-kw">`break`</span> will return a value from the <span class="tok-kw">`switch`</span>.

A <span class="tok-kw">`continue`</span> targeting a switch must have an
operand. When executed, it will jump to the matching prong, as if the
<span class="tok-kw">`switch`</span> were executed again with the <span class="tok-kw">`continue`</span>'s operand replacing the initial switch value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;switch continue&quot; {
    sw: switch (@as(i32, 5)) {
        5 =&gt; continue :sw 4,

        // `continue` can occur multiple times within a single switch prong.
        2...4 =&gt; |v| {
            if (v &gt; 3) {
                continue :sw 2;
            } else if (v == 3) {

                // `break` can target labeled loops.
                break :sw;
            }

            continue :sw 1;
        },

        1 =&gt; return,

        else =&gt; unreachable,
    }
}</code></pre>
<figcaption>test_switch_continue.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_continue.zig
1/1 test_switch_continue.test.switch continue...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Semantically, this is equivalent to the following loop:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;switch continue, equivalent loop&quot; {
    var sw: i32 = 5;
    while (true) {
        switch (sw) {
            5 =&gt; {
                sw = 4;
                continue;
            },
            2...4 =&gt; |v| {
                if (v &gt; 3) {
                    sw = 2;
                    continue;
                } else if (v == 3) {
                    break;
                }

                sw = 1;
                continue;
            },
            1 =&gt; return,
            else =&gt; unreachable,
        }
    }
}</code></pre>
<figcaption>test_switch_continue_equivalent.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_continue_equivalent.zig
1/1 test_switch_continue_equivalent.test.switch continue, equivalent loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This can improve clarity of (for example) state machines, where the syntax <span class="tok-kw">`continue`</span>` :sw .next_state` is unambiguous, explicit, and immediately understandable.

However, the motivating example is a switch on each element of an array, where using a single switch can improve clarity and performance:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

const Instruction = enum {
    add,
    mul,
    end,
};

fn evaluate(initial_stack: []const i32, code: []const Instruction) !i32 {
    var buffer: [8]i32 = undefined;
    var stack = std.ArrayListUnmanaged(i32).initBuffer(&amp;buffer);
    try stack.appendSliceBounded(initial_stack);
    var ip: usize = 0;

    return vm: switch (code[ip]) {
        // Because all code after `continue` is unreachable, this branch does
        // not provide a result.
        .add =&gt; {
            try stack.appendBounded(stack.pop().? + stack.pop().?);

            ip += 1;
            continue :vm code[ip];
        },
        .mul =&gt; {
            try stack.appendBounded(stack.pop().? * stack.pop().?);

            ip += 1;
            continue :vm code[ip];
        },
        .end =&gt; stack.pop().?,
    };
}

test &quot;evaluate&quot; {
    const result = try evaluate(&amp;.{ 7, 2, -3 }, &amp;.{ .mul, .add, .end });
    try expectEqual(1, result);
}</code></pre>
<figcaption>test_switch_dispatch_loop.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_dispatch_loop.zig
1/1 test_switch_dispatch_loop.test.evaluate...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

If the operand to <span class="tok-kw">`continue`</span> is
[comptime](zig-0.15.1.md#comptime)-known, then it can be lowered to an unconditional branch
to the relevant case. Such a branch is perfectly predicted, and hence
typically very fast to execute.

If the operand is runtime-known, each <span class="tok-kw">`continue`</span> can
embed a conditional branch inline (ideally through a jump table), which
allows a CPU to predict its target independently of any other prong. A
loop-based lowering would force every branch through the same dispatch
point, hindering branch prediction.

### [Inline Switch Prongs](zig-0.15.1.md#toc-Inline-Switch-Prongs) <a href="zig-0.15.1.md#Inline-Switch-Prongs" class="hdr">§</a>

Switch prongs can be marked as <span class="tok-kw">`inline`</span> to generate
the prong's body for each possible value it could have, making the
captured value [comptime](zig-0.15.1.md#comptime).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const expectError = std.testing.expectError;

fn isFieldOptional(comptime T: type, field_index: usize) !bool {
    const fields = @typeInfo(T).@&quot;struct&quot;.fields;
    return switch (field_index) {
        // This prong is analyzed twice with `idx` being a
        // comptime-known value each time.
        inline 0, 1 =&gt; |idx| @typeInfo(fields[idx].type) == .optional,
        else =&gt; return error.IndexOutOfBounds,
    };
}

const Struct1 = struct { a: u32, b: ?u32 };

test &quot;using @typeInfo with runtime values&quot; {
    var index: usize = 0;
    try expect(!try isFieldOptional(Struct1, index));
    index += 1;
    try expect(try isFieldOptional(Struct1, index));
    index += 1;
    try expectError(error.IndexOutOfBounds, isFieldOptional(Struct1, index));
}

// Calls to `isFieldOptional` on `Struct1` get unrolled to an equivalent
// of this function:
fn isFieldOptionalUnrolled(field_index: usize) !bool {
    return switch (field_index) {
        0 =&gt; false,
        1 =&gt; true,
        else =&gt; return error.IndexOutOfBounds,
    };
}</code></pre>
<figcaption>test_inline_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_switch.zig
1/1 test_inline_switch.test.using @typeInfo with runtime values...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The <span class="tok-kw">`inline`</span> keyword may also be combined with ranges:

<figure>
<pre><code>fn isFieldOptional(comptime T: type, field_index: usize) !bool {
    const fields = @typeInfo(T).@&quot;struct&quot;.fields;
    return switch (field_index) {
        inline 0...fields.len - 1 =&gt; |idx| @typeInfo(fields[idx].type) == .optional,
        else =&gt; return error.IndexOutOfBounds,
    };
}</code></pre>
<figcaption>inline_prong_range.zig</figcaption>
</figure>

<span class="tok-kw">`inline`</span>` `<span class="tok-kw">`else`</span> prongs can be used as a type safe
alternative to <span class="tok-kw">`inline`</span>` `<span class="tok-kw">`for`</span> loops:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const SliceTypeA = extern struct {
    len: usize,
    ptr: [*]u32,
};
const SliceTypeB = extern struct {
    ptr: [*]SliceTypeA,
    len: usize,
};
const AnySlice = union(enum) {
    a: SliceTypeA,
    b: SliceTypeB,
    c: []const u8,
    d: []AnySlice,
};

fn withFor(any: AnySlice) usize {
    const Tag = @typeInfo(AnySlice).@&quot;union&quot;.tag_type.?;
    inline for (@typeInfo(Tag).@&quot;enum&quot;.fields) |field| {
        // With `inline for` the function gets generated as
        // a series of `if` statements relying on the optimizer
        // to convert it to a switch.
        if (field.value == @intFromEnum(any)) {
            return @field(any, field.name).len;
        }
    }
    // When using `inline for` the compiler doesn&#39;t know that every
    // possible case has been handled requiring an explicit `unreachable`.
    unreachable;
}

fn withSwitch(any: AnySlice) usize {
    return switch (any) {
        // With `inline else` the function is explicitly generated
        // as the desired switch and the compiler can check that
        // every possible case is handled.
        inline else =&gt; |slice| slice.len,
    };
}

test &quot;inline for and inline else similarity&quot; {
    const any = AnySlice{ .c = &quot;hello&quot; };
    try expect(withFor(any) == 5);
    try expect(withSwitch(any) == 5);
}</code></pre>
<figcaption>test_inline_else.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_else.zig
1/1 test_inline_else.test.inline for and inline else similarity...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When using an inline prong switching on an union an additional
capture can be used to obtain the union's enum tag value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const U = union(enum) {
    a: u32,
    b: f32,
};

fn getNum(u: U) u32 {
    switch (u) {
        // Here `num` is a runtime-known value that is either
        // `u.a` or `u.b` and `tag` is `u`&#39;s comptime-known tag value.
        inline else =&gt; |num, tag| {
            if (tag == .b) {
                return @intFromFloat(num);
            }
            return num;
        },
    }
}

test &quot;test&quot; {
    const u = U{ .b = 42 };
    try expect(getNum(u) == 42);
}</code></pre>
<figcaption>test_inline_switch_union_tag.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_switch_union_tag.zig
1/1 test_inline_switch_union_tag.test.test...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [inline while](zig-0.15.1.md#inline-while)
- [inline for](zig-0.15.1.md#inline-for)

