<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Result Location Semantics -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Result Location Semantics](zig-0.15.1.md#toc-Result-Location-Semantics) <a href="zig-0.15.1.md#Result-Location-Semantics" class="hdr">§</a>

During compilation, every Zig expression and sub-expression is assigned optional result location
information. This information dictates what type the expression should have (its result type), and
where the resulting value should be placed in memory (its result location). The information is
optional in the sense that not every expression has this information: assignment to
`_`, for instance, does not provide any information about the type of an
expression, nor does it provide a concrete memory location to place it in.

As a motivating example, consider the statement <span class="tok-kw">`const`</span>` x: `<span class="tok-type">`u32`</span>` = `<span class="tok-number">`42`</span>`;`. The type
annotation here provides a result type of <span class="tok-type">`u32`</span> to the initialization expression
<span class="tok-number">`42`</span>, instructing the compiler to coerce this integer (initially of type
<span class="tok-type">`comptime_int`</span>) to this type. We will see more examples shortly.

This is not an implementation detail: the logic outlined above is codified into the Zig language
specification, and is the primary mechanism of type inference in the language. This system is
collectively referred to as "Result Location Semantics".

### [Result Types](zig-0.15.1.md#toc-Result-Types) <a href="zig-0.15.1.md#Result-Types" class="hdr">§</a>

Result types are propagated recursively through expressions where possible. For instance, if the
expression `&e` has result type `*`<span class="tok-type">`u32`</span>, then
`e` is given a result type of <span class="tok-type">`u32`</span>, allowing the
language to perform this coercion before taking a reference.

The result type mechanism is utilized by casting builtins such as <span class="tok-builtin">`@intCast`</span>.
Rather than taking as an argument the type to cast to, these builtins use their result type to
determine this information. The result type is often known from context; where it is not, the
<span class="tok-builtin">`@as`</span> builtin can be used to explicitly provide a result type.

We can break down the result types for each component of a simple expression as follows:

<figure>
<pre><code>const expectEqual = @import(&quot;std&quot;).testing.expectEqual;
test &quot;result type propagates through struct initializer&quot; {
    const S = struct { x: u32 };
    const val: u64 = 123;
    const s: S = .{ .x = @intCast(val) };
    // .{ .x = @intCast(val) }   has result type `S` due to the type annotation
    //         @intCast(val)     has result type `u32` due to the type of the field `S.x`
    //                  val      has no result type, as it is permitted to be any integer type
    try expectEqual(@as(u32, 123), s.x);
}</code></pre>
<figcaption>result_type_propagation.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test result_type_propagation.zig
1/1 result_type_propagation.test.result type propagates through struct initializer...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This result type information is useful for the aforementioned cast builtins, as well as to avoid
the construction of pre-coercion values, and to avoid the need for explicit type coercions in some
cases. The following table details how some common expressions propagate result types, where
`x` and `y` are arbitrary sub-expressions.

<div class="table-wrapper">

| Expression | Parent Result Type | Sub-expression Result Type |
|----|----|----|
| <span class="tok-kw">`const`</span>` val: T = x` | \- | `x` is a `T` |
| <span class="tok-kw">`var`</span>` val: T = x` | \- | `x` is a `T` |
| `val = x` | \- | `x` is a <span class="tok-builtin">`@TypeOf`</span>`(val)` |
| <span class="tok-builtin">`@as`</span>`(T, x)` | \- | `x` is a `T` |
| `&x` | `*T` | `x` is a `T` |
| `&x` | `[]T` | `x` is some array of `T` |
| `f(x)` | \- | `x` has the type of the first parameter of `f` |
| `.{x}` | `T` | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"0"`</span>`)` |
| `.{ .a = x }` | `T` | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"a"`</span>`)` |
| `T{x}` | \- | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"0"`</span>`)` |
| `T{ .a = x }` | \- | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"a"`</span>`)` |
| <span class="tok-builtin">`@Type`</span>`(x)` | \- | `x` is a `std.builtin.Type` |
| <span class="tok-builtin">`@typeInfo`</span>`(x)` | \- | `x` is a <span class="tok-type">`type`</span> |
| `x << y` | \- | `y` is a `std.math.Log2IntCeil(`<span class="tok-builtin">`@TypeOf`</span>`(x))` |

</div>

### [Result Locations](zig-0.15.1.md#toc-Result-Locations) <a href="zig-0.15.1.md#Result-Locations" class="hdr">§</a>

In addition to result type information, every expression may be optionally assigned a result
location: a pointer to which the value must be directly written. This system can be used to prevent
intermediate copies when initializing data structures, which can be important for types which must
have a fixed memory address ("pinned" types).

When compiling the simple assignment expression `x = e`, many languages would
create the temporary value `e` on the stack, and then assign it to
`x`, potentially performing a type coercion in the process. Zig approaches this
differently. The expression `e` is given a result type matching the type of
`x`, and a result location of `&x`. For many syntactic
forms of `e`, this has no practical impact. However, it can have important
semantic effects when working with more complex syntax forms.

For instance, if the expression `.{ .a = x, .b = y }` has a result location of
`ptr`, then `x` is given a result location of
`&ptr.a`, and `y` a result location of `&ptr.b`.
Without this system, this expression would construct a temporary struct value entirely on the stack, and
only then copy it to the destination address. In essence, Zig desugars the assignment
`foo = .{ .a = x, .b = y }` to the two statements `foo.a = x; foo.b = y;`.

This can sometimes be important when assigning an aggregate value where the initialization
expression depends on the previous value of the aggregate. The easiest way to demonstrate this is by
attempting to swap fields of a struct or array - the following logic looks sound, but in fact is not:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
test &quot;attempt to swap array elements with array initializer&quot; {
    var arr: [2]u32 = .{ 1, 2 };
    arr = .{ arr[1], arr[0] };
    // The previous line is equivalent to the following two lines:
    //   arr[0] = arr[1];
    //   arr[1] = arr[0];
    // So this fails!
    try expect(arr[0] == 2); // succeeds
    try expect(arr[1] == 1); // fails
}</code></pre>
<figcaption>result_location_interfering_with_swap.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test result_location_interfering_with_swap.zig
1/1 result_location_interfering_with_swap.test.attempt to swap array elements with array initializer...FAIL (TestUnexpectedResult)
/home/andy/dev/zig/lib/std/testing.zig:607:14: 0x102f019 in expect (std.zig)
    if (!ok) return error.TestUnexpectedResult;
             ^
/home/andy/dev/zig/doc/langref/result_location_interfering_with_swap.zig:10:5: 0x102f144 in test.attempt to swap array elements with array initializer (result_location_interfering_with_swap.zig)
    try expect(arr[1] == 1); // fails
    ^
0 passed; 0 skipped; 1 failed.
error: the following test command failed with exit code 1:
/home/andy/dev/zig/.zig-cache/o/a8056b54531d62dabec9b7d39a01cdc4/test --seed=0x22452da4</code></pre>
<figcaption>Shell</figcaption>
</figure>

The following table details how some common expressions propagate result locations, where
`x` and `y` are arbitrary sub-expressions. Note that
some expressions cannot provide meaningful result locations to sub-expressions, even if they
themselves have a result location.

<div class="table-wrapper">

| Expression | Result Location | Sub-expression Result Locations |
|----|----|----|
| <span class="tok-kw">`const`</span>` val: T = x` | \- | `x` has result location `&val` |
| <span class="tok-kw">`var`</span>` val: T = x` | \- | `x` has result location `&val` |
| `val = x` | \- | `x` has result location `&val` |
| <span class="tok-builtin">`@as`</span>`(T, x)` | `ptr` | `x` has no result location |
| `&x` | `ptr` | `x` has no result location |
| `f(x)` | `ptr` | `x` has no result location |
| `.{x}` | `ptr` | `x` has result location `&ptr[`<span class="tok-number">`0`</span>`]` |
| `.{ .a = x }` | `ptr` | `x` has result location `&ptr.a` |
| `T{x}` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| `T{ .a = x }` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| <span class="tok-builtin">`@Type`</span>`(x)` | `ptr` | `x` has no result location |
| <span class="tok-builtin">`@typeInfo`</span>`(x)` | `ptr` | `x` has no result location |
| `x << y` | `ptr` | `x` and `y` do not have result locations |

</div>

