<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: defer -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [defer](zig-0.15.1.md#toc-defer) <a href="zig-0.15.1.md#defer" class="hdr">§</a>

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

- [Errors](zig-0.15.1.md#Errors)

