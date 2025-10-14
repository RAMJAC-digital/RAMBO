<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Integers -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Integers](zig-0.15.1.md#toc-Integers) <a href="zig-0.15.1.md#Integers" class="hdr">§</a>

### [Integer Literals](zig-0.15.1.md#toc-Integer-Literals) <a href="zig-0.15.1.md#Integer-Literals" class="hdr">§</a>

<figure>
<pre><code>const decimal_int = 98222;
const hex_int = 0xff;
const another_hex_int = 0xFF;
const octal_int = 0o755;
const binary_int = 0b11110000;

// underscores may be placed between two digits as a visual separator
const one_billion = 1_000_000_000;
const binary_mask = 0b1_1111_1111;
const permissions = 0o7_5_5;
const big_address = 0xFF80_0000_0000_0000;</code></pre>
<figcaption>integer_literals.zig</figcaption>
</figure>

### [Runtime Integer Values](zig-0.15.1.md#toc-Runtime-Integer-Values) <a href="zig-0.15.1.md#Runtime-Integer-Values" class="hdr">§</a>

Integer literals have no size limitation, and if any Illegal Behavior occurs,
the compiler catches it.

However, once an integer value is no longer known at compile-time, it must have a
known size, and is vulnerable to safety-checked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

<figure>
<pre><code>fn divide(a: i32, b: i32) i32 {
    return a / b;
}</code></pre>
<figcaption>runtime_vs_comptime.zig</figcaption>
</figure>

In this function, values `a` and `b` are known only at runtime,
and thus this division operation is vulnerable to both [Integer Overflow](zig-0.15.1.md#Integer-Overflow) and
[Division by Zero](zig-0.15.1.md#Division-by-Zero).

Operators such as `+` and `-` cause [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior) on
integer overflow. Alternative operators are provided for wrapping and saturating arithmetic on all targets.
`+%` and `-%` perform wrapping arithmetic
while `+|` and `-|` perform saturating arithmetic.

Zig supports arbitrary bit-width integers, referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>. For signed integer types, Zig uses a
[two's complement](https://en.wikipedia.org/wiki/Two's_complement) representation.

See also:

- [Wrapping Operations](zig-0.15.1.md#Wrapping-Operations)

