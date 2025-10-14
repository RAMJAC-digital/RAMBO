<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Blocks -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Blocks](zig-0.15.1.md#toc-Blocks) <a href="zig-0.15.1.md#Blocks" class="hdr">§</a>

Blocks are used to limit the scope of variable declarations:

<figure>
<pre><code>test &quot;access variable after block scope&quot; {
    {
        var x: i32 = 1;
        _ = &amp;x;
    }
    x += 1;
}</code></pre>
<figcaption>test_blocks.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_blocks.zig
/home/andy/dev/zig/doc/langref/test_blocks.zig:6:5: error: use of undeclared identifier &#39;x&#39;
    x += 1;
    ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Blocks are expressions. When labeled, <span class="tok-kw">`break`</span> can be used
to return a value from the block:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;labeled break from labeled block expression&quot; {
    var y: i32 = 123;

    const x = blk: {
        y += 1;
        break :blk y;
    };
    try expect(x == 124);
    try expect(y == 124);
}</code></pre>
<figcaption>test_labeled_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_labeled_break.zig
1/1 test_labeled_break.test.labeled break from labeled block expression...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Here, `blk` can be any name.

See also:

- [Labeled while](zig-0.15.1.md#Labeled-while)
- [Labeled for](zig-0.15.1.md#Labeled-for)

### [Shadowing](zig-0.15.1.md#toc-Shadowing) <a href="zig-0.15.1.md#Shadowing" class="hdr">§</a>

[Identifiers](zig-0.15.1.md#Identifiers) are never allowed to "hide" other identifiers by using the same name:

<figure>
<pre><code>const pi = 3.14;

test &quot;inside test block&quot; {
    // Let&#39;s even go inside another block
    {
        var pi: i32 = 1234;
    }
}</code></pre>
<figcaption>test_shadowing.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_shadowing.zig
/home/andy/dev/zig/doc/langref/test_shadowing.zig:6:13: error: local variable shadows declaration of &#39;pi&#39;
        var pi: i32 = 1234;
            ^~
/home/andy/dev/zig/doc/langref/test_shadowing.zig:1:1: note: declared here
const pi = 3.14;
^~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Because of this, when you read Zig code you can always rely on an identifier to consistently mean
the same thing within the scope it is defined. Note that you can, however, use the same name if
the scopes are separate:

<figure>
<pre><code>test &quot;separate scopes&quot; {
    {
        const pi = 3.14;
        _ = pi;
    }
    {
        var pi: bool = true;
        _ = &amp;pi;
    }
}</code></pre>
<figcaption>test_scopes.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_scopes.zig
1/1 test_scopes.test.separate scopes...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Empty Blocks](zig-0.15.1.md#toc-Empty-Blocks) <a href="zig-0.15.1.md#Empty-Blocks" class="hdr">§</a>

An empty block is equivalent to <span class="tok-type">`void`</span>`{}`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test {
    const a = {};
    const b = void{};
    try expect(@TypeOf(a) == void);
    try expect(@TypeOf(b) == void);
    try expect(a == b);
}</code></pre>
<figcaption>test_empty_block.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_empty_block.zig
1/1 test_empty_block.test_0...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

