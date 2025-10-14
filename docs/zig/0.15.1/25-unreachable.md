<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: unreachable -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [unreachable](zig-0.15.1.md#toc-unreachable) <a href="zig-0.15.1.md#unreachable" class="hdr">§</a>

In [Debug](zig-0.15.1.md#Debug) and [ReleaseSafe](zig-0.15.1.md#ReleaseSafe) mode
<span class="tok-kw">`unreachable`</span> emits a call to `panic` with the message `reached unreachable code`.

In [ReleaseFast](zig-0.15.1.md#ReleaseFast) and [ReleaseSmall](zig-0.15.1.md#ReleaseSmall) mode, the optimizer uses the assumption that <span class="tok-kw">`unreachable`</span> code
will never be hit to perform optimizations.

### [Basics](zig-0.15.1.md#toc-Basics) <a href="zig-0.15.1.md#Basics" class="hdr">§</a>

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

### [At Compile-Time](zig-0.15.1.md#toc-At-Compile-Time) <a href="zig-0.15.1.md#At-Compile-Time" class="hdr">§</a>

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

- [Zig Test](zig-0.15.1.md#Zig-Test)
- [Build Mode](zig-0.15.1.md#Build-Mode)
- [comptime](zig-0.15.1.md#comptime)

