<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Control Flow

Included sections:
- Blocks
- switch
- while
- for
- if
- defer
- unreachable
- noreturn

## [Blocks](../zig-0.15.1.md#toc-Blocks) <a href="../zig-0.15.1.md#Blocks" class="hdr">§</a>

Blocks are used to limit the scope of variable declarations:

<figure>
<pre><code>test &quot;access variable after block scope&quot; {
    {
        var x: i32 = 1;
        _ = &amp;x;
    }
    x += 1;
}</code></pre>
<figcaption>test_blocks.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_blocks.zig
/home/andy/dev/zig/doc/langref/test_blocks.zig:6:5: error: use of undeclared identifier &#39;x&#39;
    x += 1;
    ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Blocks are expressions. When labeled, <span class="tok-kw">`break`</span> can be used
to return a value from the block:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;labeled break from labeled block expression&quot; {
    var y: i32 = 123;

    const x = blk: {
        y += 1;
        break :blk y;
    };
    try expect(x == 124);
    try expect(y == 124);
}</code></pre>
<figcaption>test_labeled_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_labeled_break.zig
1/1 test_labeled_break.test.labeled break from labeled block expression...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Here, `blk` can be any name.

See also:

- [Labeled while](../zig-0.15.1.md#Labeled-while)
- [Labeled for](../zig-0.15.1.md#Labeled-for)

### [Shadowing](../zig-0.15.1.md#toc-Shadowing) <a href="../zig-0.15.1.md#Shadowing" class="hdr">§</a>

[Identifiers](../zig-0.15.1.md#Identifiers) are never allowed to "hide" other identifiers by using the same name:

<figure>
<pre><code>const pi = 3.14;

test &quot;inside test block&quot; {
    // Let&#39;s even go inside another block
    {
        var pi: i32 = 1234;
    }
}</code></pre>
<figcaption>test_shadowing.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_shadowing.zig
/home/andy/dev/zig/doc/langref/test_shadowing.zig:6:13: error: local variable shadows declaration of &#39;pi&#39;
        var pi: i32 = 1234;
            ^~
/home/andy/dev/zig/doc/langref/test_shadowing.zig:1:1: note: declared here
const pi = 3.14;
^~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Because of this, when you read Zig code you can always rely on an identifier to consistently mean
the same thing within the scope it is defined. Note that you can, however, use the same name if
the scopes are separate:

<figure>
<pre><code>test &quot;separate scopes&quot; {
    {
        const pi = 3.14;
        _ = pi;
    }
    {
        var pi: bool = true;
        _ = &amp;pi;
    }
}</code></pre>
<figcaption>test_scopes.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_scopes.zig
1/1 test_scopes.test.separate scopes...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Empty Blocks](../zig-0.15.1.md#toc-Empty-Blocks) <a href="../zig-0.15.1.md#Empty-Blocks" class="hdr">§</a>

An empty block is equivalent to <span class="tok-type">`void`</span>`{}`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test {
    const a = {};
    const b = void{};
    try expect(@TypeOf(a) == void);
    try expect(@TypeOf(b) == void);
    try expect(a == b);
}</code></pre>
<figcaption>test_empty_block.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_empty_block.zig
1/1 test_empty_block.test_0...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [switch](../zig-0.15.1.md#toc-switch) <a href="../zig-0.15.1.md#switch" class="hdr">§</a>

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
of a [Tagged union](../zig-0.15.1.md#Tagged-union). Modifications to the field values can be
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

- [comptime](../zig-0.15.1.md#comptime)
- [enum](../zig-0.15.1.md#enum)
- [@compileError](../zig-0.15.1.md#compileError)
- [Compile Variables](../zig-0.15.1.md#Compile-Variables)

### [Exhaustive Switching](../zig-0.15.1.md#toc-Exhaustive-Switching) <a href="../zig-0.15.1.md#Exhaustive-Switching" class="hdr">§</a>

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

### [Switching with Enum Literals](../zig-0.15.1.md#toc-Switching-with-Enum-Literals) <a href="../zig-0.15.1.md#Switching-with-Enum-Literals" class="hdr">§</a>

[Enum Literals](../zig-0.15.1.md#Enum-Literals) can be useful to use with <span class="tok-kw">`switch`</span> to avoid
repetitively specifying [enum](../zig-0.15.1.md#enum) or [union](../zig-0.15.1.md#union) types:

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

### [Labeled switch](../zig-0.15.1.md#toc-Labeled-switch) <a href="../zig-0.15.1.md#Labeled-switch" class="hdr">§</a>

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
[comptime](../zig-0.15.1.md#comptime)-known, then it can be lowered to an unconditional branch
to the relevant case. Such a branch is perfectly predicted, and hence
typically very fast to execute.

If the operand is runtime-known, each <span class="tok-kw">`continue`</span> can
embed a conditional branch inline (ideally through a jump table), which
allows a CPU to predict its target independently of any other prong. A
loop-based lowering would force every branch through the same dispatch
point, hindering branch prediction.

### [Inline Switch Prongs](../zig-0.15.1.md#toc-Inline-Switch-Prongs) <a href="../zig-0.15.1.md#Inline-Switch-Prongs" class="hdr">§</a>

Switch prongs can be marked as <span class="tok-kw">`inline`</span> to generate
the prong's body for each possible value it could have, making the
captured value [comptime](../zig-0.15.1.md#comptime).

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

- [inline while](../zig-0.15.1.md#inline-while)
- [inline for](../zig-0.15.1.md#inline-for)

## [while](../zig-0.15.1.md#toc-while) <a href="../zig-0.15.1.md#while" class="hdr">§</a>

A while loop is used to repeatedly execute an expression until
some condition is no longer true.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while basic&quot; {
    var i: usize = 0;
    while (i &lt; 10) {
        i += 1;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while.zig
1/1 test_while.test.while basic...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use <span class="tok-kw">`break`</span> to exit a while loop early.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while break&quot; {
    var i: usize = 0;
    while (true) {
        if (i == 10)
            break;
        i += 1;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_break.zig
1/1 test_while_break.test.while break...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use <span class="tok-kw">`continue`</span> to jump back to the beginning of the loop.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while continue&quot; {
    var i: usize = 0;
    while (true) {
        i += 1;
        if (i &lt; 10)
            continue;
        break;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while_continue.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_continue.zig
1/1 test_while_continue.test.while continue...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

While loops support a continue expression which is executed when the loop
is continued. The <span class="tok-kw">`continue`</span> keyword respects this expression.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while loop continue expression&quot; {
    var i: usize = 0;
    while (i &lt; 10) : (i += 1) {}
    try expect(i == 10);
}

test &quot;while loop continue expression, more complicated&quot; {
    var i: usize = 1;
    var j: usize = 1;
    while (i * j &lt; 2000) : ({
        i *= 2;
        j *= 3;
    }) {
        const my_ij = i * j;
        try expect(my_ij &lt; 2000);
    }
}</code></pre>
<figcaption>test_while_continue_expression.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_continue_expression.zig
1/2 test_while_continue_expression.test.while loop continue expression...OK
2/2 test_while_continue_expression.test.while loop continue expression, more complicated...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

While loops are expressions. The result of the expression is the
result of the <span class="tok-kw">`else`</span> clause of a while loop, which is executed when
the condition of the while loop is tested as false.

<span class="tok-kw">`break`</span>, like <span class="tok-kw">`return`</span>, accepts a value
parameter. This is the result of the <span class="tok-kw">`while`</span> expression.
When you <span class="tok-kw">`break`</span> from a while loop, the <span class="tok-kw">`else`</span> branch is not
evaluated.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while else&quot; {
    try expect(rangeHasNumber(0, 10, 5));
    try expect(!rangeHasNumber(0, 10, 15));
}

fn rangeHasNumber(begin: usize, end: usize, number: usize) bool {
    var i = begin;
    return while (i &lt; end) : (i += 1) {
        if (i == number) {
            break true;
        }
    } else false;
}</code></pre>
<figcaption>test_while_else.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_else.zig
1/1 test_while_else.test.while else...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled while](../zig-0.15.1.md#toc-Labeled-while) <a href="../zig-0.15.1.md#Labeled-while" class="hdr">§</a>

When a <span class="tok-kw">`while`</span> loop is labeled, it can be referenced from a <span class="tok-kw">`break`</span>
or <span class="tok-kw">`continue`</span> from within a nested loop:

<figure>
<pre><code>test &quot;nested break&quot; {
    outer: while (true) {
        while (true) {
            break :outer;
        }
    }
}

test &quot;nested continue&quot; {
    var i: usize = 0;
    outer: while (i &lt; 10) : (i += 1) {
        while (true) {
            continue :outer;
        }
    }
}</code></pre>
<figcaption>test_while_nested_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_nested_break.zig
1/2 test_while_nested_break.test.nested break...OK
2/2 test_while_nested_break.test.nested continue...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [while with Optionals](../zig-0.15.1.md#toc-while-with-Optionals) <a href="../zig-0.15.1.md#while-with-Optionals" class="hdr">§</a>

Just like [if](../zig-0.15.1.md#if) expressions, while loops can take an optional as the
condition and capture the payload. When [null](../zig-0.15.1.md#null) is encountered the loop
exits.

When the `|x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Optional Type](../zig-0.15.1.md#Optional-Type).

The <span class="tok-kw">`else`</span> branch is allowed on optional iteration. In this case, it will
be executed on the first null value encountered.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while null capture&quot; {
    var sum1: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| {
        sum1 += value;
    }
    try expect(sum1 == 3);

    // null capture with an else block
    var sum2: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| {
        sum2 += value;
    } else {
        try expect(sum2 == 3);
    }

    // null capture with a continue expression
    var i: u32 = 0;
    var sum3: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| : (i += 1) {
        sum3 += value;
    }
    try expect(i == 3);
}

var numbers_left: u32 = undefined;
fn eventuallyNullSequence() ?u32 {
    return if (numbers_left == 0) null else blk: {
        numbers_left -= 1;
        break :blk numbers_left;
    };
}</code></pre>
<figcaption>test_while_null_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_null_capture.zig
1/1 test_while_null_capture.test.while null capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [while with Error Unions](../zig-0.15.1.md#toc-while-with-Error-Unions) <a href="../zig-0.15.1.md#while-with-Error-Unions" class="hdr">§</a>

Just like [if](../zig-0.15.1.md#if) expressions, while loops can take an error union as
the condition and capture the payload or the error code. When the
condition results in an error code the else branch is evaluated and
the loop is finished.

When the <span class="tok-kw">`else`</span>` |x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Error Union Type](../zig-0.15.1.md#Error-Union-Type).

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while error union capture&quot; {
    var sum1: u32 = 0;
    numbers_left = 3;
    while (eventuallyErrorSequence()) |value| {
        sum1 += value;
    } else |err| {
        try expect(err == error.ReachedZero);
    }
}

var numbers_left: u32 = undefined;

fn eventuallyErrorSequence() anyerror!u32 {
    return if (numbers_left == 0) error.ReachedZero else blk: {
        numbers_left -= 1;
        break :blk numbers_left;
    };
}</code></pre>
<figcaption>test_while_error_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_error_capture.zig
1/1 test_while_error_capture.test.while error union capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline while](../zig-0.15.1.md#toc-inline-while) <a href="../zig-0.15.1.md#inline-while" class="hdr">§</a>

While loops can be inlined. This causes the loop to be unrolled, which
allows the code to do some things which only work at compile time,
such as use types as first class values.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;inline while loop&quot; {
    comptime var i = 0;
    var sum: usize = 0;
    inline while (i &lt; 3) : (i += 1) {
        const T = switch (i) {
            0 =&gt; f32,
            1 =&gt; i8,
            2 =&gt; bool,
            else =&gt; unreachable,
        };
        sum += typeNameLength(T);
    }
    try expect(sum == 9);
}

fn typeNameLength(comptime T: type) usize {
    return @typeName(T).len;
}</code></pre>
<figcaption>test_inline_while.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_while.zig
1/1 test_inline_while.test.inline while loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It is recommended to use <span class="tok-kw">`inline`</span> loops only for one of these reasons:

- You need the loop to execute at [comptime](../zig-0.15.1.md#comptime) for the semantics to work.
- You have a benchmark to prove that forcibly unrolling the loop in this way is measurably faster.

See also:

- [if](../zig-0.15.1.md#if)
- [Optionals](../zig-0.15.1.md#Optionals)
- [Errors](../zig-0.15.1.md#Errors)
- [comptime](../zig-0.15.1.md#comptime)
- [unreachable](../zig-0.15.1.md#unreachable)

## [for](../zig-0.15.1.md#toc-for) <a href="../zig-0.15.1.md#for" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;for basics&quot; {
    const items = [_]i32{ 4, 5, 3, 4, 0 };
    var sum: i32 = 0;

    // For loops iterate over slices and arrays.
    for (items) |value| {
        // Break and continue are supported.
        if (value == 0) {
            continue;
        }
        sum += value;
    }
    try expect(sum == 16);

    // To iterate over a portion of a slice, reslice.
    for (items[0..1]) |value| {
        sum += value;
    }
    try expect(sum == 20);

    // To access the index of iteration, specify a second condition as well
    // as a second capture value.
    var sum2: i32 = 0;
    for (items, 0..) |_, i| {
        try expect(@TypeOf(i) == usize);
        sum2 += @as(i32, @intCast(i));
    }
    try expect(sum2 == 10);

    // To iterate over consecutive integers, use the range syntax.
    // Unbounded range is always a compile error.
    var sum3: usize = 0;
    for (0..5) |i| {
        sum3 += i;
    }
    try expect(sum3 == 10);
}

test &quot;multi object for&quot; {
    const items = [_]usize{ 1, 2, 3 };
    const items2 = [_]usize{ 4, 5, 6 };
    var count: usize = 0;

    // Iterate over multiple objects.
    // All lengths must be equal at the start of the loop, otherwise detectable
    // illegal behavior occurs.
    for (items, items2) |i, j| {
        count += i + j;
    }

    try expect(count == 21);
}

test &quot;for reference&quot; {
    var items = [_]i32{ 3, 4, 2 };

    // Iterate over the slice by reference by
    // specifying that the capture value is a pointer.
    for (&amp;items) |*value| {
        value.* += 1;
    }

    try expect(items[0] == 4);
    try expect(items[1] == 5);
    try expect(items[2] == 3);
}

test &quot;for else&quot; {
    // For allows an else attached to it, the same as a while loop.
    const items = [_]?i32{ 3, 4, null, 5 };

    // For loops can also be used as expressions.
    // Similar to while loops, when you break from a for loop, the else branch is not evaluated.
    var sum: i32 = 0;
    const result = for (items) |value| {
        if (value != null) {
            sum += value.?;
        }
    } else blk: {
        try expect(sum == 12);
        break :blk sum;
    };
    try expect(result == 12);
}</code></pre>
<figcaption>test_for.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_for.zig
1/4 test_for.test.for basics...OK
2/4 test_for.test.multi object for...OK
3/4 test_for.test.for reference...OK
4/4 test_for.test.for else...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled for](../zig-0.15.1.md#toc-Labeled-for) <a href="../zig-0.15.1.md#Labeled-for" class="hdr">§</a>

When a <span class="tok-kw">`for`</span> loop is labeled, it can be referenced from a <span class="tok-kw">`break`</span>
or <span class="tok-kw">`continue`</span> from within a nested loop:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;nested break&quot; {
    var count: usize = 0;
    outer: for (1..6) |_| {
        for (1..6) |_| {
            count += 1;
            break :outer;
        }
    }
    try expect(count == 1);
}

test &quot;nested continue&quot; {
    var count: usize = 0;
    outer: for (1..9) |_| {
        for (1..6) |_| {
            count += 1;
            continue :outer;
        }
    }

    try expect(count == 8);
}</code></pre>
<figcaption>test_for_nested_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_for_nested_break.zig
1/2 test_for_nested_break.test.nested break...OK
2/2 test_for_nested_break.test.nested continue...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline for](../zig-0.15.1.md#toc-inline-for) <a href="../zig-0.15.1.md#inline-for" class="hdr">§</a>

For loops can be inlined. This causes the loop to be unrolled, which
allows the code to do some things which only work at compile time,
such as use types as first class values.
The capture value and iterator value of inlined for loops are
compile-time known.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;inline for loop&quot; {
    const nums = [_]i32{ 2, 4, 6 };
    var sum: usize = 0;
    inline for (nums) |i| {
        const T = switch (i) {
            2 =&gt; f32,
            4 =&gt; i8,
            6 =&gt; bool,
            else =&gt; unreachable,
        };
        sum += typeNameLength(T);
    }
    try expect(sum == 9);
}

fn typeNameLength(comptime T: type) usize {
    return @typeName(T).len;
}</code></pre>
<figcaption>test_inline_for.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_for.zig
1/1 test_inline_for.test.inline for loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It is recommended to use <span class="tok-kw">`inline`</span> loops only for one of these reasons:

- You need the loop to execute at [comptime](../zig-0.15.1.md#comptime) for the semantics to work.
- You have a benchmark to prove that forcibly unrolling the loop in this way is measurably faster.

See also:

- [while](../zig-0.15.1.md#while)
- [comptime](../zig-0.15.1.md#comptime)
- [Arrays](../zig-0.15.1.md#Arrays)
- [Slices](../zig-0.15.1.md#Slices)

## [if](../zig-0.15.1.md#toc-if) <a href="../zig-0.15.1.md#if" class="hdr">§</a>

<figure>
<pre><code>// If expressions have three uses, corresponding to the three types:
// * bool
// * ?T
// * anyerror!T

const expect = @import(&quot;std&quot;).testing.expect;

test &quot;if expression&quot; {
    // If expressions are used instead of a ternary expression.
    const a: u32 = 5;
    const b: u32 = 4;
    const result = if (a != b) 47 else 3089;
    try expect(result == 47);
}

test &quot;if boolean&quot; {
    // If expressions test boolean conditions.
    const a: u32 = 5;
    const b: u32 = 4;
    if (a != b) {
        try expect(true);
    } else if (a == 9) {
        unreachable;
    } else {
        unreachable;
    }
}

test &quot;if error union&quot; {
    // If expressions test for errors.
    // Note the |err| capture on the else.

    const a: anyerror!u32 = 0;
    if (a) |value| {
        try expect(value == 0);
    } else |err| {
        _ = err;
        unreachable;
    }

    const b: anyerror!u32 = error.BadValue;
    if (b) |value| {
        _ = value;
        unreachable;
    } else |err| {
        try expect(err == error.BadValue);
    }

    // The else and |err| capture is strictly required.
    if (a) |value| {
        try expect(value == 0);
    } else |_| {}

    // To check only the error value, use an empty block expression.
    if (b) |_| {} else |err| {
        try expect(err == error.BadValue);
    }

    // Access the value by reference using a pointer capture.
    var c: anyerror!u32 = 3;
    if (c) |*value| {
        value.* = 9;
    } else |_| {
        unreachable;
    }

    if (c) |value| {
        try expect(value == 9);
    } else |_| {
        unreachable;
    }
}</code></pre>
<figcaption>test_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_if.zig
1/3 test_if.test.if expression...OK
2/3 test_if.test.if boolean...OK
3/3 test_if.test.if error union...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [if with Optionals](../zig-0.15.1.md#toc-if-with-Optionals) <a href="../zig-0.15.1.md#if-with-Optionals" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;if optional&quot; {
    // If expressions test for null.

    const a: ?u32 = 0;
    if (a) |value| {
        try expect(value == 0);
    } else {
        unreachable;
    }

    const b: ?u32 = null;
    if (b) |_| {
        unreachable;
    } else {
        try expect(true);
    }

    // The else is not required.
    if (a) |value| {
        try expect(value == 0);
    }

    // To test against null only, use the binary equality operator.
    if (b == null) {
        try expect(true);
    }

    // Access the value by reference using a pointer capture.
    var c: ?u32 = 3;
    if (c) |*value| {
        value.* = 2;
    }

    if (c) |value| {
        try expect(value == 2);
    } else {
        unreachable;
    }
}

test &quot;if error union with optional&quot; {
    // If expressions test for errors before unwrapping optionals.
    // The |optional_value| capture&#39;s type is ?u32.

    const a: anyerror!?u32 = 0;
    if (a) |optional_value| {
        try expect(optional_value.? == 0);
    } else |err| {
        _ = err;
        unreachable;
    }

    const b: anyerror!?u32 = null;
    if (b) |optional_value| {
        try expect(optional_value == null);
    } else |_| {
        unreachable;
    }

    const c: anyerror!?u32 = error.BadValue;
    if (c) |optional_value| {
        _ = optional_value;
        unreachable;
    } else |err| {
        try expect(err == error.BadValue);
    }

    // Access the value by reference by using a pointer capture each time.
    var d: anyerror!?u32 = 3;
    if (d) |*optional_value| {
        if (optional_value.*) |*value| {
            value.* = 9;
        }
    } else |_| {
        unreachable;
    }

    if (d) |optional_value| {
        try expect(optional_value.? == 9);
    } else |_| {
        unreachable;
    }
}</code></pre>
<figcaption>test_if_optionals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_if_optionals.zig
1/2 test_if_optionals.test.if optional...OK
2/2 test_if_optionals.test.if error union with optional...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optionals](../zig-0.15.1.md#Optionals)
- [Errors](../zig-0.15.1.md#Errors)

## [defer](../zig-0.15.1.md#toc-defer) <a href="../zig-0.15.1.md#defer" class="hdr">§</a>

Executes an expression unconditionally at scope exit.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const print = std.debug.print;

fn deferExample() !usize {
    var a: usize = 1;

    {
        defer a = 2;
        a = 1;
    }
    try expect(a == 2);

    a = 5;
    return a;
}

test &quot;defer basics&quot; {
    try expect((try deferExample()) == 5);
}</code></pre>
<figcaption>test_defer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_defer.zig
1/1 test_defer.test.defer basics...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Defer expressions are evaluated in reverse order.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const print = std.debug.print;

pub fn main() void {
    print(&quot;\n&quot;, .{});

    defer {
        print(&quot;1 &quot;, .{});
    }
    defer {
        print(&quot;2 &quot;, .{});
    }
    if (false) {
        // defers are not run if they are never executed.
        defer {
            print(&quot;3 &quot;, .{});
        }
    }
}</code></pre>
<figcaption>defer_unwind.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe defer_unwind.zig
$ ./defer_unwind

2 1</code></pre>
<figcaption>Shell</figcaption>
</figure>

Inside a defer expression the return statement is not allowed.

<figure>
<pre><code>fn deferInvalidExample() !void {
    defer {
        return error.DeferError;
    }

    return error.DeferError;
}</code></pre>
<figcaption>test_invalid_defer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_invalid_defer.zig
/home/andy/dev/zig/doc/langref/test_invalid_defer.zig:3:9: error: cannot return from defer expression
        return error.DeferError;
        ^~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_invalid_defer.zig:2:5: note: defer expression here
    defer {
    ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Errors](../zig-0.15.1.md#Errors)

## [unreachable](../zig-0.15.1.md#toc-unreachable) <a href="../zig-0.15.1.md#unreachable" class="hdr">§</a>

In [Debug](../zig-0.15.1.md#Debug) and [ReleaseSafe](../zig-0.15.1.md#ReleaseSafe) mode
<span class="tok-kw">`unreachable`</span> emits a call to `panic` with the message `reached unreachable code`.

In [ReleaseFast](../zig-0.15.1.md#ReleaseFast) and [ReleaseSmall](../zig-0.15.1.md#ReleaseSmall) mode, the optimizer uses the assumption that <span class="tok-kw">`unreachable`</span> code
will never be hit to perform optimizations.

### [Basics](../zig-0.15.1.md#toc-Basics) <a href="../zig-0.15.1.md#Basics" class="hdr">§</a>

<figure>
<pre><code>// unreachable is used to assert that control flow will never reach a
// particular location:
test &quot;basic math&quot; {
    const x = 1;
    const y = 2;
    if (x + y != 3) {
        unreachable;
    }
}</code></pre>
<figcaption>test_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_unreachable.zig
1/1 test_unreachable.test.basic math...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In fact, this is how `std.debug.assert` is implemented:

<figure>
<pre><code>// This is how std.debug.assert is implemented
fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

// This test will fail because we hit unreachable.
test &quot;this will fail&quot; {
    assert(false);
}</code></pre>
<figcaption>test_assertion_failure.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_assertion_failure.zig
1/1 test_assertion_failure.test.this will fail...thread 1095255 panic: reached unreachable code
/home/andy/dev/zig/doc/langref/test_assertion_failure.zig:3:14: 0x102c039 in assert (test_assertion_failure.zig)
    if (!ok) unreachable; // assertion failure
             ^
/home/andy/dev/zig/doc/langref/test_assertion_failure.zig:8:11: 0x102c00e in test.this will fail (test_assertion_failure.zig)
    assert(false);
          ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cb30 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155d51 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114faed in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f381 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/f18320f47d920de319059b03c14e5385/test --seed=0xba1429fd</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [At Compile-Time](../zig-0.15.1.md#toc-At-Compile-Time) <a href="../zig-0.15.1.md#At-Compile-Time" class="hdr">§</a>

<figure>
<pre><code>const assert = @import(&quot;std&quot;).debug.assert;

test &quot;type of unreachable&quot; {
    comptime {
        // The type of unreachable is noreturn.

        // However this assertion will still fail to compile because
        // unreachable expressions are compile errors.

        assert(@TypeOf(unreachable) == noreturn);
    }
}</code></pre>
<figcaption>test_comptime_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_unreachable.zig
/home/andy/dev/zig/doc/langref/test_comptime_unreachable.zig:10:16: error: unreachable code
        assert(@TypeOf(unreachable) == noreturn);
               ^~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_unreachable.zig:10:24: note: control flow is diverted here
        assert(@TypeOf(unreachable) == noreturn);
                       ^~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Zig Test](../zig-0.15.1.md#Zig-Test)
- [Build Mode](../zig-0.15.1.md#Build-Mode)
- [comptime](../zig-0.15.1.md#comptime)

## [noreturn](../zig-0.15.1.md#toc-noreturn) <a href="../zig-0.15.1.md#noreturn" class="hdr">§</a>

<span class="tok-type">`noreturn`</span> is the type of:

- <span class="tok-kw">`break`</span>
- <span class="tok-kw">`continue`</span>
- <span class="tok-kw">`return`</span>
- <span class="tok-kw">`unreachable`</span>
- <span class="tok-kw">`while`</span>` (`<span class="tok-null">`true`</span>`) {}`

When resolving types together, such as <span class="tok-kw">`if`</span> clauses or <span class="tok-kw">`switch`</span> prongs,
the <span class="tok-type">`noreturn`</span> type is compatible with every other type. Consider:

<figure>
<pre><code>fn foo(condition: bool, b: u32) void {
    const a = if (condition) b else return;
    _ = a;
    @panic(&quot;do something with a&quot;);
}
test &quot;noreturn&quot; {
    foo(false, 1);
}</code></pre>
<figcaption>test_noreturn.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_noreturn.zig
1/1 test_noreturn.test.noreturn...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Another use case for <span class="tok-type">`noreturn`</span> is the `exit` function:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const native_arch = builtin.cpu.arch;
const expect = std.testing.expect;

const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .{ .x86_stdcall = .{} } else .c;
extern &quot;kernel32&quot; fn ExitProcess(exit_code: c_uint) callconv(WINAPI) noreturn;

test &quot;foo&quot; {
    const value = bar() catch ExitProcess(1);
    try expect(value == 1234);
}

fn bar() anyerror!u32 {
    return 1234;
}</code></pre>
<figcaption>test_noreturn_from_exit.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_noreturn_from_exit.zig -target x86_64-windows --test-no-exec</code></pre>
<figcaption>Shell</figcaption>
</figure>


