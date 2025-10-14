<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: opaque -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [opaque](zig-0.15.1.md#toc-opaque) <a href="zig-0.15.1.md#opaque" class="hdr">§</a>

<span class="tok-kw">`opaque`</span>` {}` declares a new type with an unknown (but non-zero) size and alignment.
It can contain declarations the same as [structs](zig-0.15.1.md#struct), [unions](zig-0.15.1.md#union),
and [enums](zig-0.15.1.md#enum).

This is typically used for type safety when interacting with C code that does not expose struct details.
Example:

<figure>
<pre><code>const Derp = opaque {};
const Wat = opaque {};

extern fn bar(d: *Derp) void;
fn foo(w: *Wat) callconv(.c) void {
    bar(w);
}

test &quot;call foo&quot; {
    foo(undefined);
}</code></pre>
<figcaption>test_opaque.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_opaque.zig
/home/andy/dev/zig/doc/langref/test_opaque.zig:6:9: error: expected type &#39;*test_opaque.Derp&#39;, found &#39;*test_opaque.Wat&#39;
    bar(w);
        ^
/home/andy/dev/zig/doc/langref/test_opaque.zig:6:9: note: pointer type child &#39;test_opaque.Wat&#39; cannot cast into pointer type child &#39;test_opaque.Derp&#39;
/home/andy/dev/zig/doc/langref/test_opaque.zig:2:13: note: opaque declared here
const Wat = opaque {};
            ^~~~~~~~~
/home/andy/dev/zig/doc/langref/test_opaque.zig:1:14: note: opaque declared here
const Derp = opaque {};
             ^~~~~~~~~
/home/andy/dev/zig/doc/langref/test_opaque.zig:4:18: note: parameter type declared here
extern fn bar(d: *Derp) void;
                 ^~~~~
referenced by:
    test.call foo: /home/andy/dev/zig/doc/langref/test_opaque.zig:10:8
</code></pre>
<figcaption>Shell</figcaption>
</figure>

