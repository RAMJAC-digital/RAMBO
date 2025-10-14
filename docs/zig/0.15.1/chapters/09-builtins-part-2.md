<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Builtins (Part 2)

Included sections:
- Builtin Functions

### [@ptrCast](../zig-0.15.1.md#toc-ptrCast) <a href="../zig-0.15.1.md#ptrCast" class="hdr">§</a>

    @ptrCast(value: anytype) anytype

Converts a pointer of one type to a pointer of another type. The return type is the inferred result type.

[Optional Pointers](../zig-0.15.1.md#Optional-Pointers) are allowed. Casting an optional pointer which is [null](../zig-0.15.1.md#null)
to a non-optional pointer invokes safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

<span class="tok-builtin">`@ptrCast`</span> cannot be used for:

- Removing <span class="tok-kw">`const`</span> qualifier, use [@constCast](../zig-0.15.1.md#constCast).
- Removing <span class="tok-kw">`volatile`</span> qualifier, use [@volatileCast](../zig-0.15.1.md#volatileCast).
- Changing pointer address space, use [@addrSpaceCast](../zig-0.15.1.md#addrSpaceCast).
- Increasing pointer alignment, use [@alignCast](../zig-0.15.1.md#alignCast).
- Casting a non-slice pointer to a slice, use slicing syntax `ptr[start..end]`.


### [@ptrFromInt](../zig-0.15.1.md#toc-ptrFromInt) <a href="../zig-0.15.1.md#ptrFromInt" class="hdr">§</a>

    @ptrFromInt(address: usize) anytype

Converts an integer to a [pointer](../zig-0.15.1.md#Pointers). The return type is the inferred result type.
To convert the other way, use [@intFromPtr](../zig-0.15.1.md#intFromPtr). Casting an address of 0 to a destination type
which in not [optional](../zig-0.15.1.md#Optional-Pointers) and does not have the <span class="tok-kw">`allowzero`</span> attribute will result in a
[Pointer Cast Invalid Null](../zig-0.15.1.md#Pointer-Cast-Invalid-Null) panic when runtime safety checks are enabled.

If the destination pointer type does not allow address zero and `address`
is zero, this invokes safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).


### [@rem](../zig-0.15.1.md#toc-rem) <a href="../zig-0.15.1.md#rem" class="hdr">§</a>

    @rem(numerator: T, denominator: T) T

Remainder division. For unsigned integers this is the same as
`numerator % denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span>, otherwise the
operation will result in a [Remainder Division by Zero](../zig-0.15.1.md#Remainder-Division-by-Zero) when runtime safety checks are enabled.

- <span class="tok-builtin">`@rem`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`2`</span>
- `(`<span class="tok-builtin">`@divTrunc`</span>`(a, b) * b) + `<span class="tok-builtin">`@rem`</span>`(a, b) == a`

For a function that returns an error code, see <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.rem`.

See also:

- [@mod](../zig-0.15.1.md#mod)


### [@returnAddress](../zig-0.15.1.md#toc-returnAddress) <a href="../zig-0.15.1.md#returnAddress" class="hdr">§</a>

    @returnAddress() usize

This function returns the address of the next machine code instruction that will be executed
when the current function returns.

The implications of this are target-specific and not consistent across
all platforms.

This function is only valid within function scope. If the function gets inlined into
a calling function, the returned address will apply to the calling function.


### [@select](../zig-0.15.1.md#toc-select) <a href="../zig-0.15.1.md#select" class="hdr">§</a>

    @select(comptime T: type, pred: @Vector(len, bool), a: @Vector(len, T), b: @Vector(len, T)) @Vector(len, T)

Selects values element-wise from `a` or `b` based on `pred`. If `pred[i]` is <span class="tok-null">`true`</span>, the corresponding element in the result will be `a[i]` and otherwise `b[i]`.

See also:

- [Vectors](../zig-0.15.1.md#Vectors)


### [@setEvalBranchQuota](../zig-0.15.1.md#toc-setEvalBranchQuota) <a href="../zig-0.15.1.md#setEvalBranchQuota" class="hdr">§</a>

    @setEvalBranchQuota(comptime new_quota: u32) void

Increase the maximum number of backwards branches that compile-time code
execution can use before giving up and making a compile error.

If the `new_quota` is smaller than the default quota (<span class="tok-number">`1000`</span>) or
a previously explicitly set quota, it is ignored.

Example:

<figure>
<pre><code>test &quot;foo&quot; {
    comptime {
        var i = 0;
        while (i &lt; 1001) : (i += 1) {}
    }
}</code></pre>
<figcaption>test_without_setEvalBranchQuota_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_without_setEvalBranchQuota_builtin.zig
/home/andy/dev/zig/doc/langref/test_without_setEvalBranchQuota_builtin.zig:4:9: error: evaluation exceeded 1000 backwards branches
        while (i &lt; 1001) : (i += 1) {}
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_without_setEvalBranchQuota_builtin.zig:4:9: note: use @setEvalBranchQuota() to raise the branch limit from 1000
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Now we use <span class="tok-builtin">`@setEvalBranchQuota`</span>:

<figure>
<pre><code>test &quot;foo&quot; {
    comptime {
        @setEvalBranchQuota(1001);
        var i = 0;
        while (i &lt; 1001) : (i += 1) {}
    }
}</code></pre>
<figcaption>test_setEvalBranchQuota_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_setEvalBranchQuota_builtin.zig
1/1 test_setEvalBranchQuota_builtin.test.foo...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [comptime](../zig-0.15.1.md#comptime)


### [@setFloatMode](../zig-0.15.1.md#toc-setFloatMode) <a href="../zig-0.15.1.md#setFloatMode" class="hdr">§</a>

    @setFloatMode(comptime mode: FloatMode) void

Changes the current scope's rules about how floating point operations are defined.

- `Strict` (default) - Floating point operations follow strict IEEE compliance.
- `Optimized` - Floating point operations may do all of the following:
  - Assume the arguments and result are not NaN. Optimizations are required to retain legal behavior over NaNs, but the value of the result is undefined.
  - Assume the arguments and result are not +/-Inf. Optimizations are required to retain legal behavior over +/-Inf, but the value of the result is undefined.
  - Treat the sign of a zero argument or result as insignificant.
  - Use the reciprocal of an argument rather than perform division.
  - Perform floating-point contraction (e.g. fusing a multiply followed by an addition into a fused multiply-add).
  - Perform algebraically equivalent transformations that may change results in floating point (e.g. reassociate).

  This is equivalent to `-ffast-math` in GCC.

The floating point mode is inherited by child scopes, and can be overridden in any scope.
You can set the floating point mode in a struct or module scope by using a comptime block.

`FloatMode` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.FloatMode`.

See also:

- [Floating Point Operations](../zig-0.15.1.md#Floating-Point-Operations)


### [@setRuntimeSafety](../zig-0.15.1.md#toc-setRuntimeSafety) <a href="../zig-0.15.1.md#setRuntimeSafety" class="hdr">§</a>

    @setRuntimeSafety(comptime safety_on: bool) void

Sets whether runtime safety checks are enabled for the scope that contains the function call.

<figure>
<pre><code>test &quot;@setRuntimeSafety&quot; {
    // The builtin applies to the scope that it is called in. So here, integer overflow
    // will not be caught in ReleaseFast and ReleaseSmall modes:
    // var x: u8 = 255;
    // x += 1; // Unchecked Illegal Behavior in ReleaseFast/ReleaseSmall modes.
    {
        // However this block has safety enabled, so safety checks happen here,
        // even in ReleaseFast and ReleaseSmall modes.
        @setRuntimeSafety(true);
        var x: u8 = 255;
        x += 1;

        {
            // The value can be overridden at any scope. So here integer overflow
            // would not be caught in any build mode.
            @setRuntimeSafety(false);
            // var x: u8 = 255;
            // x += 1; // Unchecked Illegal Behavior in all build modes.
        }
    }
}</code></pre>
<figcaption>test_setRuntimeSafety_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_setRuntimeSafety_builtin.zig -OReleaseFast
1/1 test_setRuntimeSafety_builtin.test.@setRuntimeSafety...thread 1101377 panic: integer overflow
/home/andy/dev/zig/doc/langref/test_setRuntimeSafety_builtin.zig:11:11: 0x103eb98 in test.@setRuntimeSafety (test)
        x += 1;
          ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x10323df in main (test)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x102ff7d in posixCallMainAndExit (test)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x102fa7d in _start (test)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/2d6906f7b8821b0f5d6faa657d7405fc/test --seed=0xbd188e37</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note: it is [planned](https://github.com/ziglang/zig/issues/978) to replace
<span class="tok-builtin">`@setRuntimeSafety`</span> with `@optimizeFor`


### [@shlExact](../zig-0.15.1.md#toc-shlExact) <a href="../zig-0.15.1.md#shlExact" class="hdr">§</a>

    @shlExact(value: T, shift_amt: Log2T) T

Performs the left shift operation (`<<`).
For unsigned integers, the result is [undefined](../zig-0.15.1.md#undefined) if any 1 bits
are shifted out. For signed integers, the result is [undefined](../zig-0.15.1.md#undefined) if
any bits that disagree with the resultant sign bit are shifted out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

<span class="tok-type">`comptime_int`</span> is modeled as an integer with an infinite number of bits,
meaning that in such case, <span class="tok-builtin">`@shlExact`</span> always produces a result and
cannot produce a compile error.

See also:

- [@shrExact](../zig-0.15.1.md#shrExact)
- [@shlWithOverflow](../zig-0.15.1.md#shlWithOverflow)


### [@shlWithOverflow](../zig-0.15.1.md#toc-shlWithOverflow) <a href="../zig-0.15.1.md#shlWithOverflow" class="hdr">§</a>

    @shlWithOverflow(a: anytype, shift_amt: Log2T) struct { @TypeOf(a), u1 }

Performs `a << b` and returns a tuple with the result and a possible overflow bit.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits` triggers safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

See also:

- [@shlExact](../zig-0.15.1.md#shlExact)
- [@shrExact](../zig-0.15.1.md#shrExact)


### [@shrExact](../zig-0.15.1.md#toc-shrExact) <a href="../zig-0.15.1.md#shrExact" class="hdr">§</a>

    @shrExact(value: T, shift_amt: Log2T) T

Performs the right shift operation (`>>`). Caller guarantees
that the shift will not shift any 1 bits out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

See also:

- [@shlExact](../zig-0.15.1.md#shlExact)
- [@shlWithOverflow](../zig-0.15.1.md#shlWithOverflow)


### [@shuffle](../zig-0.15.1.md#toc-shuffle) <a href="../zig-0.15.1.md#shuffle" class="hdr">§</a>

    @shuffle(comptime E: type, a: @Vector(a_len, E), b: @Vector(b_len, E), comptime mask: @Vector(mask_len, i32)) @Vector(mask_len, E)

Constructs a new [vector](../zig-0.15.1.md#Vectors) by selecting elements from `a` and
`b` based on `mask`.

Each element in `mask` selects an element from either `a` or
`b`. Positive numbers select from `a` starting at 0.
Negative values select from `b`, starting at `-`<span class="tok-number">`1`</span> and going down.
It is recommended to use the `~` operator for indexes from `b`
so that both indexes can start from <span class="tok-number">`0`</span> (i.e. `~`<span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`i32`</span>`, `<span class="tok-number">`0`</span>`)` is
`-`<span class="tok-number">`1`</span>).

For each element of `mask`, if it or the selected value from
`a` or `b` is <span class="tok-null">`undefined`</span>,
then the resulting element is <span class="tok-null">`undefined`</span>.

`a_len` and `b_len` may differ in length. Out-of-bounds element
indexes in `mask` result in compile errors.

If `a` or `b` is <span class="tok-null">`undefined`</span>, it
is equivalent to a vector of all <span class="tok-null">`undefined`</span> with the same length as the other vector.
If both vectors are <span class="tok-null">`undefined`</span>, <span class="tok-builtin">`@shuffle`</span> returns
a vector with all elements <span class="tok-null">`undefined`</span>.

`E` must be an [integer](../zig-0.15.1.md#Integers), [float](../zig-0.15.1.md#Floats),
[pointer](../zig-0.15.1.md#Pointers), or <span class="tok-type">`bool`</span>. The mask may be any vector length, and its
length determines the result length.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @shuffle&quot; {
    const a = @Vector(7, u8){ &#39;o&#39;, &#39;l&#39;, &#39;h&#39;, &#39;e&#39;, &#39;r&#39;, &#39;z&#39;, &#39;w&#39; };
    const b = @Vector(4, u8){ &#39;w&#39;, &#39;d&#39;, &#39;!&#39;, &#39;x&#39; };

    // To shuffle within a single vector, pass undefined as the second argument.
    // Notice that we can re-order, duplicate, or omit elements of the input vector
    const mask1 = @Vector(5, i32){ 2, 3, 1, 1, 0 };
    const res1: @Vector(5, u8) = @shuffle(u8, a, undefined, mask1);
    try expect(std.mem.eql(u8, &amp;@as([5]u8, res1), &quot;hello&quot;));

    // Combining two vectors
    const mask2 = @Vector(6, i32){ -1, 0, 4, 1, -2, -3 };
    const res2: @Vector(6, u8) = @shuffle(u8, a, b, mask2);
    try expect(std.mem.eql(u8, &amp;@as([6]u8, res2), &quot;world!&quot;));
}</code></pre>
<figcaption>test_shuffle_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_shuffle_builtin.zig
1/1 test_shuffle_builtin.test.vector @shuffle...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Vectors](../zig-0.15.1.md#Vectors)


### [@sizeOf](../zig-0.15.1.md#toc-sizeOf) <a href="../zig-0.15.1.md#sizeOf" class="hdr">§</a>

    @sizeOf(comptime T: type) comptime_int

This function returns the number of bytes it takes to store `T` in memory.
The result is a target-specific compile time constant.

This size may contain padding bytes. If there were two consecutive T in memory, the padding would be the offset
in bytes between element at index 0 and the element at index 1. For [integer](../zig-0.15.1.md#Integers),
consider whether you want to use <span class="tok-builtin">`@sizeOf`</span>`(T)` or
<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits`.

This function measures the size at runtime. For types that are disallowed at runtime, such as
<span class="tok-type">`comptime_int`</span> and <span class="tok-type">`type`</span>, the result is <span class="tok-number">`0`</span>.

See also:

- [@bitSizeOf](../zig-0.15.1.md#bitSizeOf)
- [@typeInfo](../zig-0.15.1.md#typeInfo)


### [@splat](../zig-0.15.1.md#toc-splat) <a href="../zig-0.15.1.md#splat" class="hdr">§</a>

    @splat(scalar: anytype) anytype

Produces an array or vector where each element is the value
`scalar`. The return type and thus the length of the
vector is inferred.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @splat&quot; {
    const scalar: u32 = 5;
    const result: @Vector(4, u32) = @splat(scalar);
    try expect(std.mem.eql(u32, &amp;@as([4]u32, result), &amp;[_]u32{ 5, 5, 5, 5 }));
}

test &quot;array @splat&quot; {
    const scalar: u32 = 5;
    const result: [4]u32 = @splat(scalar);
    try expect(std.mem.eql(u32, &amp;@as([4]u32, result), &amp;[_]u32{ 5, 5, 5, 5 }));
}</code></pre>
<figcaption>test_splat_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_splat_builtin.zig
1/2 test_splat_builtin.test.vector @splat...OK
2/2 test_splat_builtin.test.array @splat...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

`scalar` must be an [integer](../zig-0.15.1.md#Integers), [bool](../zig-0.15.1.md#Primitive-Types),
[float](../zig-0.15.1.md#Floats), or [pointer](../zig-0.15.1.md#Pointers).

See also:

- [Vectors](../zig-0.15.1.md#Vectors)
- [@shuffle](../zig-0.15.1.md#shuffle)


### [@reduce](../zig-0.15.1.md#toc-reduce) <a href="../zig-0.15.1.md#reduce" class="hdr">§</a>

    @reduce(comptime op: std.builtin.ReduceOp, value: anytype) E

Transforms a [vector](../zig-0.15.1.md#Vectors) into a scalar value (of type `E`)
by performing a sequential horizontal reduction of its elements using the
specified operator `op`.

Not every operator is available for every vector element type:

- Every operator is available for [integer](../zig-0.15.1.md#Integers) vectors.
- `.And`, `.Or`,
  `.Xor` are additionally available for
  <span class="tok-type">`bool`</span> vectors,
- `.Min`, `.Max`,
  `.Add`, `.Mul` are
  additionally available for [floating point](../zig-0.15.1.md#Floats) vectors,

Note that `.Add` and `.Mul`
reductions on integral types are wrapping; when applied on floating point
types the operation associativity is preserved, unless the float mode is
set to `Optimized`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @reduce&quot; {
    const V = @Vector(4, i32);
    const value = V{ 1, -1, 1, -1 };
    const result = value &gt; @as(V, @splat(0));
    // result is { true, false, true, false };
    try comptime expect(@TypeOf(result) == @Vector(4, bool));
    const is_all_true = @reduce(.And, result);
    try comptime expect(@TypeOf(is_all_true) == bool);
    try expect(is_all_true == false);
}</code></pre>
<figcaption>test_reduce_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_reduce_builtin.zig
1/1 test_reduce_builtin.test.vector @reduce...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Vectors](../zig-0.15.1.md#Vectors)
- [@setFloatMode](../zig-0.15.1.md#setFloatMode)


### [@src](../zig-0.15.1.md#toc-src) <a href="../zig-0.15.1.md#src" class="hdr">§</a>

    @src() std.builtin.SourceLocation

Returns a `SourceLocation` struct representing the function's name and location in the source code. This must be called in a function.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;@src&quot; {
    try doTheTest();
}

fn doTheTest() !void {
    const src = @src();

    try expect(src.line == 9);
    try expect(src.column == 17);
    try expect(std.mem.endsWith(u8, src.fn_name, &quot;doTheTest&quot;));
    try expect(std.mem.endsWith(u8, src.file, &quot;test_src_builtin.zig&quot;));
}</code></pre>
<figcaption>test_src_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_src_builtin.zig
1/1 test_src_builtin.test.@src...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>


### [@sqrt](../zig-0.15.1.md#toc-sqrt) <a href="../zig-0.15.1.md#sqrt" class="hdr">§</a>

    @sqrt(value: anytype) @TypeOf(value)

Performs the square root of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@sin](../zig-0.15.1.md#toc-sin) <a href="../zig-0.15.1.md#sin" class="hdr">§</a>

    @sin(value: anytype) @TypeOf(value)

Sine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@cos](../zig-0.15.1.md#toc-cos) <a href="../zig-0.15.1.md#cos" class="hdr">§</a>

    @cos(value: anytype) @TypeOf(value)

Cosine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@tan](../zig-0.15.1.md#toc-tan) <a href="../zig-0.15.1.md#tan" class="hdr">§</a>

    @tan(value: anytype) @TypeOf(value)

Tangent trigonometric function on a floating point number in radians.
Uses a dedicated hardware instruction when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@exp](../zig-0.15.1.md#toc-exp) <a href="../zig-0.15.1.md#exp" class="hdr">§</a>

    @exp(value: anytype) @TypeOf(value)

Base-e exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@exp2](../zig-0.15.1.md#toc-exp2) <a href="../zig-0.15.1.md#exp2" class="hdr">§</a>

    @exp2(value: anytype) @TypeOf(value)

Base-2 exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@log](../zig-0.15.1.md#toc-log) <a href="../zig-0.15.1.md#log" class="hdr">§</a>

    @log(value: anytype) @TypeOf(value)

Returns the natural logarithm of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@log2](../zig-0.15.1.md#toc-log2) <a href="../zig-0.15.1.md#log2" class="hdr">§</a>

    @log2(value: anytype) @TypeOf(value)

Returns the logarithm to the base 2 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@log10](../zig-0.15.1.md#toc-log10) <a href="../zig-0.15.1.md#log10" class="hdr">§</a>

    @log10(value: anytype) @TypeOf(value)

Returns the logarithm to the base 10 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@abs](../zig-0.15.1.md#toc-abs) <a href="../zig-0.15.1.md#abs" class="hdr">§</a>

    @abs(value: anytype) anytype

Returns the absolute value of an integer or a floating point number. Uses a dedicated hardware instruction
when available.
The return type is always an unsigned integer of the same bit width as the operand if the operand is an integer.
Unsigned integer operands are supported. The builtin cannot overflow for signed integer operands.

Supports [Floats](../zig-0.15.1.md#Floats), [Integers](../zig-0.15.1.md#Integers) and [Vectors](../zig-0.15.1.md#Vectors) of floats or integers.


### [@floor](../zig-0.15.1.md#toc-floor) <a href="../zig-0.15.1.md#floor" class="hdr">§</a>

    @floor(value: anytype) @TypeOf(value)

Returns the largest integral value not greater than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@ceil](../zig-0.15.1.md#toc-ceil) <a href="../zig-0.15.1.md#ceil" class="hdr">§</a>

    @ceil(value: anytype) @TypeOf(value)

Returns the smallest integral value not less than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@trunc](../zig-0.15.1.md#toc-trunc) <a href="../zig-0.15.1.md#trunc" class="hdr">§</a>

    @trunc(value: anytype) @TypeOf(value)

Rounds the given floating point number to an integer, towards zero.
Uses a dedicated hardware instruction when available.

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@round](../zig-0.15.1.md#toc-round) <a href="../zig-0.15.1.md#round" class="hdr">§</a>

    @round(value: anytype) @TypeOf(value)

Rounds the given floating point number to the nearest integer. If two integers are equally close, rounds away from zero.
Uses a dedicated hardware instruction when available.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;@round&quot; {
    try expect(@round(1.4) == 1);
    try expect(@round(1.5) == 2);
    try expect(@round(-1.4) == -1);
    try expect(@round(-2.5) == -3);
}</code></pre>
<figcaption>test_round_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_round_builtin.zig
1/1 test_round_builtin.test.@round...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Supports [Floats](../zig-0.15.1.md#Floats) and [Vectors](../zig-0.15.1.md#Vectors) of floats.


### [@subWithOverflow](../zig-0.15.1.md#toc-subWithOverflow) <a href="../zig-0.15.1.md#subWithOverflow" class="hdr">§</a>

    @subWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a - b` and returns a tuple with the result and a possible overflow bit.


### [@tagName](../zig-0.15.1.md#toc-tagName) <a href="../zig-0.15.1.md#tagName" class="hdr">§</a>

    @tagName(value: anytype) [:0]const u8

Converts an enum value or union value to a string literal representing the name.

If the enum is non-exhaustive and the tag value does not map to a name, it invokes safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).


### [@This](../zig-0.15.1.md#toc-This) <a href="../zig-0.15.1.md#This" class="hdr">§</a>

    @This() type

Returns the innermost struct, enum, or union that this function call is inside.
This can be useful for an anonymous struct that needs to refer to itself:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;@This()&quot; {
    var items = [_]i32{ 1, 2, 3, 4 };
    const list = List(i32){ .items = items[0..] };
    try expect(list.length() == 4);
}

fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,

        fn length(self: Self) usize {
            return self.items.len;
        }
    };
}</code></pre>
<figcaption>test_this_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_this_builtin.zig
1/1 test_this_builtin.test.@This()...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When <span class="tok-builtin">`@This`</span>`()` is used at file scope, it returns a reference to the
struct that corresponds to the current file.


### [@trap](../zig-0.15.1.md#toc-trap) <a href="../zig-0.15.1.md#trap" class="hdr">§</a>

    @trap() noreturn

This function inserts a platform-specific trap/jam instruction which can be used to exit the program abnormally.
This may be implemented by explicitly emitting an invalid instruction which may cause an illegal instruction exception of some sort.
Unlike for <span class="tok-builtin">`@breakpoint`</span>`()`, execution does not continue after this point.

Outside function scope, this builtin causes a compile error.

See also:

- [@breakpoint](../zig-0.15.1.md#breakpoint)


### [@truncate](../zig-0.15.1.md#toc-truncate) <a href="../zig-0.15.1.md#truncate" class="hdr">§</a>

    @truncate(integer: anytype) anytype

This function truncates bits from an integer type, resulting in a smaller
or same-sized integer type. The return type is the inferred result type.

This function always truncates the significant bits of the integer, regardless
of endianness on the target platform.

Calling <span class="tok-builtin">`@truncate`</span> on a number out of range of the destination type is well defined and working code:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;integer truncation&quot; {
    const a: u16 = 0xabcd;
    const b: u8 = @truncate(a);
    try expect(b == 0xcd);
}</code></pre>
<figcaption>test_truncate_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_truncate_builtin.zig
1/1 test_truncate_builtin.test.integer truncation...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use [@intCast](../zig-0.15.1.md#intCast) to convert numbers guaranteed to fit the destination type.


### [@Type](../zig-0.15.1.md#toc-Type) <a href="../zig-0.15.1.md#Type" class="hdr">§</a>

    @Type(comptime info: std.builtin.Type) type

This function is the inverse of [@typeInfo](../zig-0.15.1.md#typeInfo). It reifies type information
into a <span class="tok-type">`type`</span>.

It is available for the following types:

- <span class="tok-type">`type`</span>
- <span class="tok-type">`noreturn`</span>
- <span class="tok-type">`void`</span>
- <span class="tok-type">`bool`</span>
- [Integers](../zig-0.15.1.md#Integers) - The maximum bit count for an integer type is <span class="tok-number">`65535`</span>.
- [Floats](../zig-0.15.1.md#Floats)
- [Pointers](../zig-0.15.1.md#Pointers)
- <span class="tok-type">`comptime_int`</span>
- <span class="tok-type">`comptime_float`</span>
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`undefined`</span>`)`
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`null`</span>`)`
- [Arrays](../zig-0.15.1.md#Arrays)
- [Optionals](../zig-0.15.1.md#Optionals)
- [Error Set Type](../zig-0.15.1.md#Error-Set-Type)
- [Error Union Type](../zig-0.15.1.md#Error-Union-Type)
- [Vectors](../zig-0.15.1.md#Vectors)
- [opaque](../zig-0.15.1.md#opaque)
- <span class="tok-kw">`anyframe`</span>
- [struct](../zig-0.15.1.md#struct)
- [enum](../zig-0.15.1.md#enum)
- [Enum Literals](../zig-0.15.1.md#Enum-Literals)
- [union](../zig-0.15.1.md#union)
- [Functions](../zig-0.15.1.md#Functions)


### [@typeInfo](../zig-0.15.1.md#toc-typeInfo) <a href="../zig-0.15.1.md#typeInfo" class="hdr">§</a>

    @typeInfo(comptime T: type) std.builtin.Type

Provides type reflection.

Type information of [structs](../zig-0.15.1.md#struct), [unions](../zig-0.15.1.md#union), [enums](../zig-0.15.1.md#enum), and
[error sets](../zig-0.15.1.md#Error-Set-Type) has fields which are guaranteed to be in the same
order as appearance in the source file.

Type information of [structs](../zig-0.15.1.md#struct), [unions](../zig-0.15.1.md#union), [enums](../zig-0.15.1.md#enum), and
[opaques](../zig-0.15.1.md#opaque) has declarations, which are also guaranteed to be in the same
order as appearance in the source file.


### [@typeName](../zig-0.15.1.md#toc-typeName) <a href="../zig-0.15.1.md#typeName" class="hdr">§</a>

    @typeName(T: type) *const [N:0]u8

This function returns the string representation of a type, as
an array. It is equivalent to a string literal of the type name.
The returned type name is fully qualified with the parent namespace included
as part of the type name with a series of dots.


### [@TypeOf](../zig-0.15.1.md#toc-TypeOf) <a href="../zig-0.15.1.md#TypeOf" class="hdr">§</a>

    @TypeOf(...) type

<span class="tok-builtin">`@TypeOf`</span> is a special builtin function that takes any (non-zero) number of expressions
as parameters and returns the type of the result, using [Peer Type Resolution](../zig-0.15.1.md#Peer-Type-Resolution).

The expressions are evaluated, however they are guaranteed to have no *runtime* side-effects:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;no runtime side effects&quot; {
    var data: i32 = 0;
    const T = @TypeOf(foo(i32, &amp;data));
    try comptime expect(T == i32);
    try expect(data == 0);
}

fn foo(comptime T: type, ptr: *T) T {
    ptr.* += 1;
    return ptr.*;
}</code></pre>
<figcaption>test_TypeOf_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_TypeOf_builtin.zig
1/1 test_TypeOf_builtin.test.no runtime side effects...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>


### [@unionInit](../zig-0.15.1.md#toc-unionInit) <a href="../zig-0.15.1.md#unionInit" class="hdr">§</a>

    @unionInit(comptime Union: type, comptime active_field_name: []const u8, init_expr) Union

This is the same thing as [union](../zig-0.15.1.md#union) initialization syntax, except that the field name is a
[comptime](../zig-0.15.1.md#comptime)-known value rather than an identifier token.

<span class="tok-builtin">`@unionInit`</span> forwards its [result location](../zig-0.15.1.md#Result-Location-Semantics) to `init_expr`.


### [@Vector](../zig-0.15.1.md#toc-Vector) <a href="../zig-0.15.1.md#Vector" class="hdr">§</a>

    @Vector(len: comptime_int, Element: type) type

Creates [Vectors](../zig-0.15.1.md#Vectors).


### [@volatileCast](../zig-0.15.1.md#toc-volatileCast) <a href="../zig-0.15.1.md#volatileCast" class="hdr">§</a>

    @volatileCast(value: anytype) DestType

Remove <span class="tok-kw">`volatile`</span> qualifier from a pointer.


### [@workGroupId](../zig-0.15.1.md#toc-workGroupId) <a href="../zig-0.15.1.md#workGroupId" class="hdr">§</a>

    @workGroupId(comptime dimension: u32) u32

Returns the index of the work group in the current kernel invocation in dimension `dimension`.


### [@workGroupSize](../zig-0.15.1.md#toc-workGroupSize) <a href="../zig-0.15.1.md#workGroupSize" class="hdr">§</a>

    @workGroupSize(comptime dimension: u32) u32

Returns the number of work items that a work group has in dimension `dimension`.


### [@workItemId](../zig-0.15.1.md#toc-workItemId) <a href="../zig-0.15.1.md#workItemId" class="hdr">§</a>

    @workItemId(comptime dimension: u32) u32

Returns the index of the work item in the work group in dimension `dimension`. This function returns values between <span class="tok-number">`0`</span> (inclusive) and <span class="tok-builtin">`@workGroupSize`</span>`(dimension)` (exclusive).


