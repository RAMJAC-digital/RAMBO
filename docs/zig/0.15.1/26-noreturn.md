<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: noreturn -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [noreturn](zig-0.15.1.md#toc-noreturn) <a href="zig-0.15.1.md#noreturn" class="hdr">§</a>

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

