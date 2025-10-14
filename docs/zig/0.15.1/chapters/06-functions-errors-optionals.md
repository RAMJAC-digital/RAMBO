<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Functions, Errors & Optionals

Included sections:
- Functions
- Errors
- Optionals
- Casting
- Zero Bit Types

### [Pass-by-value Parameters](../zig-0.15.1.md#toc-Pass-by-value-Parameters) <a href="../zig-0.15.1.md#Pass-by-value-Parameters" class="hdr">§</a>

Primitive types such as [Integers](../zig-0.15.1.md#Integers) and [Floats](../zig-0.15.1.md#Floats) passed as parameters
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


### [Function Parameter Type Inference](../zig-0.15.1.md#toc-Function-Parameter-Type-Inference) <a href="../zig-0.15.1.md#Function-Parameter-Type-Inference" class="hdr">§</a>

Function parameters can be declared with <span class="tok-kw">`anytype`</span> in place of the type.
In this case the parameter types will be inferred when the function is called.
Use [@TypeOf](../zig-0.15.1.md#TypeOf) and [@typeInfo](../zig-0.15.1.md#typeInfo) to get information about the inferred type.

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


### [inline fn](../zig-0.15.1.md#toc-inline-fn) <a href="../zig-0.15.1.md#inline-fn" class="hdr">§</a>

Adding the <span class="tok-kw">`inline`</span> keyword to a function definition makes that
function become *semantically inlined* at the callsite. This is
not a hint to be possibly observed by optimization passes, but has
implications on the types and values involved in the function call.

Unlike normal function calls, arguments at an inline function callsite which are
compile-time known are treated as [Compile Time Parameters](../zig-0.15.1.md#Compile-Time-Parameters). This can potentially
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


### [Function Reflection](../zig-0.15.1.md#toc-Function-Reflection) <a href="../zig-0.15.1.md#Function-Reflection" class="hdr">§</a>

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

## [Errors](../zig-0.15.1.md#toc-Errors) <a href="../zig-0.15.1.md#Errors" class="hdr">§</a>


### [Error Set Type](../zig-0.15.1.md#toc-Error-Set-Type) <a href="../zig-0.15.1.md#Error-Set-Type" class="hdr">§</a>

An error set is like an [enum](../zig-0.15.1.md#enum).
However, each error name across the entire compilation gets assigned an unsigned integer
greater than 0. You are allowed to declare the same error name more than once, and if you do, it
gets assigned the same integer value.

The error set type defaults to a <span class="tok-type">`u16`</span>, though if the maximum number of distinct
error values is provided via the <span class="kbd">--error-limit \[num\]</span> command line parameter an integer type
with the minimum number of bits required to represent all of the error values will be used.

You can [coerce](../zig-0.15.1.md#Type-Coercion) an error from a subset to a superset:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test &quot;coerce subset to superset&quot; {
    const err = foo(AllocationError.OutOfMemory);
    try std.testing.expect(err == FileOpenError.OutOfMemory);
}

fn foo(err: AllocationError) FileOpenError {
    return err;
}</code></pre>
<figcaption>test_coerce_error_subset_to_superset.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_error_subset_to_superset.zig
1/1 test_coerce_error_subset_to_superset.test.coerce subset to superset...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

But you cannot [coerce](../zig-0.15.1.md#Type-Coercion) an error from a superset to a subset:

<figure>
<pre><code>const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test &quot;coerce superset to subset&quot; {
    foo(FileOpenError.OutOfMemory) catch {};
}

fn foo(err: FileOpenError) AllocationError {
    return err;
}</code></pre>
<figcaption>test_coerce_error_superset_to_subset.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_error_superset_to_subset.zig
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: error: expected type &#39;error{OutOfMemory}&#39;, found &#39;error{AccessDenied,FileNotFound,OutOfMemory}&#39;
    return err;
           ^~~
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: &#39;error.AccessDenied&#39; not a member of destination error set
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: &#39;error.FileNotFound&#39; not a member of destination error set
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:15:28: note: function return type declared here
fn foo(err: FileOpenError) AllocationError {
                           ^~~~~~~~~~~~~~~
referenced by:
    test.coerce superset to subset: /home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:12:8
</code></pre>
<figcaption>Shell</figcaption>
</figure>

There is a shortcut for declaring an error set with only 1 value, and then getting that value:

<figure>
<pre><code>const err = error.FileNotFound;</code></pre>
<figcaption>single_value_error_set_shortcut.zig</figcaption>
</figure>

This is equivalent to:

<figure>
<pre><code>const err = (error{FileNotFound}).FileNotFound;</code></pre>
<figcaption>single_value_error_set.zig</figcaption>
</figure>

This becomes useful when using [Inferred Error Sets](../zig-0.15.1.md#Inferred-Error-Sets).

#### [The Global Error Set](../zig-0.15.1.md#toc-The-Global-Error-Set) <a href="../zig-0.15.1.md#The-Global-Error-Set" class="hdr">§</a>

<span class="tok-type">`anyerror`</span> refers to the global error set.
This is the error set that contains all errors in the entire compilation unit, i.e. it is the union of all other error sets.

You can [coerce](../zig-0.15.1.md#Type-Coercion) any error set to the global one, and you can explicitly
cast an error of the global error set to a non-global one. This inserts a language-level
assert to make sure the error value is in fact in the destination error set.

The global error set should generally be avoided because it prevents the
compiler from knowing what errors are possible at compile-time. Knowing
the error set at compile-time is better for generated documentation and
helpful error messages, such as forgetting a possible error value in a [switch](../zig-0.15.1.md#switch).


### [Error Union Type](../zig-0.15.1.md#toc-Error-Union-Type) <a href="../zig-0.15.1.md#Error-Union-Type" class="hdr">§</a>

An error set type and normal type can be combined with the `!`
binary operator to form an error union type. You are likely to use an
error union type more often than an error set type by itself.

Here is a function to parse a string into a 64-bit integer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const maxInt = std.math.maxInt;

pub fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;

    for (buf) |c| {
        const digit = charToDigit(c);

        if (digit &gt;= radix) {
            return error.InvalidChar;
        }

        // x *= radix
        var ov = @mulWithOverflow(x, radix);
        if (ov[1] != 0) return error.OverFlow;

        // x += digit
        ov = @addWithOverflow(ov[0], digit);
        if (ov[1] != 0) return error.OverFlow;
        x = ov[0];
    }

    return x;
}

fn charToDigit(c: u8) u8 {
    return switch (c) {
        &#39;0&#39;...&#39;9&#39; =&gt; c - &#39;0&#39;,
        &#39;A&#39;...&#39;Z&#39; =&gt; c - &#39;A&#39; + 10,
        &#39;a&#39;...&#39;z&#39; =&gt; c - &#39;a&#39; + 10,
        else =&gt; maxInt(u8),
    };
}

test &quot;parse u64&quot; {
    const result = try parseU64(&quot;1234&quot;, 10);
    try std.testing.expect(result == 1234);
}</code></pre>
<figcaption>error_union_parsing_u64.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test error_union_parsing_u64.zig
1/1 error_union_parsing_u64.test.parse u64...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Notice the return type is `!`<span class="tok-type">`u64`</span>. This means that the function
either returns an unsigned 64 bit integer, or an error. We left off the error set
to the left of the `!`, so the error set is inferred.

Within the function definition, you can see some return statements that return
an error, and at the bottom a return statement that returns a <span class="tok-type">`u64`</span>.
Both types [coerce](../zig-0.15.1.md#Type-Coercion) to <span class="tok-type">`anyerror`</span>`!`<span class="tok-type">`u64`</span>.

What it looks like to use this function varies depending on what you're
trying to do. One of the following:

- You want to provide a default value if it returned an error.
- If it returned an error then you want to return the same error.
- You know with complete certainty it will not return an error, so want to unconditionally unwrap it.
- You want to take a different action for each possible error.

#### [catch](../zig-0.15.1.md#toc-catch) <a href="../zig-0.15.1.md#catch" class="hdr">§</a>

If you want to provide a default value, you can use the <span class="tok-kw">`catch`</span> binary operator:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch 13;
    _ = number; // ...
}</code></pre>
<figcaption>catch.zig</figcaption>
</figure>

In this code, `number` will be equal to the successfully parsed string, or
a default value of 13. The type of the right hand side of the binary <span class="tok-kw">`catch`</span> operator must
match the unwrapped error union type, or be of type <span class="tok-type">`noreturn`</span>.

If you want to provide a default value with
<span class="tok-kw">`catch`</span> after performing some logic, you
can combine <span class="tok-kw">`catch`</span> with named [Blocks](../zig-0.15.1.md#Blocks):

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch blk: {
        // do things
        break :blk 13;
    };
    _ = number; // number is now initialized
}</code></pre>
<figcaption>handle_error_with_catch_block.zig.zig</figcaption>
</figure>

#### [try](../zig-0.15.1.md#toc-try) <a href="../zig-0.15.1.md#try" class="hdr">§</a>

Let's say you wanted to return the error if you got one, otherwise continue with the
function logic:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) !void {
    const number = parseU64(str, 10) catch |err| return err;
    _ = number; // ...
}</code></pre>
<figcaption>catch_err_return.zig</figcaption>
</figure>

There is a shortcut for this. The <span class="tok-kw">`try`</span> expression:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) !void {
    const number = try parseU64(str, 10);
    _ = number; // ...
}</code></pre>
<figcaption>try.zig</figcaption>
</figure>

<span class="tok-kw">`try`</span> evaluates an error union expression. If it is an error, it returns
from the current function with the same error. Otherwise, the expression results in
the unwrapped value.

Maybe you know with complete certainty that an expression will never be an error.
In this case you can do this:

<span class="tok-kw">`const`</span>` number = parseU64(`<span class="tok-str">`"1234"`</span>`, `<span class="tok-number">`10`</span>`) `<span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span>`;`

Here we know for sure that "1234" will parse successfully. So we put the
<span class="tok-kw">`unreachable`</span> value on the right hand side.
<span class="tok-kw">`unreachable`</span> invokes safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior), so
in [Debug](../zig-0.15.1.md#Debug) and [ReleaseSafe](../zig-0.15.1.md#ReleaseSafe), triggers a safety panic by default. So, while
we're debugging the application, if there *was* a surprise error here, the application
would crash appropriately.

You may want to take a different action for every situation. For that, we combine
the [if](../zig-0.15.1.md#if) and [switch](../zig-0.15.1.md#switch) expression:

<figure>
<pre><code>fn doAThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow =&gt; {
            // handle overflow...
        },
        // we promise that InvalidChar won&#39;t happen (or crash in debug mode if it does)
        error.InvalidChar =&gt; unreachable,
    }
}</code></pre>
<figcaption>handle_all_error_scenarios.zig</figcaption>
</figure>

Finally, you may want to handle only some errors. For that, you can capture the unhandled
errors in the <span class="tok-kw">`else`</span> case, which now contains a narrower error set:

<figure>
<pre><code>fn doAnotherThing(str: []u8) error{InvalidChar}!void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow =&gt; {
            // handle overflow...
        },
        else =&gt; |leftover_err| return leftover_err,
    }
}</code></pre>
<figcaption>handle_some_error_scenarios.zig</figcaption>
</figure>

You must use the variable capture syntax. If you don't need the
variable, you can capture with `_` and avoid the
<span class="tok-kw">`switch`</span>.

<figure>
<pre><code>fn doADifferentThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |_| {
        // do as you&#39;d like
    }
}</code></pre>
<figcaption>handle_no_error_scenarios.zig</figcaption>
</figure>

#### [errdefer](../zig-0.15.1.md#toc-errdefer) <a href="../zig-0.15.1.md#errdefer" class="hdr">§</a>

The other component to error handling is defer statements.
In addition to an unconditional [defer](../zig-0.15.1.md#defer), Zig has <span class="tok-kw">`errdefer`</span>,
which evaluates the deferred expression on block exit path if and only if
the function returned with an error from the block.

Example:

<figure>
<pre><code>fn createFoo(param: i32) !Foo {
    const foo = try tryToAllocateFoo();
    // now we have allocated foo. we need to free it if the function fails.
    // but we want to return it if the function succeeds.
    errdefer deallocateFoo(foo);

    const tmp_buf = allocateTmpBuffer() orelse return error.OutOfMemory;
    // tmp_buf is truly a temporary resource, and we for sure want to clean it up
    // before this block leaves scope
    defer deallocateTmpBuffer(tmp_buf);

    if (param &gt; 1337) return error.InvalidParam;

    // here the errdefer will not run since we&#39;re returning success from the function.
    // but the defer will run!
    return foo;
}</code></pre>
<figcaption>errdefer_example.zig</figcaption>
</figure>

The neat thing about this is that you get robust error handling without
the verbosity and cognitive overhead of trying to make sure every exit path
is covered. The deallocation code is always directly following the allocation code.

The <span class="tok-kw">`errdefer`</span> statement can optionally capture the error:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

fn captureError(captured: *?anyerror) !void {
    errdefer |err| {
        captured.* = err;
    }
    return error.GeneralFailure;
}

test &quot;errdefer capture&quot; {
    var captured: ?anyerror = null;

    if (captureError(&amp;captured)) unreachable else |err| {
        try std.testing.expectEqual(error.GeneralFailure, captured.?);
        try std.testing.expectEqual(error.GeneralFailure, err);
    }
}</code></pre>
<figcaption>test_errdefer_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_errdefer_capture.zig
1/1 test_errdefer_capture.test.errdefer capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

A couple of other tidbits about error handling:

- These primitives give enough expressiveness that it's completely practical
  to have failing to check for an error be a compile error. If you really want
  to ignore the error, you can add <span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span> and
  get the added benefit of crashing in Debug and ReleaseSafe modes if your assumption was wrong.
- Since Zig understands error types, it can pre-weight branches in favor of
  errors not occurring. Just a small optimization benefit that is not available
  in other languages.

See also:

- [defer](../zig-0.15.1.md#defer)
- [if](../zig-0.15.1.md#if)
- [switch](../zig-0.15.1.md#switch)

An error union is created with the `!` binary operator.
You can use compile-time reflection to access the child type of an error union:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;error union&quot; {
    var foo: anyerror!i32 = undefined;

    // Coerce from child type of an error union:
    foo = 1234;

    // Coerce from an error set:
    foo = error.SomeError;

    // Use compile-time reflection to access the payload type of an error union:
    try comptime expect(@typeInfo(@TypeOf(foo)).error_union.payload == i32);

    // Use compile-time reflection to access the error set type of an error union:
    try comptime expect(@typeInfo(@TypeOf(foo)).error_union.error_set == anyerror);
}</code></pre>
<figcaption>test_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_error_union.zig
1/1 test_error_union.test.error union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Merging Error Sets](../zig-0.15.1.md#toc-Merging-Error-Sets) <a href="../zig-0.15.1.md#Merging-Error-Sets" class="hdr">§</a>

Use the `||` operator to merge two error sets together. The resulting
error set contains the errors of both error sets. Doc comments from the left-hand
side override doc comments from the right-hand side. In this example, the doc
comments for `C.PathNotFound` is `A doc comment`.

This is especially useful for functions which return different error sets depending
on [comptime](../zig-0.15.1.md#comptime) branches. For example, the Zig standard library uses
`LinuxFileOpenError || WindowsFileOpenError` for the error set of opening
files.

<figure>
<pre><code>const A = error{
    NotDir,

    /// A doc comment
    PathNotFound,
};
const B = error{
    OutOfMemory,

    /// B doc comment
    PathNotFound,
};

const C = A || B;

fn foo() C!void {
    return error.NotDir;
}

test &quot;merge error sets&quot; {
    if (foo()) {
        @panic(&quot;unexpected&quot;);
    } else |err| switch (err) {
        error.OutOfMemory =&gt; @panic(&quot;unexpected&quot;),
        error.PathNotFound =&gt; @panic(&quot;unexpected&quot;),
        error.NotDir =&gt; {},
    }
}</code></pre>
<figcaption>test_merging_error_sets.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_merging_error_sets.zig
1/1 test_merging_error_sets.test.merge error sets...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Inferred Error Sets](../zig-0.15.1.md#toc-Inferred-Error-Sets) <a href="../zig-0.15.1.md#Inferred-Error-Sets" class="hdr">§</a>

Because many functions in Zig return a possible error, Zig supports inferring the error set.
To infer the error set for a function, prepend the `!` operator to the function’s return type, like `!T`:

<figure>
<pre><code>// With an inferred error set
pub fn add_inferred(comptime T: type, a: T, b: T) !T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

// With an explicit error set
pub fn add_explicit(comptime T: type, a: T, b: T) Error!T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

const Error = error{
    Overflow,
};

const std = @import(&quot;std&quot;);

test &quot;inferred error set&quot; {
    if (add_inferred(u8, 255, 1)) |_| unreachable else |err| switch (err) {
        error.Overflow =&gt; {}, // ok
    }
}</code></pre>
<figcaption>test_inferred_error_sets.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inferred_error_sets.zig
1/1 test_inferred_error_sets.test.inferred error set...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When a function has an inferred error set, that function becomes generic and thus it becomes
trickier to do certain things with it, such as obtain a function pointer, or have an error
set that is consistent across different build targets. Additionally, inferred error sets
are incompatible with recursion.

In these situations, it is recommended to use an explicit error set. You can generally start
with an empty error set and let compile errors guide you toward completing the set.

These limitations may be overcome in a future version of Zig.


### [Error Return Traces](../zig-0.15.1.md#toc-Error-Return-Traces) <a href="../zig-0.15.1.md#Error-Return-Traces" class="hdr">§</a>

Error Return Traces show all the points in the code that an error was returned to the calling function. This makes it practical to use [try](../zig-0.15.1.md#try) everywhere and then still be able to know what happened if an error ends up bubbling all the way out of your application.

<figure>
<pre><code>pub fn main() !void {
    try foo(12);
}

fn foo(x: i32) !void {
    if (x &gt;= 5) {
        try bar();
    } else {
        try bang2();
    }
}

fn bar() !void {
    if (baz()) {
        try quux();
    } else |err| switch (err) {
        error.FileNotFound =&gt; try hello(),
    }
}

fn baz() !void {
    try bang1();
}

fn quux() !void {
    try bang2();
}

fn hello() !void {
    try bang2();
}

fn bang1() !void {
    return error.FileNotFound;
}

fn bang2() !void {
    return error.PermissionDenied;
}</code></pre>
<figcaption>error_return_trace.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe error_return_trace.zig
$ ./error_return_trace
error: PermissionDenied
/home/andy/dev/zig/doc/langref/error_return_trace.zig:34:5: 0x113d34c in bang1 (error_return_trace.zig)
    return error.FileNotFound;
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:22:5: 0x113d396 in baz (error_return_trace.zig)
    try bang1();
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:38:5: 0x113d3cc in bang2 (error_return_trace.zig)
    return error.PermissionDenied;
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:30:5: 0x113d476 in hello (error_return_trace.zig)
    try bang2();
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:17:31: 0x113d54e in bar (error_return_trace.zig)
        error.FileNotFound =&gt; try hello(),
                              ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:7:9: 0x113d634 in foo (error_return_trace.zig)
        try bar();
        ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:2:5: 0x113d6fb in main (error_return_trace.zig)
    try foo(12);
    ^</code></pre>
<figcaption>Shell</figcaption>
</figure>

Look closely at this example. This is no stack trace.

You can see that the final error bubbled up was `PermissionDenied`,
but the original error that started this whole thing was `FileNotFound`. In the `bar` function, the code handles the original error code,
and then returns another one, from the switch statement. Error Return Traces make this clear, whereas a stack trace would look like this:

<figure>
<pre><code>pub fn main() void {
    foo(12);
}

fn foo(x: i32) void {
    if (x &gt;= 5) {
        bar();
    } else {
        bang2();
    }
}

fn bar() void {
    if (baz()) {
        quux();
    } else {
        hello();
    }
}

fn baz() bool {
    return bang1();
}

fn quux() void {
    bang2();
}

fn hello() void {
    bang2();
}

fn bang1() bool {
    return false;
}

fn bang2() void {
    @panic(&quot;PermissionDenied&quot;);
}</code></pre>
<figcaption>stack_trace.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe stack_trace.zig
$ ./stack_trace
thread 1093966 panic: PermissionDenied
/home/andy/dev/zig/doc/langref/stack_trace.zig:38:5: 0x1140e4c in bang2 (stack_trace.zig)
    @panic(&quot;PermissionDenied&quot;);
    ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:30:10: 0x114148c in hello (stack_trace.zig)
    bang2();
         ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:17:14: 0x1140e03 in bar (stack_trace.zig)
        hello();
             ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:7:12: 0x1140a98 in foo (stack_trace.zig)
        bar();
           ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:2:8: 0x113f851 in main (stack_trace.zig)
    foo(12);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113ea9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113e331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

Here, the stack trace does not explain how the control
flow in `bar` got to the `hello()` call.
One would have to open a debugger or further instrument the application
in order to find out. The error return trace, on the other hand,
shows exactly how the error bubbled up.

This debugging feature makes it easier to iterate quickly on code that
robustly handles all error conditions. This means that Zig developers
will naturally find themselves writing correct, robust code in order
to increase their development pace.

Error Return Traces are enabled by default in [Debug](../zig-0.15.1.md#Debug) builds and disabled by default in [ReleaseFast](../zig-0.15.1.md#ReleaseFast), [ReleaseSafe](../zig-0.15.1.md#ReleaseSafe) and [ReleaseSmall](../zig-0.15.1.md#ReleaseSmall) builds.

There are a few ways to activate this error return tracing feature:

- Return an error from main
- An error makes its way to <span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span> and you have not overridden the default panic handler
- Use [errorReturnTrace](../zig-0.15.1.md#errorReturnTrace) to access the current return trace. You can use `std.debug.dumpStackTrace` to print it. This function returns comptime-known [null](../zig-0.15.1.md#null) when building without error return tracing support.

#### [Implementation Details](../zig-0.15.1.md#toc-Implementation-Details) <a href="../zig-0.15.1.md#Implementation-Details" class="hdr">§</a>

To analyze performance cost, there are two cases:

- when no errors are returned
- when returning errors

For the case when no errors are returned, the cost is a single memory write operation, only in the first non-failable function in the call graph that calls a failable function, i.e. when a function returning <span class="tok-type">`void`</span> calls a function returning <span class="tok-kw">`error`</span>.
This is to initialize this struct in the stack memory:

<figure>
<pre><code>pub const StackTrace = struct {
    index: usize,
    instruction_addresses: [N]usize,
};</code></pre>
<figcaption>stack_trace_struct.zig</figcaption>
</figure>

Here, N is the maximum function call depth as determined by call graph analysis. Recursion is ignored and counts for 2.

A pointer to `StackTrace` is passed as a secret parameter to every function that can return an error, but it's always the first parameter, so it can likely sit in a register and stay there.

That's it for the path when no errors occur. It's practically free in terms of performance.

When generating the code for a function that returns an error, just before the <span class="tok-kw">`return`</span> statement (only for the <span class="tok-kw">`return`</span> statements that return errors), Zig generates a call to this function:

<figure>
<pre><code>// marked as &quot;no-inline&quot; in LLVM IR
fn __zig_return_error(stack_trace: *StackTrace) void {
    stack_trace.instruction_addresses[stack_trace.index] = @returnAddress();
    stack_trace.index = (stack_trace.index + 1) % N;
}</code></pre>
<figcaption>zig_return_error_fn.zig</figcaption>
</figure>

The cost is 2 math operations plus some memory reads and writes. The memory accessed is constrained and should remain cached for the duration of the error return bubbling.

As for code size cost, 1 function call before a return statement is no big deal. Even so,
I have [a plan](https://github.com/ziglang/zig/issues/690) to make the call to
`__zig_return_error` a tail call, which brings the code size cost down to actually zero. What is a return statement in code without error return tracing can become a jump instruction in code with error return tracing.

## [Optionals](../zig-0.15.1.md#toc-Optionals) <a href="../zig-0.15.1.md#Optionals" class="hdr">§</a>

One area that Zig provides safety without compromising efficiency or
readability is with the optional type.

The question mark symbolizes the optional type. You can convert a type to an optional
type by putting a question mark in front of it, like this:

<figure>
<pre><code>// normal integer
const normal_int: i32 = 1234;

// optional integer
const optional_int: ?i32 = 5678;</code></pre>
<figcaption>optional_integer.zig</figcaption>
</figure>

Now the variable `optional_int` could be an <span class="tok-type">`i32`</span>, or <span class="tok-null">`null`</span>.

Instead of integers, let's talk about pointers. Null references are the source of many runtime
exceptions, and even stand accused of being
[the worst mistake of computer science](https://www.lucidchart.com/techblog/2015/08/31/the-worst-mistake-of-computer-science/).

Zig does not have them.

Instead, you can use an optional pointer. This secretly compiles down to a normal pointer,
since we know we can use 0 as the null value for the optional type. But the compiler
can check your work and make sure you don't assign null to something that can't be null.

Typically the downside of not having null is that it makes the code more verbose to
write. But, let's compare some equivalent C code and Zig code.

Task: call malloc, if the result is null, return null.

C code

<figure>
<pre><code>// malloc prototype included for reference
void *malloc(size_t size);

struct Foo *do_a_thing(void) {
    char *ptr = malloc(1234);
    if (!ptr) return NULL;
    // ...
}</code></pre>
<figcaption>call_malloc_in_c.c</figcaption>
</figure>

Zig code

<figure>
<pre><code>// malloc prototype included for reference
extern fn malloc(size: usize) ?[*]u8;

fn doAThing() ?*Foo {
    const ptr = malloc(1234) orelse return null;
    _ = ptr; // ...
}</code></pre>
<figcaption>call_malloc_from_zig.zig</figcaption>
</figure>

Here, Zig is at least as convenient, if not more, than C. And, the type of "ptr"
is `[*]`<span class="tok-type">`u8`</span> *not* `?[*]`<span class="tok-type">`u8`</span>. The <span class="tok-kw">`orelse`</span> keyword
unwrapped the optional type and therefore `ptr` is guaranteed to be non-null everywhere
it is used in the function.

The other form of checking against NULL you might see looks like this:

<figure>
<pre><code>void do_a_thing(struct Foo *foo) {
    // do some stuff

    if (foo) {
        do_something_with_foo(foo);
    }

    // do some stuff
}</code></pre>
<figcaption>checking_null_in_c.c</figcaption>
</figure>

In Zig you can accomplish the same thing:

<figure>
<pre><code>const Foo = struct {};
fn doSomethingWithFoo(foo: *Foo) void {
    _ = foo;
}

fn doAThing(optional_foo: ?*Foo) void {
    // do some stuff

    if (optional_foo) |foo| {
        doSomethingWithFoo(foo);
    }

    // do some stuff
}</code></pre>
<figcaption>checking_null_in_zig.zig</figcaption>
</figure>

Once again, the notable thing here is that inside the if block,
`foo` is no longer an optional pointer, it is a pointer, which
cannot be null.

One benefit to this is that functions which take pointers as arguments can
be annotated with the "nonnull" attribute - `__attribute__((nonnull))` in
[GCC](https://gcc.gnu.org/onlinedocs/gcc-4.0.0/gcc/Function-Attributes.html).
The optimizer can sometimes make better decisions knowing that pointer arguments
cannot be null.


### [Optional Type](../zig-0.15.1.md#toc-Optional-Type) <a href="../zig-0.15.1.md#Optional-Type" class="hdr">§</a>

An optional is created by putting `?` in front of a type. You can use compile-time
reflection to access the child type of an optional:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;optional type&quot; {
    // Declare an optional and coerce from null:
    var foo: ?i32 = null;

    // Coerce from child type of an optional
    foo = 1234;

    // Use compile-time reflection to access the child type of the optional:
    try comptime expect(@typeInfo(@TypeOf(foo)).optional.child == i32);
}</code></pre>
<figcaption>test_optional_type.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_optional_type.zig
1/1 test_optional_type.test.optional type...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>


### [null](../zig-0.15.1.md#toc-null) <a href="../zig-0.15.1.md#null" class="hdr">§</a>

Just like [undefined](../zig-0.15.1.md#undefined), <span class="tok-null">`null`</span> has its own type, and the only way to use it is to
cast it to a different type:

<figure>
<pre><code>const optional_value: ?i32 = null;</code></pre>
<figcaption>null.zig</figcaption>
</figure>


### [Optional Pointers](../zig-0.15.1.md#toc-Optional-Pointers) <a href="../zig-0.15.1.md#Optional-Pointers" class="hdr">§</a>

An optional pointer is guaranteed to be the same size as a pointer. The <span class="tok-null">`null`</span> of
the optional is guaranteed to be address 0.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;optional pointers&quot; {
    // Pointers cannot be null. If you want a null pointer, use the optional
    // prefix `?` to make the pointer type optional.
    var ptr: ?*i32 = null;

    var x: i32 = 1;
    ptr = &amp;x;

    try expect(ptr.?.* == 1);

    // Optional pointers are the same size as normal pointers, because pointer
    // value 0 is used as the null value.
    try expect(@sizeOf(?*i32) == @sizeOf(*i32));
}</code></pre>
<figcaption>test_optional_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_optional_pointer.zig
1/1 test_optional_pointer.test.optional pointers...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [while with Optionals](../zig-0.15.1.md#while-with-Optionals)
- [if with Optionals](../zig-0.15.1.md#if-with-Optionals)

## [Casting](../zig-0.15.1.md#toc-Casting) <a href="../zig-0.15.1.md#Casting" class="hdr">§</a>

A **type cast** converts a value of one type to another.
Zig has [Type Coercion](../zig-0.15.1.md#Type-Coercion) for conversions that are known to be completely safe and unambiguous,
and [Explicit Casts](../zig-0.15.1.md#Explicit-Casts) for conversions that one would not want to happen on accident.
There is also a third kind of type conversion called [Peer Type Resolution](../zig-0.15.1.md#Peer-Type-Resolution) for
the case when a result type must be decided given multiple operand types.


