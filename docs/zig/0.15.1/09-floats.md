<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Floats -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Floats](zig-0.15.1.md#toc-Floats) <a href="zig-0.15.1.md#Floats" class="hdr">§</a>

Zig has the following floating point types:

- <span class="tok-type">`f16`</span> - IEEE-754-2008 binary16
- <span class="tok-type">`f32`</span> - IEEE-754-2008 binary32
- <span class="tok-type">`f64`</span> - IEEE-754-2008 binary64
- <span class="tok-type">`f80`</span> - IEEE-754-2008 80-bit extended precision
- <span class="tok-type">`f128`</span> - IEEE-754-2008 binary128
- <span class="tok-type">`c_longdouble`</span> - matches `long double` for the target C ABI

### [Float Literals](zig-0.15.1.md#toc-Float-Literals) <a href="zig-0.15.1.md#Float-Literals" class="hdr">§</a>

Float literals have type <span class="tok-type">`comptime_float`</span> which is guaranteed to have
the same precision and operations of the largest other floating point type, which is
<span class="tok-type">`f128`</span>.

Float literals [coerce](zig-0.15.1.md#Type-Coercion) to any floating point type,
and to any [integer](zig-0.15.1.md#Integers) type when there is no fractional component.

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

### [Floating Point Operations](zig-0.15.1.md#toc-Floating-Point-Operations) <a href="zig-0.15.1.md#Floating-Point-Operations" class="hdr">§</a>

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

- [@setFloatMode](zig-0.15.1.md#setFloatMode)
- [Division by Zero](zig-0.15.1.md#Division-by-Zero)

