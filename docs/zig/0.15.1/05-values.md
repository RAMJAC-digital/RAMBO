<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Values -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Values](zig-0.15.1.md#toc-Values) <a href="zig-0.15.1.md#Values" class="hdr">§</a>

<figure>
<pre><code>// Top-level declarations are order-independent:
const print = std.debug.print;
const std = @import(&quot;std&quot;);
const os = std.os;
const assert = std.debug.assert;

pub fn main() void {
    // integers
    const one_plus_one: i32 = 1 + 1;
    print(&quot;1 + 1 = {}\n&quot;, .{one_plus_one});

    // floats
    const seven_div_three: f32 = 7.0 / 3.0;
    print(&quot;7.0 / 3.0 = {}\n&quot;, .{seven_div_three});

    // boolean
    print(&quot;{}\n{}\n{}\n&quot;, .{
        true and false,
        true or false,
        !true,
    });

    // optional
    var optional_value: ?[]const u8 = null;
    assert(optional_value == null);

    print(&quot;\noptional 1\ntype: {}\nvalue: {?s}\n&quot;, .{
        @TypeOf(optional_value), optional_value,
    });

    optional_value = &quot;hi&quot;;
    assert(optional_value != null);

    print(&quot;\noptional 2\ntype: {}\nvalue: {?s}\n&quot;, .{
        @TypeOf(optional_value), optional_value,
    });

    // error union
    var number_or_error: anyerror!i32 = error.ArgNotFound;

    print(&quot;\nerror union 1\ntype: {}\nvalue: {!}\n&quot;, .{
        @TypeOf(number_or_error),
        number_or_error,
    });

    number_or_error = 1234;

    print(&quot;\nerror union 2\ntype: {}\nvalue: {!}\n&quot;, .{
        @TypeOf(number_or_error), number_or_error,
    });
}</code></pre>
<figcaption>values.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe values.zig
$ ./values
1 + 1 = 2
7.0 / 3.0 = 2.3333333
false
true
false

optional 1
type: ?[]const u8
value: null

optional 2
type: ?[]const u8
value: hi

error union 1
type: anyerror!i32
value: error.ArgNotFound

error union 2
type: anyerror!i32
value: 1234</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Primitive Types](zig-0.15.1.md#toc-Primitive-Types) <a href="zig-0.15.1.md#Primitive-Types" class="hdr">§</a>

<div class="table-wrapper">

| Type | C Equivalent | Description |
|----|----|----|
| <span class="tok-type">`i8`</span> | `int8_t` | signed 8-bit integer |
| <span class="tok-type">`u8`</span> | `uint8_t` | unsigned 8-bit integer |
| <span class="tok-type">`i16`</span> | `int16_t` | signed 16-bit integer |
| <span class="tok-type">`u16`</span> | `uint16_t` | unsigned 16-bit integer |
| <span class="tok-type">`i32`</span> | `int32_t` | signed 32-bit integer |
| <span class="tok-type">`u32`</span> | `uint32_t` | unsigned 32-bit integer |
| <span class="tok-type">`i64`</span> | `int64_t` | signed 64-bit integer |
| <span class="tok-type">`u64`</span> | `uint64_t` | unsigned 64-bit integer |
| <span class="tok-type">`i128`</span> | `__int128` | signed 128-bit integer |
| <span class="tok-type">`u128`</span> | `unsigned __int128` | unsigned 128-bit integer |
| <span class="tok-type">`isize`</span> | `intptr_t` | signed pointer sized integer |
| <span class="tok-type">`usize`</span> | `uintptr_t`, `size_t` | unsigned pointer sized integer. Also see [\#5185](https://github.com/ziglang/zig/issues/5185) |
| <span class="tok-type">`c_char`</span> | `char` | for ABI compatibility with C |
| <span class="tok-type">`c_short`</span> | `short` | for ABI compatibility with C |
| <span class="tok-type">`c_ushort`</span> | `unsigned short` | for ABI compatibility with C |
| <span class="tok-type">`c_int`</span> | `int` | for ABI compatibility with C |
| <span class="tok-type">`c_uint`</span> | `unsigned int` | for ABI compatibility with C |
| <span class="tok-type">`c_long`</span> | `long` | for ABI compatibility with C |
| <span class="tok-type">`c_ulong`</span> | `unsigned long` | for ABI compatibility with C |
| <span class="tok-type">`c_longlong`</span> | `long long` | for ABI compatibility with C |
| <span class="tok-type">`c_ulonglong`</span> | `unsigned long long` | for ABI compatibility with C |
| <span class="tok-type">`c_longdouble`</span> | `long double` | for ABI compatibility with C |
| <span class="tok-type">`f16`</span> | `_Float16` | 16-bit floating point (10-bit mantissa) IEEE-754-2008 binary16 |
| <span class="tok-type">`f32`</span> | `float` | 32-bit floating point (23-bit mantissa) IEEE-754-2008 binary32 |
| <span class="tok-type">`f64`</span> | `double` | 64-bit floating point (52-bit mantissa) IEEE-754-2008 binary64 |
| <span class="tok-type">`f80`</span> | `long double` | 80-bit floating point (64-bit mantissa) IEEE-754-2008 80-bit extended precision |
| <span class="tok-type">`f128`</span> | `_Float128` | 128-bit floating point (112-bit mantissa) IEEE-754-2008 binary128 |
| <span class="tok-type">`bool`</span> | `bool` | <span class="tok-null">`true`</span> or <span class="tok-null">`false`</span> |
| <span class="tok-type">`anyopaque`</span> | `void` | Used for type-erased pointers. |
| <span class="tok-type">`void`</span> | (none) | Always the value <span class="tok-type">`void`</span>`{}` |
| <span class="tok-type">`noreturn`</span> | (none) | the type of <span class="tok-kw">`break`</span>, <span class="tok-kw">`continue`</span>, <span class="tok-kw">`return`</span>, <span class="tok-kw">`unreachable`</span>, and <span class="tok-kw">`while`</span>` (`<span class="tok-null">`true`</span>`) {}` |
| <span class="tok-type">`type`</span> | (none) | the type of types |
| <span class="tok-type">`anyerror`</span> | (none) | an error code |
| <span class="tok-type">`comptime_int`</span> | (none) | Only allowed for [comptime](zig-0.15.1.md#comptime)-known values. The type of integer literals. |
| <span class="tok-type">`comptime_float`</span> | (none) | Only allowed for [comptime](zig-0.15.1.md#comptime)-known values. The type of float literals. |

Primitive Types

</div>

In addition to the integer types above, arbitrary bit-width integers can be referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>.

See also:

- [Integers](zig-0.15.1.md#Integers)
- [Floats](zig-0.15.1.md#Floats)
- [void](zig-0.15.1.md#void)
- [Errors](zig-0.15.1.md#Errors)
- [@Type](zig-0.15.1.md#Type)

### [Primitive Values](zig-0.15.1.md#toc-Primitive-Values) <a href="zig-0.15.1.md#Primitive-Values" class="hdr">§</a>

<div class="table-wrapper">

| Name | Description |
|----|----|
| <span class="tok-null">`true`</span> and <span class="tok-null">`false`</span> | <span class="tok-type">`bool`</span> values |
| <span class="tok-null">`null`</span> | used to set an optional type to <span class="tok-null">`null`</span> |
| <span class="tok-null">`undefined`</span> | used to leave a value unspecified |

Primitive Values

</div>

See also:

- [Optionals](zig-0.15.1.md#Optionals)
- [undefined](zig-0.15.1.md#undefined)

### [String Literals and Unicode Code Point Literals](zig-0.15.1.md#toc-String-Literals-and-Unicode-Code-Point-Literals) <a href="zig-0.15.1.md#String-Literals-and-Unicode-Code-Point-Literals" class="hdr">§</a>

String literals are constant single-item [Pointers](zig-0.15.1.md#Pointers) to null-terminated byte arrays.
The type of string literals encodes both the length, and the fact that they are null-terminated,
and thus they can be [coerced](zig-0.15.1.md#Type-Coercion) to both [Slices](zig-0.15.1.md#Slices) and
[Null-Terminated Pointers](zig-0.15.1.md#Sentinel-Terminated-Pointers).
Dereferencing string literals converts them to [Arrays](zig-0.15.1.md#Arrays).

Because Zig source code is [UTF-8 encoded](zig-0.15.1.md#Source-Encoding), any
non-ASCII bytes appearing within a string literal in source code carry
their UTF-8 meaning into the content of the string in the Zig program;
the bytes are not modified by the compiler. It is possible to embed
non-UTF-8 bytes into a string literal using `\xNN` notation.

Indexing into a string containing non-ASCII bytes returns individual
bytes, whether valid UTF-8 or not.

Unicode code point literals have type <span class="tok-type">`comptime_int`</span>, the same as
[Integer Literals](zig-0.15.1.md#Integer-Literals). All [Escape Sequences](zig-0.15.1.md#Escape-Sequences) are valid in both string literals
and Unicode code point literals.

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;
const mem = @import(&quot;std&quot;).mem; // will be used to compare bytes

pub fn main() void {
    const bytes = &quot;hello&quot;;
    print(&quot;{}\n&quot;, .{@TypeOf(bytes)}); // *const [5:0]u8
    print(&quot;{d}\n&quot;, .{bytes.len}); // 5
    print(&quot;{c}\n&quot;, .{bytes[1]}); // &#39;e&#39;
    print(&quot;{d}\n&quot;, .{bytes[5]}); // 0
    print(&quot;{}\n&quot;, .{&#39;e&#39; == &#39;\x65&#39;}); // true
    print(&quot;{d}\n&quot;, .{&#39;\u{1f4a9}&#39;}); // 128169
    print(&quot;{d}\n&quot;, .{&#39;💯&#39;}); // 128175
    print(&quot;{u}\n&quot;, .{&#39;⚡&#39;});
    print(&quot;{}\n&quot;, .{mem.eql(u8, &quot;hello&quot;, &quot;h\x65llo&quot;)}); // true
    print(&quot;{}\n&quot;, .{mem.eql(u8, &quot;💯&quot;, &quot;\xf0\x9f\x92\xaf&quot;)}); // also true
    const invalid_utf8 = &quot;\xff\xfe&quot;; // non-UTF-8 strings are possible with \xNN notation.
    print(&quot;0x{x}\n&quot;, .{invalid_utf8[1]}); // indexing them returns individual bytes...
    print(&quot;0x{x}\n&quot;, .{&quot;💯&quot;[1]}); // ...as does indexing part-way through non-ASCII characters
}</code></pre>
<figcaption>string_literals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe string_literals.zig
$ ./string_literals
*const [5:0]u8
5
e
0
true
128169
128175
⚡
true
true
0xfe
0x9f</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Arrays](zig-0.15.1.md#Arrays)
- [Source Encoding](zig-0.15.1.md#Source-Encoding)

#### [Escape Sequences](zig-0.15.1.md#toc-Escape-Sequences) <a href="zig-0.15.1.md#Escape-Sequences" class="hdr">§</a>

<div class="table-wrapper">

| Escape Sequence | Name |
|----|----|
| `\n` | Newline |
| `\r` | Carriage Return |
| `\t` | Tab |
| `\\` | Backslash |
| `\'` | Single Quote |
| `\"` | Double Quote |
| `\xNN` | hexadecimal 8-bit byte value (2 digits) |
| `\u{NNNNNN}` | hexadecimal Unicode scalar value UTF-8 encoded (1 or more digits) |

Escape Sequences

</div>

Note that the maximum valid Unicode scalar value is <span class="tok-number">`0x10ffff`</span>.

#### [Multiline String Literals](zig-0.15.1.md#toc-Multiline-String-Literals) <a href="zig-0.15.1.md#Multiline-String-Literals" class="hdr">§</a>

Multiline string literals have no escapes and can span across multiple lines.
To start a multiline string literal, use the <span class="tok-str">`\\`</span> token. Just like a comment,
the string literal goes until the end of the line. The end of the line is
not included in the string literal.
However, if the next line begins with <span class="tok-str">`\\`</span> then a newline is appended and
the string literal continues.

<figure>
<pre><code>const hello_world_in_c =
    \\#include &lt;stdio.h&gt;
    \\
    \\int main(int argc, char **argv) {
    \\    printf(&quot;hello world\n&quot;);
    \\    return 0;
    \\}
;</code></pre>
<figcaption>multiline_string_literals.zig</figcaption>
</figure>

See also:

- [@embedFile](zig-0.15.1.md#embedFile)

### [Assignment](zig-0.15.1.md#toc-Assignment) <a href="zig-0.15.1.md#Assignment" class="hdr">§</a>

Use the <span class="tok-kw">`const`</span> keyword to assign a value to an identifier:

<figure>
<pre><code>const x = 1234;

fn foo() void {
    // It works at file scope as well as inside functions.
    const y = 5678;

    // Once assigned, an identifier cannot be changed.
    y += 1;
}

pub fn main() void {
    foo();
}</code></pre>
<figcaption>constant_identifier_cannot_change.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe constant_identifier_cannot_change.zig
/home/andy/dev/zig/doc/langref/constant_identifier_cannot_change.zig:8:5: error: cannot assign to constant
    y += 1;
    ^
referenced by:
    main: /home/andy/dev/zig/doc/langref/constant_identifier_cannot_change.zig:12:8
    callMain [inlined]: /home/andy/dev/zig/lib/std/start.zig:618:22
    callMainWithArgs [inlined]: /home/andy/dev/zig/lib/std/start.zig:587:20
    posixCallMainAndExit: /home/andy/dev/zig/lib/std/start.zig:542:36
    2 reference(s) hidden; use &#39;-freference-trace=6&#39; to see all references
</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-kw">`const`</span> applies to all of the bytes that the identifier immediately addresses. [Pointers](zig-0.15.1.md#Pointers) have their own const-ness.

If you need a variable that you can modify, use the <span class="tok-kw">`var`</span> keyword:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    var y: i32 = 5678;

    y += 1;

    print(&quot;{d}&quot;, .{y});
}</code></pre>
<figcaption>mutable_var.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe mutable_var.zig
$ ./mutable_var
5679</code></pre>
<figcaption>Shell</figcaption>
</figure>

Variables must be initialized:

<figure>
<pre><code>pub fn main() void {
    var x: i32;

    x = 1;
}</code></pre>
<figcaption>var_must_be_initialized.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe var_must_be_initialized.zig
/home/andy/dev/zig/doc/langref/var_must_be_initialized.zig:2:15: error: expected &#39;=&#39;, found &#39;;&#39;
    var x: i32;
              ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [undefined](zig-0.15.1.md#toc-undefined) <a href="zig-0.15.1.md#undefined" class="hdr">§</a>

Use <span class="tok-null">`undefined`</span> to leave variables uninitialized:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    var x: i32 = undefined;
    x = 1;
    print(&quot;{d}&quot;, .{x});
}</code></pre>
<figcaption>assign_undefined.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe assign_undefined.zig
$ ./assign_undefined
1</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-null">`undefined`</span> can be [coerced](zig-0.15.1.md#Type-Coercion) to any type.
Once this happens, it is no longer possible to detect that the value is <span class="tok-null">`undefined`</span>.
<span class="tok-null">`undefined`</span> means the value could be anything, even something that is nonsense
according to the type. Translated into English, <span class="tok-null">`undefined`</span> means "Not a meaningful
value. Using this value would be a bug. The value will be unused, or overwritten before being used."

In [Debug](zig-0.15.1.md#Debug) and [ReleaseSafe](zig-0.15.1.md#ReleaseSafe) mode, Zig writes <span class="tok-number">`0xaa`</span> bytes to undefined memory. This is to catch
bugs early, and to help detect use of undefined memory in a debugger. However, this behavior is only an
implementation feature, not a language semantic, so it is not guaranteed to be observable to code.

#### [Destructuring](zig-0.15.1.md#toc-Destructuring) <a href="zig-0.15.1.md#Destructuring" class="hdr">§</a>

A destructuring assignment can separate elements of indexable aggregate types
([Tuples](zig-0.15.1.md#Tuples), [Arrays](zig-0.15.1.md#Arrays), [Vectors](zig-0.15.1.md#Vectors)):

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    var x: u32 = undefined;
    var y: u32 = undefined;
    var z: u32 = undefined;

    const tuple = .{ 1, 2, 3 };

    x, y, z = tuple;

    print(&quot;tuple: x = {}, y = {}, z = {}\n&quot;, .{x, y, z});

    const array = [_]u32{ 4, 5, 6 };

    x, y, z = array;

    print(&quot;array: x = {}, y = {}, z = {}\n&quot;, .{x, y, z});

    const vector: @Vector(3, u32) = .{ 7, 8, 9 };

    x, y, z = vector;

    print(&quot;vector: x = {}, y = {}, z = {}\n&quot;, .{x, y, z});
}</code></pre>
<figcaption>destructuring_to_existing.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_to_existing.zig
$ ./destructuring_to_existing
tuple: x = 1, y = 2, z = 3
array: x = 4, y = 5, z = 6
vector: x = 7, y = 8, z = 9</code></pre>
<figcaption>Shell</figcaption>
</figure>

A destructuring expression may only appear within a block (i.e. not at container scope).
The left hand side of the assignment must consist of a comma separated list,
each element of which may be either an lvalue (for instance, an existing \`var\`) or a variable declaration:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    var x: u32 = undefined;

    const tuple = .{ 1, 2, 3 };

    x, var y : u32, const z = tuple;

    print(&quot;x = {}, y = {}, z = {}\n&quot;, .{x, y, z});

    // y is mutable
    y = 100;

    // You can use _ to throw away unwanted values.
    _, x, _ = tuple;

    print(&quot;x = {}&quot;, .{x});
}</code></pre>
<figcaption>destructuring_mixed.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_mixed.zig
$ ./destructuring_mixed
x = 1, y = 2, z = 3
x = 2</code></pre>
<figcaption>Shell</figcaption>
</figure>

A destructure may be prefixed with the <span class="tok-kw">`comptime`</span> keyword, in which case the entire
destructure expression is evaluated at [comptime](zig-0.15.1.md#comptime). All <span class="tok-kw">`var`</span>s declared would
be <span class="tok-kw">`comptime`</span>` `<span class="tok-kw">`var`</span>s and all expressions (both result locations and the assignee
expression) are evaluated at [comptime](zig-0.15.1.md#comptime).

See also:

- [Destructuring Tuples](zig-0.15.1.md#Destructuring-Tuples)
- [Destructuring Arrays](zig-0.15.1.md#Destructuring-Arrays)
- [Destructuring Vectors](zig-0.15.1.md#Destructuring-Vectors)

