<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Builtin Functions -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Builtin Functions](zig-0.15.1.md#toc-Builtin-Functions) <a href="zig-0.15.1.md#Builtin-Functions" class="hdr">§</a>

Builtin functions are provided by the compiler and are prefixed with `@`.
The <span class="tok-kw">`comptime`</span> keyword on a parameter means that the parameter must be known
at compile time.

### [@addrSpaceCast](zig-0.15.1.md#toc-addrSpaceCast) <a href="zig-0.15.1.md#addrSpaceCast" class="hdr">§</a>

    @addrSpaceCast(ptr: anytype) anytype

Converts a pointer from one address space to another. The new address space is inferred
based on the result type. Depending on the current target and address spaces, this cast
may be a no-op, a complex operation, or illegal. If the cast is legal, then the resulting
pointer points to the same memory location as the pointer operand. It is always valid to
cast a pointer between the same address spaces.

### [@addWithOverflow](zig-0.15.1.md#toc-addWithOverflow) <a href="zig-0.15.1.md#addWithOverflow" class="hdr">§</a>

    @addWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a + b` and returns a tuple with the result and a possible overflow bit.

### [@alignCast](zig-0.15.1.md#toc-alignCast) <a href="zig-0.15.1.md#alignCast" class="hdr">§</a>

    @alignCast(ptr: anytype) anytype

`ptr` can be `*T`, `?*T`, or `[]T`.
Changes the alignment of a pointer. The alignment to use is inferred based on the result type.

A [pointer alignment safety check](zig-0.15.1.md#Incorrect-Pointer-Alignment) is added
to the generated code to make sure the pointer is aligned as promised.

### [@alignOf](zig-0.15.1.md#toc-alignOf) <a href="zig-0.15.1.md#alignOf" class="hdr">§</a>

    @alignOf(comptime T: type) comptime_int

This function returns the number of bytes that this type should be aligned to
for the current target to match the C ABI. When the child type of a pointer has
this alignment, the alignment can be omitted from the type.

    const assert = @import("std").debug.assert;
    comptime {
        assert(*u32 == *align(@alignOf(u32)) u32);
    }

The result is a target-specific compile time constant. It is guaranteed to be
less than or equal to [@sizeOf(T)](zig-0.15.1.md#sizeOf).

See also:

- [Alignment](zig-0.15.1.md#Alignment)

### [@as](zig-0.15.1.md#toc-as) <a href="zig-0.15.1.md#as" class="hdr">§</a>

    @as(comptime T: type, expression) T

Performs [Type Coercion](zig-0.15.1.md#Type-Coercion). This cast is allowed when the conversion is unambiguous and safe,
and is the preferred way to convert between types, whenever possible.

### [@atomicLoad](zig-0.15.1.md#toc-atomicLoad) <a href="zig-0.15.1.md#atomicLoad" class="hdr">§</a>

    @atomicLoad(comptime T: type, ptr: *const T, comptime ordering: AtomicOrder) T

This builtin function atomically dereferences a pointer to a `T` and returns the value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](zig-0.15.1.md#atomicStore)
- [@atomicRmw](zig-0.15.1.md#atomicRmw)
- [@cmpxchgWeak](zig-0.15.1.md#cmpxchgWeak)
- [@cmpxchgStrong](zig-0.15.1.md#cmpxchgStrong)

### [@atomicRmw](zig-0.15.1.md#toc-atomicRmw) <a href="zig-0.15.1.md#atomicRmw" class="hdr">§</a>

    @atomicRmw(comptime T: type, ptr: *T, comptime op: AtomicRmwOp, operand: T, comptime ordering: AtomicOrder) T

This builtin function dereferences a pointer to a `T` and atomically
modifies the value and returns the previous value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

`AtomicRmwOp` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicRmwOp`.

See also:

- [@atomicStore](zig-0.15.1.md#atomicStore)
- [@atomicLoad](zig-0.15.1.md#atomicLoad)
- [@cmpxchgWeak](zig-0.15.1.md#cmpxchgWeak)
- [@cmpxchgStrong](zig-0.15.1.md#cmpxchgStrong)

### [@atomicStore](zig-0.15.1.md#toc-atomicStore) <a href="zig-0.15.1.md#atomicStore" class="hdr">§</a>

    @atomicStore(comptime T: type, ptr: *T, value: T, comptime ordering: AtomicOrder) void

This builtin function dereferences a pointer to a `T` and atomically stores the given value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicLoad](zig-0.15.1.md#atomicLoad)
- [@atomicRmw](zig-0.15.1.md#atomicRmw)
- [@cmpxchgWeak](zig-0.15.1.md#cmpxchgWeak)
- [@cmpxchgStrong](zig-0.15.1.md#cmpxchgStrong)

### [@bitCast](zig-0.15.1.md#toc-bitCast) <a href="zig-0.15.1.md#bitCast" class="hdr">§</a>

    @bitCast(value: anytype) anytype

Converts a value of one type to another type. The return type is the
inferred result type.

Asserts that <span class="tok-builtin">`@sizeOf`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(value)) == `<span class="tok-builtin">`@sizeOf`</span>`(DestType)`.

Asserts that <span class="tok-builtin">`@typeInfo`</span>`(DestType) != .pointer`. Use <span class="tok-builtin">`@ptrCast`</span> or <span class="tok-builtin">`@ptrFromInt`</span> if you need this.

Can be used for these things for example:

- Convert <span class="tok-type">`f32`</span> to <span class="tok-type">`u32`</span> bits
- Convert <span class="tok-type">`i32`</span> to <span class="tok-type">`u32`</span> preserving twos complement

Works at compile-time if `value` is known at compile time. It's a compile error to bitcast a value of undefined layout; this means that, besides the restriction from types which possess dedicated casting builtins (enums, pointers, error sets), bare structs, error unions, slices, optionals, and any other type without a well-defined memory layout, also cannot be used in this operation.

### [@bitOffsetOf](zig-0.15.1.md#toc-bitOffsetOf) <a href="zig-0.15.1.md#bitOffsetOf" class="hdr">§</a>

    @bitOffsetOf(comptime T: type, comptime field_name: []const u8) comptime_int

Returns the bit offset of a field relative to its containing struct.

For non [packed structs](zig-0.15.1.md#packed-struct), this will always be divisible by <span class="tok-number">`8`</span>.
For packed structs, non-byte-aligned fields will share a byte offset, but they will have different
bit offsets.

See also:

- [@offsetOf](zig-0.15.1.md#offsetOf)

### [@bitSizeOf](zig-0.15.1.md#toc-bitSizeOf) <a href="zig-0.15.1.md#bitSizeOf" class="hdr">§</a>

    @bitSizeOf(comptime T: type) comptime_int

This function returns the number of bits it takes to store `T` in memory if the type
were a field in a packed struct/union.
The result is a target-specific compile time constant.

This function measures the size at runtime. For types that are disallowed at runtime, such as
<span class="tok-type">`comptime_int`</span> and <span class="tok-type">`type`</span>, the result is <span class="tok-number">`0`</span>.

See also:

- [@sizeOf](zig-0.15.1.md#sizeOf)
- [@typeInfo](zig-0.15.1.md#typeInfo)

### [@branchHint](zig-0.15.1.md#toc-branchHint) <a href="zig-0.15.1.md#branchHint" class="hdr">§</a>

    @branchHint(hint: BranchHint) void

Hints to the optimizer how likely a given branch of control flow is to be reached.

`BranchHint` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.BranchHint`.

This function is only valid as the first statement in a control flow branch, or the first statement in a function.

### [@breakpoint](zig-0.15.1.md#toc-breakpoint) <a href="zig-0.15.1.md#breakpoint" class="hdr">§</a>

    @breakpoint() void

This function inserts a platform-specific debug trap instruction which causes
debuggers to break there.
Unlike for <span class="tok-builtin">`@trap`</span>`()`, execution may continue after this point if the program is resumed.

This function is only valid within function scope.

See also:

- [@trap](zig-0.15.1.md#trap)

### [@mulAdd](zig-0.15.1.md#toc-mulAdd) <a href="zig-0.15.1.md#mulAdd" class="hdr">§</a>

    @mulAdd(comptime T: type, a: T, b: T, c: T) T

Fused multiply-add, similar to `(a * b) + c`, except
only rounds once, and is thus more accurate.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@byteSwap](zig-0.15.1.md#toc-byteSwap) <a href="zig-0.15.1.md#byteSwap" class="hdr">§</a>

    @byteSwap(operand: anytype) T

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type with bit count evenly divisible by 8.

`operand` may be an [integer](zig-0.15.1.md#Integers) or [vector](zig-0.15.1.md#Vectors).

Swaps the byte order of the integer. This converts a big endian integer to a little endian integer,
and converts a little endian integer to a big endian integer.

Note that for the purposes of memory layout with respect to endianness, the integer type should be
related to the number of bytes reported by [@sizeOf](zig-0.15.1.md#sizeOf) bytes. This is demonstrated with
<span class="tok-type">`u24`</span>. <span class="tok-builtin">`@sizeOf`</span>`(`<span class="tok-type">`u24`</span>`) == `<span class="tok-number">`4`</span>, which means that a
<span class="tok-type">`u24`</span> stored in memory takes 4 bytes, and those 4 bytes are what are swapped on
a little vs big endian system. On the other hand, if `T` is specified to
be <span class="tok-type">`u24`</span>, then only 3 bytes are reversed.

### [@bitReverse](zig-0.15.1.md#toc-bitReverse) <a href="zig-0.15.1.md#bitReverse" class="hdr">§</a>

    @bitReverse(integer: anytype) T

<span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-kw">`anytype`</span>`)` accepts any integer type or integer vector type.

Reverses the bitpattern of an integer value, including the sign bit if applicable.

For example 0b10110110 (<span class="tok-type">`u8`</span>` = `<span class="tok-number">`182`</span>, <span class="tok-type">`i8`</span>` = -`<span class="tok-number">`74`</span>)
becomes 0b01101101 (<span class="tok-type">`u8`</span>` = `<span class="tok-number">`109`</span>, <span class="tok-type">`i8`</span>` = `<span class="tok-number">`109`</span>).

### [@offsetOf](zig-0.15.1.md#toc-offsetOf) <a href="zig-0.15.1.md#offsetOf" class="hdr">§</a>

    @offsetOf(comptime T: type, comptime field_name: []const u8) comptime_int

Returns the byte offset of a field relative to its containing struct.

See also:

- [@bitOffsetOf](zig-0.15.1.md#bitOffsetOf)

### [@call](zig-0.15.1.md#toc-call) <a href="zig-0.15.1.md#call" class="hdr">§</a>

    @call(modifier: std.builtin.CallModifier, function: anytype, args: anytype) anytype

Calls a function, in the same way that invoking an expression with parentheses does:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;noinline function call&quot; {
    try expect(@call(.auto, add, .{ 3, 9 }) == 12);
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}</code></pre>
<figcaption>test_call_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_call_builtin.zig
1/1 test_call_builtin.test.noinline function call...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-builtin">`@call`</span> allows more flexibility than normal function call syntax does. The
`CallModifier` enum is reproduced here:

<figure>
<pre><code>pub const CallModifier = enum {
    /// Equivalent to function call syntax.
    auto,

    /// Equivalent to async keyword used with function call syntax.
    async_kw,

    /// Prevents tail call optimization. This guarantees that the return
    /// address will point to the callsite, as opposed to the callsite&#39;s
    /// callsite. If the call is otherwise required to be tail-called
    /// or inlined, a compile error is emitted instead.
    never_tail,

    /// Guarantees that the call will not be inlined. If the call is
    /// otherwise required to be inlined, a compile error is emitted instead.
    never_inline,

    /// Asserts that the function call will not suspend. This allows a
    /// non-async function to call an async function.
    no_async,

    /// Guarantees that the call will be generated with tail call optimization.
    /// If this is not possible, a compile error is emitted instead.
    always_tail,

    /// Guarantees that the call will be inlined at the callsite.
    /// If this is not possible, a compile error is emitted instead.
    always_inline,

    /// Evaluates the call at compile-time. If the call cannot be completed at
    /// compile-time, a compile error is emitted instead.
    compile_time,
};</code></pre>
<figcaption>builtin.CallModifier struct.zig</figcaption>
</figure>

### [@cDefine](zig-0.15.1.md#toc-cDefine) <a href="zig-0.15.1.md#cDefine" class="hdr">§</a>

    @cDefine(comptime name: []const u8, value) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#define $name $value` to the <span class="tok-builtin">`@cImport`</span>
temporary buffer.

To define without a value, like this:

``` c
#define _GNU_SOURCE
```

Use the void value, like this:

    @cDefine("_GNU_SOURCE", {})

See also:

- [Import from C Header File](zig-0.15.1.md#Import-from-C-Header-File)
- [@cInclude](zig-0.15.1.md#cInclude)
- [@cImport](zig-0.15.1.md#cImport)
- [@cUndef](zig-0.15.1.md#cUndef)
- [void](zig-0.15.1.md#void)

### [@cImport](zig-0.15.1.md#toc-cImport) <a href="zig-0.15.1.md#cImport" class="hdr">§</a>

    @cImport(expression) type

This function parses C code and imports the functions, types, variables,
and compatible macro definitions into a new empty struct type, and then
returns that type.

`expression` is interpreted at compile time. The builtin functions
<span class="tok-builtin">`@cInclude`</span>, <span class="tok-builtin">`@cDefine`</span>, and <span class="tok-builtin">`@cUndef`</span> work
within this expression, appending to a temporary buffer which is then parsed as C code.

Usually you should only have one <span class="tok-builtin">`@cImport`</span> in your entire application, because it saves the compiler
from invoking clang multiple times, and prevents inline functions from being duplicated.

Reasons for having multiple <span class="tok-builtin">`@cImport`</span> expressions would be:

- To avoid a symbol collision, for example if foo.h and bar.h both `#define CONNECTION_COUNT`
- To analyze the C code with different preprocessor defines

See also:

- [Import from C Header File](zig-0.15.1.md#Import-from-C-Header-File)
- [@cInclude](zig-0.15.1.md#cInclude)
- [@cDefine](zig-0.15.1.md#cDefine)
- [@cUndef](zig-0.15.1.md#cUndef)

### [@cInclude](zig-0.15.1.md#toc-cInclude) <a href="zig-0.15.1.md#cInclude" class="hdr">§</a>

    @cInclude(comptime path: []const u8) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#include <$path>\n` to the `c_import`
temporary buffer.

See also:

- [Import from C Header File](zig-0.15.1.md#Import-from-C-Header-File)
- [@cImport](zig-0.15.1.md#cImport)
- [@cDefine](zig-0.15.1.md#cDefine)
- [@cUndef](zig-0.15.1.md#cUndef)

### [@clz](zig-0.15.1.md#toc-clz) <a href="zig-0.15.1.md#clz" class="hdr">§</a>

    @clz(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type.

`operand` may be an [integer](zig-0.15.1.md#Integers) or [vector](zig-0.15.1.md#Vectors).

Counts the number of most-significant (leading in a big-endian sense) zeroes in an integer - "count leading zeroes".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

If `operand` is zero, <span class="tok-builtin">`@clz`</span> returns the bit width
of integer type `T`.

See also:

- [@ctz](zig-0.15.1.md#ctz)
- [@popCount](zig-0.15.1.md#popCount)

### [@cmpxchgStrong](zig-0.15.1.md#toc-cmpxchgStrong) <a href="zig-0.15.1.md#cmpxchgStrong" class="hdr">§</a>

    @cmpxchgStrong(comptime T: type, ptr: *T, expected_value: T, new_value: T, success_order: AtomicOrder, fail_order: AtomicOrder) ?T

This function performs a strong atomic compare-and-exchange operation, returning <span class="tok-null">`null`</span>
if the current value is the given expected value. It's the equivalent of this code,
except atomic:

<figure>
<pre><code>fn cmpxchgStrongButNotAtomic(comptime T: type, ptr: *T, expected_value: T, new_value: T) ?T {
    const old_value = ptr.*;
    if (old_value == expected_value) {
        ptr.* = new_value;
        return null;
    } else {
        return old_value;
    }
}</code></pre>
<figcaption>not_atomic_cmpxchgStrong.zig</figcaption>
</figure>

If you are using cmpxchg in a retry loop, [@cmpxchgWeak](zig-0.15.1.md#cmpxchgWeak) is the better choice, because it can be implemented
more efficiently in machine instructions.

`T` must be a pointer, a <span class="tok-type">`bool`</span>,
an integer, an enum, or a packed struct.

<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(ptr)).pointer.alignment` must be `>= `<span class="tok-builtin">`@sizeOf`</span>`(T).`

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](zig-0.15.1.md#atomicStore)
- [@atomicLoad](zig-0.15.1.md#atomicLoad)
- [@atomicRmw](zig-0.15.1.md#atomicRmw)
- [@cmpxchgWeak](zig-0.15.1.md#cmpxchgWeak)

### [@cmpxchgWeak](zig-0.15.1.md#toc-cmpxchgWeak) <a href="zig-0.15.1.md#cmpxchgWeak" class="hdr">§</a>

    @cmpxchgWeak(comptime T: type, ptr: *T, expected_value: T, new_value: T, success_order: AtomicOrder, fail_order: AtomicOrder) ?T

This function performs a weak atomic compare-and-exchange operation, returning <span class="tok-null">`null`</span>
if the current value is the given expected value. It's the equivalent of this code,
except atomic:

<figure>
<pre><code>fn cmpxchgWeakButNotAtomic(comptime T: type, ptr: *T, expected_value: T, new_value: T) ?T {
    const old_value = ptr.*;
    if (old_value == expected_value and usuallyTrueButSometimesFalse()) {
        ptr.* = new_value;
        return null;
    } else {
        return old_value;
    }
}</code></pre>
<figcaption>cmpxchgWeakButNotAtomic</figcaption>
</figure>

If you are using cmpxchg in a retry loop, the sporadic failure will be no problem, and `cmpxchgWeak`
is the better choice, because it can be implemented more efficiently in machine instructions.
However if you need a stronger guarantee, use [@cmpxchgStrong](zig-0.15.1.md#cmpxchgStrong).

`T` must be a pointer, a <span class="tok-type">`bool`</span>,
an integer, an enum, or a packed struct.

<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(ptr)).pointer.alignment` must be `>= `<span class="tok-builtin">`@sizeOf`</span>`(T).`

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](zig-0.15.1.md#atomicStore)
- [@atomicLoad](zig-0.15.1.md#atomicLoad)
- [@atomicRmw](zig-0.15.1.md#atomicRmw)
- [@cmpxchgStrong](zig-0.15.1.md#cmpxchgStrong)

### [@compileError](zig-0.15.1.md#toc-compileError) <a href="zig-0.15.1.md#compileError" class="hdr">§</a>

    @compileError(comptime msg: []const u8) noreturn

This function, when semantically analyzed, causes a compile error with the
message `msg`.

There are several ways that code avoids being semantically checked, such as
using <span class="tok-kw">`if`</span> or <span class="tok-kw">`switch`</span> with compile time constants,
and <span class="tok-kw">`comptime`</span> functions.

### [@compileLog](zig-0.15.1.md#toc-compileLog) <a href="zig-0.15.1.md#compileLog" class="hdr">§</a>

    @compileLog(...) void

This function prints the arguments passed to it at compile-time.

To prevent accidentally leaving compile log statements in a codebase,
a compilation error is added to the build, pointing to the compile
log statement. This error prevents code from being generated, but
does not otherwise interfere with analysis.

This function can be used to do "printf debugging" on
compile-time executing code.

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

const num1 = blk: {
    var val1: i32 = 99;
    @compileLog(&quot;comptime val1 = &quot;, val1);
    val1 = val1 + 1;
    break :blk val1;
};

test &quot;main&quot; {
    @compileLog(&quot;comptime in main&quot;);

    print(&quot;Runtime in main, num1 = {}.\n&quot;, .{num1});
}</code></pre>
<figcaption>test_compileLog_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_compileLog_builtin.zig
/home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:5:5: error: found compile log statement
    @compileLog(&quot;comptime val1 = &quot;, val1);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:11:5: note: also here
    @compileLog(&quot;comptime in main&quot;);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    test.main: /home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:13:46

Compile Log Output:
@as(*const [16:0]u8, &quot;comptime val1 = &quot;), @as(i32, 99)
@as(*const [16:0]u8, &quot;comptime in main&quot;)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@constCast](zig-0.15.1.md#toc-constCast) <a href="zig-0.15.1.md#constCast" class="hdr">§</a>

    @constCast(value: anytype) DestType

Remove <span class="tok-kw">`const`</span> qualifier from a pointer.

### [@ctz](zig-0.15.1.md#toc-ctz) <a href="zig-0.15.1.md#ctz" class="hdr">§</a>

    @ctz(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type.

`operand` may be an [integer](zig-0.15.1.md#Integers) or [vector](zig-0.15.1.md#Vectors).

Counts the number of least-significant (trailing in a big-endian sense) zeroes in an integer - "count trailing zeroes".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

If `operand` is zero, <span class="tok-builtin">`@ctz`</span> returns
the bit width of integer type `T`.

See also:

- [@clz](zig-0.15.1.md#clz)
- [@popCount](zig-0.15.1.md#popCount)

### [@cUndef](zig-0.15.1.md#toc-cUndef) <a href="zig-0.15.1.md#cUndef" class="hdr">§</a>

    @cUndef(comptime name: []const u8) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#undef $name` to the <span class="tok-builtin">`@cImport`</span>
temporary buffer.

See also:

- [Import from C Header File](zig-0.15.1.md#Import-from-C-Header-File)
- [@cImport](zig-0.15.1.md#cImport)
- [@cDefine](zig-0.15.1.md#cDefine)
- [@cInclude](zig-0.15.1.md#cInclude)

### [@cVaArg](zig-0.15.1.md#toc-cVaArg) <a href="zig-0.15.1.md#cVaArg" class="hdr">§</a>

    @cVaArg(operand: *std.builtin.VaList, comptime T: type) T

Implements the C macro `va_arg`.

See also:

- [@cVaCopy](zig-0.15.1.md#cVaCopy)
- [@cVaEnd](zig-0.15.1.md#cVaEnd)
- [@cVaStart](zig-0.15.1.md#cVaStart)

### [@cVaCopy](zig-0.15.1.md#toc-cVaCopy) <a href="zig-0.15.1.md#cVaCopy" class="hdr">§</a>

    @cVaCopy(src: *std.builtin.VaList) std.builtin.VaList

Implements the C macro `va_copy`.

See also:

- [@cVaArg](zig-0.15.1.md#cVaArg)
- [@cVaEnd](zig-0.15.1.md#cVaEnd)
- [@cVaStart](zig-0.15.1.md#cVaStart)

### [@cVaEnd](zig-0.15.1.md#toc-cVaEnd) <a href="zig-0.15.1.md#cVaEnd" class="hdr">§</a>

    @cVaEnd(src: *std.builtin.VaList) void

Implements the C macro `va_end`.

See also:

- [@cVaArg](zig-0.15.1.md#cVaArg)
- [@cVaCopy](zig-0.15.1.md#cVaCopy)
- [@cVaStart](zig-0.15.1.md#cVaStart)

### [@cVaStart](zig-0.15.1.md#toc-cVaStart) <a href="zig-0.15.1.md#cVaStart" class="hdr">§</a>

    @cVaStart() std.builtin.VaList

Implements the C macro `va_start`. Only valid inside a variadic function.

See also:

- [@cVaArg](zig-0.15.1.md#cVaArg)
- [@cVaCopy](zig-0.15.1.md#cVaCopy)
- [@cVaEnd](zig-0.15.1.md#cVaEnd)

### [@divExact](zig-0.15.1.md#toc-divExact) <a href="zig-0.15.1.md#divExact" class="hdr">§</a>

    @divExact(numerator: T, denominator: T) T

Exact division. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
<span class="tok-builtin">`@divTrunc`</span>`(numerator, denominator) * denominator == numerator`.

- <span class="tok-builtin">`@divExact`</span>`(`<span class="tok-number">`6`</span>`, `<span class="tok-number">`3`</span>`) == `<span class="tok-number">`2`</span>
- <span class="tok-builtin">`@divExact`</span>`(a, b) * b == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divExact`.

See also:

- [@divTrunc](zig-0.15.1.md#divTrunc)
- [@divFloor](zig-0.15.1.md#divFloor)

### [@divFloor](zig-0.15.1.md#toc-divFloor) <a href="zig-0.15.1.md#divFloor" class="hdr">§</a>

    @divFloor(numerator: T, denominator: T) T

Floored division. Rounds toward negative infinity. For unsigned integers it is
the same as `numerator / denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
`!(`<span class="tok-builtin">`@typeInfo`</span>`(T) == .int `<span class="tok-kw">`and`</span>` T.is_signed `<span class="tok-kw">`and`</span>` numerator == std.math.minInt(T) `<span class="tok-kw">`and`</span>` denominator == -`<span class="tok-number">`1`</span>`)`.

- <span class="tok-builtin">`@divFloor`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`2`</span>
- `(`<span class="tok-builtin">`@divFloor`</span>`(a, b) * b) + `<span class="tok-builtin">`@mod`</span>`(a, b) == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divFloor`.

See also:

- [@divTrunc](zig-0.15.1.md#divTrunc)
- [@divExact](zig-0.15.1.md#divExact)

### [@divTrunc](zig-0.15.1.md#toc-divTrunc) <a href="zig-0.15.1.md#divTrunc" class="hdr">§</a>

    @divTrunc(numerator: T, denominator: T) T

Truncated division. Rounds toward zero. For unsigned integers it is
the same as `numerator / denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
`!(`<span class="tok-builtin">`@typeInfo`</span>`(T) == .int `<span class="tok-kw">`and`</span>` T.is_signed `<span class="tok-kw">`and`</span>` numerator == std.math.minInt(T) `<span class="tok-kw">`and`</span>` denominator == -`<span class="tok-number">`1`</span>`)`.

- <span class="tok-builtin">`@divTrunc`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`1`</span>
- `(`<span class="tok-builtin">`@divTrunc`</span>`(a, b) * b) + `<span class="tok-builtin">`@rem`</span>`(a, b) == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divTrunc`.

See also:

- [@divFloor](zig-0.15.1.md#divFloor)
- [@divExact](zig-0.15.1.md#divExact)

### [@embedFile](zig-0.15.1.md#toc-embedFile) <a href="zig-0.15.1.md#embedFile" class="hdr">§</a>

    @embedFile(comptime path: []const u8) *const [N:0]u8

This function returns a compile time constant pointer to null-terminated,
fixed-size array with length equal to the byte count of the file given by
`path`. The contents of the array are the contents of the file.
This is equivalent to a [string literal](zig-0.15.1.md#String-Literals-and-Unicode-Code-Point-Literals)
with the file contents.

`path` is absolute or relative to the current file, just like <span class="tok-builtin">`@import`</span>.

See also:

- [@import](zig-0.15.1.md#import)

### [@enumFromInt](zig-0.15.1.md#toc-enumFromInt) <a href="zig-0.15.1.md#enumFromInt" class="hdr">§</a>

    @enumFromInt(integer: anytype) anytype

Converts an integer into an [enum](zig-0.15.1.md#enum) value. The return type is the inferred result type.

Attempting to convert an integer with no corresponding value in the enum invokes
safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).
Note that a [non-exhaustive enum](zig-0.15.1.md#Non-exhaustive-enum) has corresponding values for all
integers in the enum's integer tag type: the `_` value represents all
the remaining unnamed integers in the enum's tag type.

See also:

- [@intFromEnum](zig-0.15.1.md#intFromEnum)

### [@errorFromInt](zig-0.15.1.md#toc-errorFromInt) <a href="zig-0.15.1.md#errorFromInt" class="hdr">§</a>

    @errorFromInt(value: std.meta.Int(.unsigned, @bitSizeOf(anyerror))) anyerror

Converts from the integer representation of an error into [The Global Error Set](zig-0.15.1.md#The-Global-Error-Set) type.

It is generally recommended to avoid this
cast, as the integer representation of an error is not stable across source code changes.

Attempting to convert an integer that does not correspond to any error results in
safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

See also:

- [@intFromError](zig-0.15.1.md#intFromError)

### [@errorName](zig-0.15.1.md#toc-errorName) <a href="zig-0.15.1.md#errorName" class="hdr">§</a>

    @errorName(err: anyerror) [:0]const u8

This function returns the string representation of an error. The string representation
of <span class="tok-kw">`error`</span>`.OutOfMem` is <span class="tok-str">`"OutOfMem"`</span>.

If there are no calls to <span class="tok-builtin">`@errorName`</span> in an entire application,
or all calls have a compile-time known value for `err`, then no
error name table will be generated.

### [@errorReturnTrace](zig-0.15.1.md#toc-errorReturnTrace) <a href="zig-0.15.1.md#errorReturnTrace" class="hdr">§</a>

    @errorReturnTrace() ?*builtin.StackTrace

If the binary is built with error return tracing, and this function is invoked in a
function that calls a function with an error or error union return type, returns a
stack trace object. Otherwise returns [null](zig-0.15.1.md#null).

### [@errorCast](zig-0.15.1.md#toc-errorCast) <a href="zig-0.15.1.md#errorCast" class="hdr">§</a>

    @errorCast(value: anytype) anytype

Converts an error set or error union value from one error set to another error set. The return type is the
inferred result type. Attempting to convert an error which is not in the destination error
set results in safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

### [@export](zig-0.15.1.md#toc-export) <a href="zig-0.15.1.md#export" class="hdr">§</a>

    @export(comptime ptr: *const anyopaque, comptime options: std.builtin.ExportOptions) void

Creates a symbol in the output object file which refers to the target of `ptr`.

`ptr` must point to a global variable or a comptime-known constant.

This builtin can be called from a [comptime](zig-0.15.1.md#comptime) block to conditionally export symbols.
When `ptr` points to a function with the C calling convention and
`options.linkage` is `.strong`, this is equivalent to
the <span class="tok-kw">`export`</span> keyword used on a function:

<figure>
<pre><code>comptime {
    @export(&amp;internalName, .{ .name = &quot;foo&quot;, .linkage = .strong });
}

fn internalName() callconv(.c) void {}</code></pre>
<figcaption>export_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_builtin.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

This is equivalent to:

<figure>
<pre><code>export fn foo() void {}</code></pre>
<figcaption>export_builtin_equivalent_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_builtin_equivalent_code.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note that even when using <span class="tok-kw">`export`</span>, the `@"foo"` syntax for
[identifiers](zig-0.15.1.md#Identifiers) can be used to choose any string for the symbol name:

<figure>
<pre><code>export fn @&quot;A function name that is a complete sentence.&quot;() void {}</code></pre>
<figcaption>export_any_symbol_name.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_any_symbol_name.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

When looking at the resulting object, you can see the symbol is used verbatim:

    00000000000001f0 T A function name that is a complete sentence.

See also:

- [Exporting a C Library](zig-0.15.1.md#Exporting-a-C-Library)

### [@extern](zig-0.15.1.md#toc-extern) <a href="zig-0.15.1.md#extern" class="hdr">§</a>

    @extern(T: type, comptime options: std.builtin.ExternOptions) T

Creates a reference to an external symbol in the output object file.
T must be a pointer type.

See also:

- [@export](zig-0.15.1.md#export)

### [@field](zig-0.15.1.md#toc-field) <a href="zig-0.15.1.md#field" class="hdr">§</a>

    @field(lhs: anytype, comptime field_name: []const u8) (field)

Performs field access by a compile-time string. Works on both fields and declarations.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Point = struct {
    x: u32,
    y: u32,

    pub var z: u32 = 1;
};

test &quot;field access by string&quot; {
    const expect = std.testing.expect;
    var p = Point{ .x = 0, .y = 0 };

    @field(p, &quot;x&quot;) = 4;
    @field(p, &quot;y&quot;) = @field(p, &quot;x&quot;) + 1;

    try expect(@field(p, &quot;x&quot;) == 4);
    try expect(@field(p, &quot;y&quot;) == 5);
}

test &quot;decl access by string&quot; {
    const expect = std.testing.expect;

    try expect(@field(Point, &quot;z&quot;) == 1);

    @field(Point, &quot;z&quot;) = 2;
    try expect(@field(Point, &quot;z&quot;) == 2);
}</code></pre>
<figcaption>test_field_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_field_builtin.zig
1/2 test_field_builtin.test.field access by string...OK
2/2 test_field_builtin.test.decl access by string...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@fieldParentPtr](zig-0.15.1.md#toc-fieldParentPtr) <a href="zig-0.15.1.md#fieldParentPtr" class="hdr">§</a>

    @fieldParentPtr(comptime field_name: []const u8, field_ptr: *T) anytype

Given a pointer to a struct field, returns a pointer to the struct containing that field.
The return type (and struct in question) is the inferred result type.

If `field_ptr` does not point to the `field_name` field of an instance of
the result type, and the result type has ill-defined layout, invokes unchecked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

### [@FieldType](zig-0.15.1.md#toc-FieldType) <a href="zig-0.15.1.md#FieldType" class="hdr">§</a>

    @FieldType(comptime Type: type, comptime field_name: []const u8) type

Given a type and the name of one of its fields, returns the type of that field.

### [@floatCast](zig-0.15.1.md#toc-floatCast) <a href="zig-0.15.1.md#floatCast" class="hdr">§</a>

    @floatCast(value: anytype) anytype

Convert from one float type to another. This cast is safe, but may cause the
numeric value to lose precision. The return type is the inferred result type.

### [@floatFromInt](zig-0.15.1.md#toc-floatFromInt) <a href="zig-0.15.1.md#floatFromInt" class="hdr">§</a>

    @floatFromInt(int: anytype) anytype

Converts an integer to the closest floating point representation. The return type is the inferred result type.
To convert the other way, use [@intFromFloat](zig-0.15.1.md#intFromFloat). This operation is legal
for all values of all integer types.

### [@frameAddress](zig-0.15.1.md#toc-frameAddress) <a href="zig-0.15.1.md#frameAddress" class="hdr">§</a>

    @frameAddress() usize

This function returns the base pointer of the current stack frame.

The implications of this are target-specific and not consistent across all
platforms. The frame address may not be available in release mode due to
aggressive optimizations.

This function is only valid within function scope.

### [@hasDecl](zig-0.15.1.md#toc-hasDecl) <a href="zig-0.15.1.md#hasDecl" class="hdr">§</a>

    @hasDecl(comptime Container: type, comptime name: []const u8) bool

Returns whether or not a [container](zig-0.15.1.md#Containers) has a declaration
matching `name`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Foo = struct {
    nope: i32,

    pub var blah = &quot;xxx&quot;;
    const hi = 1;
};

test &quot;@hasDecl&quot; {
    try expect(@hasDecl(Foo, &quot;blah&quot;));

    // Even though `hi` is private, @hasDecl returns true because this test is
    // in the same file scope as Foo. It would return false if Foo was declared
    // in a different file.
    try expect(@hasDecl(Foo, &quot;hi&quot;));

    // @hasDecl is for declarations; not fields.
    try expect(!@hasDecl(Foo, &quot;nope&quot;));
    try expect(!@hasDecl(Foo, &quot;nope1234&quot;));
}</code></pre>
<figcaption>test_hasDecl_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_hasDecl_builtin.zig
1/1 test_hasDecl_builtin.test.@hasDecl...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@hasField](zig-0.15.1.md#hasField)

### [@hasField](zig-0.15.1.md#toc-hasField) <a href="zig-0.15.1.md#hasField" class="hdr">§</a>

    @hasField(comptime Container: type, comptime name: []const u8) bool

Returns whether the field name of a struct, union, or enum exists.

The result is a compile time constant.

It does not include functions, variables, or constants.

See also:

- [@hasDecl](zig-0.15.1.md#hasDecl)

### [@import](zig-0.15.1.md#toc-import) <a href="zig-0.15.1.md#import" class="hdr">§</a>

    @import(comptime target: []const u8) anytype

Imports the file at `target`, adding it to the compilation if it is not already
added. `target` is either a relative path to another file from the file containing
the <span class="tok-builtin">`@import`</span> call, or it is the name of a [module](zig-0.15.1.md#Compilation-Model), with
the import referring to the root source file of that module. Either way, the file path must end in
either `.zig` (for a Zig source file) or `.zon` (for a ZON data file).

If `target` refers to a Zig source file, then <span class="tok-builtin">`@import`</span> returns
that file's [corresponding struct type](zig-0.15.1.md#Source-File-Structs), essentially as if the builtin call was
replaced by <span class="tok-kw">`struct`</span>` { FILE_CONTENTS }`. The return type is <span class="tok-type">`type`</span>.

If `target` refers to a ZON file, then <span class="tok-builtin">`@import`</span> returns the value
of the literal in the file. If there is an inferred [result type](zig-0.15.1.md#Result-Types), then the return type
is that type, and the ZON literal is interpreted as that type ([Result Types](zig-0.15.1.md#Result-Types) are propagated through
the ZON expression). Otherwise, the return type is the type of the equivalent Zig expression, essentially as
if the builtin call was replaced by the ZON file contents.

The following modules are always available for import:

- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`)` - Zig Standard Library
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`)` - Target-specific information. The command `zig build-exe --show-builtin` outputs the source to stdout for reference.
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)` - Alias for the root module. In typical project structures, this means it refers back to `src/main.zig`.

See also:

- [Compile Variables](zig-0.15.1.md#Compile-Variables)
- [@embedFile](zig-0.15.1.md#embedFile)

### [@inComptime](zig-0.15.1.md#toc-inComptime) <a href="zig-0.15.1.md#inComptime" class="hdr">§</a>

    @inComptime() bool

Returns whether the builtin was run in a <span class="tok-kw">`comptime`</span> context. The result is a compile-time constant.

This can be used to provide alternative, comptime-friendly implementations of functions. It should not be used, for instance, to exclude certain functions from being evaluated at comptime.

See also:

- [comptime](zig-0.15.1.md#comptime)

### [@intCast](zig-0.15.1.md#toc-intCast) <a href="zig-0.15.1.md#intCast" class="hdr">§</a>

    @intCast(int: anytype) anytype

Converts an integer to another integer while keeping the same numerical value.
The return type is the inferred result type.
Attempting to convert a number which is out of range of the destination type results in
safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

<figure>
<pre><code>test &quot;integer cast panic&quot; {
    var a: u16 = 0xabcd; // runtime-known
    _ = &amp;a;
    const b: u8 = @intCast(a);
    _ = b;
}</code></pre>
<figcaption>test_intCast_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_intCast_builtin.zig
1/1 test_intCast_builtin.test.integer cast panic...thread 1097950 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/test_intCast_builtin.zig:4:19: 0x102c020 in test.integer cast panic (test_intCast_builtin.zig)
    const b: u8 = @intCast(a);
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
/home/andy/dev/zig/.zig-cache/o/f8f5d23c1adeea76700e35886c1e4bcf/test --seed=0x8786b231</code></pre>
<figcaption>Shell</figcaption>
</figure>

To truncate the significant bits of a number out of range of the destination type, use [@truncate](zig-0.15.1.md#truncate).

If `T` is <span class="tok-type">`comptime_int`</span>,
then this is semantically equivalent to [Type Coercion](zig-0.15.1.md#Type-Coercion).

### [@intFromBool](zig-0.15.1.md#toc-intFromBool) <a href="zig-0.15.1.md#intFromBool" class="hdr">§</a>

    @intFromBool(value: bool) u1

Converts <span class="tok-null">`true`</span> to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`u1`</span>`, `<span class="tok-number">`1`</span>`)` and <span class="tok-null">`false`</span> to
<span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`u1`</span>`, `<span class="tok-number">`0`</span>`)`.

### [@intFromEnum](zig-0.15.1.md#toc-intFromEnum) <a href="zig-0.15.1.md#intFromEnum" class="hdr">§</a>

    @intFromEnum(enum_or_tagged_union: anytype) anytype

Converts an enumeration value into its integer tag type. When a tagged union is passed,
the tag value is used as the enumeration value.

If there is only one possible enum value, the result is a <span class="tok-type">`comptime_int`</span>
known at [comptime](zig-0.15.1.md#comptime).

See also:

- [@enumFromInt](zig-0.15.1.md#enumFromInt)

### [@intFromError](zig-0.15.1.md#toc-intFromError) <a href="zig-0.15.1.md#intFromError" class="hdr">§</a>

    @intFromError(err: anytype) std.meta.Int(.unsigned, @bitSizeOf(anyerror))

Supports the following types:

- [The Global Error Set](zig-0.15.1.md#The-Global-Error-Set)
- [Error Set Type](zig-0.15.1.md#Error-Set-Type)
- [Error Union Type](zig-0.15.1.md#Error-Union-Type)

Converts an error to the integer representation of an error.

It is generally recommended to avoid this
cast, as the integer representation of an error is not stable across source code changes.

See also:

- [@errorFromInt](zig-0.15.1.md#errorFromInt)

### [@intFromFloat](zig-0.15.1.md#toc-intFromFloat) <a href="zig-0.15.1.md#intFromFloat" class="hdr">§</a>

    @intFromFloat(float: anytype) anytype

Converts the integer part of a floating point number to the inferred result type.

If the integer part of the floating point number cannot fit in the destination type,
it invokes safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

See also:

- [@floatFromInt](zig-0.15.1.md#floatFromInt)

### [@intFromPtr](zig-0.15.1.md#toc-intFromPtr) <a href="zig-0.15.1.md#intFromPtr" class="hdr">§</a>

    @intFromPtr(value: anytype) usize

Converts `value` to a <span class="tok-type">`usize`</span> which is the address of the pointer.
`value` can be `*T` or `?*T`.

To convert the other way, use [@ptrFromInt](zig-0.15.1.md#ptrFromInt)

### [@max](zig-0.15.1.md#toc-max) <a href="zig-0.15.1.md#max" class="hdr">§</a>

    @max(...) T

Takes two or more arguments and returns the biggest value included (the maximum). This builtin accepts integers, floats, and vectors of either. In the latter case, the operation is performed element wise.

NaNs are handled as follows: return the biggest non-NaN value included. If all operands are NaN, return NaN.

See also:

- [@min](zig-0.15.1.md#min)
- [Vectors](zig-0.15.1.md#Vectors)

### [@memcpy](zig-0.15.1.md#toc-memcpy) <a href="zig-0.15.1.md#memcpy" class="hdr">§</a>

    @memcpy(noalias dest, noalias source) void

This function copies bytes from one region of memory to another.

`dest` must be a mutable slice, a mutable pointer to an array, or
a mutable many-item [pointer](zig-0.15.1.md#Pointers). It may have any
alignment, and it may have any element type.

`source` must be a slice, a pointer to
an array, or a many-item [pointer](zig-0.15.1.md#Pointers). It may
have any alignment, and it may have any element type.

The `source` element type must have the same in-memory
representation as the `dest` element type.

Similar to [for](zig-0.15.1.md#for) loops, at least one of `source` and
`dest` must provide a length, and if two lengths are provided,
they must be equal.

Finally, the two memory regions must not overlap.

### [@memset](zig-0.15.1.md#toc-memset) <a href="zig-0.15.1.md#memset" class="hdr">§</a>

    @memset(dest, elem) void

This function sets all the elements of a memory region to `elem`.

`dest` must be a mutable slice or a mutable pointer to an array.
It may have any alignment, and it may have any element type.

`elem` is coerced to the element type of `dest`.

For securely zeroing out sensitive contents from memory, you should use
`std.crypto.secureZero`

### [@memmove](zig-0.15.1.md#toc-memmove) <a href="zig-0.15.1.md#memmove" class="hdr">§</a>

    @memmove(dest, source) void

This function copies bytes from one region of memory to another, but unlike
[@memcpy](zig-0.15.1.md#memcpy) the regions may overlap.

`dest` must be a mutable slice, a mutable pointer to an array, or
a mutable many-item [pointer](zig-0.15.1.md#Pointers). It may have any
alignment, and it may have any element type.

`source` must be a slice, a pointer to
an array, or a many-item [pointer](zig-0.15.1.md#Pointers). It may
have any alignment, and it may have any element type.

The `source` element type must have the same in-memory
representation as the `dest` element type.

Similar to [for](zig-0.15.1.md#for) loops, at least one of `source` and
`dest` must provide a length, and if two lengths are provided,
they must be equal.

### [@min](zig-0.15.1.md#toc-min) <a href="zig-0.15.1.md#min" class="hdr">§</a>

    @min(...) T

Takes two or more arguments and returns the smallest value included (the minimum). This builtin accepts integers, floats, and vectors of either. In the latter case, the operation is performed element wise.

NaNs are handled as follows: return the smallest non-NaN value included. If all operands are NaN, return NaN.

See also:

- [@max](zig-0.15.1.md#max)
- [Vectors](zig-0.15.1.md#Vectors)

### [@wasmMemorySize](zig-0.15.1.md#toc-wasmMemorySize) <a href="zig-0.15.1.md#wasmMemorySize" class="hdr">§</a>

    @wasmMemorySize(index: u32) usize

This function returns the size of the Wasm memory identified by `index` as
an unsigned value in units of Wasm pages. Note that each Wasm page is 64KB in size.

This function is a low level intrinsic with no safety mechanisms usually useful for allocator
designers targeting Wasm. So unless you are writing a new allocator from scratch, you should use
something like <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).heap.WasmPageAllocator`.

See also:

- [@wasmMemoryGrow](zig-0.15.1.md#wasmMemoryGrow)

### [@wasmMemoryGrow](zig-0.15.1.md#toc-wasmMemoryGrow) <a href="zig-0.15.1.md#wasmMemoryGrow" class="hdr">§</a>

    @wasmMemoryGrow(index: u32, delta: usize) isize

This function increases the size of the Wasm memory identified by `index` by
`delta` in units of unsigned number of Wasm pages. Note that each Wasm page
is 64KB in size. On success, returns previous memory size; on failure, if the allocation fails,
returns -1.

This function is a low level intrinsic with no safety mechanisms usually useful for allocator
designers targeting Wasm. So unless you are writing a new allocator from scratch, you should use
something like <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).heap.WasmPageAllocator`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const native_arch = @import(&quot;builtin&quot;).target.cpu.arch;
const expect = std.testing.expect;

test &quot;@wasmMemoryGrow&quot; {
    if (native_arch != .wasm32) return error.SkipZigTest;

    const prev = @wasmMemorySize(0);
    try expect(prev == @wasmMemoryGrow(0, 1));
    try expect(prev + 1 == @wasmMemorySize(0));
}</code></pre>
<figcaption>test_wasmMemoryGrow_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wasmMemoryGrow_builtin.zig
1/1 test_wasmMemoryGrow_builtin.test.@wasmMemoryGrow...SKIP
0 passed; 1 skipped; 0 failed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@wasmMemorySize](zig-0.15.1.md#wasmMemorySize)

### [@mod](zig-0.15.1.md#toc-mod) <a href="zig-0.15.1.md#mod" class="hdr">§</a>

    @mod(numerator: T, denominator: T) T

Modulus division. For unsigned integers this is the same as
`numerator % denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span>, otherwise the
operation will result in a [Remainder Division by Zero](zig-0.15.1.md#Remainder-Division-by-Zero) when runtime safety checks are enabled.

- <span class="tok-builtin">`@mod`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == `<span class="tok-number">`1`</span>
- `(`<span class="tok-builtin">`@divFloor`</span>`(a, b) * b) + `<span class="tok-builtin">`@mod`</span>`(a, b) == a`

For a function that returns an error code, see <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.mod`.

See also:

- [@rem](zig-0.15.1.md#rem)

### [@mulWithOverflow](zig-0.15.1.md#toc-mulWithOverflow) <a href="zig-0.15.1.md#mulWithOverflow" class="hdr">§</a>

    @mulWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a * b` and returns a tuple with the result and a possible overflow bit.

### [@panic](zig-0.15.1.md#toc-panic) <a href="zig-0.15.1.md#panic" class="hdr">§</a>

    @panic(message: []const u8) noreturn

Invokes the panic handler function. By default the panic handler function
calls the public `panic` function exposed in the root source file, or
if there is not one specified, the `std.builtin.default_panic`
function from `std/builtin.zig`.

Generally it is better to use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).debug.panic`.
However, <span class="tok-builtin">`@panic`</span> can be useful for 2 scenarios:

- From library code, calling the programmer's panic function if they exposed one in the root source file.
- When mixing C and Zig code, calling the canonical panic implementation across multiple .o files.

See also:

- [Panic Handler](zig-0.15.1.md#Panic-Handler)

### [@popCount](zig-0.15.1.md#toc-popCount) <a href="zig-0.15.1.md#popCount" class="hdr">§</a>

    @popCount(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type.

`operand` may be an [integer](zig-0.15.1.md#Integers) or [vector](zig-0.15.1.md#Vectors).

Counts the number of bits set in an integer - "population count".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

See also:

- [@ctz](zig-0.15.1.md#ctz)
- [@clz](zig-0.15.1.md#clz)

### [@prefetch](zig-0.15.1.md#toc-prefetch) <a href="zig-0.15.1.md#prefetch" class="hdr">§</a>

    @prefetch(ptr: anytype, comptime options: PrefetchOptions) void

This builtin tells the compiler to emit a prefetch instruction if supported by the
target CPU. If the target CPU does not support the requested prefetch instruction,
this builtin is a no-op. This function has no effect on the behavior of the program,
only on the performance characteristics.

The `ptr` argument may be any pointer type and determines the memory
address to prefetch. This function does not dereference the pointer, it is perfectly legal
to pass a pointer to invalid memory to this function and no Illegal Behavior will result.

`PrefetchOptions` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.PrefetchOptions`.

### [@ptrCast](zig-0.15.1.md#toc-ptrCast) <a href="zig-0.15.1.md#ptrCast" class="hdr">§</a>

    @ptrCast(value: anytype) anytype

Converts a pointer of one type to a pointer of another type. The return type is the inferred result type.

[Optional Pointers](zig-0.15.1.md#Optional-Pointers) are allowed. Casting an optional pointer which is [null](zig-0.15.1.md#null)
to a non-optional pointer invokes safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

<span class="tok-builtin">`@ptrCast`</span> cannot be used for:

- Removing <span class="tok-kw">`const`</span> qualifier, use [@constCast](zig-0.15.1.md#constCast).
- Removing <span class="tok-kw">`volatile`</span> qualifier, use [@volatileCast](zig-0.15.1.md#volatileCast).
- Changing pointer address space, use [@addrSpaceCast](zig-0.15.1.md#addrSpaceCast).
- Increasing pointer alignment, use [@alignCast](zig-0.15.1.md#alignCast).
- Casting a non-slice pointer to a slice, use slicing syntax `ptr[start..end]`.

### [@ptrFromInt](zig-0.15.1.md#toc-ptrFromInt) <a href="zig-0.15.1.md#ptrFromInt" class="hdr">§</a>

    @ptrFromInt(address: usize) anytype

Converts an integer to a [pointer](zig-0.15.1.md#Pointers). The return type is the inferred result type.
To convert the other way, use [@intFromPtr](zig-0.15.1.md#intFromPtr). Casting an address of 0 to a destination type
which in not [optional](zig-0.15.1.md#Optional-Pointers) and does not have the <span class="tok-kw">`allowzero`</span> attribute will result in a
[Pointer Cast Invalid Null](zig-0.15.1.md#Pointer-Cast-Invalid-Null) panic when runtime safety checks are enabled.

If the destination pointer type does not allow address zero and `address`
is zero, this invokes safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

### [@rem](zig-0.15.1.md#toc-rem) <a href="zig-0.15.1.md#rem" class="hdr">§</a>

    @rem(numerator: T, denominator: T) T

Remainder division. For unsigned integers this is the same as
`numerator % denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span>, otherwise the
operation will result in a [Remainder Division by Zero](zig-0.15.1.md#Remainder-Division-by-Zero) when runtime safety checks are enabled.

- <span class="tok-builtin">`@rem`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`2`</span>
- `(`<span class="tok-builtin">`@divTrunc`</span>`(a, b) * b) + `<span class="tok-builtin">`@rem`</span>`(a, b) == a`

For a function that returns an error code, see <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.rem`.

See also:

- [@mod](zig-0.15.1.md#mod)

### [@returnAddress](zig-0.15.1.md#toc-returnAddress) <a href="zig-0.15.1.md#returnAddress" class="hdr">§</a>

    @returnAddress() usize

This function returns the address of the next machine code instruction that will be executed
when the current function returns.

The implications of this are target-specific and not consistent across
all platforms.

This function is only valid within function scope. If the function gets inlined into
a calling function, the returned address will apply to the calling function.

### [@select](zig-0.15.1.md#toc-select) <a href="zig-0.15.1.md#select" class="hdr">§</a>

    @select(comptime T: type, pred: @Vector(len, bool), a: @Vector(len, T), b: @Vector(len, T)) @Vector(len, T)

Selects values element-wise from `a` or `b` based on `pred`. If `pred[i]` is <span class="tok-null">`true`</span>, the corresponding element in the result will be `a[i]` and otherwise `b[i]`.

See also:

- [Vectors](zig-0.15.1.md#Vectors)

### [@setEvalBranchQuota](zig-0.15.1.md#toc-setEvalBranchQuota) <a href="zig-0.15.1.md#setEvalBranchQuota" class="hdr">§</a>

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

- [comptime](zig-0.15.1.md#comptime)

### [@setFloatMode](zig-0.15.1.md#toc-setFloatMode) <a href="zig-0.15.1.md#setFloatMode" class="hdr">§</a>

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

- [Floating Point Operations](zig-0.15.1.md#Floating-Point-Operations)

### [@setRuntimeSafety](zig-0.15.1.md#toc-setRuntimeSafety) <a href="zig-0.15.1.md#setRuntimeSafety" class="hdr">§</a>

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

### [@shlExact](zig-0.15.1.md#toc-shlExact) <a href="zig-0.15.1.md#shlExact" class="hdr">§</a>

    @shlExact(value: T, shift_amt: Log2T) T

Performs the left shift operation (`<<`).
For unsigned integers, the result is [undefined](zig-0.15.1.md#undefined) if any 1 bits
are shifted out. For signed integers, the result is [undefined](zig-0.15.1.md#undefined) if
any bits that disagree with the resultant sign bit are shifted out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

<span class="tok-type">`comptime_int`</span> is modeled as an integer with an infinite number of bits,
meaning that in such case, <span class="tok-builtin">`@shlExact`</span> always produces a result and
cannot produce a compile error.

See also:

- [@shrExact](zig-0.15.1.md#shrExact)
- [@shlWithOverflow](zig-0.15.1.md#shlWithOverflow)

### [@shlWithOverflow](zig-0.15.1.md#toc-shlWithOverflow) <a href="zig-0.15.1.md#shlWithOverflow" class="hdr">§</a>

    @shlWithOverflow(a: anytype, shift_amt: Log2T) struct { @TypeOf(a), u1 }

Performs `a << b` and returns a tuple with the result and a possible overflow bit.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits` triggers safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

See also:

- [@shlExact](zig-0.15.1.md#shlExact)
- [@shrExact](zig-0.15.1.md#shrExact)

### [@shrExact](zig-0.15.1.md#toc-shrExact) <a href="zig-0.15.1.md#shrExact" class="hdr">§</a>

    @shrExact(value: T, shift_amt: Log2T) T

Performs the right shift operation (`>>`). Caller guarantees
that the shift will not shift any 1 bits out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

See also:

- [@shlExact](zig-0.15.1.md#shlExact)
- [@shlWithOverflow](zig-0.15.1.md#shlWithOverflow)

### [@shuffle](zig-0.15.1.md#toc-shuffle) <a href="zig-0.15.1.md#shuffle" class="hdr">§</a>

    @shuffle(comptime E: type, a: @Vector(a_len, E), b: @Vector(b_len, E), comptime mask: @Vector(mask_len, i32)) @Vector(mask_len, E)

Constructs a new [vector](zig-0.15.1.md#Vectors) by selecting elements from `a` and
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

`E` must be an [integer](zig-0.15.1.md#Integers), [float](zig-0.15.1.md#Floats),
[pointer](zig-0.15.1.md#Pointers), or <span class="tok-type">`bool`</span>. The mask may be any vector length, and its
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

- [Vectors](zig-0.15.1.md#Vectors)

### [@sizeOf](zig-0.15.1.md#toc-sizeOf) <a href="zig-0.15.1.md#sizeOf" class="hdr">§</a>

    @sizeOf(comptime T: type) comptime_int

This function returns the number of bytes it takes to store `T` in memory.
The result is a target-specific compile time constant.

This size may contain padding bytes. If there were two consecutive T in memory, the padding would be the offset
in bytes between element at index 0 and the element at index 1. For [integer](zig-0.15.1.md#Integers),
consider whether you want to use <span class="tok-builtin">`@sizeOf`</span>`(T)` or
<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits`.

This function measures the size at runtime. For types that are disallowed at runtime, such as
<span class="tok-type">`comptime_int`</span> and <span class="tok-type">`type`</span>, the result is <span class="tok-number">`0`</span>.

See also:

- [@bitSizeOf](zig-0.15.1.md#bitSizeOf)
- [@typeInfo](zig-0.15.1.md#typeInfo)

### [@splat](zig-0.15.1.md#toc-splat) <a href="zig-0.15.1.md#splat" class="hdr">§</a>

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

`scalar` must be an [integer](zig-0.15.1.md#Integers), [bool](zig-0.15.1.md#Primitive-Types),
[float](zig-0.15.1.md#Floats), or [pointer](zig-0.15.1.md#Pointers).

See also:

- [Vectors](zig-0.15.1.md#Vectors)
- [@shuffle](zig-0.15.1.md#shuffle)

### [@reduce](zig-0.15.1.md#toc-reduce) <a href="zig-0.15.1.md#reduce" class="hdr">§</a>

    @reduce(comptime op: std.builtin.ReduceOp, value: anytype) E

Transforms a [vector](zig-0.15.1.md#Vectors) into a scalar value (of type `E`)
by performing a sequential horizontal reduction of its elements using the
specified operator `op`.

Not every operator is available for every vector element type:

- Every operator is available for [integer](zig-0.15.1.md#Integers) vectors.
- `.And`, `.Or`,
  `.Xor` are additionally available for
  <span class="tok-type">`bool`</span> vectors,
- `.Min`, `.Max`,
  `.Add`, `.Mul` are
  additionally available for [floating point](zig-0.15.1.md#Floats) vectors,

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

- [Vectors](zig-0.15.1.md#Vectors)
- [@setFloatMode](zig-0.15.1.md#setFloatMode)

### [@src](zig-0.15.1.md#toc-src) <a href="zig-0.15.1.md#src" class="hdr">§</a>

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

### [@sqrt](zig-0.15.1.md#toc-sqrt) <a href="zig-0.15.1.md#sqrt" class="hdr">§</a>

    @sqrt(value: anytype) @TypeOf(value)

Performs the square root of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@sin](zig-0.15.1.md#toc-sin) <a href="zig-0.15.1.md#sin" class="hdr">§</a>

    @sin(value: anytype) @TypeOf(value)

Sine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@cos](zig-0.15.1.md#toc-cos) <a href="zig-0.15.1.md#cos" class="hdr">§</a>

    @cos(value: anytype) @TypeOf(value)

Cosine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@tan](zig-0.15.1.md#toc-tan) <a href="zig-0.15.1.md#tan" class="hdr">§</a>

    @tan(value: anytype) @TypeOf(value)

Tangent trigonometric function on a floating point number in radians.
Uses a dedicated hardware instruction when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@exp](zig-0.15.1.md#toc-exp) <a href="zig-0.15.1.md#exp" class="hdr">§</a>

    @exp(value: anytype) @TypeOf(value)

Base-e exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@exp2](zig-0.15.1.md#toc-exp2) <a href="zig-0.15.1.md#exp2" class="hdr">§</a>

    @exp2(value: anytype) @TypeOf(value)

Base-2 exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@log](zig-0.15.1.md#toc-log) <a href="zig-0.15.1.md#log" class="hdr">§</a>

    @log(value: anytype) @TypeOf(value)

Returns the natural logarithm of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@log2](zig-0.15.1.md#toc-log2) <a href="zig-0.15.1.md#log2" class="hdr">§</a>

    @log2(value: anytype) @TypeOf(value)

Returns the logarithm to the base 2 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@log10](zig-0.15.1.md#toc-log10) <a href="zig-0.15.1.md#log10" class="hdr">§</a>

    @log10(value: anytype) @TypeOf(value)

Returns the logarithm to the base 10 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@abs](zig-0.15.1.md#toc-abs) <a href="zig-0.15.1.md#abs" class="hdr">§</a>

    @abs(value: anytype) anytype

Returns the absolute value of an integer or a floating point number. Uses a dedicated hardware instruction
when available.
The return type is always an unsigned integer of the same bit width as the operand if the operand is an integer.
Unsigned integer operands are supported. The builtin cannot overflow for signed integer operands.

Supports [Floats](zig-0.15.1.md#Floats), [Integers](zig-0.15.1.md#Integers) and [Vectors](zig-0.15.1.md#Vectors) of floats or integers.

### [@floor](zig-0.15.1.md#toc-floor) <a href="zig-0.15.1.md#floor" class="hdr">§</a>

    @floor(value: anytype) @TypeOf(value)

Returns the largest integral value not greater than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@ceil](zig-0.15.1.md#toc-ceil) <a href="zig-0.15.1.md#ceil" class="hdr">§</a>

    @ceil(value: anytype) @TypeOf(value)

Returns the smallest integral value not less than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@trunc](zig-0.15.1.md#toc-trunc) <a href="zig-0.15.1.md#trunc" class="hdr">§</a>

    @trunc(value: anytype) @TypeOf(value)

Rounds the given floating point number to an integer, towards zero.
Uses a dedicated hardware instruction when available.

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@round](zig-0.15.1.md#toc-round) <a href="zig-0.15.1.md#round" class="hdr">§</a>

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

Supports [Floats](zig-0.15.1.md#Floats) and [Vectors](zig-0.15.1.md#Vectors) of floats.

### [@subWithOverflow](zig-0.15.1.md#toc-subWithOverflow) <a href="zig-0.15.1.md#subWithOverflow" class="hdr">§</a>

    @subWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a - b` and returns a tuple with the result and a possible overflow bit.

### [@tagName](zig-0.15.1.md#toc-tagName) <a href="zig-0.15.1.md#tagName" class="hdr">§</a>

    @tagName(value: anytype) [:0]const u8

Converts an enum value or union value to a string literal representing the name.

If the enum is non-exhaustive and the tag value does not map to a name, it invokes safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

### [@This](zig-0.15.1.md#toc-This) <a href="zig-0.15.1.md#This" class="hdr">§</a>

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

### [@trap](zig-0.15.1.md#toc-trap) <a href="zig-0.15.1.md#trap" class="hdr">§</a>

    @trap() noreturn

This function inserts a platform-specific trap/jam instruction which can be used to exit the program abnormally.
This may be implemented by explicitly emitting an invalid instruction which may cause an illegal instruction exception of some sort.
Unlike for <span class="tok-builtin">`@breakpoint`</span>`()`, execution does not continue after this point.

Outside function scope, this builtin causes a compile error.

See also:

- [@breakpoint](zig-0.15.1.md#breakpoint)

### [@truncate](zig-0.15.1.md#toc-truncate) <a href="zig-0.15.1.md#truncate" class="hdr">§</a>

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

Use [@intCast](zig-0.15.1.md#intCast) to convert numbers guaranteed to fit the destination type.

### [@Type](zig-0.15.1.md#toc-Type) <a href="zig-0.15.1.md#Type" class="hdr">§</a>

    @Type(comptime info: std.builtin.Type) type

This function is the inverse of [@typeInfo](zig-0.15.1.md#typeInfo). It reifies type information
into a <span class="tok-type">`type`</span>.

It is available for the following types:

- <span class="tok-type">`type`</span>
- <span class="tok-type">`noreturn`</span>
- <span class="tok-type">`void`</span>
- <span class="tok-type">`bool`</span>
- [Integers](zig-0.15.1.md#Integers) - The maximum bit count for an integer type is <span class="tok-number">`65535`</span>.
- [Floats](zig-0.15.1.md#Floats)
- [Pointers](zig-0.15.1.md#Pointers)
- <span class="tok-type">`comptime_int`</span>
- <span class="tok-type">`comptime_float`</span>
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`undefined`</span>`)`
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`null`</span>`)`
- [Arrays](zig-0.15.1.md#Arrays)
- [Optionals](zig-0.15.1.md#Optionals)
- [Error Set Type](zig-0.15.1.md#Error-Set-Type)
- [Error Union Type](zig-0.15.1.md#Error-Union-Type)
- [Vectors](zig-0.15.1.md#Vectors)
- [opaque](zig-0.15.1.md#opaque)
- <span class="tok-kw">`anyframe`</span>
- [struct](zig-0.15.1.md#struct)
- [enum](zig-0.15.1.md#enum)
- [Enum Literals](zig-0.15.1.md#Enum-Literals)
- [union](zig-0.15.1.md#union)
- [Functions](zig-0.15.1.md#Functions)

### [@typeInfo](zig-0.15.1.md#toc-typeInfo) <a href="zig-0.15.1.md#typeInfo" class="hdr">§</a>

    @typeInfo(comptime T: type) std.builtin.Type

Provides type reflection.

Type information of [structs](zig-0.15.1.md#struct), [unions](zig-0.15.1.md#union), [enums](zig-0.15.1.md#enum), and
[error sets](zig-0.15.1.md#Error-Set-Type) has fields which are guaranteed to be in the same
order as appearance in the source file.

Type information of [structs](zig-0.15.1.md#struct), [unions](zig-0.15.1.md#union), [enums](zig-0.15.1.md#enum), and
[opaques](zig-0.15.1.md#opaque) has declarations, which are also guaranteed to be in the same
order as appearance in the source file.

### [@typeName](zig-0.15.1.md#toc-typeName) <a href="zig-0.15.1.md#typeName" class="hdr">§</a>

    @typeName(T: type) *const [N:0]u8

This function returns the string representation of a type, as
an array. It is equivalent to a string literal of the type name.
The returned type name is fully qualified with the parent namespace included
as part of the type name with a series of dots.

### [@TypeOf](zig-0.15.1.md#toc-TypeOf) <a href="zig-0.15.1.md#TypeOf" class="hdr">§</a>

    @TypeOf(...) type

<span class="tok-builtin">`@TypeOf`</span> is a special builtin function that takes any (non-zero) number of expressions
as parameters and returns the type of the result, using [Peer Type Resolution](zig-0.15.1.md#Peer-Type-Resolution).

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

### [@unionInit](zig-0.15.1.md#toc-unionInit) <a href="zig-0.15.1.md#unionInit" class="hdr">§</a>

    @unionInit(comptime Union: type, comptime active_field_name: []const u8, init_expr) Union

This is the same thing as [union](zig-0.15.1.md#union) initialization syntax, except that the field name is a
[comptime](zig-0.15.1.md#comptime)-known value rather than an identifier token.

<span class="tok-builtin">`@unionInit`</span> forwards its [result location](zig-0.15.1.md#Result-Location-Semantics) to `init_expr`.

### [@Vector](zig-0.15.1.md#toc-Vector) <a href="zig-0.15.1.md#Vector" class="hdr">§</a>

    @Vector(len: comptime_int, Element: type) type

Creates [Vectors](zig-0.15.1.md#Vectors).

### [@volatileCast](zig-0.15.1.md#toc-volatileCast) <a href="zig-0.15.1.md#volatileCast" class="hdr">§</a>

    @volatileCast(value: anytype) DestType

Remove <span class="tok-kw">`volatile`</span> qualifier from a pointer.

### [@workGroupId](zig-0.15.1.md#toc-workGroupId) <a href="zig-0.15.1.md#workGroupId" class="hdr">§</a>

    @workGroupId(comptime dimension: u32) u32

Returns the index of the work group in the current kernel invocation in dimension `dimension`.

### [@workGroupSize](zig-0.15.1.md#toc-workGroupSize) <a href="zig-0.15.1.md#workGroupSize" class="hdr">§</a>

    @workGroupSize(comptime dimension: u32) u32

Returns the number of work items that a work group has in dimension `dimension`.

### [@workItemId](zig-0.15.1.md#toc-workItemId) <a href="zig-0.15.1.md#workItemId" class="hdr">§</a>

    @workItemId(comptime dimension: u32) u32

Returns the index of the work item in the work group in dimension `dimension`. This function returns values between <span class="tok-number">`0`</span> (inclusive) and <span class="tok-builtin">`@workGroupSize`</span>`(dimension)` (exclusive).

