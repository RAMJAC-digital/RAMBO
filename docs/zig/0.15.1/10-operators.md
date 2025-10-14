<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Operators -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Operators](zig-0.15.1.md#toc-Operators) <a href="zig-0.15.1.md#Operators" class="hdr">§</a>

There is no operator overloading. When you see an operator in Zig, you know that
it is doing something from this table, and nothing else.

### [Table of Operators](zig-0.15.1.md#toc-Table-of-Operators) <a href="zig-0.15.1.md#Table-of-Operators" class="hdr">§</a>

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
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 + 5 == 7</code></pre></td>
</tr>
<tr>
<td>Wrapping Addition</td>
<td><pre><code>a +% b
a +%= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u32, 0xffffffff) +% 1 == 0</code></pre></td>
</tr>
<tr>
<td>Saturating Addition</td>
<td><pre><code>a +| b
a +|= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 255) +| 1 == @as(u8, 255)</code></pre></td>
</tr>
<tr>
<td>Subtraction</td>
<td><pre><code>a - b
a -= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 - 5 == -3</code></pre></td>
</tr>
<tr>
<td>Wrapping Subtraction</td>
<td><pre><code>a -% b
a -%= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 0) -% 1 == 255</code></pre></td>
</tr>
<tr>
<td>Saturating Subtraction</td>
<td><pre><code>a -| b
a -|= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u32, 0) -| 1 == 0</code></pre></td>
</tr>
<tr>
<td>Negation</td>
<td><pre><code>-a</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
</ul></td>
<td><pre><code>-1 == 0 - 1</code></pre></td>
</tr>
<tr>
<td>Wrapping Negation</td>
<td><pre><code>-%a</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
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
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 * 5 == 10</code></pre></td>
</tr>
<tr>
<td>Wrapping Multiplication</td>
<td><pre><code>a *% b
a *%= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="zig-0.15.1.md#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *% 2 == 144</code></pre></td>
</tr>
<tr>
<td>Saturating Multiplication</td>
<td><pre><code>a *| b
a *|= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *| 2 == 255</code></pre></td>
</tr>
<tr>
<td>Division</td>
<td><pre><code>a / b
a /= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Default-Operations">overflow</a> for integers.</li>
<li>Can cause <a href="zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for floats in <a href="zig-0.15.1.md#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed integer operands must be comptime-known and positive. In other cases, use
<a href="zig-0.15.1.md#divTrunc">@divTrunc</a>,
<a href="zig-0.15.1.md#divFloor">@divFloor</a>, or
<a href="zig-0.15.1.md#divExact">@divExact</a> instead.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 / 5 == 2</code></pre></td>
</tr>
<tr>
<td>Remainder Division</td>
<td><pre><code>a % b
a %= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="zig-0.15.1.md#Division-by-Zero">Division by Zero</a> for floats in <a href="zig-0.15.1.md#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed or floating-point operands must be comptime-known and positive. In other cases, use
<a href="zig-0.15.1.md#rem">@rem</a> or
<a href="zig-0.15.1.md#mod">@mod</a> instead.</li>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 % 3 == 1</code></pre></td>
</tr>
<tr>
<td>Bit Shift Left</td>
<td><pre><code>a &lt;&lt; b
a &lt;&lt;= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the left, inserting new zeroes at the
least-significant bit.</li>
<li><code>b</code> must be
<a href="zig-0.15.1.md#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="zig-0.15.1.md#shlExact">@shlExact</a>.</li>
<li>See also <a href="zig-0.15.1.md#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>0b1 &lt;&lt; 8 == 0b100000000</code></pre></td>
</tr>
<tr>
<td>Saturating Bit Shift Left</td>
<td><pre><code>a &lt;&lt;| b
a &lt;&lt;|= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>See also <a href="zig-0.15.1.md#shlExact">@shlExact</a>.</li>
<li>See also <a href="zig-0.15.1.md#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 1) &lt;&lt;| 8 == 255</code></pre></td>
</tr>
<tr>
<td>Bit Shift Right</td>
<td><pre><code>a &gt;&gt; b
a &gt;&gt;= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the right, inserting zeroes at the most-significant bit.</li>
<li><code>b</code> must be
<a href="zig-0.15.1.md#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="zig-0.15.1.md#shrExact">@shrExact</a>.</li>
</ul></td>
<td><pre><code>0b1010 &gt;&gt; 1 == 0b101</code></pre></td>
</tr>
<tr>
<td>Bitwise And</td>
<td><pre><code>a &amp; b
a &amp;= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 &amp; 0b101 == 0b001</code></pre></td>
</tr>
<tr>
<td>Bitwise Or</td>
<td><pre><code>a | b
a |= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b010 | 0b100 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Xor</td>
<td><pre><code>a ^ b
a ^= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 ^ 0b101 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Not</td>
<td><pre><code>~a</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
</ul></td>
<td></td>
<td><pre><code>~@as(u8, 0b10101111) == 0b01010000</code></pre></td>
</tr>
<tr>
<td>Defaulting Optional Unwrap</td>
<td><pre><code>a orelse b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>null</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="zig-0.15.1.md#noreturn">noreturn</a>.</td>
<td><pre><code>const value: ?u32 = null;
const unwrapped = value orelse 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Optional Unwrap</td>
<td><pre><code>a.?</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Optionals">Optionals</a></li>
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
<li><a href="zig-0.15.1.md#Errors">Error Unions</a></li>
</ul></td>
<td>If <code>a</code> is an <span class="tok-kw"><code>error</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="zig-0.15.1.md#noreturn">noreturn</a>.
<code>err</code> is the <span class="tok-kw"><code>error</code></span> and is in scope of the expression <code>b</code>.</td>
<td><pre><code>const value: anyerror!u32 = error.Broken;
const unwrapped = value catch 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Logical And</td>
<td><pre><code>a and b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Primitive-Types">bool</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>false</code></span>, returns <span class="tok-null"><code>false</code></span>
without evaluating <code>b</code>. Otherwise, returns <code>b</code>.</td>
<td><pre><code>(false and true) == false</code></pre></td>
</tr>
<tr>
<td>Logical Or</td>
<td><pre><code>a or b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Primitive-Types">bool</a></li>
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
<li><a href="zig-0.15.1.md#Primitive-Types">bool</a></li>
</ul></td>
<td></td>
<td><pre><code>!false == true</code></pre></td>
</tr>
<tr>
<td>Equality</td>
<td><pre><code>a == b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
<li><a href="zig-0.15.1.md#Primitive-Types">bool</a></li>
<li><a href="zig-0.15.1.md#Primitive-Types">type</a></li>
<li><a href="zig-0.15.1.md#packed-struct">packed struct</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 == 1) == true</code></pre></td>
</tr>
<tr>
<td>Null Check</td>
<td><pre><code>a == null</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>false</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value == null) == true</code></pre></td>
</tr>
<tr>
<td>Inequality</td>
<td><pre><code>a != b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
<li><a href="zig-0.15.1.md#Primitive-Types">bool</a></li>
<li><a href="zig-0.15.1.md#Primitive-Types">type</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>true</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 != 1) == false</code></pre></td>
</tr>
<tr>
<td>Non-Null Check</td>
<td><pre><code>a != null</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>true</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value != null) == false</code></pre></td>
</tr>
<tr>
<td>Greater Than</td>
<td><pre><code>a &gt; b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt; 1) == true</code></pre></td>
</tr>
<tr>
<td>Greater or Equal</td>
<td><pre><code>a &gt;= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt;= 1) == true</code></pre></td>
</tr>
<tr>
<td>Less Than</td>
<td><pre><code>a &lt; b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt; 2) == true</code></pre></td>
</tr>
<tr>
<td>Lesser or Equal</td>
<td><pre><code>a &lt;= b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Integers">Integers</a></li>
<li><a href="zig-0.15.1.md#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="zig-0.15.1.md#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt;= 2) == true</code></pre></td>
</tr>
<tr>
<td>Array Concatenation</td>
<td><pre><code>a ++ b</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the lengths of both <code>a</code> and <code>b</code> are <a href="zig-0.15.1.md#comptime">compile-time known</a>.</li>
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
<li><a href="zig-0.15.1.md#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the length of <code>a</code> and <code>b</code> are <a href="zig-0.15.1.md#comptime">compile-time known</a>.</li>
</ul></td>
<td><pre><code>const mem = @import(&quot;std&quot;).mem;
const pattern = &quot;ab&quot; ** 3;
mem.eql(u8, pattern, &quot;ababab&quot;)</code></pre></td>
</tr>
<tr>
<td>Pointer Dereference</td>
<td><pre><code>a.*</code></pre></td>
<td><ul>
<li><a href="zig-0.15.1.md#Pointers">Pointers</a></li>
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
<li><a href="zig-0.15.1.md#Error-Set-Type">Error Set Type</a></li>
</ul></td>
<td><a href="zig-0.15.1.md#Merging-Error-Sets">Merging Error Sets</a></td>
<td><pre><code>const A = error{One};
const B = error{Two};
(A || B) == error{One, Two}</code></pre></td>
</tr>
</tbody>
</table>

</div>

### [Precedence](zig-0.15.1.md#toc-Precedence) <a href="zig-0.15.1.md#Precedence" class="hdr">§</a>

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

