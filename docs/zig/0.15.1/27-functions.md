<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Functions -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Functions](zig-0.15.1.md#toc-Functions) <a href="zig-0.15.1.md#Functions" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const native_arch = builtin.cpu.arch;
const expect = std.testing.expect;

// Functions are declared like this
fn add(a: i8, b: i8) i8 {
    if (a == 0) {
        return b;
    }

    return a + b;
}

// The export specifier makes a function externally visible in the generated
// object file, and makes it use the C ABI.
export fn sub(a: i8, b: i8) i8 {
    return a - b;
}

// The extern specifier is used to declare a function that will be resolved
// at link time, when linking statically, or at runtime, when linking
// dynamically. The quoted identifier after the extern keyword specifies
// the library that has the function. (e.g. &quot;c&quot; -&gt; libc.so)
// The callconv specifier changes the calling convention of the function.
extern &quot;kernel32&quot; fn ExitProcess(exit_code: u32) callconv(.winapi) noreturn;
extern &quot;c&quot; fn atan2(a: f64, b: f64) f64;

// The @branchHint builtin can be used to tell the optimizer that a function is rarely called (&quot;cold&quot;).
fn abort() noreturn {
    @branchHint(.cold);
    while (true) {}
}

// The naked calling convention makes a function not have any function prologue or epilogue.
// This can be useful when integrating with assembly.
fn _start() callconv(.naked) noreturn {
    abort();
}

// The inline calling convention forces a function to be inlined at all call sites.
// If the function cannot be inlined, it is a compile-time error.
inline fn shiftLeftOne(a: u32) u32 {
    return a &lt;&lt; 1;
}

// The pub specifier allows the function to be visible when importing.
// Another file can use @import and call sub2
pub fn sub2(a: i8, b: i8) i8 {
    return a - b;
}

// Function pointers are prefixed with `*const `.
const Call2Op = *const fn (a: i8, b: i8) i8;
fn doOp(fnCall: Call2Op, op1: i8, op2: i8) i8 {
    return fnCall(op1, op2);
}

test &quot;function&quot; {
    try expect(doOp(add, 5, 6) == 11);
    try expect(doOp(sub2, 5, 6) == -1);
}</code></pre>
<figcaption>test_functions.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_functions.zig
1/1 test_functions.test.function...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

There is a difference between a function *body* and a function *pointer*.
Function bodies are [comptime](zig-0.15.1.md#comptime)-only types while function [Pointers](zig-0.15.1.md#Pointers) may be
runtime-known.

### [Pass-by-value Parameters](zig-0.15.1.md#toc-Pass-by-value-Parameters) <a href="zig-0.15.1.md#Pass-by-value-Parameters" class="hdr">§</a>

Primitive types such as [Integers](zig-0.15.1.md#Integers) and [Floats](zig-0.15.1.md#Floats) passed as parameters
are copied, and then the copy is available in the function body. This is called "passing by value".
Copying a primitive type is essentially free and typically involves nothing more than
setting a register.

Structs, unions, and arrays can sometimes be more efficiently passed as a reference, since a copy
could be arbitrarily expensive depending on the size. When these types are passed
as parameters, Zig may choose to copy and pass by value, or pass by reference, whichever way
Zig decides will be faster. This is made possible, in part, by the fact that parameters are immutable.

<figure>
<pre><code>const Point = struct {
    x: i32,
    y: i32,
};

fn foo(point: Point) i32 {
    // Here, `point` could be a reference, or a copy. The function body
    // can ignore the difference and treat it as a value. Be very careful
    // taking the address of the parameter - it should be treated as if
    // the address will become invalid when the function returns.
    return point.x + point.y;
}

const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pass struct to function&quot; {
    try expect(foo(Point{ .x = 1, .y = 2 }) == 3);
}</code></pre>
<figcaption>test_pass_by_reference_or_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pass_by_reference_or_value.zig
1/1 test_pass_by_reference_or_value.test.pass struct to function...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

For extern functions, Zig follows the C ABI for passing structs and unions by value.

### [Function Parameter Type Inference](zig-0.15.1.md#toc-Function-Parameter-Type-Inference) <a href="zig-0.15.1.md#Function-Parameter-Type-Inference" class="hdr">§</a>

Function parameters can be declared with <span class="tok-kw">`anytype`</span> in place of the type.
In this case the parameter types will be inferred when the function is called.
Use [@TypeOf](zig-0.15.1.md#TypeOf) and [@typeInfo](zig-0.15.1.md#typeInfo) to get information about the inferred type.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

fn addFortyTwo(x: anytype) @TypeOf(x) {
    return x + 42;
}

test &quot;fn type inference&quot; {
    try expect(addFortyTwo(1) == 43);
    try expect(@TypeOf(addFortyTwo(1)) == comptime_int);
    const y: i64 = 2;
    try expect(addFortyTwo(y) == 44);
    try expect(@TypeOf(addFortyTwo(y)) == i64);
}</code></pre>
<figcaption>test_fn_type_inference.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fn_type_inference.zig
1/1 test_fn_type_inference.test.fn type inference...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline fn](zig-0.15.1.md#toc-inline-fn) <a href="zig-0.15.1.md#inline-fn" class="hdr">§</a>

Adding the <span class="tok-kw">`inline`</span> keyword to a function definition makes that
function become *semantically inlined* at the callsite. This is
not a hint to be possibly observed by optimization passes, but has
implications on the types and values involved in the function call.

Unlike normal function calls, arguments at an inline function callsite which are
compile-time known are treated as [Compile Time Parameters](zig-0.15.1.md#Compile-Time-Parameters). This can potentially
propagate all the way to the return value:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    if (foo(1200, 34) != 1234) {
        @compileError(&quot;bad&quot;);
    }
}

inline fn foo(a: i32, b: i32) i32 {
    std.debug.print(&quot;runtime a = {} b = {}&quot;, .{ a, b });
    return a + b;
}</code></pre>
<figcaption>inline_call.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe inline_call.zig
$ ./inline_call
runtime a = 1200 b = 34</code></pre>
<figcaption>Shell</figcaption>
</figure>

If <span class="tok-kw">`inline`</span> is removed, the test fails with the compile error
instead of passing.

It is generally better to let the compiler decide when to inline a
function, except for these scenarios:

- To change how many stack frames are in the call stack, for debugging purposes.
- To force comptime-ness of the arguments to propagate to the return value of the function, as in the above example.
- Real world performance measurements demand it.

Note that <span class="tok-kw">`inline`</span> actually *restricts*
what the compiler is allowed to do. This can harm binary size,
compilation speed, and even runtime performance.

### [Function Reflection](zig-0.15.1.md#toc-Function-Reflection) <a href="zig-0.15.1.md#Function-Reflection" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const math = std.math;
const testing = std.testing;

test &quot;fn reflection&quot; {
    try testing.expect(@typeInfo(@TypeOf(testing.expect)).@&quot;fn&quot;.params[0].type.? == bool);
    try testing.expect(@typeInfo(@TypeOf(testing.tmpDir)).@&quot;fn&quot;.return_type.? == testing.TmpDir);

    try testing.expect(@typeInfo(@TypeOf(math.Log2Int)).@&quot;fn&quot;.is_generic);
}</code></pre>
<figcaption>test_fn_reflection.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fn_reflection.zig
1/1 test_fn_reflection.test.fn reflection...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

