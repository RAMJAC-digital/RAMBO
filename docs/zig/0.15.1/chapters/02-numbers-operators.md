<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Numbers & Operators

Included sections:
- Integers
- Floats
- Operators

## [Integers](../zig-0.15.1.md#toc-Integers) <a href="../zig-0.15.1.md#Integers" class="hdr">§</a>

### [Integer Literals](../zig-0.15.1.md#toc-Integer-Literals) <a href="../zig-0.15.1.md#Integer-Literals" class="hdr">§</a>

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

### [Runtime Integer Values](../zig-0.15.1.md#toc-Runtime-Integer-Values) <a href="../zig-0.15.1.md#Runtime-Integer-Values" class="hdr">§</a>

Integer literals have no size limitation, and if any Illegal Behavior occurs,
the compiler catches it.

However, once an integer value is no longer known at compile-time, it must have a
known size, and is vulnerable to safety-checked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

<figure>
<pre><code>fn divide(a: i32, b: i32) i32 {
    return a / b;
}</code></pre>
<figcaption>runtime_vs_comptime.zig</figcaption>
</figure>

In this function, values `a` and `b` are known only at runtime,
and thus this division operation is vulnerable to both [Integer Overflow](../zig-0.15.1.md#Integer-Overflow) and
[Division by Zero](../zig-0.15.1.md#Division-by-Zero).

Operators such as `+` and `-` cause [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) on
integer overflow. Alternative operators are provided for wrapping and saturating arithmetic on all targets.
`+%` and `-%` perform wrapping arithmetic
while `+|` and `-|` perform saturating arithmetic.

Zig supports arbitrary bit-width integers, referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>. For signed integer types, Zig uses a
[two's complement](https://en.wikipedia.org/wiki/Two's_complement) representation.

See also:

- [Wrapping Operations](../zig-0.15.1.md#Wrapping-Operations)

## [Floats](../zig-0.15.1.md#toc-Floats) <a href="../zig-0.15.1.md#Floats" class="hdr">§</a>

Zig has the following floating point types:

- <span class="tok-type">`f16`</span> - IEEE-754-2008 binary16
- <span class="tok-type">`f32`</span> - IEEE-754-2008 binary32
- <span class="tok-type">`f64`</span> - IEEE-754-2008 binary64
- <span class="tok-type">`f80`</span> - IEEE-754-2008 80-bit extended precision
- <span class="tok-type">`f128`</span> - IEEE-754-2008 binary128
- <span class="tok-type">`c_longdouble`</span> - matches `long double` for the target C ABI

### [Float Literals](../zig-0.15.1.md#toc-Float-Literals) <a href="../zig-0.15.1.md#Float-Literals" class="hdr">§</a>

Float literals have type <span class="tok-type">`comptime_float`</span> which is guaranteed to have
the same precision and operations of the largest other floating point type, which is
<span class="tok-type">`f128`</span>.

Float literals [coerce](../zig-0.15.1.md#Type-Coercion) to any floating point type,
and to any [integer](../zig-0.15.1.md#Integers) type when there is no fractional component.

<figure>
<pre><code>const floating_point = 123.0E+77;
const another_float = 123.0;
const yet_another = 123.0e+77;

const hex_floating_point = 0x103.70p-5;
const another_hex_float = 0x103.70;
const yet_another_hex_float = 0x103.70P-5;

// underscores may be placed between two digits as a visual separator
const lightspeed = 299_792_458.000_000;
const nanosecond = 0.000_000_001;
const more_hex = 0x1234_5678.9ABC_CDEFp-10;</code></pre>
<figcaption>float_literals.zig</figcaption>
</figure>

There is no syntax for NaN, infinity, or negative infinity. For these special values,
one must use the standard library:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const inf = std.math.inf(f32);
const negative_inf = -std.math.inf(f64);
const nan = std.math.nan(f128);</code></pre>
<figcaption>float_special_values.zig</figcaption>
</figure>

### [Floating Point Operations](../zig-0.15.1.md#toc-Floating-Point-Operations) <a href="../zig-0.15.1.md#Floating-Point-Operations" class="hdr">§</a>

By default floating point operations use `Strict` mode,
but you can switch to `Optimized` mode on a per-block basis:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const big = @as(f64, 1 &lt;&lt; 40);

export fn foo_strict(x: f64) f64 {
    return x + big - big;
}

export fn foo_optimized(x: f64) f64 {
    @setFloatMode(.optimized);
    return x + big - big;
}</code></pre>
<figcaption>float_mode_obj.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj float_mode_obj.zig -O ReleaseFast</code></pre>
<figcaption>Shell</figcaption>
</figure>

For this test we have to separate code into two object files -
otherwise the optimizer figures out all the values at compile-time,
which operates in strict mode.

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

extern fn foo_strict(x: f64) f64;
extern fn foo_optimized(x: f64) f64;

pub fn main() void {
    const x = 0.001;
    print(&quot;optimized = {}\n&quot;, .{foo_optimized(x)});
    print(&quot;strict = {}\n&quot;, .{foo_strict(x)});
}</code></pre>
<figcaption>float_mode_exe.zig</figcaption>
</figure>

See also:

- [@setFloatMode](../zig-0.15.1.md#setFloatMode)
- [Division by Zero](../zig-0.15.1.md#Division-by-Zero)

## [Operators](../zig-0.15.1.md#toc-Operators) <a href="../zig-0.15.1.md#Operators" class="hdr">§</a>

There is no operator overloading. When you see an operator in Zig, you know that
it is doing something from this table, and nothing else.

### [Table of Operators](../zig-0.15.1.md#toc-Table-of-Operators) <a href="../zig-0.15.1.md#Table-of-Operators" class="hdr">§</a>

<div class="table-wrapper">

<table>
<colgroup>
<col style="width: 20%" />
<col style="width: 20%" />
<col style="width: 20%" />
<col style="width: 20%" />
<col style="width: 20%" />
</colgroup>
<thead>
<tr>
<th scope="col">Name</th>
<th scope="col">Syntax</th>
<th scope="col">Types</th>
<th scope="col">Remarks</th>
<th scope="col">Example</th>
</tr>
</thead>
<tbody>
<tr>
<td>Addition</td>
<td><pre><code>a + b
a += b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 + 5 == 7</code></pre></td>
</tr>
<tr>
<td>Wrapping Addition</td>
<td><pre><code>a +% b
a +%= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u32, 0xffffffff) +% 1 == 0</code></pre></td>
</tr>
<tr>
<td>Saturating Addition</td>
<td><pre><code>a +| b
a +|= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 255) +| 1 == @as(u8, 255)</code></pre></td>
</tr>
<tr>
<td>Subtraction</td>
<td><pre><code>a - b
a -= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 - 5 == -3</code></pre></td>
</tr>
<tr>
<td>Wrapping Subtraction</td>
<td><pre><code>a -% b
a -%= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 0) -% 1 == 255</code></pre></td>
</tr>
<tr>
<td>Saturating Subtraction</td>
<td><pre><code>a -| b
a -|= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u32, 0) -| 1 == 0</code></pre></td>
</tr>
<tr>
<td>Negation</td>
<td><pre><code>-a</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
</ul></td>
<td><pre><code>-1 == 0 - 1</code></pre></td>
</tr>
<tr>
<td>Wrapping Negation</td>
<td><pre><code>-%a</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
</ul></td>
<td><pre><code>-%@as(i8, -128) == -128</code></pre></td>
</tr>
<tr>
<td>Multiplication</td>
<td><pre><code>a * b
a *= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 * 5 == 10</code></pre></td>
</tr>
<tr>
<td>Wrapping Multiplication</td>
<td><pre><code>a *% b
a *%= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="../zig-0.15.1.md#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *% 2 == 144</code></pre></td>
</tr>
<tr>
<td>Saturating Multiplication</td>
<td><pre><code>a *| b
a *|= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *| 2 == 255</code></pre></td>
</tr>
<tr>
<td>Division</td>
<td><pre><code>a / b
a /= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Can cause <a href="../zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="../zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for floats in <a href="../zig-0.15.1.md#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed integer operands must be comptime-known and positive. In other cases, use
<a href="../zig-0.15.1.md#divTrunc">@divTrunc</a>,
<a href="../zig-0.15.1.md#divFloor">@divFloor</a>, or
<a href="../zig-0.15.1.md#divExact">@divExact</a> instead.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 / 5 == 2</code></pre></td>
</tr>
<tr>
<td>Remainder Division</td>
<td><pre><code>a % b
a %= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="../zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="../zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for floats in <a href="../zig-0.15.1.md#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed or floating-point operands must be comptime-known and positive. In other cases, use
<a href="../zig-0.15.1.md#rem">@rem</a> or
<a href="../zig-0.15.1.md#mod">@mod</a> instead.</li>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 % 3 == 1</code></pre></td>
</tr>
<tr>
<td>Bit Shift Left</td>
<td><pre><code>a &lt;&lt; b
a &lt;&lt;= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the left, inserting new zeroes at the
least-significant bit.</li>
<li><code>b</code> must be
<a href="../zig-0.15.1.md#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="../zig-0.15.1.md#shlExact">@shlExact</a>.</li>
<li>See also <a href="../zig-0.15.1.md#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>0b1 &lt;&lt; 8 == 0b100000000</code></pre></td>
</tr>
<tr>
<td>Saturating Bit Shift Left</td>
<td><pre><code>a &lt;&lt;| b
a &lt;&lt;|= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>See also <a href="../zig-0.15.1.md#shlExact">@shlExact</a>.</li>
<li>See also <a href="../zig-0.15.1.md#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 1) &lt;&lt;| 8 == 255</code></pre></td>
</tr>
<tr>
<td>Bit Shift Right</td>
<td><pre><code>a &gt;&gt; b
a &gt;&gt;= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the right, inserting zeroes at the most-significant bit.</li>
<li><code>b</code> must be
<a href="../zig-0.15.1.md#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="../zig-0.15.1.md#shrExact">@shrExact</a>.</li>
</ul></td>
<td><pre><code>0b1010 &gt;&gt; 1 == 0b101</code></pre></td>
</tr>
<tr>
<td>Bitwise And</td>
<td><pre><code>a &amp; b
a &amp;= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 &amp; 0b101 == 0b001</code></pre></td>
</tr>
<tr>
<td>Bitwise Or</td>
<td><pre><code>a | b
a |= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b010 | 0b100 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Xor</td>
<td><pre><code>a ^ b
a ^= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 ^ 0b101 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Not</td>
<td><pre><code>~a</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td></td>
<td><pre><code>~@as(u8, 0b10101111) == 0b01010000</code></pre></td>
</tr>
<tr>
<td>Defaulting Optional Unwrap</td>
<td><pre><code>a orelse b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>null</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="../zig-0.15.1.md#noreturn">noreturn</a>.</td>
<td><pre><code>const value: ?u32 = null;
const unwrapped = value orelse 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Optional Unwrap</td>
<td><pre><code>a.?</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>Equivalent to:
<pre><code>a orelse unreachable</code></pre></td>
<td><pre><code>const value: ?u32 = 5678;
value.? == 5678</code></pre></td>
</tr>
<tr>
<td>Defaulting Error Unwrap</td>
<td><pre><code>a catch b
a catch |err| b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Errors">Error Unions</a></li>
</ul></td>
<td>If <code>a</code> is an <span class="tok-kw"><code>error</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="../zig-0.15.1.md#noreturn">noreturn</a>.
<code>err</code> is the <span class="tok-kw"><code>error</code></span> and is in scope of the expression <code>b</code>.</td>
<td><pre><code>const value: anyerror!u32 = error.Broken;
const unwrapped = value catch 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Logical And</td>
<td><pre><code>a and b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Primitive-Types">bool</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>false</code></span>, returns <span class="tok-null"><code>false</code></span>
without evaluating <code>b</code>. Otherwise, returns <code>b</code>.</td>
<td><pre><code>(false and true) == false</code></pre></td>
</tr>
<tr>
<td>Logical Or</td>
<td><pre><code>a or b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Primitive-Types">bool</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>true</code></span>,
returns <span class="tok-null"><code>true</code></span> without evaluating
<code>b</code>. Otherwise, returns
<code>b</code>.</td>
<td><pre><code>(false or true) == true</code></pre></td>
</tr>
<tr>
<td>Boolean Not</td>
<td><pre><code>!a</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Primitive-Types">bool</a></li>
</ul></td>
<td></td>
<td><pre><code>!false == true</code></pre></td>
</tr>
<tr>
<td>Equality</td>
<td><pre><code>a == b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
<li><a href="../zig-0.15.1.md#Primitive-Types">bool</a></li>
<li><a href="../zig-0.15.1.md#Primitive-Types">type</a></li>
<li><a href="../zig-0.15.1.md#packed-struct">packed struct</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 == 1) == true</code></pre></td>
</tr>
<tr>
<td>Null Check</td>
<td><pre><code>a == null</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>false</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value == null) == true</code></pre></td>
</tr>
<tr>
<td>Inequality</td>
<td><pre><code>a != b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
<li><a href="../zig-0.15.1.md#Primitive-Types">bool</a></li>
<li><a href="../zig-0.15.1.md#Primitive-Types">type</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>true</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 != 1) == false</code></pre></td>
</tr>
<tr>
<td>Non-Null Check</td>
<td><pre><code>a != null</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>true</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value != null) == false</code></pre></td>
</tr>
<tr>
<td>Greater Than</td>
<td><pre><code>a &gt; b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt; 1) == true</code></pre></td>
</tr>
<tr>
<td>Greater or Equal</td>
<td><pre><code>a &gt;= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt;= 1) == true</code></pre></td>
</tr>
<tr>
<td>Less Than</td>
<td><pre><code>a &lt; b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt; 2) == true</code></pre></td>
</tr>
<tr>
<td>Lesser or Equal</td>
<td><pre><code>a &lt;= b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="../zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="../zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt;= 2) == true</code></pre></td>
</tr>
<tr>
<td>Array Concatenation</td>
<td><pre><code>a ++ b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the lengths of both <code>a</code> and <code>b</code> are <a href="../zig-0.15.1.md#comptime">compile-time known</a>.</li>
</ul></td>
<td><pre><code>const mem = @import(&quot;std&quot;).mem;
const array1 = [_]u32{1,2};
const array2 = [_]u32{3,4};
const together = array1 ++ array2;
mem.eql(u32, &amp;together, &amp;[_]u32{1,2,3,4})</code></pre></td>
</tr>
<tr>
<td>Array Multiplication</td>
<td><pre><code>a ** b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the length of <code>a</code> and <code>b</code> are <a href="../zig-0.15.1.md#comptime">compile-time known</a>.</li>
</ul></td>
<td><pre><code>const mem = @import(&quot;std&quot;).mem;
const pattern = &quot;ab&quot; ** 3;
mem.eql(u8, pattern, &quot;ababab&quot;)</code></pre></td>
</tr>
<tr>
<td>Pointer Dereference</td>
<td><pre><code>a.*</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Pointers">Pointers</a></li>
</ul></td>
<td>Pointer dereference.</td>
<td><pre><code>const x: u32 = 1234;
const ptr = &amp;x;
ptr.* == 1234</code></pre></td>
</tr>
<tr>
<td>Address Of</td>
<td><pre><code>&amp;a</code></pre></td>
<td>All types</td>
<td></td>
<td><pre><code>const x: u32 = 1234;
const ptr = &amp;x;
ptr.* == 1234</code></pre></td>
</tr>
<tr>
<td>Error Set Merge</td>
<td><pre><code>a || b</code></pre></td>
<td><ul>
<li><a href="../zig-0.15.1.md#Error-Set-Type">Error Set Type</a></li>
</ul></td>
<td><a href="../zig-0.15.1.md#Merging-Error-Sets">Merging Error Sets</a></td>
<td><pre><code>const A = error{One};
const B = error{Two};
(A || B) == error{One, Two}</code></pre></td>
</tr>
</tbody>
</table>

</div>

### [Precedence](../zig-0.15.1.md#toc-Precedence) <a href="../zig-0.15.1.md#Precedence" class="hdr">§</a>

    x() x[] x.y x.* x.?
    a!b
    x{}
    !x -x -%x ~x &x ?x
    * / % ** *% *| ||
    + - ++ +% -% +| -|
    << >> <<|
    & ^ | orelse catch
    == != < > <= >=
    and
    or
    = *= *%= *|= /= %= += +%= +|= -= -%= -|= <<= <<|= >>= &= ^= |=


