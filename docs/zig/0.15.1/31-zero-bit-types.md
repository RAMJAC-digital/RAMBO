<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Zero Bit Types -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Zero Bit Types](zig-0.15.1.md#toc-Zero-Bit-Types) <a href="zig-0.15.1.md#Zero-Bit-Types" class="hdr">§</a>

For some types, [@sizeOf](zig-0.15.1.md#sizeOf) is 0:

- [void](zig-0.15.1.md#void)
- The [Integers](zig-0.15.1.md#Integers) <span class="tok-type">`u0`</span> and <span class="tok-type">`i0`</span>.
- [Arrays](zig-0.15.1.md#Arrays) and [Vectors](zig-0.15.1.md#Vectors) with len 0, or with an element type that is a zero bit type.
- An [enum](zig-0.15.1.md#enum) with only 1 tag.
- A [struct](zig-0.15.1.md#struct) with all fields being zero bit types.
- A [union](zig-0.15.1.md#union) with only 1 field which is a zero bit type.

These types can only ever have one possible value, and thus
require 0 bits to represent. Code that makes use of these types is
not included in the final generated code:

<figure>
<pre><code>export fn entry() void {
    var x: void = {};
    var y: void = {};
    x = y;
    y = x;
}</code></pre>
<figcaption>zero_bit_types.zig</figcaption>
</figure>

When this turns into machine code, there is no code generated in the
body of `entry`, even in [Debug](zig-0.15.1.md#Debug) mode. For example, on x86_64:

    0000000000000010 <entry>:
      10:   55                      push   %rbp
      11:   48 89 e5                mov    %rsp,%rbp
      14:   5d                      pop    %rbp
      15:   c3                      retq   

These assembly instructions do not have any code associated with the void values -
they only perform the function call prologue and epilogue.

### [void](zig-0.15.1.md#toc-void) <a href="zig-0.15.1.md#void" class="hdr">§</a>

<span class="tok-type">`void`</span> can be useful for instantiating generic types. For example, given a
`Map(Key, Value)`, one can pass <span class="tok-type">`void`</span> for the `Value`
type to make it into a `Set`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;turn HashMap into a set with void&quot; {
    var map = std.AutoHashMap(i32, void).init(std.testing.allocator);
    defer map.deinit();

    try map.put(1, {});
    try map.put(2, {});

    try expect(map.contains(2));
    try expect(!map.contains(3));

    _ = map.remove(2);
    try expect(!map.contains(2));
}</code></pre>
<figcaption>test_void_in_hashmap.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_void_in_hashmap.zig
1/1 test_void_in_hashmap.test.turn HashMap into a set with void...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note that this is different from using a dummy value for the hash map value.
By using <span class="tok-type">`void`</span> as the type of the value, the hash map entry type has no value field, and
thus the hash map takes up less space. Further, all the code that deals with storing and loading the
value is deleted, as seen above.

<span class="tok-type">`void`</span> is distinct from <span class="tok-type">`anyopaque`</span>.
<span class="tok-type">`void`</span> has a known size of 0 bytes, and <span class="tok-type">`anyopaque`</span> has an unknown, but non-zero, size.

Expressions of type <span class="tok-type">`void`</span> are the only ones whose value can be ignored. For example, ignoring
a non-<span class="tok-type">`void`</span> expression is a compile error:

<figure>
<pre><code>test &quot;ignoring expression value&quot; {
    foo();
}

fn foo() i32 {
    return 1234;
}</code></pre>
<figcaption>test_expression_ignored.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_expression_ignored.zig
/home/andy/dev/zig/doc/langref/test_expression_ignored.zig:2:8: error: value of type &#39;i32&#39; ignored
    foo();
    ~~~^~
/home/andy/dev/zig/doc/langref/test_expression_ignored.zig:2:8: note: all non-void values must be used
/home/andy/dev/zig/doc/langref/test_expression_ignored.zig:2:8: note: to discard the value, assign it to &#39;_&#39;
</code></pre>
<figcaption>Shell</figcaption>
</figure>

However, if the expression has type <span class="tok-type">`void`</span>, there will be no error. Expression results can be explicitly ignored by assigning them to `_`.

<figure>
<pre><code>test &quot;void is ignored&quot; {
    returnsVoid();
}

test &quot;explicitly ignoring expression value&quot; {
    _ = foo();
}

fn returnsVoid() void {}

fn foo() i32 {
    return 1234;
}</code></pre>
<figcaption>test_void_ignored.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_void_ignored.zig
1/2 test_void_ignored.test.void is ignored...OK
2/2 test_void_ignored.test.explicitly ignoring expression value...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

