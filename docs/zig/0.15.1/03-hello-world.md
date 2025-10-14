<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Hello World -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Hello World](zig-0.15.1.md#toc-Hello-World) <a href="zig-0.15.1.md#Hello-World" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() !void {
    try std.fs.File.stdout().writeAll(&quot;Hello, World!\n&quot;);
}</code></pre>
<figcaption>hello.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe hello.zig
$ ./hello
Hello, World!</code></pre>
<figcaption>Shell</figcaption>
</figure>

Most of the time, it is more appropriate to write to stderr rather than stdout, and
whether or not the message is successfully written to the stream is irrelevant.
Also, formatted printing often comes in handy. For this common case,
there is a simpler API:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    std.debug.print(&quot;Hello, {s}!\n&quot;, .{&quot;World&quot;});
}</code></pre>
<figcaption>hello_again.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe hello_again.zig
$ ./hello_again
Hello, World!</code></pre>
<figcaption>Shell</figcaption>
</figure>

In this case, the `!` may be omitted from the return
type of `main` because no errors are returned from the function.

See also:

- [Values](zig-0.15.1.md#Values)
- [Tuples](zig-0.15.1.md#Tuples)
- [@import](zig-0.15.1.md#import)
- [Errors](zig-0.15.1.md#Errors)
- [Entry Point](zig-0.15.1.md#Entry-Point)
- [Source Encoding](zig-0.15.1.md#Source-Encoding)
- [try](zig-0.15.1.md#try)

