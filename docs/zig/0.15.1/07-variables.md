<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Variables -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Variables](zig-0.15.1.md#toc-Variables) <a href="zig-0.15.1.md#Variables" class="hdr">§</a>

A variable is a unit of [Memory](zig-0.15.1.md#Memory) storage.

It is generally preferable to use <span class="tok-kw">`const`</span> rather than
<span class="tok-kw">`var`</span> when declaring a variable. This causes less work for both
humans and computers to do when reading code, and creates more optimization opportunities.

The <span class="tok-kw">`extern`</span> keyword or [@extern](zig-0.15.1.md#extern) builtin function can be used to link against a variable that is exported
from another object. The <span class="tok-kw">`export`</span> keyword or [@export](zig-0.15.1.md#export) builtin function
can be used to make a variable available to other objects at link time. In both cases,
the type of the variable must be C ABI compatible.

See also:

- [Exporting a C Library](zig-0.15.1.md#Exporting-a-C-Library)

### [Identifiers](zig-0.15.1.md#toc-Identifiers) <a href="zig-0.15.1.md#Identifiers" class="hdr">§</a>

Variable identifiers are never allowed to shadow identifiers from an outer scope.

Identifiers must start with an alphabetic character or underscore and may be followed
by any number of alphanumeric characters or underscores.
They must not overlap with any keywords. See [Keyword Reference](zig-0.15.1.md#Keyword-Reference).

If a name that does not fit these requirements is needed, such as for linking with external libraries, the `@""` syntax may be used.

<figure>
<pre><code>const @&quot;identifier with spaces in it&quot; = 0xff;
const @&quot;1SmallStep4Man&quot; = 112358;

const c = @import(&quot;std&quot;).c;
pub extern &quot;c&quot; fn @&quot;error&quot;() void;
pub extern &quot;c&quot; fn @&quot;fstat$INODE64&quot;(fd: c.fd_t, buf: *c.Stat) c_int;

const Color = enum {
    red,
    @&quot;really red&quot;,
};
const color: Color = .@&quot;really red&quot;;</code></pre>
<figcaption>identifiers.zig</figcaption>
</figure>

### [Container Level Variables](zig-0.15.1.md#toc-Container-Level-Variables) <a href="zig-0.15.1.md#Container-Level-Variables" class="hdr">§</a>

[Container](zig-0.15.1.md#Containers) level variables have static lifetime and are order-independent and lazily analyzed.
The initialization value of container level variables is implicitly
[comptime](zig-0.15.1.md#comptime). If a container level variable is <span class="tok-kw">`const`</span> then its value is
<span class="tok-kw">`comptime`</span>-known, otherwise it is runtime-known.

<figure>
<pre><code>var y: i32 = add(10, x);
const x: i32 = add(12, 34);

test &quot;container level variables&quot; {
    try expect(x == 46);
    try expect(y == 56);
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

const std = @import(&quot;std&quot;);
const expect = std.testing.expect;</code></pre>
<figcaption>test_container_level_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_container_level_variables.zig
1/1 test_container_level_variables.test.container level variables...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Container level variables may be declared inside a [struct](zig-0.15.1.md#struct), [union](zig-0.15.1.md#union), [enum](zig-0.15.1.md#enum), or [opaque](zig-0.15.1.md#opaque):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;namespaced container level variable&quot; {
    try expect(foo() == 1235);
    try expect(foo() == 1236);
}

const S = struct {
    var x: i32 = 1234;
};

fn foo() i32 {
    S.x += 1;
    return S.x;
}</code></pre>
<figcaption>test_namespaced_container_level_variable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_namespaced_container_level_variable.zig
1/1 test_namespaced_container_level_variable.test.namespaced container level variable...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Static Local Variables](zig-0.15.1.md#toc-Static-Local-Variables) <a href="zig-0.15.1.md#Static-Local-Variables" class="hdr">§</a>

It is also possible to have local variables with static lifetime by using containers inside functions.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;static local variable&quot; {
    try expect(foo() == 1235);
    try expect(foo() == 1236);
}

fn foo() i32 {
    const S = struct {
        var x: i32 = 1234;
    };
    S.x += 1;
    return S.x;
}</code></pre>
<figcaption>test_static_local_variable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_static_local_variable.zig
1/1 test_static_local_variable.test.static local variable...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Thread Local Variables](zig-0.15.1.md#toc-Thread-Local-Variables) <a href="zig-0.15.1.md#Thread-Local-Variables" class="hdr">§</a>

A variable may be specified to be a thread-local variable using the
<span class="tok-kw">`threadlocal`</span> keyword,
which makes each thread work with a separate instance of the variable:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const assert = std.debug.assert;

threadlocal var x: i32 = 1234;

test &quot;thread local storage&quot; {
    const thread1 = try std.Thread.spawn(.{}, testTls, .{});
    const thread2 = try std.Thread.spawn(.{}, testTls, .{});
    testTls();
    thread1.join();
    thread2.join();
}

fn testTls() void {
    assert(x == 1234);
    x += 1;
    assert(x == 1235);
}</code></pre>
<figcaption>test_thread_local_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_thread_local_variables.zig
1/1 test_thread_local_variables.test.thread local storage...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

For [Single Threaded Builds](zig-0.15.1.md#Single-Threaded-Builds), all thread local variables are treated as regular [Container Level Variables](zig-0.15.1.md#Container-Level-Variables).

Thread local variables may not be <span class="tok-kw">`const`</span>.

### [Local Variables](zig-0.15.1.md#toc-Local-Variables) <a href="zig-0.15.1.md#Local-Variables" class="hdr">§</a>

Local variables occur inside [Functions](zig-0.15.1.md#Functions), [comptime](zig-0.15.1.md#comptime) blocks, and [@cImport](zig-0.15.1.md#cImport) blocks.

When a local variable is <span class="tok-kw">`const`</span>, it means that after initialization, the variable's
value will not change. If the initialization value of a <span class="tok-kw">`const`</span> variable is
[comptime](zig-0.15.1.md#comptime)-known, then the variable is also <span class="tok-kw">`comptime`</span>-known.

A local variable may be qualified with the <span class="tok-kw">`comptime`</span> keyword. This causes
the variable's value to be <span class="tok-kw">`comptime`</span>-known, and all loads and stores of the
variable to happen during semantic analysis of the program, rather than at runtime.
All variables declared in a <span class="tok-kw">`comptime`</span> expression are implicitly
<span class="tok-kw">`comptime`</span> variables.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;comptime vars&quot; {
    var x: i32 = 1;
    comptime var y: i32 = 1;

    x += 1;
    y += 1;

    try expect(x == 2);
    try expect(y == 2);

    if (y != 2) {
        // This compile error never triggers because y is a comptime variable,
        // and so `y != 2` is a comptime value, and this if is statically evaluated.
        @compileError(&quot;wrong y value&quot;);
    }
}</code></pre>
<figcaption>test_comptime_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_variables.zig
1/1 test_comptime_variables.test.comptime vars...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

