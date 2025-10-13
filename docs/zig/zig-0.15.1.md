<div id="contents" role="main">

## [Introduction](#toc-Introduction) <a href="#Introduction" class="hdr">§</a>

[Zig](https://ziglang.org) is a general-purpose programming language and toolchain for maintaining
**robust**, **optimal**, and **reusable** software.

Robust  
Behavior is correct even for edge cases such as out of memory.

Optimal  
Write programs the best way they can behave and perform.

Reusable  
The same code works in many environments which have different
constraints.

Maintainable  
Precisely communicate intent to the compiler and
other programmers. The language imposes a low overhead to reading code and is
resilient to changing requirements and environments.

Often the most efficient way to learn something new is to see examples, so
this documentation shows how to use each of Zig's features. It is
all on one page so you can search with your browser's search tool.

The code samples in this document are compiled and tested as part of the main test suite of Zig.

This HTML document depends on no external files, so you can use it offline.

## [Zig Standard Library](#toc-Zig-Standard-Library) <a href="#Zig-Standard-Library" class="hdr">§</a>

The [Zig Standard Library](https://ziglang.org/documentation/0.15.1/std/) has its own documentation.

Zig's Standard Library contains commonly used algorithms, data structures, and definitions to help you build programs or libraries.
You will see many examples of Zig's Standard Library used in this documentation. To learn more about the Zig Standard Library,
visit the link above.

Alternatively, the Zig Standard Library documentation is provided with each Zig distribution. It can be rendered via a local webserver with:

<figure>
<pre><code>zig std</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Hello World](#toc-Hello-World) <a href="#Hello-World" class="hdr">§</a>

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

- [Values](#Values)
- [Tuples](#Tuples)
- [@import](#import)
- [Errors](#Errors)
- [Entry Point](#Entry-Point)
- [Source Encoding](#Source-Encoding)
- [try](#try)

## [Comments](#toc-Comments) <a href="#Comments" class="hdr">§</a>

Zig supports 3 types of comments. Normal comments are ignored, but doc comments
and top-level doc comments are used by the compiler to generate the package documentation.

The generated documentation is still experimental, and can be produced with:

<figure>
<pre><code>zig test -femit-docs main.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    // Comments in Zig start with &quot;//&quot; and end at the next LF byte (end of line).
    // The line below is a comment and won&#39;t be executed.

    //print(&quot;Hello?&quot;, .{});

    print(&quot;Hello, world!\n&quot;, .{}); // another comment
}</code></pre>
<figcaption>comments.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe comments.zig
$ ./comments
Hello, world!</code></pre>
<figcaption>Shell</figcaption>
</figure>

There are no multiline comments in Zig (e.g. like `/* */`
comments in C). This allows Zig to have the property that each line
of code can be tokenized out of context.

### [Doc Comments](#toc-Doc-Comments) <a href="#Doc-Comments" class="hdr">§</a>

A doc comment is one that begins with exactly three slashes (i.e.
<span class="tok-comment">`///`</span> but not <span class="tok-comment">`////`</span>);
multiple doc comments in a row are merged together to form a multiline
doc comment. The doc comment documents whatever immediately follows it.

<figure>
<pre><code>/// A structure for storing a timestamp, with nanosecond precision (this is a
/// multiline doc comment).
const Timestamp = struct {
    /// The number of seconds since the epoch (this is also a doc comment).
    seconds: i64, // signed so we can represent pre-1970 (not a doc comment)
    /// The number of nanoseconds past the second (doc comment again).
    nanos: u32,

    /// Returns a `Timestamp` struct representing the Unix epoch; that is, the
    /// moment of 1970 Jan 1 00:00:00 UTC (this is a doc comment too).
    pub fn unixEpoch() Timestamp {
        return Timestamp{
            .seconds = 0,
            .nanos = 0,
        };
    }
};</code></pre>
<figcaption>doc_comments.zig</figcaption>
</figure>

Doc comments are only allowed in certain places; it is a compile error to
have a doc comment in an unexpected place, such as in the middle of an expression,
or just before a non-doc comment.

<figure>
<pre><code>/// doc-comment
//! top-level doc-comment
const std = @import(&quot;std&quot;);</code></pre>
<figcaption>invalid_doc-comment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj invalid_doc-comment.zig
/home/andy/dev/zig/doc/langref/invalid_doc-comment.zig:1:16: error: expected type expression, found &#39;a document comment&#39;
/// doc-comment
               ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>pub fn main() void {}

/// End of file</code></pre>
<figcaption>unattached_doc-comment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj unattached_doc-comment.zig
/home/andy/dev/zig/doc/langref/unattached_doc-comment.zig:3:1: error: unattached documentation comment
/// End of file
^~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Doc comments can be interleaved with normal comments. Currently, when producing
the package documentation, normal comments are merged with doc comments.

### [Top-Level Doc Comments](#toc-Top-Level-Doc-Comments) <a href="#Top-Level-Doc-Comments" class="hdr">§</a>

A top-level doc comment is one that begins with two slashes and an exclamation
point: <span class="tok-comment">`//!`</span>; it documents the current module.

It is a compile error if a top-level doc comment is not placed at the start
of a [container](#Containers), before any expressions.

<figure>
<pre><code>//! This module provides functions for retrieving the current date and
//! time with varying degrees of precision and accuracy. It does not
//! depend on libc, but will use functions from it if available.

const S = struct {
    //! Top level comments are allowed inside a container other than a module,
    //! but it is not very useful.  Currently, when producing the package
    //! documentation, these comments are ignored.
};</code></pre>
<figcaption>tldoc_comments.zig</figcaption>
</figure>

## [Values](#toc-Values) <a href="#Values" class="hdr">§</a>

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

### [Primitive Types](#toc-Primitive-Types) <a href="#Primitive-Types" class="hdr">§</a>

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
| <span class="tok-type">`comptime_int`</span> | (none) | Only allowed for [comptime](#comptime)-known values. The type of integer literals. |
| <span class="tok-type">`comptime_float`</span> | (none) | Only allowed for [comptime](#comptime)-known values. The type of float literals. |

Primitive Types

</div>

In addition to the integer types above, arbitrary bit-width integers can be referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>.

See also:

- [Integers](#Integers)
- [Floats](#Floats)
- [void](#void)
- [Errors](#Errors)
- [@Type](#Type)

### [Primitive Values](#toc-Primitive-Values) <a href="#Primitive-Values" class="hdr">§</a>

<div class="table-wrapper">

| Name | Description |
|----|----|
| <span class="tok-null">`true`</span> and <span class="tok-null">`false`</span> | <span class="tok-type">`bool`</span> values |
| <span class="tok-null">`null`</span> | used to set an optional type to <span class="tok-null">`null`</span> |
| <span class="tok-null">`undefined`</span> | used to leave a value unspecified |

Primitive Values

</div>

See also:

- [Optionals](#Optionals)
- [undefined](#undefined)

### [String Literals and Unicode Code Point Literals](#toc-String-Literals-and-Unicode-Code-Point-Literals) <a href="#String-Literals-and-Unicode-Code-Point-Literals" class="hdr">§</a>

String literals are constant single-item [Pointers](#Pointers) to null-terminated byte arrays.
The type of string literals encodes both the length, and the fact that they are null-terminated,
and thus they can be [coerced](#Type-Coercion) to both [Slices](#Slices) and
[Null-Terminated Pointers](#Sentinel-Terminated-Pointers).
Dereferencing string literals converts them to [Arrays](#Arrays).

Because Zig source code is [UTF-8 encoded](#Source-Encoding), any
non-ASCII bytes appearing within a string literal in source code carry
their UTF-8 meaning into the content of the string in the Zig program;
the bytes are not modified by the compiler. It is possible to embed
non-UTF-8 bytes into a string literal using `\xNN` notation.

Indexing into a string containing non-ASCII bytes returns individual
bytes, whether valid UTF-8 or not.

Unicode code point literals have type <span class="tok-type">`comptime_int`</span>, the same as
[Integer Literals](#Integer-Literals). All [Escape Sequences](#Escape-Sequences) are valid in both string literals
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

- [Arrays](#Arrays)
- [Source Encoding](#Source-Encoding)

#### [Escape Sequences](#toc-Escape-Sequences) <a href="#Escape-Sequences" class="hdr">§</a>

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

#### [Multiline String Literals](#toc-Multiline-String-Literals) <a href="#Multiline-String-Literals" class="hdr">§</a>

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

- [@embedFile](#embedFile)

### [Assignment](#toc-Assignment) <a href="#Assignment" class="hdr">§</a>

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

<span class="tok-kw">`const`</span> applies to all of the bytes that the identifier immediately addresses. [Pointers](#Pointers) have their own const-ness.

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

#### [undefined](#toc-undefined) <a href="#undefined" class="hdr">§</a>

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

<span class="tok-null">`undefined`</span> can be [coerced](#Type-Coercion) to any type.
Once this happens, it is no longer possible to detect that the value is <span class="tok-null">`undefined`</span>.
<span class="tok-null">`undefined`</span> means the value could be anything, even something that is nonsense
according to the type. Translated into English, <span class="tok-null">`undefined`</span> means "Not a meaningful
value. Using this value would be a bug. The value will be unused, or overwritten before being used."

In [Debug](#Debug) and [ReleaseSafe](#ReleaseSafe) mode, Zig writes <span class="tok-number">`0xaa`</span> bytes to undefined memory. This is to catch
bugs early, and to help detect use of undefined memory in a debugger. However, this behavior is only an
implementation feature, not a language semantic, so it is not guaranteed to be observable to code.

#### [Destructuring](#toc-Destructuring) <a href="#Destructuring" class="hdr">§</a>

A destructuring assignment can separate elements of indexable aggregate types
([Tuples](#Tuples), [Arrays](#Arrays), [Vectors](#Vectors)):

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
destructure expression is evaluated at [comptime](#comptime). All <span class="tok-kw">`var`</span>s declared would
be <span class="tok-kw">`comptime`</span>` `<span class="tok-kw">`var`</span>s and all expressions (both result locations and the assignee
expression) are evaluated at [comptime](#comptime).

See also:

- [Destructuring Tuples](#Destructuring-Tuples)
- [Destructuring Arrays](#Destructuring-Arrays)
- [Destructuring Vectors](#Destructuring-Vectors)

## [Zig Test](#toc-Zig-Test) <a href="#Zig-Test" class="hdr">§</a>

Code written within one or more <span class="tok-kw">`test`</span> declarations can be used to ensure behavior meets expectations:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;expect addOne adds one to 41&quot; {

    // The Standard Library contains useful functions to help create tests.
    // `expect` is a function that verifies its argument is true.
    // It will return an error if its argument is false to indicate a failure.
    // `try` is used to return an error to the test runner to notify it that the test failed.
    try std.testing.expect(addOne(41) == 42);
}

test addOne {
    // A test name can also be written using an identifier.
    // This is a doctest, and serves as documentation for `addOne`.
    try std.testing.expect(addOne(41) == 42);
}

/// The function `addOne` adds one to the number given as its argument.
fn addOne(number: i32) i32 {
    return number + 1;
}</code></pre>
<figcaption>testing_introduction.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_introduction.zig
1/2 testing_introduction.test.expect addOne adds one to 41...OK
2/2 testing_introduction.decltest.addOne...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The `testing_introduction.zig` code sample tests the [function](#Functions)
`addOne` to ensure that it returns <span class="tok-number">`42`</span> given the input
<span class="tok-number">`41`</span>. From this test's perspective, the `addOne` function is
said to be *code under test*.

<span class="kbd">zig test</span> is a tool that creates and runs a test build. By default, it builds and runs an
executable program using the *default test runner* provided by the [Zig Standard Library](#Zig-Standard-Library)
as its main entry point. During the build, <span class="tok-kw">`test`</span> declarations found while
[resolving](#File-and-Declaration-Discovery) the given Zig source file are included for the default test runner
to run and report on.

This documentation discusses the features of the default test runner as provided by the Zig Standard Library.
Its source code is located in `lib/compiler/test_runner.zig`.

The shell output shown above displays two lines after the <span class="kbd">zig test</span> command. These lines are
printed to standard error by the default test runner:

`1/2 testing_introduction.test.expect addOne adds one to 41...`  
Lines like this indicate which test, out of the total number of tests, is being run.
In this case, `1/2` indicates that the first test, out of a total of two tests,
is being run. Note that, when the test runner program's standard error is output
to the terminal, these lines are cleared when a test succeeds.

`2/2 testing_introduction.decltest.addOne...`  
When the test name is an identifier, the default test runner uses the text
decltest instead of test.

`All 2 tests passed.`  
This line indicates the total number of tests that have passed.

### [Test Declarations](#toc-Test-Declarations) <a href="#Test-Declarations" class="hdr">§</a>

Test declarations contain the [keyword](#Keyword-Reference) <span class="tok-kw">`test`</span>, followed by an
optional name written as a [string literal](#String-Literals-and-Unicode-Code-Point-Literals) or an
[identifier](#Identifiers), followed by a [block](#Blocks) containing any valid Zig code that
is allowed in a [function](#Functions).

Non-named test blocks always run during test builds and are exempt from
[Skip Tests](#Skip-Tests).

Test declarations are similar to [Functions](#Functions): they have a return type and a block of code. The implicit
return type of <span class="tok-kw">`test`</span> is the [Error Union Type](#Error-Union-Type) <span class="tok-type">`anyerror`</span>`!`<span class="tok-type">`void`</span>,
and it cannot be changed. When a Zig source file is not built using the <span class="kbd">zig test</span> tool, the test
declarations are omitted from the build.

Test declarations can be written in the same file, where code under test is written, or in a separate Zig source file.
Since test declarations are top-level declarations, they are order-independent and can
be written before or after the code under test.

See also:

- [The Global Error Set](#The-Global-Error-Set)
- [Grammar](#Grammar)

#### [Doctests](#toc-Doctests) <a href="#Doctests" class="hdr">§</a>

Test declarations named using an identifier are *doctests*. The identifier must refer to another declaration in
scope. A doctest, like a [doc comment](#Doc-Comments), serves as documentation for the associated declaration, and
will appear in the generated documentation for the declaration.

An effective doctest should be self-contained and focused on the declaration being tested, answering questions a new
user might have about its interface or intended usage, while avoiding unnecessary or confusing details. A doctest is not
a substitute for a doc comment, but rather a supplement and companion providing a testable, code-driven example, verified
by <span class="kbd">zig test</span>.

### [Test Failure](#toc-Test-Failure) <a href="#Test-Failure" class="hdr">§</a>

The default test runner checks for an [error](#Errors) returned from a test.
When a test returns an error, the test is considered a failure and its [error return trace](#Error-Return-Traces)
is output to standard error. The total number of failures will be reported after all tests have run.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;expect this to fail&quot; {
    try std.testing.expect(false);
}

test &quot;expect this to succeed&quot; {
    try std.testing.expect(true);
}</code></pre>
<figcaption>testing_failure.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_failure.zig
1/2 testing_failure.test.expect this to fail...FAIL (TestUnexpectedResult)
/home/andy/dev/zig/lib/std/testing.zig:607:14: 0x102f019 in expect (std.zig)
    if (!ok) return error.TestUnexpectedResult;
             ^
/home/andy/dev/zig/doc/langref/testing_failure.zig:4:5: 0x102f078 in test.expect this to fail (testing_failure.zig)
    try std.testing.expect(false);
    ^
2/2 testing_failure.test.expect this to succeed...OK
1 passed; 0 skipped; 1 failed.
error: the following test command failed with exit code 1:
/home/andy/dev/zig/.zig-cache/o/8ba6040bfa3fe5b54273009f6f88094d/test --seed=0x7a8bebf7</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Skip Tests](#toc-Skip-Tests) <a href="#Skip-Tests" class="hdr">§</a>

One way to skip tests is to filter them out by using the <span class="kbd">zig test</span> command line parameter
<span class="kbd">--test-filter \[text\]</span>. This makes the test build only include tests whose name contains the
supplied filter text. Note that non-named tests are run even when using the <span class="kbd">--test-filter \[text\]</span>
command line parameter.

To programmatically skip a test, make a <span class="tok-kw">`test`</span> return the error
<span class="tok-kw">`error`</span>`.SkipZigTest` and the default test runner will consider the test as being skipped.
The total number of skipped tests will be reported after all tests have run.

<figure>
<pre><code>test &quot;this will be skipped&quot; {
    return error.SkipZigTest;
}</code></pre>
<figcaption>testing_skip.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_skip.zig
1/1 testing_skip.test.this will be skipped...SKIP
0 passed; 1 skipped; 0 failed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Report Memory Leaks](#toc-Report-Memory-Leaks) <a href="#Report-Memory-Leaks" class="hdr">§</a>

When code allocates [Memory](#Memory) using the [Zig Standard Library](#Zig-Standard-Library)'s testing allocator,
`std.testing.allocator`, the default test runner will report any leaks that are
found from using the testing allocator:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;detect leak&quot; {
    var list = std.array_list.Managed(u21).init(std.testing.allocator);
    // missing `defer list.deinit();`
    try list.append(&#39;☔&#39;);

    try std.testing.expect(list.items.len == 1);
}</code></pre>
<figcaption>testing_detect_leak.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_detect_leak.zig
1/1 testing_detect_leak.test.detect leak...OK
[gpa] (err): memory address 0x7f05ba780000 leaked:
/home/andy/dev/zig/lib/std/array_list.zig:468:67: 0x10aa91e in ensureTotalCapacityPrecise (std.zig)
                const new_memory = try self.allocator.alignedAlloc(T, alignment, new_capacity);
                                                                  ^
/home/andy/dev/zig/lib/std/array_list.zig:444:51: 0x107ca04 in ensureTotalCapacity (std.zig)
            return self.ensureTotalCapacityPrecise(better_capacity);
                                                  ^
/home/andy/dev/zig/lib/std/array_list.zig:494:41: 0x105590d in addOne (std.zig)
            try self.ensureTotalCapacity(newlen);
                                        ^
/home/andy/dev/zig/lib/std/array_list.zig:252:49: 0x1038771 in append (std.zig)
            const new_item_ptr = try self.addOne();
                                                ^
/home/andy/dev/zig/doc/langref/testing_detect_leak.zig:6:20: 0x10350a9 in test.detect leak (testing_detect_leak.zig)
    try list.append(&#39;☔&#39;);
                   ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x1174740 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1170d61 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x116aafd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x116a391 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^

All 1 tests passed.
1 errors were logged.
1 tests leaked memory.
error: the following test command failed with exit code 1:
/home/andy/dev/zig/.zig-cache/o/63899a4b3b3d04b1043e75c5b90543d1/test --seed=0xe371a8c1</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [defer](#defer)
- [Memory](#Memory)

### [Detecting Test Build](#toc-Detecting-Test-Build) <a href="#Detecting-Test-Build" class="hdr">§</a>

Use the [compile variable](#Compile-Variables) <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`).is_test`
to detect a test build:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;

test &quot;builtin.is_test&quot; {
    try expect(isATest());
}

fn isATest() bool {
    return builtin.is_test;
}</code></pre>
<figcaption>testing_detect_test.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_detect_test.zig
1/1 testing_detect_test.test.builtin.is_test...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Test Output and Logging](#toc-Test-Output-and-Logging) <a href="#Test-Output-and-Logging" class="hdr">§</a>

The default test runner and the Zig Standard Library's testing namespace output messages to standard error.

### [The Testing Namespace](#toc-The-Testing-Namespace) <a href="#The-Testing-Namespace" class="hdr">§</a>

The Zig Standard Library's `testing` namespace contains useful functions to help
you create tests. In addition to the `expect` function, this document uses a couple of more functions
as exemplified here:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;expectEqual demo&quot; {
    const expected: i32 = 42;
    const actual = 42;

    // The first argument to `expectEqual` is the known, expected, result.
    // The second argument is the result of some expression.
    // The actual&#39;s type is casted to the type of expected.
    try std.testing.expectEqual(expected, actual);
}

test &quot;expectError demo&quot; {
    const expected_error = error.DemoError;
    const actual_error_union: anyerror!void = error.DemoError;

    // `expectError` will fail when the actual error is different than
    // the expected error.
    try std.testing.expectError(expected_error, actual_error_union);
}</code></pre>
<figcaption>testing_namespace.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test testing_namespace.zig
1/2 testing_namespace.test.expectEqual demo...OK
2/2 testing_namespace.test.expectError demo...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The Zig Standard Library also contains functions to compare [Slices](#Slices), strings, and more. See the rest of the
`std.testing` namespace in the [Zig Standard Library](#Zig-Standard-Library) for more available functions.

### [Test Tool Documentation](#toc-Test-Tool-Documentation) <a href="#Test-Tool-Documentation" class="hdr">§</a>

<span class="kbd">zig test</span> has a few command line parameters which affect the compilation.
See <span class="kbd">zig test --help</span> for a full list.

## [Variables](#toc-Variables) <a href="#Variables" class="hdr">§</a>

A variable is a unit of [Memory](#Memory) storage.

It is generally preferable to use <span class="tok-kw">`const`</span> rather than
<span class="tok-kw">`var`</span> when declaring a variable. This causes less work for both
humans and computers to do when reading code, and creates more optimization opportunities.

The <span class="tok-kw">`extern`</span> keyword or [@extern](#extern) builtin function can be used to link against a variable that is exported
from another object. The <span class="tok-kw">`export`</span> keyword or [@export](#export) builtin function
can be used to make a variable available to other objects at link time. In both cases,
the type of the variable must be C ABI compatible.

See also:

- [Exporting a C Library](#Exporting-a-C-Library)

### [Identifiers](#toc-Identifiers) <a href="#Identifiers" class="hdr">§</a>

Variable identifiers are never allowed to shadow identifiers from an outer scope.

Identifiers must start with an alphabetic character or underscore and may be followed
by any number of alphanumeric characters or underscores.
They must not overlap with any keywords. See [Keyword Reference](#Keyword-Reference).

If a name that does not fit these requirements is needed, such as for linking with external libraries, the `@""` syntax may be used.

<figure>
<pre><code>const @&quot;identifier with spaces in it&quot; = 0xff;
const @&quot;1SmallStep4Man&quot; = 112358;

const c = @import(&quot;std&quot;).c;
pub extern &quot;c&quot; fn @&quot;error&quot;() void;
pub extern &quot;c&quot; fn @&quot;fstat$INODE64&quot;(fd: c.fd_t, buf: *c.Stat) c_int;

const Color = enum {
    red,
    @&quot;really red&quot;,
};
const color: Color = .@&quot;really red&quot;;</code></pre>
<figcaption>identifiers.zig</figcaption>
</figure>

### [Container Level Variables](#toc-Container-Level-Variables) <a href="#Container-Level-Variables" class="hdr">§</a>

[Container](#Containers) level variables have static lifetime and are order-independent and lazily analyzed.
The initialization value of container level variables is implicitly
[comptime](#comptime). If a container level variable is <span class="tok-kw">`const`</span> then its value is
<span class="tok-kw">`comptime`</span>-known, otherwise it is runtime-known.

<figure>
<pre><code>var y: i32 = add(10, x);
const x: i32 = add(12, 34);

test &quot;container level variables&quot; {
    try expect(x == 46);
    try expect(y == 56);
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

const std = @import(&quot;std&quot;);
const expect = std.testing.expect;</code></pre>
<figcaption>test_container_level_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_container_level_variables.zig
1/1 test_container_level_variables.test.container level variables...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Container level variables may be declared inside a [struct](#struct), [union](#union), [enum](#enum), or [opaque](#opaque):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;namespaced container level variable&quot; {
    try expect(foo() == 1235);
    try expect(foo() == 1236);
}

const S = struct {
    var x: i32 = 1234;
};

fn foo() i32 {
    S.x += 1;
    return S.x;
}</code></pre>
<figcaption>test_namespaced_container_level_variable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_namespaced_container_level_variable.zig
1/1 test_namespaced_container_level_variable.test.namespaced container level variable...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Static Local Variables](#toc-Static-Local-Variables) <a href="#Static-Local-Variables" class="hdr">§</a>

It is also possible to have local variables with static lifetime by using containers inside functions.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;static local variable&quot; {
    try expect(foo() == 1235);
    try expect(foo() == 1236);
}

fn foo() i32 {
    const S = struct {
        var x: i32 = 1234;
    };
    S.x += 1;
    return S.x;
}</code></pre>
<figcaption>test_static_local_variable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_static_local_variable.zig
1/1 test_static_local_variable.test.static local variable...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Thread Local Variables](#toc-Thread-Local-Variables) <a href="#Thread-Local-Variables" class="hdr">§</a>

A variable may be specified to be a thread-local variable using the
<span class="tok-kw">`threadlocal`</span> keyword,
which makes each thread work with a separate instance of the variable:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const assert = std.debug.assert;

threadlocal var x: i32 = 1234;

test &quot;thread local storage&quot; {
    const thread1 = try std.Thread.spawn(.{}, testTls, .{});
    const thread2 = try std.Thread.spawn(.{}, testTls, .{});
    testTls();
    thread1.join();
    thread2.join();
}

fn testTls() void {
    assert(x == 1234);
    x += 1;
    assert(x == 1235);
}</code></pre>
<figcaption>test_thread_local_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_thread_local_variables.zig
1/1 test_thread_local_variables.test.thread local storage...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

For [Single Threaded Builds](#Single-Threaded-Builds), all thread local variables are treated as regular [Container Level Variables](#Container-Level-Variables).

Thread local variables may not be <span class="tok-kw">`const`</span>.

### [Local Variables](#toc-Local-Variables) <a href="#Local-Variables" class="hdr">§</a>

Local variables occur inside [Functions](#Functions), [comptime](#comptime) blocks, and [@cImport](#cImport) blocks.

When a local variable is <span class="tok-kw">`const`</span>, it means that after initialization, the variable's
value will not change. If the initialization value of a <span class="tok-kw">`const`</span> variable is
[comptime](#comptime)-known, then the variable is also <span class="tok-kw">`comptime`</span>-known.

A local variable may be qualified with the <span class="tok-kw">`comptime`</span> keyword. This causes
the variable's value to be <span class="tok-kw">`comptime`</span>-known, and all loads and stores of the
variable to happen during semantic analysis of the program, rather than at runtime.
All variables declared in a <span class="tok-kw">`comptime`</span> expression are implicitly
<span class="tok-kw">`comptime`</span> variables.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;comptime vars&quot; {
    var x: i32 = 1;
    comptime var y: i32 = 1;

    x += 1;
    y += 1;

    try expect(x == 2);
    try expect(y == 2);

    if (y != 2) {
        // This compile error never triggers because y is a comptime variable,
        // and so `y != 2` is a comptime value, and this if is statically evaluated.
        @compileError(&quot;wrong y value&quot;);
    }
}</code></pre>
<figcaption>test_comptime_variables.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_variables.zig
1/1 test_comptime_variables.test.comptime vars...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Integers](#toc-Integers) <a href="#Integers" class="hdr">§</a>

### [Integer Literals](#toc-Integer-Literals) <a href="#Integer-Literals" class="hdr">§</a>

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

### [Runtime Integer Values](#toc-Runtime-Integer-Values) <a href="#Runtime-Integer-Values" class="hdr">§</a>

Integer literals have no size limitation, and if any Illegal Behavior occurs,
the compiler catches it.

However, once an integer value is no longer known at compile-time, it must have a
known size, and is vulnerable to safety-checked [Illegal Behavior](#Illegal-Behavior).

<figure>
<pre><code>fn divide(a: i32, b: i32) i32 {
    return a / b;
}</code></pre>
<figcaption>runtime_vs_comptime.zig</figcaption>
</figure>

In this function, values `a` and `b` are known only at runtime,
and thus this division operation is vulnerable to both [Integer Overflow](#Integer-Overflow) and
[Division by Zero](#Division-by-Zero).

Operators such as `+` and `-` cause [Illegal Behavior](#Illegal-Behavior) on
integer overflow. Alternative operators are provided for wrapping and saturating arithmetic on all targets.
`+%` and `-%` perform wrapping arithmetic
while `+|` and `-|` perform saturating arithmetic.

Zig supports arbitrary bit-width integers, referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>. For signed integer types, Zig uses a
[two's complement](https://en.wikipedia.org/wiki/Two's_complement) representation.

See also:

- [Wrapping Operations](#Wrapping-Operations)

## [Floats](#toc-Floats) <a href="#Floats" class="hdr">§</a>

Zig has the following floating point types:

- <span class="tok-type">`f16`</span> - IEEE-754-2008 binary16
- <span class="tok-type">`f32`</span> - IEEE-754-2008 binary32
- <span class="tok-type">`f64`</span> - IEEE-754-2008 binary64
- <span class="tok-type">`f80`</span> - IEEE-754-2008 80-bit extended precision
- <span class="tok-type">`f128`</span> - IEEE-754-2008 binary128
- <span class="tok-type">`c_longdouble`</span> - matches `long double` for the target C ABI

### [Float Literals](#toc-Float-Literals) <a href="#Float-Literals" class="hdr">§</a>

Float literals have type <span class="tok-type">`comptime_float`</span> which is guaranteed to have
the same precision and operations of the largest other floating point type, which is
<span class="tok-type">`f128`</span>.

Float literals [coerce](#Type-Coercion) to any floating point type,
and to any [integer](#Integers) type when there is no fractional component.

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

### [Floating Point Operations](#toc-Floating-Point-Operations) <a href="#Floating-Point-Operations" class="hdr">§</a>

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

- [@setFloatMode](#setFloatMode)
- [Division by Zero](#Division-by-Zero)

## [Operators](#toc-Operators) <a href="#Operators" class="hdr">§</a>

There is no operator overloading. When you see an operator in Zig, you know that
it is doing something from this table, and nothing else.

### [Table of Operators](#toc-Table-of-Operators) <a href="#Table-of-Operators" class="hdr">§</a>

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
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 + 5 == 7</code></pre></td>
</tr>
<tr>
<td>Wrapping Addition</td>
<td><pre><code>a +% b
a +%= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#addWithOverflow">@addWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u32, 0xffffffff) +% 1 == 0</code></pre></td>
</tr>
<tr>
<td>Saturating Addition</td>
<td><pre><code>a +| b
a +|= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 255) +| 1 == @as(u8, 255)</code></pre></td>
</tr>
<tr>
<td>Subtraction</td>
<td><pre><code>a - b
a -= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 - 5 == -3</code></pre></td>
</tr>
<tr>
<td>Wrapping Subtraction</td>
<td><pre><code>a -% b
a -%= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#subWithOverflow">@subWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 0) -% 1 == 255</code></pre></td>
</tr>
<tr>
<td>Saturating Subtraction</td>
<td><pre><code>a -| b
a -|= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u32, 0) -| 1 == 0</code></pre></td>
</tr>
<tr>
<td>Negation</td>
<td><pre><code>-a</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Default-Operations">overflow</a> for integers.</li>
</ul></td>
<td><pre><code>-1 == 0 - 1</code></pre></td>
</tr>
<tr>
<td>Wrapping Negation</td>
<td><pre><code>-%a</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
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
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Default-Operations">overflow</a> for integers.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>2 * 5 == 10</code></pre></td>
</tr>
<tr>
<td>Wrapping Multiplication</td>
<td><pre><code>a *% b
a *%= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Twos-complement wrapping behavior.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
<li>See also <a href="#mulWithOverflow">@mulWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *% 2 == 144</code></pre></td>
</tr>
<tr>
<td>Saturating Multiplication</td>
<td><pre><code>a *| b
a *|= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>@as(u8, 200) *| 2 == 255</code></pre></td>
</tr>
<tr>
<td>Division</td>
<td><pre><code>a / b
a /= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Default-Operations">overflow</a> for integers.</li>
<li>Can cause <a href="#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="#Division-by-Zero">Division by Zero</a> for floats in <a href="#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed integer operands must be comptime-known and positive. In other cases, use
<a href="#divTrunc">@divTrunc</a>,
<a href="#divFloor">@divFloor</a>, or
<a href="#divExact">@divExact</a> instead.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 / 5 == 2</code></pre></td>
</tr>
<tr>
<td>Remainder Division</td>
<td><pre><code>a % b
a %= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td><ul>
<li>Can cause <a href="#Division-by-Zero">Division by Zero</a> for integers.</li>
<li>Can cause <a href="#Division-by-Zero">Division by Zero</a> for floats in <a href="#Floating-Point-Operations">FloatMode.Optimized Mode</a>.</li>
<li>Signed or floating-point operands must be comptime-known and positive. In other cases, use
<a href="#rem">@rem</a> or
<a href="#mod">@mod</a> instead.</li>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>10 % 3 == 1</code></pre></td>
</tr>
<tr>
<td>Bit Shift Left</td>
<td><pre><code>a &lt;&lt; b
a &lt;&lt;= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the left, inserting new zeroes at the
least-significant bit.</li>
<li><code>b</code> must be
<a href="#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="#shlExact">@shlExact</a>.</li>
<li>See also <a href="#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>0b1 &lt;&lt; 8 == 0b100000000</code></pre></td>
</tr>
<tr>
<td>Saturating Bit Shift Left</td>
<td><pre><code>a &lt;&lt;| b
a &lt;&lt;|= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>See also <a href="#shlExact">@shlExact</a>.</li>
<li>See also <a href="#shlWithOverflow">@shlWithOverflow</a>.</li>
</ul></td>
<td><pre><code>@as(u8, 1) &lt;&lt;| 8 == 255</code></pre></td>
</tr>
<tr>
<td>Bit Shift Right</td>
<td><pre><code>a &gt;&gt; b
a &gt;&gt;= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Moves all bits to the right, inserting zeroes at the most-significant bit.</li>
<li><code>b</code> must be
<a href="#comptime">comptime-known</a> or have a type with log2 number
of bits as <code>a</code>.</li>
<li>See also <a href="#shrExact">@shrExact</a>.</li>
</ul></td>
<td><pre><code>0b1010 &gt;&gt; 1 == 0b101</code></pre></td>
</tr>
<tr>
<td>Bitwise And</td>
<td><pre><code>a &amp; b
a &amp;= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 &amp; 0b101 == 0b001</code></pre></td>
</tr>
<tr>
<td>Bitwise Or</td>
<td><pre><code>a | b
a |= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b010 | 0b100 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Xor</td>
<td><pre><code>a ^ b
a ^= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td><ul>
<li>Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</li>
</ul></td>
<td><pre><code>0b011 ^ 0b101 == 0b110</code></pre></td>
</tr>
<tr>
<td>Bitwise Not</td>
<td><pre><code>~a</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
</ul></td>
<td></td>
<td><pre><code>~@as(u8, 0b10101111) == 0b01010000</code></pre></td>
</tr>
<tr>
<td>Defaulting Optional Unwrap</td>
<td><pre><code>a orelse b</code></pre></td>
<td><ul>
<li><a href="#Optionals">Optionals</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>null</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="#noreturn">noreturn</a>.</td>
<td><pre><code>const value: ?u32 = null;
const unwrapped = value orelse 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Optional Unwrap</td>
<td><pre><code>a.?</code></pre></td>
<td><ul>
<li><a href="#Optionals">Optionals</a></li>
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
<li><a href="#Errors">Error Unions</a></li>
</ul></td>
<td>If <code>a</code> is an <span class="tok-kw"><code>error</code></span>,
returns <code>b</code> ("default value"),
otherwise returns the unwrapped value of <code>a</code>.
Note that <code>b</code> may be a value of type <a href="#noreturn">noreturn</a>.
<code>err</code> is the <span class="tok-kw"><code>error</code></span> and is in scope of the expression <code>b</code>.</td>
<td><pre><code>const value: anyerror!u32 = error.Broken;
const unwrapped = value catch 1234;
unwrapped == 1234</code></pre></td>
</tr>
<tr>
<td>Logical And</td>
<td><pre><code>a and b</code></pre></td>
<td><ul>
<li><a href="#Primitive-Types">bool</a></li>
</ul></td>
<td>If <code>a</code> is <span class="tok-null"><code>false</code></span>, returns <span class="tok-null"><code>false</code></span>
without evaluating <code>b</code>. Otherwise, returns <code>b</code>.</td>
<td><pre><code>(false and true) == false</code></pre></td>
</tr>
<tr>
<td>Logical Or</td>
<td><pre><code>a or b</code></pre></td>
<td><ul>
<li><a href="#Primitive-Types">bool</a></li>
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
<li><a href="#Primitive-Types">bool</a></li>
</ul></td>
<td></td>
<td><pre><code>!false == true</code></pre></td>
</tr>
<tr>
<td>Equality</td>
<td><pre><code>a == b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
<li><a href="#Primitive-Types">bool</a></li>
<li><a href="#Primitive-Types">type</a></li>
<li><a href="#packed-struct">packed struct</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 == 1) == true</code></pre></td>
</tr>
<tr>
<td>Null Check</td>
<td><pre><code>a == null</code></pre></td>
<td><ul>
<li><a href="#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>false</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value == null) == true</code></pre></td>
</tr>
<tr>
<td>Inequality</td>
<td><pre><code>a != b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
<li><a href="#Primitive-Types">bool</a></li>
<li><a href="#Primitive-Types">type</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a and b are equal, otherwise returns <span class="tok-null"><code>true</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 != 1) == false</code></pre></td>
</tr>
<tr>
<td>Non-Null Check</td>
<td><pre><code>a != null</code></pre></td>
<td><ul>
<li><a href="#Optionals">Optionals</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>false</code></span> if a is <span class="tok-null"><code>null</code></span>, otherwise returns <span class="tok-null"><code>true</code></span>.</td>
<td><pre><code>const value: ?u32 = null;
(value != null) == false</code></pre></td>
</tr>
<tr>
<td>Greater Than</td>
<td><pre><code>a &gt; b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt; 1) == true</code></pre></td>
</tr>
<tr>
<td>Greater or Equal</td>
<td><pre><code>a &gt;= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is greater than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(2 &gt;= 1) == true</code></pre></td>
</tr>
<tr>
<td>Less Than</td>
<td><pre><code>a &lt; b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt; 2) == true</code></pre></td>
</tr>
<tr>
<td>Lesser or Equal</td>
<td><pre><code>a &lt;= b</code></pre></td>
<td><ul>
<li><a href="#Integers">Integers</a></li>
<li><a href="#Floats">Floats</a></li>
</ul></td>
<td>Returns <span class="tok-null"><code>true</code></span> if a is less than or equal to b, otherwise returns <span class="tok-null"><code>false</code></span>.
Invokes <a href="#Peer-Type-Resolution">Peer Type Resolution</a> for the operands.</td>
<td><pre><code>(1 &lt;= 2) == true</code></pre></td>
</tr>
<tr>
<td>Array Concatenation</td>
<td><pre><code>a ++ b</code></pre></td>
<td><ul>
<li><a href="#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the lengths of both <code>a</code> and <code>b</code> are <a href="#comptime">compile-time known</a>.</li>
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
<li><a href="#Arrays">Arrays</a></li>
</ul></td>
<td><ul>
<li>Only available when the length of <code>a</code> and <code>b</code> are <a href="#comptime">compile-time known</a>.</li>
</ul></td>
<td><pre><code>const mem = @import(&quot;std&quot;).mem;
const pattern = &quot;ab&quot; ** 3;
mem.eql(u8, pattern, &quot;ababab&quot;)</code></pre></td>
</tr>
<tr>
<td>Pointer Dereference</td>
<td><pre><code>a.*</code></pre></td>
<td><ul>
<li><a href="#Pointers">Pointers</a></li>
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
<li><a href="#Error-Set-Type">Error Set Type</a></li>
</ul></td>
<td><a href="#Merging-Error-Sets">Merging Error Sets</a></td>
<td><pre><code>const A = error{One};
const B = error{Two};
(A || B) == error{One, Two}</code></pre></td>
</tr>
</tbody>
</table>

</div>

### [Precedence](#toc-Precedence) <a href="#Precedence" class="hdr">§</a>

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

## [Arrays](#toc-Arrays) <a href="#Arrays" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const assert = @import(&quot;std&quot;).debug.assert;
const mem = @import(&quot;std&quot;).mem;

// array literal
const message = [_]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, &#39;o&#39; };

// alternative initialization using result location
const alt_message: [5]u8 = .{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, &#39;o&#39; };

comptime {
    assert(mem.eql(u8, &amp;message, &amp;alt_message));
}

// get the size of an array
comptime {
    assert(message.len == 5);
}

// A string literal is a single-item pointer to an array.
const same_message = &quot;hello&quot;;

comptime {
    assert(mem.eql(u8, &amp;message, same_message));
}

test &quot;iterate over an array&quot; {
    var sum: usize = 0;
    for (message) |byte| {
        sum += byte;
    }
    try expect(sum == &#39;h&#39; + &#39;e&#39; + &#39;l&#39; * 2 + &#39;o&#39;);
}

// modifiable array
var some_integers: [100]i32 = undefined;

test &quot;modify an array&quot; {
    for (&amp;some_integers, 0..) |*item, i| {
        item.* = @intCast(i);
    }
    try expect(some_integers[10] == 10);
    try expect(some_integers[99] == 99);
}

// array concatenation works if the values are known
// at compile time
const part_one = [_]i32{ 1, 2, 3, 4 };
const part_two = [_]i32{ 5, 6, 7, 8 };
const all_of_it = part_one ++ part_two;
comptime {
    assert(mem.eql(i32, &amp;all_of_it, &amp;[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 }));
}

// remember that string literals are arrays
const hello = &quot;hello&quot;;
const world = &quot;world&quot;;
const hello_world = hello ++ &quot; &quot; ++ world;
comptime {
    assert(mem.eql(u8, hello_world, &quot;hello world&quot;));
}

// ** does repeating patterns
const pattern = &quot;ab&quot; ** 3;
comptime {
    assert(mem.eql(u8, pattern, &quot;ababab&quot;));
}

// initialize an array to zero
const all_zero = [_]u16{0} ** 10;

comptime {
    assert(all_zero.len == 10);
    assert(all_zero[5] == 0);
}

// use compile-time code to initialize an array
var fancy_array = init: {
    var initial_value: [10]Point = undefined;
    for (&amp;initial_value, 0..) |*pt, i| {
        pt.* = Point{
            .x = @intCast(i),
            .y = @intCast(i * 2),
        };
    }
    break :init initial_value;
};
const Point = struct {
    x: i32,
    y: i32,
};

test &quot;compile-time array initialization&quot; {
    try expect(fancy_array[4].x == 4);
    try expect(fancy_array[4].y == 8);
}

// call a function to initialize an array
var more_points = [_]Point{makePoint(3)} ** 10;
fn makePoint(x: i32) Point {
    return Point{
        .x = x,
        .y = x * 2,
    };
}
test &quot;array initialization with function calls&quot; {
    try expect(more_points[4].x == 3);
    try expect(more_points[4].y == 6);
    try expect(more_points.len == 10);
}</code></pre>
<figcaption>test_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_arrays.zig
1/4 test_arrays.test.iterate over an array...OK
2/4 test_arrays.test.modify an array...OK
3/4 test_arrays.test.compile-time array initialization...OK
4/4 test_arrays.test.array initialization with function calls...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [for](#for)
- [Slices](#Slices)

### [Multidimensional Arrays](#toc-Multidimensional-Arrays) <a href="#Multidimensional-Arrays" class="hdr">§</a>

Multidimensional arrays can be created by nesting arrays:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const mat4x5 = [4][5]f32{
    [_]f32{ 1.0, 0.0, 0.0, 0.0, 0.0 },
    [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 },
    [_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0 },
    [_]f32{ 0.0, 0.0, 0.0, 1.0, 9.9 },
};
test &quot;multidimensional arrays&quot; {
    // mat4x5 itself is a one-dimensional array of arrays.
    try expectEqual(mat4x5[1], [_]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 });

    // Access the 2D array by indexing the outer array, and then the inner array.
    try expect(mat4x5[3][4] == 9.9);

    // Here we iterate with for loops.
    for (mat4x5, 0..) |row, row_index| {
        for (row, 0..) |cell, column_index| {
            if (row_index == column_index) {
                try expect(cell == 1.0);
            }
        }
    }

    // Initialize a multidimensional array to zeros.
    const all_zero: [4][5]f32 = .{.{0} ** 5} ** 4;
    try expect(all_zero[0][0] == 0);
}</code></pre>
<figcaption>test_multidimensional_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_multidimensional_arrays.zig
1/1 test_multidimensional_arrays.test.multidimensional arrays...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Sentinel-Terminated Arrays](#toc-Sentinel-Terminated-Arrays) <a href="#Sentinel-Terminated-Arrays" class="hdr">§</a>

The syntax `[N:x]T` describes an array which has a sentinel element of value `x` at the
index corresponding to the length `N`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated sentinel array&quot; {
    const array = [_:0]u8{ 1, 2, 3, 4 };

    try expect(@TypeOf(array) == [4:0]u8);
    try expect(array.len == 4);
    try expect(array[4] == 0);
}

test &quot;extra 0s in 0-terminated sentinel array&quot; {
    // The sentinel value may appear earlier, but does not influence the compile-time &#39;len&#39;.
    const array = [_:0]u8{ 1, 0, 0, 4 };

    try expect(@TypeOf(array) == [4:0]u8);
    try expect(array.len == 4);
    try expect(array[4] == 0);
}</code></pre>
<figcaption>test_null_terminated_array.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_array.zig
1/2 test_null_terminated_array.test.0-terminated sentinel array...OK
2/2 test_null_terminated_array.test.extra 0s in 0-terminated sentinel array...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Pointers](#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Slices](#Sentinel-Terminated-Slices)

### [Destructuring Arrays](#toc-Destructuring-Arrays) <a href="#Destructuring-Arrays" class="hdr">§</a>

Arrays can be destructured:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

fn swizzleRgbaToBgra(rgba: [4]u8) [4]u8 {
    // readable swizzling by destructuring
    const r, const g, const b, const a = rgba;
    return .{ b, g, r, a };
}

pub fn main() void {
    const pos = [_]i32{ 1, 2 };
    const x, const y = pos;
    print(&quot;x = {}, y = {}\n&quot;, .{x, y});

    const orange: [4]u8 = .{ 255, 165, 0, 255 };
    print(&quot;{any}\n&quot;, .{swizzleRgbaToBgra(orange)});
}</code></pre>
<figcaption>destructuring_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_arrays.zig
$ ./destructuring_arrays
x = 1, y = 2
{ 0, 165, 255, 255 }</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](#Destructuring)
- [Destructuring Tuples](#Destructuring-Tuples)
- [Destructuring Vectors](#Destructuring-Vectors)

## [Vectors](#toc-Vectors) <a href="#Vectors" class="hdr">§</a>

A vector is a group of booleans, [Integers](#Integers), [Floats](#Floats), or
[Pointers](#Pointers) which are operated on in parallel, using SIMD instructions if possible.
Vector types are created with the builtin function [@Vector](#Vector).

Vectors generally support the same builtin operators as their underlying base types.
The only exception to this is the keywords \`and\` and \`or\` on vectors of bools, since
these operators affect control flow, which is not allowed for vectors.
All other operations are performed element-wise, and return a vector of the same length
as the input vectors. This includes:

- Arithmetic (`+`, `-`, `/`, `*`,
  <span class="tok-builtin">`@divFloor`</span>, <span class="tok-builtin">`@sqrt`</span>, <span class="tok-builtin">`@ceil`</span>,
  <span class="tok-builtin">`@log`</span>, etc.)
- Bitwise operators (`>>`, `<<`, `&`,
  `|`, `~`, etc.)
- Comparison operators (`<`, `>`, `==`, etc.)
- Boolean not (`!`)

It is prohibited to use a math operator on a mixture of scalars (individual numbers)
and vectors. Zig provides the [@splat](#splat) builtin to easily convert from scalars
to vectors, and it supports [@reduce](#reduce) and array indexing syntax to convert
from vectors to scalars. Vectors also support assignment to and from fixed-length
arrays with comptime-known length.

For rearranging elements within and between vectors, Zig provides the [@shuffle](#shuffle) and [@select](#select) functions.

Operations on vectors shorter than the target machine's native SIMD size will typically compile to single SIMD
instructions, while vectors longer than the target machine's native SIMD size will compile to multiple SIMD
instructions. If a given operation doesn't have SIMD support on the target architecture, the compiler will default
to operating on each vector element one at a time. Zig supports any comptime-known vector length up to 2^32-1,
although small powers of two (2-64) are most typical. Note that excessively long vector lengths (e.g. 2^20) may
result in compiler crashes on current versions of Zig.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

test &quot;Basic vector usage&quot; {
    // Vectors have a compile-time known length and base type.
    const a = @Vector(4, i32){ 1, 2, 3, 4 };
    const b = @Vector(4, i32){ 5, 6, 7, 8 };

    // Math operations take place element-wise.
    const c = a + b;

    // Individual vector elements can be accessed using array indexing syntax.
    try expectEqual(6, c[0]);
    try expectEqual(8, c[1]);
    try expectEqual(10, c[2]);
    try expectEqual(12, c[3]);
}

test &quot;Conversion between vectors, arrays, and slices&quot; {
    // Vectors and fixed-length arrays can be automatically assigned back and forth
    const arr1: [4]f32 = [_]f32{ 1.1, 3.2, 4.5, 5.6 };
    const vec: @Vector(4, f32) = arr1;
    const arr2: [4]f32 = vec;
    try expectEqual(arr1, arr2);

    // You can also assign from a slice with comptime-known length to a vector using .*
    const vec2: @Vector(2, f32) = arr1[1..3].*;

    const slice: []const f32 = &amp;arr1;
    var offset: u32 = 1; // var to make it runtime-known
    _ = &amp;offset; // suppress &#39;var is never mutated&#39; error
    // To extract a comptime-known length from a runtime-known offset,
    // first extract a new slice from the starting offset, then an array of
    // comptime-known length
    const vec3: @Vector(2, f32) = slice[offset..][0..2].*;
    try expectEqual(slice[offset], vec2[0]);
    try expectEqual(slice[offset + 1], vec2[1]);
    try expectEqual(vec2, vec3);
}</code></pre>
<figcaption>test_vector.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_vector.zig
1/2 test_vector.test.Basic vector usage...OK
2/2 test_vector.test.Conversion between vectors, arrays, and slices...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

TODO talk about C ABI interop  
TODO consider suggesting std.MultiArrayList

See also:

- [@splat](#splat)
- [@shuffle](#shuffle)
- [@select](#select)
- [@reduce](#reduce)

### [Destructuring Vectors](#toc-Destructuring-Vectors) <a href="#Destructuring-Vectors" class="hdr">§</a>

Vectors can be destructured:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

// emulate punpckldq
pub fn unpack(x: @Vector(4, f32), y: @Vector(4, f32)) @Vector(4, f32) {
    const a, const c, _, _ = x;
    const b, const d, _, _ = y;
    return .{ a, b, c, d };
}

pub fn main() void {
    const x: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
    const y: @Vector(4, f32) = .{ 5.0, 6.0, 7.0, 8.0 };
    print(&quot;{}&quot;, .{unpack(x, y)});
}</code></pre>
<figcaption>destructuring_vectors.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_vectors.zig
$ ./destructuring_vectors
{ 1, 5, 2, 6 }</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](#Destructuring)
- [Destructuring Tuples](#Destructuring-Tuples)
- [Destructuring Arrays](#Destructuring-Arrays)

## [Pointers](#toc-Pointers) <a href="#Pointers" class="hdr">§</a>

Zig has two kinds of pointers: single-item and many-item.

- `*T` - single-item pointer to exactly one item.
  - Supports deref syntax: `ptr.*`
  - Supports slice syntax: `ptr[`<span class="tok-number">`0`</span>`..`<span class="tok-number">`1`</span>`]`
  - Supports pointer subtraction: `ptr - ptr`
- `[*]T` - many-item pointer to unknown number of items.
  - Supports index syntax: `ptr[i]`
  - Supports slice syntax: `ptr[start..end]` and `ptr[start..]`
  - Supports pointer-integer arithmetic: `ptr + int`, `ptr - int`
  - Supports pointer subtraction: `ptr - ptr`

  `T` must have a known size, which means that it cannot be
  <span class="tok-type">`anyopaque`</span> or any other [opaque type](#opaque).

These types are closely related to [Arrays](#Arrays) and [Slices](#Slices):

- `*[N]T` - pointer to N items, same as single-item pointer to an array.
  - Supports index syntax: `array_ptr[i]`
  - Supports slice syntax: `array_ptr[start..end]`
  - Supports len property: `array_ptr.len`
  - Supports pointer subtraction: `array_ptr - array_ptr`

<!-- -->

- `[]T` - is a slice (a fat pointer, which contains a pointer of type `[*]T` and a length).
  - Supports index syntax: `slice[i]`
  - Supports slice syntax: `slice[start..end]`
  - Supports len property: `slice.len`

Use `&x` to obtain a single-item pointer:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;address of syntax&quot; {
    // Get the address of a variable:
    const x: i32 = 1234;
    const x_ptr = &amp;x;

    // Dereference a pointer:
    try expect(x_ptr.* == 1234);

    // When you get the address of a const variable, you get a const single-item pointer.
    try expect(@TypeOf(x_ptr) == *const i32);

    // If you want to mutate the value, you&#39;d need an address of a mutable variable:
    var y: i32 = 5678;
    const y_ptr = &amp;y;
    try expect(@TypeOf(y_ptr) == *i32);
    y_ptr.* += 1;
    try expect(y_ptr.* == 5679);
}

test &quot;pointer array access&quot; {
    // Taking an address of an individual element gives a
    // single-item pointer. This kind of pointer
    // does not support pointer arithmetic.
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const ptr = &amp;array[2];
    try expect(@TypeOf(ptr) == *u8);

    try expect(array[2] == 3);
    ptr.* += 1;
    try expect(array[2] == 4);
}

test &quot;slice syntax&quot; {
    // Get a pointer to a variable:
    var x: i32 = 1234;
    const x_ptr = &amp;x;

    // Convert to array pointer using slice syntax:
    const x_array_ptr = x_ptr[0..1];
    try expect(@TypeOf(x_array_ptr) == *[1]i32);

    // Coerce to many-item pointer:
    const x_many_ptr: [*]i32 = x_array_ptr;
    try expect(x_many_ptr[0] == 1234);
}</code></pre>
<figcaption>test_single_item_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_single_item_pointer.zig
1/3 test_single_item_pointer.test.address of syntax...OK
2/3 test_single_item_pointer.test.pointer array access...OK
3/3 test_single_item_pointer.test.slice syntax...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig supports pointer arithmetic. It's better to assign the pointer to `[*]T` and increment that variable. For example, directly incrementing the pointer from a slice will corrupt it.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pointer arithmetic with many-item pointer&quot; {
    const array = [_]i32{ 1, 2, 3, 4 };
    var ptr: [*]const i32 = &amp;array;

    try expect(ptr[0] == 1);
    ptr += 1;
    try expect(ptr[0] == 2);

    // slicing a many-item pointer without an end is equivalent to
    // pointer arithmetic: `ptr[start..] == ptr + start`
    try expect(ptr[1..] == ptr + 1);

    // subtraction between any two pointers except slices based on element size is supported
    try expect(&amp;ptr[1] - &amp;ptr[0] == 1);
}

test &quot;pointer arithmetic with slices&quot; {
    var array = [_]i32{ 1, 2, 3, 4 };
    var length: usize = 0; // var to make it runtime-known
    _ = &amp;length; // suppress &#39;var is never mutated&#39; error
    var slice = array[length..array.len];

    try expect(slice[0] == 1);
    try expect(slice.len == 4);

    slice.ptr += 1;
    // now the slice is in an bad state since len has not been updated

    try expect(slice[0] == 2);
    try expect(slice.len == 4);
}</code></pre>
<figcaption>test_pointer_arithmetic.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_arithmetic.zig
1/2 test_pointer_arithmetic.test.pointer arithmetic with many-item pointer...OK
2/2 test_pointer_arithmetic.test.pointer arithmetic with slices...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In Zig, we generally prefer [Slices](#Slices) rather than [Sentinel-Terminated Pointers](#Sentinel-Terminated-Pointers).
You can turn an array or pointer into a slice using slice syntax.

Slices have bounds checking and are therefore protected
against this kind of Illegal Behavior. This is one reason
we prefer slices to pointers.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pointer slicing&quot; {
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var start: usize = 2; // var to make it runtime-known
    _ = &amp;start; // suppress &#39;var is never mutated&#39; error
    const slice = array[start..4];
    try expect(slice.len == 2);

    try expect(array[3] == 4);
    slice[1] += 1;
    try expect(array[3] == 5);
}</code></pre>
<figcaption>test_slice_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_slice_bounds.zig
1/1 test_slice_bounds.test.pointer slicing...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Pointers work at compile-time too, as long as the code does not depend on
an undefined memory layout:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;comptime pointers&quot; {
    comptime {
        var x: i32 = 1;
        const ptr = &amp;x;
        ptr.* += 1;
        x += 1;
        try expect(ptr.* == 3);
    }
}</code></pre>
<figcaption>test_comptime_pointers.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_pointers.zig
1/1 test_comptime_pointers.test.comptime pointers...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

To convert an integer address into a pointer, use <span class="tok-builtin">`@ptrFromInt`</span>.
To convert a pointer to an integer, use <span class="tok-builtin">`@intFromPtr`</span>:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;@intFromPtr and @ptrFromInt&quot; {
    const ptr: *i32 = @ptrFromInt(0xdeadbee0);
    const addr = @intFromPtr(ptr);
    try expect(@TypeOf(addr) == usize);
    try expect(addr == 0xdeadbee0);
}</code></pre>
<figcaption>test_integer_pointer_conversion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_integer_pointer_conversion.zig
1/1 test_integer_pointer_conversion.test.@intFromPtr and @ptrFromInt...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig is able to preserve memory addresses in comptime code, as long as
the pointer is never dereferenced:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;comptime @ptrFromInt&quot; {
    comptime {
        // Zig is able to do this at compile-time, as long as
        // ptr is never dereferenced.
        const ptr: *i32 = @ptrFromInt(0xdeadbee0);
        const addr = @intFromPtr(ptr);
        try expect(@TypeOf(addr) == usize);
        try expect(addr == 0xdeadbee0);
    }
}</code></pre>
<figcaption>test_comptime_pointer_conversion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_pointer_conversion.zig
1/1 test_comptime_pointer_conversion.test.comptime @ptrFromInt...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

[@ptrCast](#ptrCast) converts a pointer's element type to another. This
creates a new pointer that can cause undetectable Illegal Behavior
depending on the loads and stores that pass through it. Generally, other
kinds of type conversions are preferable to
<span class="tok-builtin">`@ptrCast`</span> if possible.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;pointer casting&quot; {
    const bytes align(@alignOf(u32)) = [_]u8{ 0x12, 0x12, 0x12, 0x12 };
    const u32_ptr: *const u32 = @ptrCast(&amp;bytes);
    try expect(u32_ptr.* == 0x12121212);

    // Even this example is contrived - there are better ways to do the above than
    // pointer casting. For example, using a slice narrowing cast:
    const u32_value = std.mem.bytesAsSlice(u32, bytes[0..])[0];
    try expect(u32_value == 0x12121212);

    // And even another way, the most straightforward way to do it:
    try expect(@as(u32, @bitCast(bytes)) == 0x12121212);
}

test &quot;pointer child type&quot; {
    // pointer types have a `child` field which tells you the type they point to.
    try expect(@typeInfo(*u32).pointer.child == u32);
}</code></pre>
<figcaption>test_pointer_casting.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_casting.zig
1/2 test_pointer_casting.test.pointer casting...OK
2/2 test_pointer_casting.test.pointer child type...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optional Pointers](#Optional-Pointers)
- [@ptrFromInt](#ptrFromInt)
- [@intFromPtr](#intFromPtr)
- [C Pointers](#C-Pointers)

### [volatile](#toc-volatile) <a href="#volatile" class="hdr">§</a>

Loads and stores are assumed to not have side effects. If a given load or store
should have side effects, such as Memory Mapped Input/Output (MMIO), use <span class="tok-kw">`volatile`</span>.
In the following code, loads and stores with `mmio_ptr` are guaranteed to all happen
and in the same order as in source code:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;volatile&quot; {
    const mmio_ptr: *volatile u8 = @ptrFromInt(0x12345678);
    try expect(@TypeOf(mmio_ptr) == *volatile u8);
}</code></pre>
<figcaption>test_volatile.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_volatile.zig
1/1 test_volatile.test.volatile...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note that <span class="tok-kw">`volatile`</span> is unrelated to concurrency and [Atomics](#Atomics).
If you see code that is using <span class="tok-kw">`volatile`</span> for something other than Memory Mapped
Input/Output, it is probably a bug.

### [Alignment](#toc-Alignment) <a href="#Alignment" class="hdr">§</a>

Each type has an **alignment** - a number of bytes such that,
when a value of the type is loaded from or stored to memory,
the memory address must be evenly divisible by this number. You can use
[@alignOf](#alignOf) to find out this value for any type.

Alignment depends on the CPU architecture, but is always a power of two, and
less than <span class="tok-number">`1`</span>` << `<span class="tok-number">`29`</span>.

In Zig, a pointer type has an alignment value. If the value is equal to the
alignment of the underlying type, it can be omitted from the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;

test &quot;variable alignment&quot; {
    var x: i32 = 1234;
    const align_of_i32 = @alignOf(@TypeOf(x));
    try expect(@TypeOf(&amp;x) == *i32);
    try expect(*i32 == *align(align_of_i32) i32);
    if (builtin.target.cpu.arch == .x86_64) {
        try expect(@typeInfo(*i32).pointer.alignment == 4);
    }
}</code></pre>
<figcaption>test_variable_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_variable_alignment.zig
1/1 test_variable_alignment.test.variable alignment...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In the same way that a `*`<span class="tok-type">`i32`</span> can be [coerced](#Type-Coercion) to a
`*`<span class="tok-kw">`const`</span>` `<span class="tok-type">`i32`</span>, a pointer with a larger alignment can be implicitly
cast to a pointer with a smaller alignment, but not vice versa.

You can specify alignment on variables and functions. If you do this, then
pointers to them get the specified alignment:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

var foo: u8 align(4) = 100;

test &quot;global variable alignment&quot; {
    try expect(@typeInfo(@TypeOf(&amp;foo)).pointer.alignment == 4);
    try expect(@TypeOf(&amp;foo) == *align(4) u8);
    const as_pointer_to_array: *align(4) [1]u8 = &amp;foo;
    const as_slice: []align(4) u8 = as_pointer_to_array;
    const as_unaligned_slice: []u8 = as_slice;
    try expect(as_unaligned_slice[0] == 100);
}

fn derp() align(@sizeOf(usize) * 2) i32 {
    return 1234;
}
fn noop1() align(1) void {}
fn noop4() align(4) void {}

test &quot;function alignment&quot; {
    try expect(derp() == 1234);
    try expect(@TypeOf(derp) == fn () i32);
    try expect(@TypeOf(&amp;derp) == *align(@sizeOf(usize) * 2) const fn () i32);

    noop1();
    try expect(@TypeOf(noop1) == fn () void);
    try expect(@TypeOf(&amp;noop1) == *align(1) const fn () void);

    noop4();
    try expect(@TypeOf(noop4) == fn () void);
    try expect(@TypeOf(&amp;noop4) == *align(4) const fn () void);
}</code></pre>
<figcaption>test_variable_func_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_variable_func_alignment.zig
1/2 test_variable_func_alignment.test.global variable alignment...OK
2/2 test_variable_func_alignment.test.function alignment...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

If you have a pointer or a slice that has a small alignment, but you know that it actually
has a bigger alignment, use [@alignCast](#alignCast) to change the
pointer into a more aligned pointer. This is a no-op at runtime, but inserts a
[safety check](#Incorrect-Pointer-Alignment):

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;pointer alignment safety&quot; {
    var array align(4) = [_]u32{ 0x11111111, 0x11111111 };
    const bytes = std.mem.sliceAsBytes(array[0..]);
    try std.testing.expect(foo(bytes) == 0x11111111);
}
fn foo(bytes: []u8) u32 {
    const slice4 = bytes[1..5];
    const int_slice = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
    return int_slice[0];
}</code></pre>
<figcaption>test_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_incorrect_pointer_alignment.zig
1/1 test_incorrect_pointer_alignment.test.pointer alignment safety...thread 1098703 panic: incorrect alignment
/home/andy/dev/zig/doc/langref/test_incorrect_pointer_alignment.zig:10:68: 0x102c2a8 in foo (test_incorrect_pointer_alignment.zig)
    const int_slice = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                                   ^
/home/andy/dev/zig/doc/langref/test_incorrect_pointer_alignment.zig:6:31: 0x102c0d2 in test.pointer alignment safety (test_incorrect_pointer_alignment.zig)
    try std.testing.expect(foo(bytes) == 0x11111111);
                              ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cf10 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1156131 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fecd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f761 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/0b2d2bfc37e3220ff3dbb549fa094812/test --seed=0xcf0b8a3a</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [allowzero](#toc-allowzero) <a href="#allowzero" class="hdr">§</a>

This pointer attribute allows a pointer to have address zero. This is only ever needed on the
freestanding OS target, where the address zero is mappable. If you want to represent null pointers, use
[Optional Pointers](#Optional-Pointers) instead. [Optional Pointers](#Optional-Pointers) with <span class="tok-kw">`allowzero`</span>
are not the same size as pointers. In this code example, if the pointer
did not have the <span class="tok-kw">`allowzero`</span> attribute, this would be a
[Pointer Cast Invalid Null](#Pointer-Cast-Invalid-Null) panic:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;allowzero&quot; {
    var zero: usize = 0; // var to make to runtime-known
    _ = &amp;zero; // suppress &#39;var is never mutated&#39; error
    const ptr: *allowzero i32 = @ptrFromInt(zero);
    try expect(@intFromPtr(ptr) == 0);
}</code></pre>
<figcaption>test_allowzero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_allowzero.zig
1/1 test_allowzero.test.allowzero...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Sentinel-Terminated Pointers](#toc-Sentinel-Terminated-Pointers) <a href="#Sentinel-Terminated-Pointers" class="hdr">§</a>

The syntax `[*:x]T` describes a pointer that
has a length determined by a sentinel value. This provides protection
against buffer overflow and overreads.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

// This is also available as `std.c.printf`.
pub extern &quot;c&quot; fn printf(format: [*:0]const u8, ...) c_int;

pub fn main() anyerror!void {
    _ = printf(&quot;Hello, world!\n&quot;); // OK

    const msg = &quot;Hello, world!\n&quot;;
    const non_null_terminated_msg: [msg.len]u8 = msg.*;
    _ = printf(&amp;non_null_terminated_msg);
}</code></pre>
<figcaption>sentinel-terminated_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe sentinel-terminated_pointer.zig -lc
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:11:16: error: expected type &#39;[*:0]const u8&#39;, found &#39;*const [14]u8&#39;
    _ = printf(&amp;non_null_terminated_msg);
               ^~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:11:16: note: destination pointer requires &#39;0&#39; sentinel
/home/andy/dev/zig/doc/langref/sentinel-terminated_pointer.zig:4:34: note: parameter type declared here
pub extern &quot;c&quot; fn printf(format: [*:0]const u8, ...) c_int;
                                 ^~~~~~~~~~~~~
referenced by:
    callMain [inlined]: /home/andy/dev/zig/lib/std/start.zig:627:37
    callMainWithArgs [inlined]: /home/andy/dev/zig/lib/std/start.zig:587:20
    main: /home/andy/dev/zig/lib/std/start.zig:602:28
    1 reference(s) hidden; use &#39;-freference-trace=4&#39; to see all references
</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Slices](#Sentinel-Terminated-Slices)
- [Sentinel-Terminated Arrays](#Sentinel-Terminated-Arrays)

## [Slices](#toc-Slices) <a href="#Slices" class="hdr">§</a>

A slice is a pointer and a length. The difference between an array and
a slice is that the array's length is part of the type and known at
compile-time, whereas the slice's length is known at runtime.
Both can be accessed with the `len` field.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const expectEqualSlices = @import(&quot;std&quot;).testing.expectEqualSlices;

test &quot;basic slices&quot; {
    var array = [_]i32{ 1, 2, 3, 4 };
    var known_at_runtime_zero: usize = 0;
    _ = &amp;known_at_runtime_zero;
    const slice = array[known_at_runtime_zero..array.len];

    // alternative initialization using result location
    const alt_slice: []const i32 = &amp;.{ 1, 2, 3, 4 };

    try expectEqualSlices(i32, slice, alt_slice);

    try expect(@TypeOf(slice) == []i32);
    try expect(&amp;slice[0] == &amp;array[0]);
    try expect(slice.len == array.len);

    // If you slice with comptime-known start and end positions, the result is
    // a pointer to an array, rather than a slice.
    const array_ptr = array[0..array.len];
    try expect(@TypeOf(array_ptr) == *[array.len]i32);

    // You can perform a slice-by-length by slicing twice. This allows the compiler
    // to perform some optimisations like recognising a comptime-known length when
    // the start position is only known at runtime.
    var runtime_start: usize = 1;
    _ = &amp;runtime_start;
    const length = 2;
    const array_ptr_len = array[runtime_start..][0..length];
    try expect(@TypeOf(array_ptr_len) == *[length]i32);

    // Using the address-of operator on a slice gives a single-item pointer.
    try expect(@TypeOf(&amp;slice[0]) == *i32);
    // Using the `ptr` field gives a many-item pointer.
    try expect(@TypeOf(slice.ptr) == [*]i32);
    try expect(@intFromPtr(slice.ptr) == @intFromPtr(&amp;slice[0]));

    // Slices have array bounds checking. If you try to access something out
    // of bounds, you&#39;ll get a safety check failure:
    slice[10] += 1;

    // Note that `slice.ptr` does not invoke safety checking, while `&amp;slice[0]`
    // asserts that the slice has len &gt; 0.

    // Empty slices can be created like this:
    const empty1 = &amp;[0]u8{};
    // If the type is known you can use this short hand:
    const empty2: []u8 = &amp;.{};
    try expect(empty1.len == 0);
    try expect(empty2.len == 0);

    // A zero-length initialization can always be used to create an empty slice, even if the slice is mutable.
    // This is because the pointed-to data is zero bits long, so its immutability is irrelevant.
}</code></pre>
<figcaption>test_basic_slices.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_basic_slices.zig
1/1 test_basic_slices.test.basic slices...thread 1100955 panic: index out of bounds: index 10, len 4
/home/andy/dev/zig/doc/langref/test_basic_slices.zig:41:10: 0x102e3c0 in test.basic slices (test_basic_slices.zig)
    slice[10] += 1;
         ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x1160b40 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1159d61 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x1153afd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x1153391 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/74bbaeeb0151197719152f62ae1ac340/test --seed=0xd51d6b2</code></pre>
<figcaption>Shell</figcaption>
</figure>

This is one reason we prefer slices to pointers.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;
const fmt = std.fmt;

test &quot;using slices for strings&quot; {
    // Zig has no concept of strings. String literals are const pointers
    // to null-terminated arrays of u8, and by convention parameters
    // that are &quot;strings&quot; are expected to be UTF-8 encoded slices of u8.
    // Here we coerce *const [5:0]u8 and *const [6:0]u8 to []const u8
    const hello: []const u8 = &quot;hello&quot;;
    const world: []const u8 = &quot;世界&quot;;

    var all_together: [100]u8 = undefined;
    // You can use slice syntax with at least one runtime-known index on an
    // array to convert an array into a slice.
    var start: usize = 0;
    _ = &amp;start;
    const all_together_slice = all_together[start..];
    // String concatenation example.
    const hello_world = try fmt.bufPrint(all_together_slice, &quot;{s} {s}&quot;, .{ hello, world });

    // Generally, you can use UTF-8 and not worry about whether something is a
    // string. If you don&#39;t need to deal with individual characters, no need
    // to decode.
    try expect(mem.eql(u8, hello_world, &quot;hello 世界&quot;));
}

test &quot;slice pointer&quot; {
    var array: [10]u8 = undefined;
    const ptr = &amp;array;
    try expect(@TypeOf(ptr) == *[10]u8);

    // A pointer to an array can be sliced just like an array:
    var start: usize = 0;
    var end: usize = 5;
    _ = .{ &amp;start, &amp;end };
    const slice = ptr[start..end];
    // The slice is mutable because we sliced a mutable pointer.
    try expect(@TypeOf(slice) == []u8);
    slice[2] = 3;
    try expect(array[2] == 3);

    // Again, slicing with comptime-known indexes will produce another pointer
    // to an array:
    const ptr2 = slice[2..3];
    try expect(ptr2.len == 1);
    try expect(ptr2[0] == 3);
    try expect(@TypeOf(ptr2) == *[1]u8);
}</code></pre>
<figcaption>test_slices.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_slices.zig
1/2 test_slices.test.using slices for strings...OK
2/2 test_slices.test.slice pointer...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Pointers](#Pointers)
- [for](#for)
- [Arrays](#Arrays)

### [Sentinel-Terminated Slices](#toc-Sentinel-Terminated-Slices) <a href="#Sentinel-Terminated-Slices" class="hdr">§</a>

The syntax `[:x]T` is a slice which has a runtime-known length
and also guarantees a sentinel value at the element indexed by the length. The type does not
guarantee that there are no sentinel elements before that. Sentinel-terminated slices allow element
access to the `len` index.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated slice&quot; {
    const slice: [:0]const u8 = &quot;hello&quot;;

    try expect(slice.len == 5);
    try expect(slice[5] == 0);
}</code></pre>
<figcaption>test_null_terminated_slice.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_slice.zig
1/1 test_null_terminated_slice.test.0-terminated slice...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Sentinel-terminated slices can also be created using a variation of the slice syntax
`data[start..end :x]`, where `data` is a many-item pointer,
array or slice and `x` is the sentinel value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;0-terminated slicing&quot; {
    var array = [_]u8{ 3, 2, 1, 0, 3, 2, 1, 0 };
    var runtime_length: usize = 3;
    _ = &amp;runtime_length;
    const slice = array[0..runtime_length :0];

    try expect(@TypeOf(slice) == [:0]u8);
    try expect(slice.len == 3);
}</code></pre>
<figcaption>test_null_terminated_slicing.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_null_terminated_slicing.zig
1/1 test_null_terminated_slicing.test.0-terminated slicing...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Sentinel-terminated slicing asserts that the element in the sentinel position of the backing data is
actually the sentinel value. If this is not the case, safety-checked [Illegal Behavior](#Illegal-Behavior) results.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;sentinel mismatch&quot; {
    var array = [_]u8{ 3, 2, 1, 0 };

    // Creating a sentinel-terminated slice from the array with a length of 2
    // will result in the value `1` occupying the sentinel element position.
    // This does not match the indicated sentinel value of `0` and will lead
    // to a runtime panic.
    var runtime_length: usize = 2;
    _ = &amp;runtime_length;
    const slice = array[0..runtime_length :0];

    _ = slice;
}</code></pre>
<figcaption>test_sentinel_mismatch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_sentinel_mismatch.zig
1/1 test_sentinel_mismatch.test.sentinel mismatch...thread 1101275 panic: sentinel mismatch: expected 0, found 1
/home/andy/dev/zig/doc/langref/test_sentinel_mismatch.zig:13:24: 0x102c117 in test.sentinel mismatch (test_sentinel_mismatch.zig)
    const slice = array[0..runtime_length :0];
                       ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cc70 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155e91 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fc2d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f4c1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/f4ab327d42c7136f49bdc07a601ab333/test --seed=0xf332bd16</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Sentinel-Terminated Pointers](#Sentinel-Terminated-Pointers)
- [Sentinel-Terminated Arrays](#Sentinel-Terminated-Arrays)

## [struct](#toc-struct) <a href="#struct" class="hdr">§</a>

<figure>
<pre><code>// Declare a struct.
// Zig gives no guarantees about the order of fields and the size of
// the struct but the fields are guaranteed to be ABI-aligned.
const Point = struct {
    x: f32,
    y: f32,
};

// Declare an instance of a struct.
const p: Point = .{
    .x = 0.12,
    .y = 0.34,
};

// Functions in the struct&#39;s namespace can be called with dot syntax.
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};

test &quot;dot product&quot; {
    const v1 = Vec3.init(1.0, 0.0, 0.0);
    const v2 = Vec3.init(0.0, 1.0, 0.0);
    try expect(v1.dot(v2) == 0.0);

    // Other than being available to call with dot syntax, struct methods are
    // not special. You can reference them as any other declaration inside
    // the struct:
    try expect(Vec3.dot(v1, v2) == 0.0);
}

// Structs can have declarations.
// Structs can have 0 fields.
const Empty = struct {
    pub const PI = 3.14;
};
test &quot;struct namespaced variable&quot; {
    try expect(Empty.PI == 3.14);
    try expect(@sizeOf(Empty) == 0);

    // Empty structs can be instantiated the same as usual.
    const does_nothing: Empty = .{};

    _ = does_nothing;
}

// Struct field order is determined by the compiler, however, a base pointer
// can be computed from a field pointer:
fn setYBasedOnX(x: *f32, y: f32) void {
    const point: *Point = @fieldParentPtr(&quot;x&quot;, x);
    point.y = y;
}
test &quot;field parent pointer&quot; {
    var point = Point{
        .x = 0.1234,
        .y = 0.5678,
    };
    setYBasedOnX(&amp;point.x, 0.9);
    try expect(point.y == 0.9);
}

// Structs can be returned from functions.
fn LinkedList(comptime T: type) type {
    return struct {
        pub const Node = struct {
            prev: ?*Node,
            next: ?*Node,
            data: T,
        };

        first: ?*Node,
        last: ?*Node,
        len: usize,
    };
}

test &quot;linked list&quot; {
    // Functions called at compile-time are memoized.
    try expect(LinkedList(i32) == LinkedList(i32));

    const list = LinkedList(i32){
        .first = null,
        .last = null,
        .len = 0,
    };
    try expect(list.len == 0);

    // Since types are first class values you can instantiate the type
    // by assigning it to a variable:
    const ListOfInts = LinkedList(i32);
    try expect(ListOfInts == LinkedList(i32));

    var node = ListOfInts.Node{
        .prev = null,
        .next = null,
        .data = 1234,
    };
    const list2 = LinkedList(i32){
        .first = &amp;node,
        .last = &amp;node,
        .len = 1,
    };

    // When using a pointer to a struct, fields can be accessed directly,
    // without explicitly dereferencing the pointer.
    // So you can do
    try expect(list2.first.?.data == 1234);
    // instead of try expect(list2.first.?.*.data == 1234);
}

const expect = @import(&quot;std&quot;).testing.expect;</code></pre>
<figcaption>test_structs.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_structs.zig
1/4 test_structs.test.dot product...OK
2/4 test_structs.test.struct namespaced variable...OK
3/4 test_structs.test.field parent pointer...OK
4/4 test_structs.test.linked list...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Default Field Values](#toc-Default-Field-Values) <a href="#Default-Field-Values" class="hdr">§</a>

Each struct field may have an expression indicating the default field
value. Such expressions are executed at [comptime](#comptime), and allow the
field to be omitted in a struct literal expression:

<figure>
<pre><code>const Foo = struct {
    a: i32 = 1234,
    b: i32,
};

test &quot;default struct initialization fields&quot; {
    const x: Foo = .{
        .b = 5,
    };
    if (x.a + x.b != 1239) {
        comptime unreachable;
    }
}</code></pre>
<figcaption>struct_default_field_values.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test struct_default_field_values.zig
1/1 struct_default_field_values.test.default struct initialization fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Faulty Default Field Values](#toc-Faulty-Default-Field-Values) <a href="#Faulty-Default-Field-Values" class="hdr">§</a>

Default field values are only appropriate when the data invariants of a struct
cannot be violated by omitting that field from an initialization.

For example, here is an inappropriate use of default struct field initialization:

<figure>
<pre><code>const Threshold = struct {
    minimum: f32 = 0.25,
    maximum: f32 = 0.75,

    const Category = enum { low, medium, high };

    fn categorize(t: Threshold, value: f32) Category {
        assert(t.maximum &gt;= t.minimum);
        if (value &lt; t.minimum) return .low;
        if (value &gt; t.maximum) return .high;
        return .medium;
    }
};

pub fn main() !void {
    var threshold: Threshold = .{
        .maximum = 0.20,
    };
    const category = threshold.categorize(0.90);
    try std.fs.File.stdout().writeAll(@tagName(category));
}

const std = @import(&quot;std&quot;);
const assert = std.debug.assert;</code></pre>
<figcaption>bad_default_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe bad_default_value.zig
$ ./bad_default_value
thread 1093499 panic: reached unreachable code
/home/andy/dev/zig/lib/std/debug.zig:559:14: 0x1044179 in assert (std.zig)
    if (!ok) unreachable; // assertion failure
             ^
/home/andy/dev/zig/doc/langref/bad_default_value.zig:8:15: 0x113ec34 in categorize (bad_default_value.zig)
        assert(t.maximum &gt;= t.minimum);
              ^
/home/andy/dev/zig/doc/langref/bad_default_value.zig:19:42: 0x113d424 in main (bad_default_value.zig)
    const category = threshold.categorize(0.90);
                                         ^
/home/andy/dev/zig/lib/std/start.zig:627:37: 0x113dc89 in posixCallMainAndExit (std.zig)
            const result = root.main() catch |err| {
                                    ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

Above you can see the danger of ignoring this principle. The default
field values caused the data invariant to be violated, causing illegal
behavior.

To fix this, remove the default values from all the struct fields, and provide
a named default value:

<figure>
<pre><code>const Threshold = struct {
    minimum: f32,
    maximum: f32,

    const default: Threshold = .{
        .minimum = 0.25,
        .maximum = 0.75,
    };
};</code></pre>
<figcaption>struct_default_value.zig</figcaption>
</figure>

If a struct value requires a runtime-known value in order to be initialized
without violating data invariants, then use an initialization method that accepts
those runtime values, and populates the remaining fields.

### [extern struct](#toc-extern-struct) <a href="#extern-struct" class="hdr">§</a>

An <span class="tok-kw">`extern`</span>` `<span class="tok-kw">`struct`</span> has in-memory layout matching
the C ABI for the target.

If well-defined in-memory layout is not required, [struct](#struct) is a better choice
because it places fewer restrictions on the compiler.

See [packed struct](#packed-struct) for a struct that has the ABI of its backing integer,
which can be useful for modeling flags.

See also:

- [extern union](#extern-union)
- [extern enum](#extern-enum)

### [packed struct](#toc-packed-struct) <a href="#packed-struct" class="hdr">§</a>

<span class="tok-kw">`packed`</span> structs, like <span class="tok-kw">`enum`</span>, are based on the concept
of interpreting integers differently. All packed structs have a **backing integer**,
which is implicitly determined by the total bit count of fields, or explicitly specified.
Packed structs have well-defined memory layout - exactly the same ABI as their backing integer.

Each field of a packed struct is interpreted as a logical sequence of bits, arranged from
least to most significant. Allowed field types:

- An [integer](#Integers) field uses exactly as many bits as its
  bit width. For example, a <span class="tok-type">`u5`</span> will use 5 bits of
  the backing integer.
- A [bool](#Primitive-Types) field uses exactly 1 bit.
- An [enum](#enum) field uses exactly the bit width of its integer tag type.
- A [packed union](#packed-union) field uses exactly the bit width of the union field with
  the largest bit width.
- A <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`struct`</span> field uses the bits of its backing integer.

This means that a <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`struct`</span> can participate
in a [@bitCast](#bitCast) or a [@ptrCast](#ptrCast) to reinterpret memory.
This even works at [comptime](#comptime):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const native_endian = @import(&quot;builtin&quot;).target.cpu.arch.endian();
const expect = std.testing.expect;

const Full = packed struct {
    number: u16,
};
const Divided = packed struct {
    half1: u8,
    quarter3: u4,
    quarter4: u4,
};

test &quot;@bitCast between packed structs&quot; {
    try doTheTest();
    try comptime doTheTest();
}

fn doTheTest() !void {
    try expect(@sizeOf(Full) == 2);
    try expect(@sizeOf(Divided) == 2);
    const full = Full{ .number = 0x1234 };
    const divided: Divided = @bitCast(full);
    try expect(divided.half1 == 0x34);
    try expect(divided.quarter3 == 0x2);
    try expect(divided.quarter4 == 0x1);

    const ordered: [2]u8 = @bitCast(full);
    switch (native_endian) {
        .big =&gt; {
            try expect(ordered[0] == 0x12);
            try expect(ordered[1] == 0x34);
        },
        .little =&gt; {
            try expect(ordered[0] == 0x34);
            try expect(ordered[1] == 0x12);
        },
    }
}</code></pre>
<figcaption>test_packed_structs.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_structs.zig
1/1 test_packed_structs.test.@bitCast between packed structs...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The backing integer can be inferred or explicitly provided. When
inferred, it will be unsigned. When explicitly provided, its bit width
will be enforced at compile time to exactly match the total bit width of
the fields:

<figure>
<pre><code>test &quot;missized packed struct&quot; {
    const S = packed struct(u32) { a: u16, b: u8 };
    _ = S{ .a = 4, .b = 2 };
}</code></pre>
<figcaption>test_missized_packed_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_missized_packed_struct.zig
/home/andy/dev/zig/doc/langref/test_missized_packed_struct.zig:2:29: error: backing integer type &#39;u32&#39; has bit size 32 but the struct fields have a total bit size of 24
    const S = packed struct(u32) { a: u16, b: u8 };
                            ^~~
referenced by:
    test.missized packed struct: /home/andy/dev/zig/doc/langref/test_missized_packed_struct.zig:2:22
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig allows the address to be taken of a non-byte-aligned field:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var foo = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointer to non-byte-aligned field&quot; {
    const ptr = &amp;foo.b;
    try expect(ptr.* == 2);
}</code></pre>
<figcaption>test_pointer_to_non-byte_aligned_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_to_non-byte_aligned_field.zig
1/1 test_pointer_to_non-byte_aligned_field.test.pointer to non-byte-aligned field...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

However, the pointer to a non-byte-aligned field has special properties and cannot
be passed when a normal pointer is expected:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var bit_field = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointer to non-byte-aligned field&quot; {
    try expect(bar(&amp;bit_field.b) == 2);
}

fn bar(x: *const u3) u3 {
    return x.*;
}</code></pre>
<figcaption>test_misaligned_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_misaligned_pointer.zig
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: error: expected type &#39;*const u3&#39;, found &#39;*align(1:3:1) u3&#39;
    try expect(bar(&amp;bit_field.b) == 2);
                   ^~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: note: pointer host size &#39;1&#39; cannot cast into pointer host size &#39;0&#39;
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:17:20: note: pointer bit offset &#39;3&#39; cannot cast into pointer bit offset &#39;0&#39;
/home/andy/dev/zig/doc/langref/test_misaligned_pointer.zig:20:11: note: parameter type declared here
fn bar(x: *const u3) u3 {
          ^~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

In this case, the function `bar` cannot be called because the pointer
to the non-ABI-aligned field mentions the bit offset, but the function expects an ABI-aligned pointer.

Pointers to non-ABI-aligned fields share the same address as the other fields within their host integer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var bit_field = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test &quot;pointers of sub-byte-aligned fields share addresses&quot; {
    try expect(@intFromPtr(&amp;bit_field.a) == @intFromPtr(&amp;bit_field.b));
    try expect(@intFromPtr(&amp;bit_field.a) == @intFromPtr(&amp;bit_field.c));
}</code></pre>
<figcaption>test_packed_struct_field_address.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_struct_field_address.zig
1/1 test_packed_struct_field_address.test.pointers of sub-byte-aligned fields share addresses...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This can be observed with [@bitOffsetOf](#bitOffsetOf) and [offsetOf](#offsetOf):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

test &quot;offsets of non-byte-aligned fields&quot; {
    comptime {
        try expect(@bitOffsetOf(BitField, &quot;a&quot;) == 0);
        try expect(@bitOffsetOf(BitField, &quot;b&quot;) == 3);
        try expect(@bitOffsetOf(BitField, &quot;c&quot;) == 6);

        try expect(@offsetOf(BitField, &quot;a&quot;) == 0);
        try expect(@offsetOf(BitField, &quot;b&quot;) == 0);
        try expect(@offsetOf(BitField, &quot;c&quot;) == 0);
    }
}</code></pre>
<figcaption>test_bitOffsetOf_offsetOf.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_bitOffsetOf_offsetOf.zig
1/1 test_bitOffsetOf_offsetOf.test.offsets of non-byte-aligned fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Packed structs have the same alignment as their backing integer, however, overaligned
pointers to packed structs can override this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const S = packed struct {
    a: u32,
    b: u32,
};
test &quot;overaligned pointer to packed struct&quot; {
    var foo: S align(4) = .{ .a = 1, .b = 2 };
    const ptr: *align(4) S = &amp;foo;
    const ptr_to_b: *u32 = &amp;ptr.b;
    try expect(ptr_to_b.* == 2);
}</code></pre>
<figcaption>test_overaligned_packed_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_overaligned_packed_struct.zig
1/1 test_overaligned_packed_struct.test.overaligned pointer to packed struct...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It's also possible to set alignment of struct fields:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

test &quot;aligned struct fields&quot; {
    const S = struct {
        a: u32 align(2),
        b: u32 align(64),
    };
    var foo = S{ .a = 1, .b = 2 };

    try expectEqual(64, @alignOf(S));
    try expectEqual(*align(2) u32, @TypeOf(&amp;foo.a));
    try expectEqual(*align(64) u32, @TypeOf(&amp;foo.b));
}</code></pre>
<figcaption>test_aligned_struct_fields.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_aligned_struct_fields.zig
1/1 test_aligned_struct_fields.test.aligned struct fields...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Equating packed structs results in a comparison of the backing integer,
and only works for the `==` and `!=` [Operators](#Operators).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;packed struct equality&quot; {
    const S = packed struct {
        a: u4,
        b: u4,
    };
    const x: S = .{ .a = 1, .b = 2 };
    const y: S = .{ .b = 2, .a = 1 };
    try expect(x == y);
}</code></pre>
<figcaption>test_packed_struct_equality.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_packed_struct_equality.zig
1/1 test_packed_struct_equality.test.packed struct equality...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Field access and assignment can be understood as shorthand for bitshifts
on the backing integer. These operations are not [atomic](#Atomics),
so beware using field access syntax when combined with memory-mapped
input-output (MMIO). Instead of field access on [volatile](#volatile) [Pointers](#Pointers),
construct a fully-formed new value first, then write that value to the volatile pointer.

<figure>
<pre><code>pub const GpioRegister = packed struct(u8) {
    GPIO0: bool,
    GPIO1: bool,
    GPIO2: bool,
    GPIO3: bool,
    reserved: u4 = 0,
};

const gpio: *volatile GpioRegister = @ptrFromInt(0x0123);

pub fn writeToGpio(new_states: GpioRegister) void {
    // Example of what not to do:
    // BAD! gpio.GPIO0 = true; BAD!

    // Instead, do this:
    gpio.* = new_states;
}</code></pre>
<figcaption>packed_struct_mmio.zig</figcaption>
</figure>

### [Struct Naming](#toc-Struct-Naming) <a href="#Struct-Naming" class="hdr">§</a>

Since all structs are anonymous, Zig infers the type name based on a few rules.

- If the struct is in the initialization expression of a variable, it gets named after
  that variable.
- If the struct is in the <span class="tok-kw">`return`</span> expression, it gets named after
  the function it is returning from, with the parameter values serialized.
- Otherwise, the struct gets a name such as `(filename.funcname__struct_ID)`.
- If the struct is declared inside another struct, it gets named after both the parent
  struct and the name inferred by the previous rules, separated by a dot.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const Foo = struct {};
    std.debug.print(&quot;variable: {s}\n&quot;, .{@typeName(Foo)});
    std.debug.print(&quot;anonymous: {s}\n&quot;, .{@typeName(struct {})});
    std.debug.print(&quot;function: {s}\n&quot;, .{@typeName(List(i32))});
}

fn List(comptime T: type) type {
    return struct {
        x: T,
    };
}</code></pre>
<figcaption>struct_name.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe struct_name.zig
$ ./struct_name
variable: struct_name.main.Foo
anonymous: struct_name.main__struct_22696
function: struct_name.List(i32)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Anonymous Struct Literals](#toc-Anonymous-Struct-Literals) <a href="#Anonymous-Struct-Literals" class="hdr">§</a>

Zig allows omitting the struct type of a literal. When the result is [coerced](#Type-Coercion),
the struct literal will directly instantiate the [result location](#Result-Location-Semantics),
with no copy:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Point = struct { x: i32, y: i32 };

test &quot;anonymous struct literal&quot; {
    const pt: Point = .{
        .x = 13,
        .y = 67,
    };
    try expect(pt.x == 13);
    try expect(pt.y == 67);
}</code></pre>
<figcaption>test_struct_result.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_struct_result.zig
1/1 test_struct_result.test.anonymous struct literal...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The struct type can be inferred. Here the [result location](#Result-Location-Semantics)
does not include a type, and so Zig infers the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;fully anonymous struct&quot; {
    try check(.{
        .int = @as(u32, 1234),
        .float = @as(f64, 12.34),
        .b = true,
        .s = &quot;hi&quot;,
    });
}

fn check(args: anytype) !void {
    try expect(args.int == 1234);
    try expect(args.float == 12.34);
    try expect(args.b);
    try expect(args.s[0] == &#39;h&#39;);
    try expect(args.s[1] == &#39;i&#39;);
}</code></pre>
<figcaption>test_anonymous_struct.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_anonymous_struct.zig
1/1 test_anonymous_struct.test.fully anonymous struct...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Tuples](#toc-Tuples) <a href="#Tuples" class="hdr">§</a>

Anonymous structs can be created without specifying field names, and are referred to as "tuples". An empty tuple looks like `.{}` and can be seen in one of the [Hello World examples](#Hello-World).

The fields are implicitly named using numbers starting from 0. Because their names are integers,
they cannot be accessed with `.` syntax without also wrapping them in
`@""`. Names inside `@""` are always recognised as
[identifiers](#Identifiers).

Like arrays, tuples have a .len field, can be indexed (provided the index is comptime-known)
and work with the ++ and \*\* operators. They can also be iterated over with [inline for](#inline-for).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;tuple&quot; {
    const values = .{
        @as(u32, 1234),
        @as(f64, 12.34),
        true,
        &quot;hi&quot;,
    } ++ .{false} ** 2;
    try expect(values[0] == 1234);
    try expect(values[4] == false);
    inline for (values, 0..) |v, i| {
        if (i != 2) continue;
        try expect(v);
    }
    try expect(values.len == 6);
    try expect(values.@&quot;3&quot;[0] == &#39;h&#39;);
}</code></pre>
<figcaption>test_tuples.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tuples.zig
1/1 test_tuples.test.tuple...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Destructuring Tuples](#toc-Destructuring-Tuples) <a href="#Destructuring-Tuples" class="hdr">§</a>

Tuples can be [destructured](#Destructuring).

Tuple destructuring is helpful for returning multiple values from a block:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    const digits = [_]i8 { 3, 8, 9, 0, 7, 4, 1 };

    const min, const max = blk: {
        var min: i8 = 127;
        var max: i8 = -128;

        for (digits) |digit| {
            if (digit &lt; min) min = digit;
            if (digit &gt; max) max = digit;
        }

        break :blk .{ min, max };
    };

    print(&quot;min = {}&quot;, .{ min });
    print(&quot;max = {}&quot;, .{ max });
}</code></pre>
<figcaption>destructuring_block.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_block.zig
$ ./destructuring_block
min = 0max = 9</code></pre>
<figcaption>Shell</figcaption>
</figure>

Tuple destructuring is helpful for dealing with functions and built-ins that return multiple values
as a tuple:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

fn divmod(numerator: u32, denominator: u32) struct { u32, u32 } {
    return .{ numerator / denominator, numerator % denominator };
}

pub fn main() void {
    const div, const mod = divmod(10, 3);

    print(&quot;10 / 3 = {}\n&quot;, .{div});
    print(&quot;10 % 3 = {}\n&quot;, .{mod});
}</code></pre>
<figcaption>destructuring_return_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe destructuring_return_value.zig
$ ./destructuring_return_value
10 / 3 = 3
10 % 3 = 1</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Destructuring](#Destructuring)
- [Destructuring Arrays](#Destructuring-Arrays)
- [Destructuring Vectors](#Destructuring-Vectors)

See also:

- [comptime](#comptime)
- [@fieldParentPtr](#fieldParentPtr)

## [enum](#toc-enum) <a href="#enum" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
const mem = @import(&quot;std&quot;).mem;

// Declare an enum.
const Type = enum {
    ok,
    not_ok,
};

// Declare a specific enum field.
const c = Type.ok;

// If you want access to the ordinal value of an enum, you
// can specify the tag type.
const Value = enum(u2) {
    zero,
    one,
    two,
};
// Now you can cast between u2 and Value.
// The ordinal value starts from 0, counting up by 1 from the previous member.
test &quot;enum ordinal value&quot; {
    try expect(@intFromEnum(Value.zero) == 0);
    try expect(@intFromEnum(Value.one) == 1);
    try expect(@intFromEnum(Value.two) == 2);
}

// You can override the ordinal value for an enum.
const Value2 = enum(u32) {
    hundred = 100,
    thousand = 1000,
    million = 1000000,
};
test &quot;set enum ordinal value&quot; {
    try expect(@intFromEnum(Value2.hundred) == 100);
    try expect(@intFromEnum(Value2.thousand) == 1000);
    try expect(@intFromEnum(Value2.million) == 1000000);
}

// You can also override only some values.
const Value3 = enum(u4) {
    a,
    b = 8,
    c,
    d = 4,
    e,
};
test &quot;enum implicit ordinal values and overridden values&quot; {
    try expect(@intFromEnum(Value3.a) == 0);
    try expect(@intFromEnum(Value3.b) == 8);
    try expect(@intFromEnum(Value3.c) == 9);
    try expect(@intFromEnum(Value3.d) == 4);
    try expect(@intFromEnum(Value3.e) == 5);
}

// Enums can have methods, the same as structs and unions.
// Enum methods are not special, they are only namespaced
// functions that you can call with dot syntax.
const Suit = enum {
    clubs,
    spades,
    diamonds,
    hearts,

    pub fn isClubs(self: Suit) bool {
        return self == Suit.clubs;
    }
};
test &quot;enum method&quot; {
    const p = Suit.spades;
    try expect(!p.isClubs());
}

// An enum can be switched upon.
const Foo = enum {
    string,
    number,
    none,
};
test &quot;enum switch&quot; {
    const p = Foo.number;
    const what_is_it = switch (p) {
        Foo.string =&gt; &quot;this is a string&quot;,
        Foo.number =&gt; &quot;this is a number&quot;,
        Foo.none =&gt; &quot;this is a none&quot;,
    };
    try expect(mem.eql(u8, what_is_it, &quot;this is a number&quot;));
}

// @typeInfo can be used to access the integer tag type of an enum.
const Small = enum {
    one,
    two,
    three,
    four,
};
test &quot;std.meta.Tag&quot; {
    try expect(@typeInfo(Small).@&quot;enum&quot;.tag_type == u2);
}

// @typeInfo tells us the field count and the fields names:
test &quot;@typeInfo&quot; {
    try expect(@typeInfo(Small).@&quot;enum&quot;.fields.len == 4);
    try expect(mem.eql(u8, @typeInfo(Small).@&quot;enum&quot;.fields[1].name, &quot;two&quot;));
}

// @tagName gives a [:0]const u8 representation of an enum value:
test &quot;@tagName&quot; {
    try expect(mem.eql(u8, @tagName(Small.three), &quot;three&quot;));
}</code></pre>
<figcaption>test_enums.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_enums.zig
1/8 test_enums.test.enum ordinal value...OK
2/8 test_enums.test.set enum ordinal value...OK
3/8 test_enums.test.enum implicit ordinal values and overridden values...OK
4/8 test_enums.test.enum method...OK
5/8 test_enums.test.enum switch...OK
6/8 test_enums.test.std.meta.Tag...OK
7/8 test_enums.test.@typeInfo...OK
8/8 test_enums.test.@tagName...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@typeInfo](#typeInfo)
- [@tagName](#tagName)
- [@sizeOf](#sizeOf)

### [extern enum](#toc-extern-enum) <a href="#extern-enum" class="hdr">§</a>

By default, enums are not guaranteed to be compatible with the C ABI:

<figure>
<pre><code>const Foo = enum { a, b, c };
export fn entry(foo: Foo) void {
    _ = foo;
}</code></pre>
<figcaption>enum_export_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj enum_export_error.zig -target x86_64-linux
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: error: parameter of type &#39;enum_export_error.Foo&#39; not allowed in function with calling convention &#39;x86_64_sysv&#39;
export fn entry(foo: Foo) void {
                ^~~~~~~~
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: note: enum tag type &#39;u2&#39; is not extern compatible
/home/andy/dev/zig/doc/langref/enum_export_error.zig:2:17: note: only integers with 0, 8, 16, 32, 64 and 128 bits are extern compatible
/home/andy/dev/zig/doc/langref/enum_export_error.zig:1:13: note: enum declared here
const Foo = enum { a, b, c };
            ^~~~~~~~~~~~~~~~
referenced by:
    root: /home/andy/dev/zig/lib/std/start.zig:3:22
    comptime: /home/andy/dev/zig/lib/std/start.zig:31:9
    2 reference(s) hidden; use &#39;-freference-trace=4&#39; to see all references
</code></pre>
<figcaption>Shell</figcaption>
</figure>

For a C-ABI-compatible enum, provide an explicit tag type to
the enum:

<figure>
<pre><code>const Foo = enum(c_int) { a, b, c };
export fn entry(foo: Foo) void {
    _ = foo;
}</code></pre>
<figcaption>enum_export.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj enum_export.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Enum Literals](#toc-Enum-Literals) <a href="#Enum-Literals" class="hdr">§</a>

Enum literals allow specifying the name of an enum field without specifying the enum type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Color = enum {
    auto,
    off,
    on,
};

test &quot;enum literals&quot; {
    const color1: Color = .auto;
    const color2 = Color.auto;
    try expect(color1 == color2);
}

test &quot;switch using enum literals&quot; {
    const color = Color.on;
    const result = switch (color) {
        .auto =&gt; false,
        .on =&gt; true,
        .off =&gt; false,
    };
    try expect(result);
}</code></pre>
<figcaption>test_enum_literals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_enum_literals.zig
1/2 test_enum_literals.test.enum literals...OK
2/2 test_enum_literals.test.switch using enum literals...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Non-exhaustive enum](#toc-Non-exhaustive-enum) <a href="#Non-exhaustive-enum" class="hdr">§</a>

A non-exhaustive enum can be created by adding a trailing `_` field.
The enum must specify a tag type and cannot consume every enumeration value.

[@enumFromInt](#enumFromInt) on a non-exhaustive enum involves the safety semantics
of [@intCast](#intCast) to the integer tag type, but beyond that always results in
a well-defined enum value.

A switch on a non-exhaustive enum can include a `_` prong as an alternative to an <span class="tok-kw">`else`</span> prong.
With a `_` prong the compiler errors if all the known tag names are not handled by the switch.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Number = enum(u8) {
    one,
    two,
    three,
    _,
};

test &quot;switch on non-exhaustive enum&quot; {
    const number = Number.one;
    const result = switch (number) {
        .one =&gt; true,
        .two, .three =&gt; false,
        _ =&gt; false,
    };
    try expect(result);
    const is_one = switch (number) {
        .one =&gt; true,
        else =&gt; false,
    };
    try expect(is_one);
}</code></pre>
<figcaption>test_switch_non-exhaustive.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_non-exhaustive.zig
1/1 test_switch_non-exhaustive.test.switch on non-exhaustive enum...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [union](#toc-union) <a href="#union" class="hdr">§</a>

A bare <span class="tok-kw">`union`</span> defines a set of possible types that a value
can be as a list of fields. Only one field can be active at a time.
The in-memory representation of bare unions is not guaranteed.
Bare unions cannot be used to reinterpret memory. For that, use [@ptrCast](#ptrCast),
or use an [extern union](#extern-union) or a [packed union](#packed-union) which have
guaranteed in-memory layout.
[Accessing the non-active field](#Wrong-Union-Field-Access) is
safety-checked [Illegal Behavior](#Illegal-Behavior):

<figure>
<pre><code>const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test &quot;simple union&quot; {
    var payload = Payload{ .int = 1234 };
    payload.float = 12.34;
}</code></pre>
<figcaption>test_wrong_union_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wrong_union_access.zig
1/1 test_wrong_union_access.test.simple union...thread 1095042 panic: access of union field &#39;float&#39; while field &#39;int&#39; is active
/home/andy/dev/zig/doc/langref/test_wrong_union_access.zig:8:12: 0x102c083 in test.simple union (test_wrong_union_access.zig)
    payload.float = 12.34;
           ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cd90 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155fb1 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fd4d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f5e1 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/ba4ad6352a6237c381e8f15c2b46bcd6/test --seed=0x8b6eed28</code></pre>
<figcaption>Shell</figcaption>
</figure>

You can activate another field by assigning the entire union:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test &quot;simple union&quot; {
    var payload = Payload{ .int = 1234 };
    try expect(payload.int == 1234);
    payload = Payload{ .float = 12.34 };
    try expect(payload.float == 12.34);
}</code></pre>
<figcaption>test_simple_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_simple_union.zig
1/1 test_simple_union.test.simple union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In order to use [switch](#switch) with a union, it must be a [Tagged union](#Tagged-union).

To initialize a union when the tag is a [comptime](#comptime)-known name, see [@unionInit](#unionInit).

### [Tagged union](#toc-Tagged-union) <a href="#Tagged-union" class="hdr">§</a>

Unions can be declared with an enum tag type.
This turns the union into a *tagged* union, which makes it eligible
to use with [switch](#switch) expressions.
Tagged unions coerce to their tag type: [Type Coercion: Unions and Enums](#Type-Coercion-Unions-and-Enums).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test &quot;switch on tagged union&quot; {
    const c = ComplexType{ .ok = 42 };
    try expect(@as(ComplexTypeTag, c) == ComplexTypeTag.ok);

    switch (c) {
        .ok =&gt; |value| try expect(value == 42),
        .not_ok =&gt; unreachable,
    }
}

test &quot;get tag type&quot; {
    try expect(std.meta.Tag(ComplexType) == ComplexTypeTag);
}</code></pre>
<figcaption>test_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagged_union.zig
1/2 test_tagged_union.test.switch on tagged union...OK
2/2 test_tagged_union.test.get tag type...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In order to modify the payload of a tagged union in a switch expression,
place a `*` before the variable name to make it a pointer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test &quot;modify tagged union in switch&quot; {
    var c = ComplexType{ .ok = 42 };

    switch (c) {
        ComplexTypeTag.ok =&gt; |*value| value.* += 1,
        ComplexTypeTag.not_ok =&gt; unreachable,
    }

    try expect(c.ok == 43);
}</code></pre>
<figcaption>test_switch_modify_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_modify_tagged_union.zig
1/1 test_switch_modify_tagged_union.test.modify tagged union in switch...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Unions can be made to infer the enum tag type.
Further, unions can have methods just like structs and enums.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Variant = union(enum) {
    int: i32,
    boolean: bool,

    // void can be omitted when inferring enum tag type.
    none,

    fn truthy(self: Variant) bool {
        return switch (self) {
            Variant.int =&gt; |x_int| x_int != 0,
            Variant.boolean =&gt; |x_bool| x_bool,
            Variant.none =&gt; false,
        };
    }
};

test &quot;union method&quot; {
    var v1: Variant = .{ .int = 1 };
    var v2: Variant = .{ .boolean = false };
    var v3: Variant = .none;

    try expect(v1.truthy());
    try expect(!v2.truthy());
    try expect(!v3.truthy());
}</code></pre>
<figcaption>test_union_method.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_union_method.zig
1/1 test_union_method.test.union method...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Unions with inferred enum tag types can also assign ordinal values to their inferred tag.
This requires the tag to specify an explicit integer type.
[@intFromEnum](#intFromEnum) can be used to access the ordinal value corresponding to the active field.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Tagged = union(enum(u32)) {
    int: i64 = 123,
    boolean: bool = 67,
};

test &quot;tag values&quot; {
    const int: Tagged = .{ .int = -40 };
    try expect(@intFromEnum(int) == 123);

    const boolean: Tagged = .{ .boolean = false };
    try expect(@intFromEnum(boolean) == 67);
}</code></pre>
<figcaption>test_tagged_union_with_tag_values.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagged_union_with_tag_values.zig
1/1 test_tagged_union_with_tag_values.test.tag values...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

[@tagName](#tagName) can be used to return a [comptime](#comptime)
`[:`<span class="tok-number">`0`</span>`]`<span class="tok-kw">`const`</span>` `<span class="tok-type">`u8`</span> value representing the field name:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Small2 = union(enum) {
    a: i32,
    b: bool,
    c: u8,
};
test &quot;@tagName&quot; {
    try expect(std.mem.eql(u8, @tagName(Small2.a), &quot;a&quot;));
}</code></pre>
<figcaption>test_tagName.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_tagName.zig
1/1 test_tagName.test.@tagName...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [extern union](#toc-extern-union) <a href="#extern-union" class="hdr">§</a>

An <span class="tok-kw">`extern`</span>` `<span class="tok-kw">`union`</span> has memory layout guaranteed to be compatible with
the target C ABI.

See also:

- [extern struct](#extern-struct)

### [packed union](#toc-packed-union) <a href="#packed-union" class="hdr">§</a>

A <span class="tok-kw">`packed`</span>` `<span class="tok-kw">`union`</span> has well-defined in-memory layout and is eligible
to be in a [packed struct](#packed-struct).

### [Anonymous Union Literals](#toc-Anonymous-Union-Literals) <a href="#Anonymous-Union-Literals" class="hdr">§</a>

[Anonymous Struct Literals](#Anonymous-Struct-Literals) syntax can be used to initialize unions without specifying
the type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Number = union {
    int: i32,
    float: f64,
};

test &quot;anonymous union literal syntax&quot; {
    const i: Number = .{ .int = 42 };
    const f = makeNumber();
    try expect(i.int == 42);
    try expect(f.float == 12.34);
}

fn makeNumber() Number {
    return .{ .float = 12.34 };
}</code></pre>
<figcaption>test_anonymous_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_anonymous_union.zig
1/1 test_anonymous_union.test.anonymous union literal syntax...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [opaque](#toc-opaque) <a href="#opaque" class="hdr">§</a>

<span class="tok-kw">`opaque`</span>` {}` declares a new type with an unknown (but non-zero) size and alignment.
It can contain declarations the same as [structs](#struct), [unions](#union),
and [enums](#enum).

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

## [Blocks](#toc-Blocks) <a href="#Blocks" class="hdr">§</a>

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

- [Labeled while](#Labeled-while)
- [Labeled for](#Labeled-for)

### [Shadowing](#toc-Shadowing) <a href="#Shadowing" class="hdr">§</a>

[Identifiers](#Identifiers) are never allowed to "hide" other identifiers by using the same name:

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

### [Empty Blocks](#toc-Empty-Blocks) <a href="#Empty-Blocks" class="hdr">§</a>

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

## [switch](#toc-switch) <a href="#switch" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;

test &quot;switch simple&quot; {
    const a: u64 = 10;
    const zz: u64 = 103;

    // All branches of a switch expression must be able to be coerced to a
    // common type.
    //
    // Branches cannot fallthrough. If fallthrough behavior is desired, combine
    // the cases and use an if.
    const b = switch (a) {
        // Multiple cases can be combined via a &#39;,&#39;
        1, 2, 3 =&gt; 0,

        // Ranges can be specified using the ... syntax. These are inclusive
        // of both ends.
        5...100 =&gt; 1,

        // Branches can be arbitrarily complex.
        101 =&gt; blk: {
            const c: u64 = 5;
            break :blk c * 2 + 1;
        },

        // Switching on arbitrary expressions is allowed as long as the
        // expression is known at compile-time.
        zz =&gt; zz,
        blk: {
            const d: u32 = 5;
            const e: u32 = 100;
            break :blk d + e;
        } =&gt; 107,

        // The else branch catches everything not already captured.
        // Else branches are mandatory unless the entire range of values
        // is handled.
        else =&gt; 9,
    };

    try expect(b == 1);
}

// Switch expressions can be used outside a function:
const os_msg = switch (builtin.target.os.tag) {
    .linux =&gt; &quot;we found a linux user&quot;,
    else =&gt; &quot;not a linux user&quot;,
};

// Inside a function, switch statements implicitly are compile-time
// evaluated if the target expression is compile-time known.
test &quot;switch inside function&quot; {
    switch (builtin.target.os.tag) {
        .fuchsia =&gt; {
            // On an OS other than fuchsia, block is not even analyzed,
            // so this compile error is not triggered.
            // On fuchsia this compile error would be triggered.
            @compileError(&quot;fuchsia not supported&quot;);
        },
        else =&gt; {},
    }
}</code></pre>
<figcaption>test_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch.zig
1/2 test_switch.test.switch simple...OK
2/2 test_switch.test.switch inside function...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-kw">`switch`</span> can be used to capture the field values
of a [Tagged union](#Tagged-union). Modifications to the field values can be
done by placing a `*` before the capture variable name,
turning it into a pointer.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;switch on tagged union&quot; {
    const Point = struct {
        x: u8,
        y: u8,
    };
    const Item = union(enum) {
        a: u32,
        c: Point,
        d,
        e: u32,
    };

    var a = Item{ .c = Point{ .x = 1, .y = 2 } };

    // Switching on more complex enums is allowed.
    const b = switch (a) {
        // A capture group is allowed on a match, and will return the enum
        // value matched. If the payload types of both cases are the same
        // they can be put into the same switch prong.
        Item.a, Item.e =&gt; |item| item,

        // A reference to the matched value can be obtained using `*` syntax.
        Item.c =&gt; |*item| blk: {
            item.*.x += 1;
            break :blk 6;
        },

        // No else is required if the types cases was exhaustively handled
        Item.d =&gt; 8,
    };

    try expect(b == 6);
    try expect(a.c.x == 2);
}</code></pre>
<figcaption>test_switch_tagged_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_tagged_union.zig
1/1 test_switch_tagged_union.test.switch on tagged union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [comptime](#comptime)
- [enum](#enum)
- [@compileError](#compileError)
- [Compile Variables](#Compile-Variables)

### [Exhaustive Switching](#toc-Exhaustive-Switching) <a href="#Exhaustive-Switching" class="hdr">§</a>

When a <span class="tok-kw">`switch`</span> expression does not have an <span class="tok-kw">`else`</span> clause,
it must exhaustively list all the possible values. Failure to do so is a compile error:

<figure>
<pre><code>const Color = enum {
    auto,
    off,
    on,
};

test &quot;exhaustive switching&quot; {
    const color = Color.off;
    switch (color) {
        Color.auto =&gt; {},
        Color.on =&gt; {},
    }
}</code></pre>
<figcaption>test_unhandled_enumeration_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_unhandled_enumeration_value.zig
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:9:5: error: switch must handle all possibilities
    switch (color) {
    ^~~~~~
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:3:5: note: unhandled enumeration value: &#39;off&#39;
    off,
    ^~~
/home/andy/dev/zig/doc/langref/test_unhandled_enumeration_value.zig:1:15: note: enum &#39;test_unhandled_enumeration_value.Color&#39; declared here
const Color = enum {
              ^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Switching with Enum Literals](#toc-Switching-with-Enum-Literals) <a href="#Switching-with-Enum-Literals" class="hdr">§</a>

[Enum Literals](#Enum-Literals) can be useful to use with <span class="tok-kw">`switch`</span> to avoid
repetitively specifying [enum](#enum) or [union](#union) types:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Color = enum {
    auto,
    off,
    on,
};

test &quot;enum literals with switch&quot; {
    const color = Color.off;
    const result = switch (color) {
        .auto =&gt; false,
        .on =&gt; false,
        .off =&gt; true,
    };
    try expect(result);
}</code></pre>
<figcaption>test_exhaustive_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_exhaustive_switch.zig
1/1 test_exhaustive_switch.test.enum literals with switch...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled switch](#toc-Labeled-switch) <a href="#Labeled-switch" class="hdr">§</a>

When a switch statement is labeled, it can be referenced from a
<span class="tok-kw">`break`</span> or <span class="tok-kw">`continue`</span>.
<span class="tok-kw">`break`</span> will return a value from the <span class="tok-kw">`switch`</span>.

A <span class="tok-kw">`continue`</span> targeting a switch must have an
operand. When executed, it will jump to the matching prong, as if the
<span class="tok-kw">`switch`</span> were executed again with the <span class="tok-kw">`continue`</span>'s operand replacing the initial switch value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;switch continue&quot; {
    sw: switch (@as(i32, 5)) {
        5 =&gt; continue :sw 4,

        // `continue` can occur multiple times within a single switch prong.
        2...4 =&gt; |v| {
            if (v &gt; 3) {
                continue :sw 2;
            } else if (v == 3) {

                // `break` can target labeled loops.
                break :sw;
            }

            continue :sw 1;
        },

        1 =&gt; return,

        else =&gt; unreachable,
    }
}</code></pre>
<figcaption>test_switch_continue.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_continue.zig
1/1 test_switch_continue.test.switch continue...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Semantically, this is equivalent to the following loop:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

test &quot;switch continue, equivalent loop&quot; {
    var sw: i32 = 5;
    while (true) {
        switch (sw) {
            5 =&gt; {
                sw = 4;
                continue;
            },
            2...4 =&gt; |v| {
                if (v &gt; 3) {
                    sw = 2;
                    continue;
                } else if (v == 3) {
                    break;
                }

                sw = 1;
                continue;
            },
            1 =&gt; return,
            else =&gt; unreachable,
        }
    }
}</code></pre>
<figcaption>test_switch_continue_equivalent.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_continue_equivalent.zig
1/1 test_switch_continue_equivalent.test.switch continue, equivalent loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This can improve clarity of (for example) state machines, where the syntax <span class="tok-kw">`continue`</span>` :sw .next_state` is unambiguous, explicit, and immediately understandable.

However, the motivating example is a switch on each element of an array, where using a single switch can improve clarity and performance:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expectEqual = std.testing.expectEqual;

const Instruction = enum {
    add,
    mul,
    end,
};

fn evaluate(initial_stack: []const i32, code: []const Instruction) !i32 {
    var buffer: [8]i32 = undefined;
    var stack = std.ArrayListUnmanaged(i32).initBuffer(&amp;buffer);
    try stack.appendSliceBounded(initial_stack);
    var ip: usize = 0;

    return vm: switch (code[ip]) {
        // Because all code after `continue` is unreachable, this branch does
        // not provide a result.
        .add =&gt; {
            try stack.appendBounded(stack.pop().? + stack.pop().?);

            ip += 1;
            continue :vm code[ip];
        },
        .mul =&gt; {
            try stack.appendBounded(stack.pop().? * stack.pop().?);

            ip += 1;
            continue :vm code[ip];
        },
        .end =&gt; stack.pop().?,
    };
}

test &quot;evaluate&quot; {
    const result = try evaluate(&amp;.{ 7, 2, -3 }, &amp;.{ .mul, .add, .end });
    try expectEqual(1, result);
}</code></pre>
<figcaption>test_switch_dispatch_loop.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_switch_dispatch_loop.zig
1/1 test_switch_dispatch_loop.test.evaluate...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

If the operand to <span class="tok-kw">`continue`</span> is
[comptime](#comptime)-known, then it can be lowered to an unconditional branch
to the relevant case. Such a branch is perfectly predicted, and hence
typically very fast to execute.

If the operand is runtime-known, each <span class="tok-kw">`continue`</span> can
embed a conditional branch inline (ideally through a jump table), which
allows a CPU to predict its target independently of any other prong. A
loop-based lowering would force every branch through the same dispatch
point, hindering branch prediction.

### [Inline Switch Prongs](#toc-Inline-Switch-Prongs) <a href="#Inline-Switch-Prongs" class="hdr">§</a>

Switch prongs can be marked as <span class="tok-kw">`inline`</span> to generate
the prong's body for each possible value it could have, making the
captured value [comptime](#comptime).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const expectError = std.testing.expectError;

fn isFieldOptional(comptime T: type, field_index: usize) !bool {
    const fields = @typeInfo(T).@&quot;struct&quot;.fields;
    return switch (field_index) {
        // This prong is analyzed twice with `idx` being a
        // comptime-known value each time.
        inline 0, 1 =&gt; |idx| @typeInfo(fields[idx].type) == .optional,
        else =&gt; return error.IndexOutOfBounds,
    };
}

const Struct1 = struct { a: u32, b: ?u32 };

test &quot;using @typeInfo with runtime values&quot; {
    var index: usize = 0;
    try expect(!try isFieldOptional(Struct1, index));
    index += 1;
    try expect(try isFieldOptional(Struct1, index));
    index += 1;
    try expectError(error.IndexOutOfBounds, isFieldOptional(Struct1, index));
}

// Calls to `isFieldOptional` on `Struct1` get unrolled to an equivalent
// of this function:
fn isFieldOptionalUnrolled(field_index: usize) !bool {
    return switch (field_index) {
        0 =&gt; false,
        1 =&gt; true,
        else =&gt; return error.IndexOutOfBounds,
    };
}</code></pre>
<figcaption>test_inline_switch.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_switch.zig
1/1 test_inline_switch.test.using @typeInfo with runtime values...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

The <span class="tok-kw">`inline`</span> keyword may also be combined with ranges:

<figure>
<pre><code>fn isFieldOptional(comptime T: type, field_index: usize) !bool {
    const fields = @typeInfo(T).@&quot;struct&quot;.fields;
    return switch (field_index) {
        inline 0...fields.len - 1 =&gt; |idx| @typeInfo(fields[idx].type) == .optional,
        else =&gt; return error.IndexOutOfBounds,
    };
}</code></pre>
<figcaption>inline_prong_range.zig</figcaption>
</figure>

<span class="tok-kw">`inline`</span>` `<span class="tok-kw">`else`</span> prongs can be used as a type safe
alternative to <span class="tok-kw">`inline`</span>` `<span class="tok-kw">`for`</span> loops:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const SliceTypeA = extern struct {
    len: usize,
    ptr: [*]u32,
};
const SliceTypeB = extern struct {
    ptr: [*]SliceTypeA,
    len: usize,
};
const AnySlice = union(enum) {
    a: SliceTypeA,
    b: SliceTypeB,
    c: []const u8,
    d: []AnySlice,
};

fn withFor(any: AnySlice) usize {
    const Tag = @typeInfo(AnySlice).@&quot;union&quot;.tag_type.?;
    inline for (@typeInfo(Tag).@&quot;enum&quot;.fields) |field| {
        // With `inline for` the function gets generated as
        // a series of `if` statements relying on the optimizer
        // to convert it to a switch.
        if (field.value == @intFromEnum(any)) {
            return @field(any, field.name).len;
        }
    }
    // When using `inline for` the compiler doesn&#39;t know that every
    // possible case has been handled requiring an explicit `unreachable`.
    unreachable;
}

fn withSwitch(any: AnySlice) usize {
    return switch (any) {
        // With `inline else` the function is explicitly generated
        // as the desired switch and the compiler can check that
        // every possible case is handled.
        inline else =&gt; |slice| slice.len,
    };
}

test &quot;inline for and inline else similarity&quot; {
    const any = AnySlice{ .c = &quot;hello&quot; };
    try expect(withFor(any) == 5);
    try expect(withSwitch(any) == 5);
}</code></pre>
<figcaption>test_inline_else.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_else.zig
1/1 test_inline_else.test.inline for and inline else similarity...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When using an inline prong switching on an union an additional
capture can be used to obtain the union's enum tag value.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const U = union(enum) {
    a: u32,
    b: f32,
};

fn getNum(u: U) u32 {
    switch (u) {
        // Here `num` is a runtime-known value that is either
        // `u.a` or `u.b` and `tag` is `u`&#39;s comptime-known tag value.
        inline else =&gt; |num, tag| {
            if (tag == .b) {
                return @intFromFloat(num);
            }
            return num;
        },
    }
}

test &quot;test&quot; {
    const u = U{ .b = 42 };
    try expect(getNum(u) == 42);
}</code></pre>
<figcaption>test_inline_switch_union_tag.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_switch_union_tag.zig
1/1 test_inline_switch_union_tag.test.test...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [inline while](#inline-while)
- [inline for](#inline-for)

## [while](#toc-while) <a href="#while" class="hdr">§</a>

A while loop is used to repeatedly execute an expression until
some condition is no longer true.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while basic&quot; {
    var i: usize = 0;
    while (i &lt; 10) {
        i += 1;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while.zig
1/1 test_while.test.while basic...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use <span class="tok-kw">`break`</span> to exit a while loop early.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while break&quot; {
    var i: usize = 0;
    while (true) {
        if (i == 10)
            break;
        i += 1;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_break.zig
1/1 test_while_break.test.while break...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use <span class="tok-kw">`continue`</span> to jump back to the beginning of the loop.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while continue&quot; {
    var i: usize = 0;
    while (true) {
        i += 1;
        if (i &lt; 10)
            continue;
        break;
    }
    try expect(i == 10);
}</code></pre>
<figcaption>test_while_continue.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_continue.zig
1/1 test_while_continue.test.while continue...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

While loops support a continue expression which is executed when the loop
is continued. The <span class="tok-kw">`continue`</span> keyword respects this expression.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while loop continue expression&quot; {
    var i: usize = 0;
    while (i &lt; 10) : (i += 1) {}
    try expect(i == 10);
}

test &quot;while loop continue expression, more complicated&quot; {
    var i: usize = 1;
    var j: usize = 1;
    while (i * j &lt; 2000) : ({
        i *= 2;
        j *= 3;
    }) {
        const my_ij = i * j;
        try expect(my_ij &lt; 2000);
    }
}</code></pre>
<figcaption>test_while_continue_expression.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_continue_expression.zig
1/2 test_while_continue_expression.test.while loop continue expression...OK
2/2 test_while_continue_expression.test.while loop continue expression, more complicated...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

While loops are expressions. The result of the expression is the
result of the <span class="tok-kw">`else`</span> clause of a while loop, which is executed when
the condition of the while loop is tested as false.

<span class="tok-kw">`break`</span>, like <span class="tok-kw">`return`</span>, accepts a value
parameter. This is the result of the <span class="tok-kw">`while`</span> expression.
When you <span class="tok-kw">`break`</span> from a while loop, the <span class="tok-kw">`else`</span> branch is not
evaluated.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while else&quot; {
    try expect(rangeHasNumber(0, 10, 5));
    try expect(!rangeHasNumber(0, 10, 15));
}

fn rangeHasNumber(begin: usize, end: usize, number: usize) bool {
    var i = begin;
    return while (i &lt; end) : (i += 1) {
        if (i == number) {
            break true;
        }
    } else false;
}</code></pre>
<figcaption>test_while_else.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_else.zig
1/1 test_while_else.test.while else...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled while](#toc-Labeled-while) <a href="#Labeled-while" class="hdr">§</a>

When a <span class="tok-kw">`while`</span> loop is labeled, it can be referenced from a <span class="tok-kw">`break`</span>
or <span class="tok-kw">`continue`</span> from within a nested loop:

<figure>
<pre><code>test &quot;nested break&quot; {
    outer: while (true) {
        while (true) {
            break :outer;
        }
    }
}

test &quot;nested continue&quot; {
    var i: usize = 0;
    outer: while (i &lt; 10) : (i += 1) {
        while (true) {
            continue :outer;
        }
    }
}</code></pre>
<figcaption>test_while_nested_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_nested_break.zig
1/2 test_while_nested_break.test.nested break...OK
2/2 test_while_nested_break.test.nested continue...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [while with Optionals](#toc-while-with-Optionals) <a href="#while-with-Optionals" class="hdr">§</a>

Just like [if](#if) expressions, while loops can take an optional as the
condition and capture the payload. When [null](#null) is encountered the loop
exits.

When the `|x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Optional Type](#Optional-Type).

The <span class="tok-kw">`else`</span> branch is allowed on optional iteration. In this case, it will
be executed on the first null value encountered.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while null capture&quot; {
    var sum1: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| {
        sum1 += value;
    }
    try expect(sum1 == 3);

    // null capture with an else block
    var sum2: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| {
        sum2 += value;
    } else {
        try expect(sum2 == 3);
    }

    // null capture with a continue expression
    var i: u32 = 0;
    var sum3: u32 = 0;
    numbers_left = 3;
    while (eventuallyNullSequence()) |value| : (i += 1) {
        sum3 += value;
    }
    try expect(i == 3);
}

var numbers_left: u32 = undefined;
fn eventuallyNullSequence() ?u32 {
    return if (numbers_left == 0) null else blk: {
        numbers_left -= 1;
        break :blk numbers_left;
    };
}</code></pre>
<figcaption>test_while_null_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_null_capture.zig
1/1 test_while_null_capture.test.while null capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [while with Error Unions](#toc-while-with-Error-Unions) <a href="#while-with-Error-Unions" class="hdr">§</a>

Just like [if](#if) expressions, while loops can take an error union as
the condition and capture the payload or the error code. When the
condition results in an error code the else branch is evaluated and
the loop is finished.

When the <span class="tok-kw">`else`</span>` |x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Error Union Type](#Error-Union-Type).

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;while error union capture&quot; {
    var sum1: u32 = 0;
    numbers_left = 3;
    while (eventuallyErrorSequence()) |value| {
        sum1 += value;
    } else |err| {
        try expect(err == error.ReachedZero);
    }
}

var numbers_left: u32 = undefined;

fn eventuallyErrorSequence() anyerror!u32 {
    return if (numbers_left == 0) error.ReachedZero else blk: {
        numbers_left -= 1;
        break :blk numbers_left;
    };
}</code></pre>
<figcaption>test_while_error_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_while_error_capture.zig
1/1 test_while_error_capture.test.while error union capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline while](#toc-inline-while) <a href="#inline-while" class="hdr">§</a>

While loops can be inlined. This causes the loop to be unrolled, which
allows the code to do some things which only work at compile time,
such as use types as first class values.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;inline while loop&quot; {
    comptime var i = 0;
    var sum: usize = 0;
    inline while (i &lt; 3) : (i += 1) {
        const T = switch (i) {
            0 =&gt; f32,
            1 =&gt; i8,
            2 =&gt; bool,
            else =&gt; unreachable,
        };
        sum += typeNameLength(T);
    }
    try expect(sum == 9);
}

fn typeNameLength(comptime T: type) usize {
    return @typeName(T).len;
}</code></pre>
<figcaption>test_inline_while.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_while.zig
1/1 test_inline_while.test.inline while loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It is recommended to use <span class="tok-kw">`inline`</span> loops only for one of these reasons:

- You need the loop to execute at [comptime](#comptime) for the semantics to work.
- You have a benchmark to prove that forcibly unrolling the loop in this way is measurably faster.

See also:

- [if](#if)
- [Optionals](#Optionals)
- [Errors](#Errors)
- [comptime](#comptime)
- [unreachable](#unreachable)

## [for](#toc-for) <a href="#for" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;for basics&quot; {
    const items = [_]i32{ 4, 5, 3, 4, 0 };
    var sum: i32 = 0;

    // For loops iterate over slices and arrays.
    for (items) |value| {
        // Break and continue are supported.
        if (value == 0) {
            continue;
        }
        sum += value;
    }
    try expect(sum == 16);

    // To iterate over a portion of a slice, reslice.
    for (items[0..1]) |value| {
        sum += value;
    }
    try expect(sum == 20);

    // To access the index of iteration, specify a second condition as well
    // as a second capture value.
    var sum2: i32 = 0;
    for (items, 0..) |_, i| {
        try expect(@TypeOf(i) == usize);
        sum2 += @as(i32, @intCast(i));
    }
    try expect(sum2 == 10);

    // To iterate over consecutive integers, use the range syntax.
    // Unbounded range is always a compile error.
    var sum3: usize = 0;
    for (0..5) |i| {
        sum3 += i;
    }
    try expect(sum3 == 10);
}

test &quot;multi object for&quot; {
    const items = [_]usize{ 1, 2, 3 };
    const items2 = [_]usize{ 4, 5, 6 };
    var count: usize = 0;

    // Iterate over multiple objects.
    // All lengths must be equal at the start of the loop, otherwise detectable
    // illegal behavior occurs.
    for (items, items2) |i, j| {
        count += i + j;
    }

    try expect(count == 21);
}

test &quot;for reference&quot; {
    var items = [_]i32{ 3, 4, 2 };

    // Iterate over the slice by reference by
    // specifying that the capture value is a pointer.
    for (&amp;items) |*value| {
        value.* += 1;
    }

    try expect(items[0] == 4);
    try expect(items[1] == 5);
    try expect(items[2] == 3);
}

test &quot;for else&quot; {
    // For allows an else attached to it, the same as a while loop.
    const items = [_]?i32{ 3, 4, null, 5 };

    // For loops can also be used as expressions.
    // Similar to while loops, when you break from a for loop, the else branch is not evaluated.
    var sum: i32 = 0;
    const result = for (items) |value| {
        if (value != null) {
            sum += value.?;
        }
    } else blk: {
        try expect(sum == 12);
        break :blk sum;
    };
    try expect(result == 12);
}</code></pre>
<figcaption>test_for.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_for.zig
1/4 test_for.test.for basics...OK
2/4 test_for.test.multi object for...OK
3/4 test_for.test.for reference...OK
4/4 test_for.test.for else...OK
All 4 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Labeled for](#toc-Labeled-for) <a href="#Labeled-for" class="hdr">§</a>

When a <span class="tok-kw">`for`</span> loop is labeled, it can be referenced from a <span class="tok-kw">`break`</span>
or <span class="tok-kw">`continue`</span> from within a nested loop:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;nested break&quot; {
    var count: usize = 0;
    outer: for (1..6) |_| {
        for (1..6) |_| {
            count += 1;
            break :outer;
        }
    }
    try expect(count == 1);
}

test &quot;nested continue&quot; {
    var count: usize = 0;
    outer: for (1..9) |_| {
        for (1..6) |_| {
            count += 1;
            continue :outer;
        }
    }

    try expect(count == 8);
}</code></pre>
<figcaption>test_for_nested_break.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_for_nested_break.zig
1/2 test_for_nested_break.test.nested break...OK
2/2 test_for_nested_break.test.nested continue...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline for](#toc-inline-for) <a href="#inline-for" class="hdr">§</a>

For loops can be inlined. This causes the loop to be unrolled, which
allows the code to do some things which only work at compile time,
such as use types as first class values.
The capture value and iterator value of inlined for loops are
compile-time known.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;inline for loop&quot; {
    const nums = [_]i32{ 2, 4, 6 };
    var sum: usize = 0;
    inline for (nums) |i| {
        const T = switch (i) {
            2 =&gt; f32,
            4 =&gt; i8,
            6 =&gt; bool,
            else =&gt; unreachable,
        };
        sum += typeNameLength(T);
    }
    try expect(sum == 9);
}

fn typeNameLength(comptime T: type) usize {
    return @typeName(T).len;
}</code></pre>
<figcaption>test_inline_for.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inline_for.zig
1/1 test_inline_for.test.inline for loop...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

It is recommended to use <span class="tok-kw">`inline`</span> loops only for one of these reasons:

- You need the loop to execute at [comptime](#comptime) for the semantics to work.
- You have a benchmark to prove that forcibly unrolling the loop in this way is measurably faster.

See also:

- [while](#while)
- [comptime](#comptime)
- [Arrays](#Arrays)
- [Slices](#Slices)

## [if](#toc-if) <a href="#if" class="hdr">§</a>

<figure>
<pre><code>// If expressions have three uses, corresponding to the three types:
// * bool
// * ?T
// * anyerror!T

const expect = @import(&quot;std&quot;).testing.expect;

test &quot;if expression&quot; {
    // If expressions are used instead of a ternary expression.
    const a: u32 = 5;
    const b: u32 = 4;
    const result = if (a != b) 47 else 3089;
    try expect(result == 47);
}

test &quot;if boolean&quot; {
    // If expressions test boolean conditions.
    const a: u32 = 5;
    const b: u32 = 4;
    if (a != b) {
        try expect(true);
    } else if (a == 9) {
        unreachable;
    } else {
        unreachable;
    }
}

test &quot;if error union&quot; {
    // If expressions test for errors.
    // Note the |err| capture on the else.

    const a: anyerror!u32 = 0;
    if (a) |value| {
        try expect(value == 0);
    } else |err| {
        _ = err;
        unreachable;
    }

    const b: anyerror!u32 = error.BadValue;
    if (b) |value| {
        _ = value;
        unreachable;
    } else |err| {
        try expect(err == error.BadValue);
    }

    // The else and |err| capture is strictly required.
    if (a) |value| {
        try expect(value == 0);
    } else |_| {}

    // To check only the error value, use an empty block expression.
    if (b) |_| {} else |err| {
        try expect(err == error.BadValue);
    }

    // Access the value by reference using a pointer capture.
    var c: anyerror!u32 = 3;
    if (c) |*value| {
        value.* = 9;
    } else |_| {
        unreachable;
    }

    if (c) |value| {
        try expect(value == 9);
    } else |_| {
        unreachable;
    }
}</code></pre>
<figcaption>test_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_if.zig
1/3 test_if.test.if expression...OK
2/3 test_if.test.if boolean...OK
3/3 test_if.test.if error union...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [if with Optionals](#toc-if-with-Optionals) <a href="#if-with-Optionals" class="hdr">§</a>

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;if optional&quot; {
    // If expressions test for null.

    const a: ?u32 = 0;
    if (a) |value| {
        try expect(value == 0);
    } else {
        unreachable;
    }

    const b: ?u32 = null;
    if (b) |_| {
        unreachable;
    } else {
        try expect(true);
    }

    // The else is not required.
    if (a) |value| {
        try expect(value == 0);
    }

    // To test against null only, use the binary equality operator.
    if (b == null) {
        try expect(true);
    }

    // Access the value by reference using a pointer capture.
    var c: ?u32 = 3;
    if (c) |*value| {
        value.* = 2;
    }

    if (c) |value| {
        try expect(value == 2);
    } else {
        unreachable;
    }
}

test &quot;if error union with optional&quot; {
    // If expressions test for errors before unwrapping optionals.
    // The |optional_value| capture&#39;s type is ?u32.

    const a: anyerror!?u32 = 0;
    if (a) |optional_value| {
        try expect(optional_value.? == 0);
    } else |err| {
        _ = err;
        unreachable;
    }

    const b: anyerror!?u32 = null;
    if (b) |optional_value| {
        try expect(optional_value == null);
    } else |_| {
        unreachable;
    }

    const c: anyerror!?u32 = error.BadValue;
    if (c) |optional_value| {
        _ = optional_value;
        unreachable;
    } else |err| {
        try expect(err == error.BadValue);
    }

    // Access the value by reference by using a pointer capture each time.
    var d: anyerror!?u32 = 3;
    if (d) |*optional_value| {
        if (optional_value.*) |*value| {
            value.* = 9;
        }
    } else |_| {
        unreachable;
    }

    if (d) |optional_value| {
        try expect(optional_value.? == 9);
    } else |_| {
        unreachable;
    }
}</code></pre>
<figcaption>test_if_optionals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_if_optionals.zig
1/2 test_if_optionals.test.if optional...OK
2/2 test_if_optionals.test.if error union with optional...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optionals](#Optionals)
- [Errors](#Errors)

## [defer](#toc-defer) <a href="#defer" class="hdr">§</a>

Executes an expression unconditionally at scope exit.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const print = std.debug.print;

fn deferExample() !usize {
    var a: usize = 1;

    {
        defer a = 2;
        a = 1;
    }
    try expect(a == 2);

    a = 5;
    return a;
}

test &quot;defer basics&quot; {
    try expect((try deferExample()) == 5);
}</code></pre>
<figcaption>test_defer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_defer.zig
1/1 test_defer.test.defer basics...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Defer expressions are evaluated in reverse order.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const print = std.debug.print;

pub fn main() void {
    print(&quot;\n&quot;, .{});

    defer {
        print(&quot;1 &quot;, .{});
    }
    defer {
        print(&quot;2 &quot;, .{});
    }
    if (false) {
        // defers are not run if they are never executed.
        defer {
            print(&quot;3 &quot;, .{});
        }
    }
}</code></pre>
<figcaption>defer_unwind.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe defer_unwind.zig
$ ./defer_unwind

2 1</code></pre>
<figcaption>Shell</figcaption>
</figure>

Inside a defer expression the return statement is not allowed.

<figure>
<pre><code>fn deferInvalidExample() !void {
    defer {
        return error.DeferError;
    }

    return error.DeferError;
}</code></pre>
<figcaption>test_invalid_defer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_invalid_defer.zig
/home/andy/dev/zig/doc/langref/test_invalid_defer.zig:3:9: error: cannot return from defer expression
        return error.DeferError;
        ^~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_invalid_defer.zig:2:5: note: defer expression here
    defer {
    ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Errors](#Errors)

## [unreachable](#toc-unreachable) <a href="#unreachable" class="hdr">§</a>

In [Debug](#Debug) and [ReleaseSafe](#ReleaseSafe) mode
<span class="tok-kw">`unreachable`</span> emits a call to `panic` with the message `reached unreachable code`.

In [ReleaseFast](#ReleaseFast) and [ReleaseSmall](#ReleaseSmall) mode, the optimizer uses the assumption that <span class="tok-kw">`unreachable`</span> code
will never be hit to perform optimizations.

### [Basics](#toc-Basics) <a href="#Basics" class="hdr">§</a>

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

### [At Compile-Time](#toc-At-Compile-Time) <a href="#At-Compile-Time" class="hdr">§</a>

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

- [Zig Test](#Zig-Test)
- [Build Mode](#Build-Mode)
- [comptime](#comptime)

## [noreturn](#toc-noreturn) <a href="#noreturn" class="hdr">§</a>

<span class="tok-type">`noreturn`</span> is the type of:

- <span class="tok-kw">`break`</span>
- <span class="tok-kw">`continue`</span>
- <span class="tok-kw">`return`</span>
- <span class="tok-kw">`unreachable`</span>
- <span class="tok-kw">`while`</span>` (`<span class="tok-null">`true`</span>`) {}`

When resolving types together, such as <span class="tok-kw">`if`</span> clauses or <span class="tok-kw">`switch`</span> prongs,
the <span class="tok-type">`noreturn`</span> type is compatible with every other type. Consider:

<figure>
<pre><code>fn foo(condition: bool, b: u32) void {
    const a = if (condition) b else return;
    _ = a;
    @panic(&quot;do something with a&quot;);
}
test &quot;noreturn&quot; {
    foo(false, 1);
}</code></pre>
<figcaption>test_noreturn.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_noreturn.zig
1/1 test_noreturn.test.noreturn...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Another use case for <span class="tok-type">`noreturn`</span> is the `exit` function:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const native_arch = builtin.cpu.arch;
const expect = std.testing.expect;

const WINAPI: std.builtin.CallingConvention = if (native_arch == .x86) .{ .x86_stdcall = .{} } else .c;
extern &quot;kernel32&quot; fn ExitProcess(exit_code: c_uint) callconv(WINAPI) noreturn;

test &quot;foo&quot; {
    const value = bar() catch ExitProcess(1);
    try expect(value == 1234);
}

fn bar() anyerror!u32 {
    return 1234;
}</code></pre>
<figcaption>test_noreturn_from_exit.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_noreturn_from_exit.zig -target x86_64-windows --test-no-exec</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Functions](#toc-Functions) <a href="#Functions" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const native_arch = builtin.cpu.arch;
const expect = std.testing.expect;

// Functions are declared like this
fn add(a: i8, b: i8) i8 {
    if (a == 0) {
        return b;
    }

    return a + b;
}

// The export specifier makes a function externally visible in the generated
// object file, and makes it use the C ABI.
export fn sub(a: i8, b: i8) i8 {
    return a - b;
}

// The extern specifier is used to declare a function that will be resolved
// at link time, when linking statically, or at runtime, when linking
// dynamically. The quoted identifier after the extern keyword specifies
// the library that has the function. (e.g. &quot;c&quot; -&gt; libc.so)
// The callconv specifier changes the calling convention of the function.
extern &quot;kernel32&quot; fn ExitProcess(exit_code: u32) callconv(.winapi) noreturn;
extern &quot;c&quot; fn atan2(a: f64, b: f64) f64;

// The @branchHint builtin can be used to tell the optimizer that a function is rarely called (&quot;cold&quot;).
fn abort() noreturn {
    @branchHint(.cold);
    while (true) {}
}

// The naked calling convention makes a function not have any function prologue or epilogue.
// This can be useful when integrating with assembly.
fn _start() callconv(.naked) noreturn {
    abort();
}

// The inline calling convention forces a function to be inlined at all call sites.
// If the function cannot be inlined, it is a compile-time error.
inline fn shiftLeftOne(a: u32) u32 {
    return a &lt;&lt; 1;
}

// The pub specifier allows the function to be visible when importing.
// Another file can use @import and call sub2
pub fn sub2(a: i8, b: i8) i8 {
    return a - b;
}

// Function pointers are prefixed with `*const `.
const Call2Op = *const fn (a: i8, b: i8) i8;
fn doOp(fnCall: Call2Op, op1: i8, op2: i8) i8 {
    return fnCall(op1, op2);
}

test &quot;function&quot; {
    try expect(doOp(add, 5, 6) == 11);
    try expect(doOp(sub2, 5, 6) == -1);
}</code></pre>
<figcaption>test_functions.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_functions.zig
1/1 test_functions.test.function...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

There is a difference between a function *body* and a function *pointer*.
Function bodies are [comptime](#comptime)-only types while function [Pointers](#Pointers) may be
runtime-known.

### [Pass-by-value Parameters](#toc-Pass-by-value-Parameters) <a href="#Pass-by-value-Parameters" class="hdr">§</a>

Primitive types such as [Integers](#Integers) and [Floats](#Floats) passed as parameters
are copied, and then the copy is available in the function body. This is called "passing by value".
Copying a primitive type is essentially free and typically involves nothing more than
setting a register.

Structs, unions, and arrays can sometimes be more efficiently passed as a reference, since a copy
could be arbitrarily expensive depending on the size. When these types are passed
as parameters, Zig may choose to copy and pass by value, or pass by reference, whichever way
Zig decides will be faster. This is made possible, in part, by the fact that parameters are immutable.

<figure>
<pre><code>const Point = struct {
    x: i32,
    y: i32,
};

fn foo(point: Point) i32 {
    // Here, `point` could be a reference, or a copy. The function body
    // can ignore the difference and treat it as a value. Be very careful
    // taking the address of the parameter - it should be treated as if
    // the address will become invalid when the function returns.
    return point.x + point.y;
}

const expect = @import(&quot;std&quot;).testing.expect;

test &quot;pass struct to function&quot; {
    try expect(foo(Point{ .x = 1, .y = 2 }) == 3);
}</code></pre>
<figcaption>test_pass_by_reference_or_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pass_by_reference_or_value.zig
1/1 test_pass_by_reference_or_value.test.pass struct to function...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

For extern functions, Zig follows the C ABI for passing structs and unions by value.

### [Function Parameter Type Inference](#toc-Function-Parameter-Type-Inference) <a href="#Function-Parameter-Type-Inference" class="hdr">§</a>

Function parameters can be declared with <span class="tok-kw">`anytype`</span> in place of the type.
In this case the parameter types will be inferred when the function is called.
Use [@TypeOf](#TypeOf) and [@typeInfo](#typeInfo) to get information about the inferred type.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

fn addFortyTwo(x: anytype) @TypeOf(x) {
    return x + 42;
}

test &quot;fn type inference&quot; {
    try expect(addFortyTwo(1) == 43);
    try expect(@TypeOf(addFortyTwo(1)) == comptime_int);
    const y: i64 = 2;
    try expect(addFortyTwo(y) == 44);
    try expect(@TypeOf(addFortyTwo(y)) == i64);
}</code></pre>
<figcaption>test_fn_type_inference.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fn_type_inference.zig
1/1 test_fn_type_inference.test.fn type inference...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [inline fn](#toc-inline-fn) <a href="#inline-fn" class="hdr">§</a>

Adding the <span class="tok-kw">`inline`</span> keyword to a function definition makes that
function become *semantically inlined* at the callsite. This is
not a hint to be possibly observed by optimization passes, but has
implications on the types and values involved in the function call.

Unlike normal function calls, arguments at an inline function callsite which are
compile-time known are treated as [Compile Time Parameters](#Compile-Time-Parameters). This can potentially
propagate all the way to the return value:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    if (foo(1200, 34) != 1234) {
        @compileError(&quot;bad&quot;);
    }
}

inline fn foo(a: i32, b: i32) i32 {
    std.debug.print(&quot;runtime a = {} b = {}&quot;, .{ a, b });
    return a + b;
}</code></pre>
<figcaption>inline_call.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe inline_call.zig
$ ./inline_call
runtime a = 1200 b = 34</code></pre>
<figcaption>Shell</figcaption>
</figure>

If <span class="tok-kw">`inline`</span> is removed, the test fails with the compile error
instead of passing.

It is generally better to let the compiler decide when to inline a
function, except for these scenarios:

- To change how many stack frames are in the call stack, for debugging purposes.
- To force comptime-ness of the arguments to propagate to the return value of the function, as in the above example.
- Real world performance measurements demand it.

Note that <span class="tok-kw">`inline`</span> actually *restricts*
what the compiler is allowed to do. This can harm binary size,
compilation speed, and even runtime performance.

### [Function Reflection](#toc-Function-Reflection) <a href="#Function-Reflection" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const math = std.math;
const testing = std.testing;

test &quot;fn reflection&quot; {
    try testing.expect(@typeInfo(@TypeOf(testing.expect)).@&quot;fn&quot;.params[0].type.? == bool);
    try testing.expect(@typeInfo(@TypeOf(testing.tmpDir)).@&quot;fn&quot;.return_type.? == testing.TmpDir);

    try testing.expect(@typeInfo(@TypeOf(math.Log2Int)).@&quot;fn&quot;.is_generic);
}</code></pre>
<figcaption>test_fn_reflection.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fn_reflection.zig
1/1 test_fn_reflection.test.fn reflection...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Errors](#toc-Errors) <a href="#Errors" class="hdr">§</a>

### [Error Set Type](#toc-Error-Set-Type) <a href="#Error-Set-Type" class="hdr">§</a>

An error set is like an [enum](#enum).
However, each error name across the entire compilation gets assigned an unsigned integer
greater than 0. You are allowed to declare the same error name more than once, and if you do, it
gets assigned the same integer value.

The error set type defaults to a <span class="tok-type">`u16`</span>, though if the maximum number of distinct
error values is provided via the <span class="kbd">--error-limit \[num\]</span> command line parameter an integer type
with the minimum number of bits required to represent all of the error values will be used.

You can [coerce](#Type-Coercion) an error from a subset to a superset:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test &quot;coerce subset to superset&quot; {
    const err = foo(AllocationError.OutOfMemory);
    try std.testing.expect(err == FileOpenError.OutOfMemory);
}

fn foo(err: AllocationError) FileOpenError {
    return err;
}</code></pre>
<figcaption>test_coerce_error_subset_to_superset.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_error_subset_to_superset.zig
1/1 test_coerce_error_subset_to_superset.test.coerce subset to superset...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

But you cannot [coerce](#Type-Coercion) an error from a superset to a subset:

<figure>
<pre><code>const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};

const AllocationError = error{
    OutOfMemory,
};

test &quot;coerce superset to subset&quot; {
    foo(FileOpenError.OutOfMemory) catch {};
}

fn foo(err: FileOpenError) AllocationError {
    return err;
}</code></pre>
<figcaption>test_coerce_error_superset_to_subset.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_error_superset_to_subset.zig
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: error: expected type &#39;error{OutOfMemory}&#39;, found &#39;error{AccessDenied,FileNotFound,OutOfMemory}&#39;
    return err;
           ^~~
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: &#39;error.AccessDenied&#39; not a member of destination error set
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:16:12: note: &#39;error.FileNotFound&#39; not a member of destination error set
/home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:15:28: note: function return type declared here
fn foo(err: FileOpenError) AllocationError {
                           ^~~~~~~~~~~~~~~
referenced by:
    test.coerce superset to subset: /home/andy/dev/zig/doc/langref/test_coerce_error_superset_to_subset.zig:12:8
</code></pre>
<figcaption>Shell</figcaption>
</figure>

There is a shortcut for declaring an error set with only 1 value, and then getting that value:

<figure>
<pre><code>const err = error.FileNotFound;</code></pre>
<figcaption>single_value_error_set_shortcut.zig</figcaption>
</figure>

This is equivalent to:

<figure>
<pre><code>const err = (error{FileNotFound}).FileNotFound;</code></pre>
<figcaption>single_value_error_set.zig</figcaption>
</figure>

This becomes useful when using [Inferred Error Sets](#Inferred-Error-Sets).

#### [The Global Error Set](#toc-The-Global-Error-Set) <a href="#The-Global-Error-Set" class="hdr">§</a>

<span class="tok-type">`anyerror`</span> refers to the global error set.
This is the error set that contains all errors in the entire compilation unit, i.e. it is the union of all other error sets.

You can [coerce](#Type-Coercion) any error set to the global one, and you can explicitly
cast an error of the global error set to a non-global one. This inserts a language-level
assert to make sure the error value is in fact in the destination error set.

The global error set should generally be avoided because it prevents the
compiler from knowing what errors are possible at compile-time. Knowing
the error set at compile-time is better for generated documentation and
helpful error messages, such as forgetting a possible error value in a [switch](#switch).

### [Error Union Type](#toc-Error-Union-Type) <a href="#Error-Union-Type" class="hdr">§</a>

An error set type and normal type can be combined with the `!`
binary operator to form an error union type. You are likely to use an
error union type more often than an error set type by itself.

Here is a function to parse a string into a 64-bit integer:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const maxInt = std.math.maxInt;

pub fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;

    for (buf) |c| {
        const digit = charToDigit(c);

        if (digit &gt;= radix) {
            return error.InvalidChar;
        }

        // x *= radix
        var ov = @mulWithOverflow(x, radix);
        if (ov[1] != 0) return error.OverFlow;

        // x += digit
        ov = @addWithOverflow(ov[0], digit);
        if (ov[1] != 0) return error.OverFlow;
        x = ov[0];
    }

    return x;
}

fn charToDigit(c: u8) u8 {
    return switch (c) {
        &#39;0&#39;...&#39;9&#39; =&gt; c - &#39;0&#39;,
        &#39;A&#39;...&#39;Z&#39; =&gt; c - &#39;A&#39; + 10,
        &#39;a&#39;...&#39;z&#39; =&gt; c - &#39;a&#39; + 10,
        else =&gt; maxInt(u8),
    };
}

test &quot;parse u64&quot; {
    const result = try parseU64(&quot;1234&quot;, 10);
    try std.testing.expect(result == 1234);
}</code></pre>
<figcaption>error_union_parsing_u64.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test error_union_parsing_u64.zig
1/1 error_union_parsing_u64.test.parse u64...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Notice the return type is `!`<span class="tok-type">`u64`</span>. This means that the function
either returns an unsigned 64 bit integer, or an error. We left off the error set
to the left of the `!`, so the error set is inferred.

Within the function definition, you can see some return statements that return
an error, and at the bottom a return statement that returns a <span class="tok-type">`u64`</span>.
Both types [coerce](#Type-Coercion) to <span class="tok-type">`anyerror`</span>`!`<span class="tok-type">`u64`</span>.

What it looks like to use this function varies depending on what you're
trying to do. One of the following:

- You want to provide a default value if it returned an error.
- If it returned an error then you want to return the same error.
- You know with complete certainty it will not return an error, so want to unconditionally unwrap it.
- You want to take a different action for each possible error.

#### [catch](#toc-catch) <a href="#catch" class="hdr">§</a>

If you want to provide a default value, you can use the <span class="tok-kw">`catch`</span> binary operator:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch 13;
    _ = number; // ...
}</code></pre>
<figcaption>catch.zig</figcaption>
</figure>

In this code, `number` will be equal to the successfully parsed string, or
a default value of 13. The type of the right hand side of the binary <span class="tok-kw">`catch`</span> operator must
match the unwrapped error union type, or be of type <span class="tok-type">`noreturn`</span>.

If you want to provide a default value with
<span class="tok-kw">`catch`</span> after performing some logic, you
can combine <span class="tok-kw">`catch`</span> with named [Blocks](#Blocks):

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) void {
    const number = parseU64(str, 10) catch blk: {
        // do things
        break :blk 13;
    };
    _ = number; // number is now initialized
}</code></pre>
<figcaption>handle_error_with_catch_block.zig.zig</figcaption>
</figure>

#### [try](#toc-try) <a href="#try" class="hdr">§</a>

Let's say you wanted to return the error if you got one, otherwise continue with the
function logic:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) !void {
    const number = parseU64(str, 10) catch |err| return err;
    _ = number; // ...
}</code></pre>
<figcaption>catch_err_return.zig</figcaption>
</figure>

There is a shortcut for this. The <span class="tok-kw">`try`</span> expression:

<figure>
<pre><code>const parseU64 = @import(&quot;error_union_parsing_u64.zig&quot;).parseU64;

fn doAThing(str: []u8) !void {
    const number = try parseU64(str, 10);
    _ = number; // ...
}</code></pre>
<figcaption>try.zig</figcaption>
</figure>

<span class="tok-kw">`try`</span> evaluates an error union expression. If it is an error, it returns
from the current function with the same error. Otherwise, the expression results in
the unwrapped value.

Maybe you know with complete certainty that an expression will never be an error.
In this case you can do this:

<span class="tok-kw">`const`</span>` number = parseU64(`<span class="tok-str">`"1234"`</span>`, `<span class="tok-number">`10`</span>`) `<span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span>`;`

Here we know for sure that "1234" will parse successfully. So we put the
<span class="tok-kw">`unreachable`</span> value on the right hand side.
<span class="tok-kw">`unreachable`</span> invokes safety-checked [Illegal Behavior](#Illegal-Behavior), so
in [Debug](#Debug) and [ReleaseSafe](#ReleaseSafe), triggers a safety panic by default. So, while
we're debugging the application, if there *was* a surprise error here, the application
would crash appropriately.

You may want to take a different action for every situation. For that, we combine
the [if](#if) and [switch](#switch) expression:

<figure>
<pre><code>fn doAThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow =&gt; {
            // handle overflow...
        },
        // we promise that InvalidChar won&#39;t happen (or crash in debug mode if it does)
        error.InvalidChar =&gt; unreachable,
    }
}</code></pre>
<figcaption>handle_all_error_scenarios.zig</figcaption>
</figure>

Finally, you may want to handle only some errors. For that, you can capture the unhandled
errors in the <span class="tok-kw">`else`</span> case, which now contains a narrower error set:

<figure>
<pre><code>fn doAnotherThing(str: []u8) error{InvalidChar}!void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow =&gt; {
            // handle overflow...
        },
        else =&gt; |leftover_err| return leftover_err,
    }
}</code></pre>
<figcaption>handle_some_error_scenarios.zig</figcaption>
</figure>

You must use the variable capture syntax. If you don't need the
variable, you can capture with `_` and avoid the
<span class="tok-kw">`switch`</span>.

<figure>
<pre><code>fn doADifferentThing(str: []u8) void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |_| {
        // do as you&#39;d like
    }
}</code></pre>
<figcaption>handle_no_error_scenarios.zig</figcaption>
</figure>

#### [errdefer](#toc-errdefer) <a href="#errdefer" class="hdr">§</a>

The other component to error handling is defer statements.
In addition to an unconditional [defer](#defer), Zig has <span class="tok-kw">`errdefer`</span>,
which evaluates the deferred expression on block exit path if and only if
the function returned with an error from the block.

Example:

<figure>
<pre><code>fn createFoo(param: i32) !Foo {
    const foo = try tryToAllocateFoo();
    // now we have allocated foo. we need to free it if the function fails.
    // but we want to return it if the function succeeds.
    errdefer deallocateFoo(foo);

    const tmp_buf = allocateTmpBuffer() orelse return error.OutOfMemory;
    // tmp_buf is truly a temporary resource, and we for sure want to clean it up
    // before this block leaves scope
    defer deallocateTmpBuffer(tmp_buf);

    if (param &gt; 1337) return error.InvalidParam;

    // here the errdefer will not run since we&#39;re returning success from the function.
    // but the defer will run!
    return foo;
}</code></pre>
<figcaption>errdefer_example.zig</figcaption>
</figure>

The neat thing about this is that you get robust error handling without
the verbosity and cognitive overhead of trying to make sure every exit path
is covered. The deallocation code is always directly following the allocation code.

The <span class="tok-kw">`errdefer`</span> statement can optionally capture the error:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

fn captureError(captured: *?anyerror) !void {
    errdefer |err| {
        captured.* = err;
    }
    return error.GeneralFailure;
}

test &quot;errdefer capture&quot; {
    var captured: ?anyerror = null;

    if (captureError(&amp;captured)) unreachable else |err| {
        try std.testing.expectEqual(error.GeneralFailure, captured.?);
        try std.testing.expectEqual(error.GeneralFailure, err);
    }
}</code></pre>
<figcaption>test_errdefer_capture.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_errdefer_capture.zig
1/1 test_errdefer_capture.test.errdefer capture...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

A couple of other tidbits about error handling:

- These primitives give enough expressiveness that it's completely practical
  to have failing to check for an error be a compile error. If you really want
  to ignore the error, you can add <span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span> and
  get the added benefit of crashing in Debug and ReleaseSafe modes if your assumption was wrong.
- Since Zig understands error types, it can pre-weight branches in favor of
  errors not occurring. Just a small optimization benefit that is not available
  in other languages.

See also:

- [defer](#defer)
- [if](#if)
- [switch](#switch)

An error union is created with the `!` binary operator.
You can use compile-time reflection to access the child type of an error union:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;error union&quot; {
    var foo: anyerror!i32 = undefined;

    // Coerce from child type of an error union:
    foo = 1234;

    // Coerce from an error set:
    foo = error.SomeError;

    // Use compile-time reflection to access the payload type of an error union:
    try comptime expect(@typeInfo(@TypeOf(foo)).error_union.payload == i32);

    // Use compile-time reflection to access the error set type of an error union:
    try comptime expect(@typeInfo(@TypeOf(foo)).error_union.error_set == anyerror);
}</code></pre>
<figcaption>test_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_error_union.zig
1/1 test_error_union.test.error union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Merging Error Sets](#toc-Merging-Error-Sets) <a href="#Merging-Error-Sets" class="hdr">§</a>

Use the `||` operator to merge two error sets together. The resulting
error set contains the errors of both error sets. Doc comments from the left-hand
side override doc comments from the right-hand side. In this example, the doc
comments for `C.PathNotFound` is `A doc comment`.

This is especially useful for functions which return different error sets depending
on [comptime](#comptime) branches. For example, the Zig standard library uses
`LinuxFileOpenError || WindowsFileOpenError` for the error set of opening
files.

<figure>
<pre><code>const A = error{
    NotDir,

    /// A doc comment
    PathNotFound,
};
const B = error{
    OutOfMemory,

    /// B doc comment
    PathNotFound,
};

const C = A || B;

fn foo() C!void {
    return error.NotDir;
}

test &quot;merge error sets&quot; {
    if (foo()) {
        @panic(&quot;unexpected&quot;);
    } else |err| switch (err) {
        error.OutOfMemory =&gt; @panic(&quot;unexpected&quot;),
        error.PathNotFound =&gt; @panic(&quot;unexpected&quot;),
        error.NotDir =&gt; {},
    }
}</code></pre>
<figcaption>test_merging_error_sets.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_merging_error_sets.zig
1/1 test_merging_error_sets.test.merge error sets...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Inferred Error Sets](#toc-Inferred-Error-Sets) <a href="#Inferred-Error-Sets" class="hdr">§</a>

Because many functions in Zig return a possible error, Zig supports inferring the error set.
To infer the error set for a function, prepend the `!` operator to the function’s return type, like `!T`:

<figure>
<pre><code>// With an inferred error set
pub fn add_inferred(comptime T: type, a: T, b: T) !T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

// With an explicit error set
pub fn add_explicit(comptime T: type, a: T, b: T) Error!T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

const Error = error{
    Overflow,
};

const std = @import(&quot;std&quot;);

test &quot;inferred error set&quot; {
    if (add_inferred(u8, 255, 1)) |_| unreachable else |err| switch (err) {
        error.Overflow =&gt; {}, // ok
    }
}</code></pre>
<figcaption>test_inferred_error_sets.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_inferred_error_sets.zig
1/1 test_inferred_error_sets.test.inferred error set...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When a function has an inferred error set, that function becomes generic and thus it becomes
trickier to do certain things with it, such as obtain a function pointer, or have an error
set that is consistent across different build targets. Additionally, inferred error sets
are incompatible with recursion.

In these situations, it is recommended to use an explicit error set. You can generally start
with an empty error set and let compile errors guide you toward completing the set.

These limitations may be overcome in a future version of Zig.

### [Error Return Traces](#toc-Error-Return-Traces) <a href="#Error-Return-Traces" class="hdr">§</a>

Error Return Traces show all the points in the code that an error was returned to the calling function. This makes it practical to use [try](#try) everywhere and then still be able to know what happened if an error ends up bubbling all the way out of your application.

<figure>
<pre><code>pub fn main() !void {
    try foo(12);
}

fn foo(x: i32) !void {
    if (x &gt;= 5) {
        try bar();
    } else {
        try bang2();
    }
}

fn bar() !void {
    if (baz()) {
        try quux();
    } else |err| switch (err) {
        error.FileNotFound =&gt; try hello(),
    }
}

fn baz() !void {
    try bang1();
}

fn quux() !void {
    try bang2();
}

fn hello() !void {
    try bang2();
}

fn bang1() !void {
    return error.FileNotFound;
}

fn bang2() !void {
    return error.PermissionDenied;
}</code></pre>
<figcaption>error_return_trace.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe error_return_trace.zig
$ ./error_return_trace
error: PermissionDenied
/home/andy/dev/zig/doc/langref/error_return_trace.zig:34:5: 0x113d34c in bang1 (error_return_trace.zig)
    return error.FileNotFound;
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:22:5: 0x113d396 in baz (error_return_trace.zig)
    try bang1();
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:38:5: 0x113d3cc in bang2 (error_return_trace.zig)
    return error.PermissionDenied;
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:30:5: 0x113d476 in hello (error_return_trace.zig)
    try bang2();
    ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:17:31: 0x113d54e in bar (error_return_trace.zig)
        error.FileNotFound =&gt; try hello(),
                              ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:7:9: 0x113d634 in foo (error_return_trace.zig)
        try bar();
        ^
/home/andy/dev/zig/doc/langref/error_return_trace.zig:2:5: 0x113d6fb in main (error_return_trace.zig)
    try foo(12);
    ^</code></pre>
<figcaption>Shell</figcaption>
</figure>

Look closely at this example. This is no stack trace.

You can see that the final error bubbled up was `PermissionDenied`,
but the original error that started this whole thing was `FileNotFound`. In the `bar` function, the code handles the original error code,
and then returns another one, from the switch statement. Error Return Traces make this clear, whereas a stack trace would look like this:

<figure>
<pre><code>pub fn main() void {
    foo(12);
}

fn foo(x: i32) void {
    if (x &gt;= 5) {
        bar();
    } else {
        bang2();
    }
}

fn bar() void {
    if (baz()) {
        quux();
    } else {
        hello();
    }
}

fn baz() bool {
    return bang1();
}

fn quux() void {
    bang2();
}

fn hello() void {
    bang2();
}

fn bang1() bool {
    return false;
}

fn bang2() void {
    @panic(&quot;PermissionDenied&quot;);
}</code></pre>
<figcaption>stack_trace.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe stack_trace.zig
$ ./stack_trace
thread 1093966 panic: PermissionDenied
/home/andy/dev/zig/doc/langref/stack_trace.zig:38:5: 0x1140e4c in bang2 (stack_trace.zig)
    @panic(&quot;PermissionDenied&quot;);
    ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:30:10: 0x114148c in hello (stack_trace.zig)
    bang2();
         ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:17:14: 0x1140e03 in bar (stack_trace.zig)
        hello();
             ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:7:12: 0x1140a98 in foo (stack_trace.zig)
        bar();
           ^
/home/andy/dev/zig/doc/langref/stack_trace.zig:2:8: 0x113f851 in main (stack_trace.zig)
    foo(12);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113ea9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113e331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

Here, the stack trace does not explain how the control
flow in `bar` got to the `hello()` call.
One would have to open a debugger or further instrument the application
in order to find out. The error return trace, on the other hand,
shows exactly how the error bubbled up.

This debugging feature makes it easier to iterate quickly on code that
robustly handles all error conditions. This means that Zig developers
will naturally find themselves writing correct, robust code in order
to increase their development pace.

Error Return Traces are enabled by default in [Debug](#Debug) builds and disabled by default in [ReleaseFast](#ReleaseFast), [ReleaseSafe](#ReleaseSafe) and [ReleaseSmall](#ReleaseSmall) builds.

There are a few ways to activate this error return tracing feature:

- Return an error from main
- An error makes its way to <span class="tok-kw">`catch`</span>` `<span class="tok-kw">`unreachable`</span> and you have not overridden the default panic handler
- Use [errorReturnTrace](#errorReturnTrace) to access the current return trace. You can use `std.debug.dumpStackTrace` to print it. This function returns comptime-known [null](#null) when building without error return tracing support.

#### [Implementation Details](#toc-Implementation-Details) <a href="#Implementation-Details" class="hdr">§</a>

To analyze performance cost, there are two cases:

- when no errors are returned
- when returning errors

For the case when no errors are returned, the cost is a single memory write operation, only in the first non-failable function in the call graph that calls a failable function, i.e. when a function returning <span class="tok-type">`void`</span> calls a function returning <span class="tok-kw">`error`</span>.
This is to initialize this struct in the stack memory:

<figure>
<pre><code>pub const StackTrace = struct {
    index: usize,
    instruction_addresses: [N]usize,
};</code></pre>
<figcaption>stack_trace_struct.zig</figcaption>
</figure>

Here, N is the maximum function call depth as determined by call graph analysis. Recursion is ignored and counts for 2.

A pointer to `StackTrace` is passed as a secret parameter to every function that can return an error, but it's always the first parameter, so it can likely sit in a register and stay there.

That's it for the path when no errors occur. It's practically free in terms of performance.

When generating the code for a function that returns an error, just before the <span class="tok-kw">`return`</span> statement (only for the <span class="tok-kw">`return`</span> statements that return errors), Zig generates a call to this function:

<figure>
<pre><code>// marked as &quot;no-inline&quot; in LLVM IR
fn __zig_return_error(stack_trace: *StackTrace) void {
    stack_trace.instruction_addresses[stack_trace.index] = @returnAddress();
    stack_trace.index = (stack_trace.index + 1) % N;
}</code></pre>
<figcaption>zig_return_error_fn.zig</figcaption>
</figure>

The cost is 2 math operations plus some memory reads and writes. The memory accessed is constrained and should remain cached for the duration of the error return bubbling.

As for code size cost, 1 function call before a return statement is no big deal. Even so,
I have [a plan](https://github.com/ziglang/zig/issues/690) to make the call to
`__zig_return_error` a tail call, which brings the code size cost down to actually zero. What is a return statement in code without error return tracing can become a jump instruction in code with error return tracing.

## [Optionals](#toc-Optionals) <a href="#Optionals" class="hdr">§</a>

One area that Zig provides safety without compromising efficiency or
readability is with the optional type.

The question mark symbolizes the optional type. You can convert a type to an optional
type by putting a question mark in front of it, like this:

<figure>
<pre><code>// normal integer
const normal_int: i32 = 1234;

// optional integer
const optional_int: ?i32 = 5678;</code></pre>
<figcaption>optional_integer.zig</figcaption>
</figure>

Now the variable `optional_int` could be an <span class="tok-type">`i32`</span>, or <span class="tok-null">`null`</span>.

Instead of integers, let's talk about pointers. Null references are the source of many runtime
exceptions, and even stand accused of being
[the worst mistake of computer science](https://www.lucidchart.com/techblog/2015/08/31/the-worst-mistake-of-computer-science/).

Zig does not have them.

Instead, you can use an optional pointer. This secretly compiles down to a normal pointer,
since we know we can use 0 as the null value for the optional type. But the compiler
can check your work and make sure you don't assign null to something that can't be null.

Typically the downside of not having null is that it makes the code more verbose to
write. But, let's compare some equivalent C code and Zig code.

Task: call malloc, if the result is null, return null.

C code

<figure>
<pre><code>// malloc prototype included for reference
void *malloc(size_t size);

struct Foo *do_a_thing(void) {
    char *ptr = malloc(1234);
    if (!ptr) return NULL;
    // ...
}</code></pre>
<figcaption>call_malloc_in_c.c</figcaption>
</figure>

Zig code

<figure>
<pre><code>// malloc prototype included for reference
extern fn malloc(size: usize) ?[*]u8;

fn doAThing() ?*Foo {
    const ptr = malloc(1234) orelse return null;
    _ = ptr; // ...
}</code></pre>
<figcaption>call_malloc_from_zig.zig</figcaption>
</figure>

Here, Zig is at least as convenient, if not more, than C. And, the type of "ptr"
is `[*]`<span class="tok-type">`u8`</span> *not* `?[*]`<span class="tok-type">`u8`</span>. The <span class="tok-kw">`orelse`</span> keyword
unwrapped the optional type and therefore `ptr` is guaranteed to be non-null everywhere
it is used in the function.

The other form of checking against NULL you might see looks like this:

<figure>
<pre><code>void do_a_thing(struct Foo *foo) {
    // do some stuff

    if (foo) {
        do_something_with_foo(foo);
    }

    // do some stuff
}</code></pre>
<figcaption>checking_null_in_c.c</figcaption>
</figure>

In Zig you can accomplish the same thing:

<figure>
<pre><code>const Foo = struct {};
fn doSomethingWithFoo(foo: *Foo) void {
    _ = foo;
}

fn doAThing(optional_foo: ?*Foo) void {
    // do some stuff

    if (optional_foo) |foo| {
        doSomethingWithFoo(foo);
    }

    // do some stuff
}</code></pre>
<figcaption>checking_null_in_zig.zig</figcaption>
</figure>

Once again, the notable thing here is that inside the if block,
`foo` is no longer an optional pointer, it is a pointer, which
cannot be null.

One benefit to this is that functions which take pointers as arguments can
be annotated with the "nonnull" attribute - `__attribute__((nonnull))` in
[GCC](https://gcc.gnu.org/onlinedocs/gcc-4.0.0/gcc/Function-Attributes.html).
The optimizer can sometimes make better decisions knowing that pointer arguments
cannot be null.

### [Optional Type](#toc-Optional-Type) <a href="#Optional-Type" class="hdr">§</a>

An optional is created by putting `?` in front of a type. You can use compile-time
reflection to access the child type of an optional:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;optional type&quot; {
    // Declare an optional and coerce from null:
    var foo: ?i32 = null;

    // Coerce from child type of an optional
    foo = 1234;

    // Use compile-time reflection to access the child type of the optional:
    try comptime expect(@typeInfo(@TypeOf(foo)).optional.child == i32);
}</code></pre>
<figcaption>test_optional_type.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_optional_type.zig
1/1 test_optional_type.test.optional type...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [null](#toc-null) <a href="#null" class="hdr">§</a>

Just like [undefined](#undefined), <span class="tok-null">`null`</span> has its own type, and the only way to use it is to
cast it to a different type:

<figure>
<pre><code>const optional_value: ?i32 = null;</code></pre>
<figcaption>null.zig</figcaption>
</figure>

### [Optional Pointers](#toc-Optional-Pointers) <a href="#Optional-Pointers" class="hdr">§</a>

An optional pointer is guaranteed to be the same size as a pointer. The <span class="tok-null">`null`</span> of
the optional is guaranteed to be address 0.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;optional pointers&quot; {
    // Pointers cannot be null. If you want a null pointer, use the optional
    // prefix `?` to make the pointer type optional.
    var ptr: ?*i32 = null;

    var x: i32 = 1;
    ptr = &amp;x;

    try expect(ptr.?.* == 1);

    // Optional pointers are the same size as normal pointers, because pointer
    // value 0 is used as the null value.
    try expect(@sizeOf(?*i32) == @sizeOf(*i32));
}</code></pre>
<figcaption>test_optional_pointer.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_optional_pointer.zig
1/1 test_optional_pointer.test.optional pointers...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [while with Optionals](#while-with-Optionals)
- [if with Optionals](#if-with-Optionals)

## [Casting](#toc-Casting) <a href="#Casting" class="hdr">§</a>

A **type cast** converts a value of one type to another.
Zig has [Type Coercion](#Type-Coercion) for conversions that are known to be completely safe and unambiguous,
and [Explicit Casts](#Explicit-Casts) for conversions that one would not want to happen on accident.
There is also a third kind of type conversion called [Peer Type Resolution](#Peer-Type-Resolution) for
the case when a result type must be decided given multiple operand types.

### [Type Coercion](#toc-Type-Coercion) <a href="#Type-Coercion" class="hdr">§</a>

Type coercion occurs when one type is expected, but different type is provided:

<figure>
<pre><code>test &quot;type coercion - variable declaration&quot; {
    const a: u8 = 1;
    const b: u16 = a;
    _ = b;
}

test &quot;type coercion - function call&quot; {
    const a: u8 = 1;
    foo(a);
}

fn foo(b: u16) void {
    _ = b;
}

test &quot;type coercion - @as builtin&quot; {
    const a: u8 = 1;
    const b = @as(u16, a);
    _ = b;
}</code></pre>
<figcaption>test_type_coercion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_type_coercion.zig
1/3 test_type_coercion.test.type coercion - variable declaration...OK
2/3 test_type_coercion.test.type coercion - function call...OK
3/3 test_type_coercion.test.type coercion - @as builtin...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Type coercions are only allowed when it is completely unambiguous how to get from one type to another,
and the transformation is guaranteed to be safe. There is one exception, which is [C Pointers](#C-Pointers).

#### [Type Coercion: Stricter Qualification](#toc-Type-Coercion-Stricter-Qualification) <a href="#Type-Coercion-Stricter-Qualification" class="hdr">§</a>

Values which have the same representation at runtime can be cast to increase the strictness
of the qualifiers, no matter how nested the qualifiers are:

- <span class="tok-kw">`const`</span> - non-const to const is allowed
- <span class="tok-kw">`volatile`</span> - non-volatile to volatile is allowed
- <span class="tok-kw">`align`</span> - bigger to smaller alignment is allowed
- [error sets](#Error-Set-Type) to supersets is allowed

These casts are no-ops at runtime since the value representation does not change.

<figure>
<pre><code>test &quot;type coercion - const qualification&quot; {
    var a: i32 = 1;
    const b: *i32 = &amp;a;
    foo(b);
}

fn foo(_: *const i32) void {}</code></pre>
<figcaption>test_no_op_casts.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_no_op_casts.zig
1/1 test_no_op_casts.test.type coercion - const qualification...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In addition, pointers coerce to const optional pointers:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;cast *[1][*:0]const u8 to []const ?[*:0]const u8&quot; {
    const window_name = [1][*:0]const u8{&quot;window name&quot;};
    const x: []const ?[*:0]const u8 = &amp;window_name;
    try expect(mem.eql(u8, mem.span(x[0].?), &quot;window name&quot;));
}</code></pre>
<figcaption>test_pointer_coerce_const_optional.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_pointer_coerce_const_optional.zig
1/1 test_pointer_coerce_const_optional.test.cast *[1][*:0]const u8 to []const ?[*:0]const u8...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Integer and Float Widening](#toc-Type-Coercion-Integer-and-Float-Widening) <a href="#Type-Coercion-Integer-and-Float-Widening" class="hdr">§</a>

[Integers](#Integers) coerce to integer types which can represent every value of the old type, and likewise
[Floats](#Floats) coerce to float types which can represent every value of the old type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const builtin = @import(&quot;builtin&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;integer widening&quot; {
    const a: u8 = 250;
    const b: u16 = a;
    const c: u32 = b;
    const d: u64 = c;
    const e: u64 = d;
    const f: u128 = e;
    try expect(f == a);
}

test &quot;implicit unsigned integer to signed integer&quot; {
    const a: u8 = 250;
    const b: i16 = a;
    try expect(b == 250);
}

test &quot;float widening&quot; {
    const a: f16 = 12.34;
    const b: f32 = a;
    const c: f64 = b;
    const d: f128 = c;
    try expect(d == a);
}</code></pre>
<figcaption>test_integer_widening.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_integer_widening.zig
1/3 test_integer_widening.test.integer widening...OK
2/3 test_integer_widening.test.implicit unsigned integer to signed integer...OK
3/3 test_integer_widening.test.float widening...OK
All 3 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Float to Int](#toc-Type-Coercion-Float-to-Int) <a href="#Type-Coercion-Float-to-Int" class="hdr">§</a>

A compiler error is appropriate because this ambiguous expression leaves the compiler
two choices about the coercion.

- Cast <span class="tok-number">`54.0`</span> to <span class="tok-type">`comptime_int`</span> resulting in <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`comptime_int`</span>`, `<span class="tok-number">`10`</span>`)`, which is casted to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`f32`</span>`, `<span class="tok-number">`10`</span>`)`
- Cast <span class="tok-number">`5`</span> to <span class="tok-type">`comptime_float`</span> resulting in <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`comptime_float`</span>`, `<span class="tok-number">`10.8`</span>`)`, which is casted to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`f32`</span>`, `<span class="tok-number">`10.8`</span>`)`

<figure>
<pre><code>// Compile time coercion of float to int
test &quot;implicit cast to comptime_int&quot; {
    const f: f32 = 54.0 / 5;
    _ = f;
}</code></pre>
<figcaption>test_ambiguous_coercion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_ambiguous_coercion.zig
/home/andy/dev/zig/doc/langref/test_ambiguous_coercion.zig:3:25: error: ambiguous coercion of division operands &#39;comptime_float&#39; and &#39;comptime_int&#39;; non-zero remainder &#39;4&#39;
    const f: f32 = 54.0 / 5;
                   ~~~~~^~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Slices, Arrays and Pointers](#toc-Type-Coercion-Slices-Arrays-and-Pointers) <a href="#Type-Coercion-Slices-Arrays-and-Pointers" class="hdr">§</a>

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

// You can assign constant pointers to arrays to a slice with
// const modifier on the element type. Useful in particular for
// String literals.
test &quot;*const [N]T to []const T&quot; {
    const x1: []const u8 = &quot;hello&quot;;
    const x2: []const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, x1, x2));

    const y: []const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect(y[0] == 1.2);
}

// Likewise, it works when the destination type is an error union.
test &quot;*const [N]T to E![]const T&quot; {
    const x1: anyerror![]const u8 = &quot;hello&quot;;
    const x2: anyerror![]const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, try x1, try x2));

    const y: anyerror![]const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect((try y)[0] == 1.2);
}

// Likewise, it works when the destination type is an optional.
test &quot;*const [N]T to ?[]const T&quot; {
    const x1: ?[]const u8 = &quot;hello&quot;;
    const x2: ?[]const u8 = &amp;[5]u8{ &#39;h&#39;, &#39;e&#39;, &#39;l&#39;, &#39;l&#39;, 111 };
    try expect(std.mem.eql(u8, x1.?, x2.?));

    const y: ?[]const f32 = &amp;[2]f32{ 1.2, 3.4 };
    try expect(y.?[0] == 1.2);
}

// In this cast, the array length becomes the slice length.
test &quot;*[N]T to []T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: []u8 = &amp;buf;
    try expect(std.mem.eql(u8, x, &quot;hello&quot;));

    const buf2 = [2]f32{ 1.2, 3.4 };
    const x2: []const f32 = &amp;buf2;
    try expect(std.mem.eql(f32, x2, &amp;[2]f32{ 1.2, 3.4 }));
}

// Single-item pointers to arrays can be coerced to many-item pointers.
test &quot;*[N]T to [*]T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: [*]u8 = &amp;buf;
    try expect(x[4] == &#39;o&#39;);
    // x[5] would be an uncaught out of bounds pointer dereference!
}

// Likewise, it works when the destination type is an optional.
test &quot;*[N]T to ?[*]T&quot; {
    var buf: [5]u8 = &quot;hello&quot;.*;
    const x: ?[*]u8 = &amp;buf;
    try expect(x.?[4] == &#39;o&#39;);
}

// Single-item pointers can be cast to len-1 single-item arrays.
test &quot;*T to *[1]T&quot; {
    var x: i32 = 1234;
    const y: *[1]i32 = &amp;x;
    const z: [*]i32 = y;
    try expect(z[0] == 1234);
}

// Sentinel-terminated slices can be coerced into sentinel-terminated pointers
test &quot;[:x]T to [*:x]T&quot; {
    const buf: [:0]const u8 = &quot;hello&quot;;
    const buf2: [*:0]const u8 = buf;
    try expect(buf2[4] == &#39;o&#39;);
}</code></pre>
<figcaption>test_coerce_slices_arrays_and_pointers.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_slices_arrays_and_pointers.zig
1/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to []const T...OK
2/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to E![]const T...OK
3/8 test_coerce_slices_arrays_and_pointers.test.*const [N]T to ?[]const T...OK
4/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to []T...OK
5/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to [*]T...OK
6/8 test_coerce_slices_arrays_and_pointers.test.*[N]T to ?[*]T...OK
7/8 test_coerce_slices_arrays_and_pointers.test.*T to *[1]T...OK
8/8 test_coerce_slices_arrays_and_pointers.test.[:x]T to [*:x]T...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [C Pointers](#C-Pointers)

#### [Type Coercion: Optionals](#toc-Type-Coercion-Optionals) <a href="#Type-Coercion-Optionals" class="hdr">§</a>

The payload type of [Optionals](#Optionals), as well as [null](#null), coerce to the optional type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coerce to optionals&quot; {
    const x: ?i32 = 1234;
    const y: ?i32 = null;

    try expect(x.? == 1234);
    try expect(y == null);
}</code></pre>
<figcaption>test_coerce_optionals.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_optionals.zig
1/1 test_coerce_optionals.test.coerce to optionals...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Optionals work nested inside the [Error Union Type](#Error-Union-Type), too:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coerce to optionals wrapped in error union&quot; {
    const x: anyerror!?i32 = 1234;
    const y: anyerror!?i32 = null;

    try expect((try x).? == 1234);
    try expect((try y) == null);
}</code></pre>
<figcaption>test_coerce_optional_wrapped_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_optional_wrapped_error_union.zig
1/1 test_coerce_optional_wrapped_error_union.test.coerce to optionals wrapped in error union...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Error Unions](#toc-Type-Coercion-Error-Unions) <a href="#Type-Coercion-Error-Unions" class="hdr">§</a>

The payload type of an [Error Union Type](#Error-Union-Type) as well as the [Error Set Type](#Error-Set-Type)
coerce to the error union type:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coercion to error unions&quot; {
    const x: anyerror!i32 = 1234;
    const y: anyerror!i32 = error.Failure;

    try expect((try x) == 1234);
    try std.testing.expectError(error.Failure, y);
}</code></pre>
<figcaption>test_coerce_to_error_union.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_to_error_union.zig
1/1 test_coerce_to_error_union.test.coercion to error unions...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Compile-Time Known Numbers](#toc-Type-Coercion-Compile-Time-Known-Numbers) <a href="#Type-Coercion-Compile-Time-Known-Numbers" class="hdr">§</a>

When a number is [comptime](#comptime)-known to be representable in the destination type,
it may be coerced:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;coercing large integer type to smaller one when value is comptime-known to fit&quot; {
    const x: u64 = 255;
    const y: u8 = x;
    try expect(y == 255);
}</code></pre>
<figcaption>test_coerce_large_to_small.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_large_to_small.zig
1/1 test_coerce_large_to_small.test.coercing large integer type to smaller one when value is comptime-known to fit...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Type Coercion: Unions and Enums](#toc-Type-Coercion-Unions-and-Enums) <a href="#Type-Coercion-Unions-and-Enums" class="hdr">§</a>

Tagged unions can be coerced to enums, and enums can be coerced to tagged unions
when they are [comptime](#comptime)-known to be a field of the union that has only one possible value, such as
[void](#void):

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const E = enum {
    one,
    two,
    three,
};

const U = union(E) {
    one: i32,
    two: f32,
    three,
};

const U2 = union(enum) {
    a: void,
    b: f32,

    fn tag(self: U2) usize {
        switch (self) {
            .a =&gt; return 1,
            .b =&gt; return 2,
        }
    }
};

test &quot;coercion between unions and enums&quot; {
    const u = U{ .two = 12.34 };
    const e: E = u; // coerce union to enum
    try expect(e == E.two);

    const three = E.three;
    const u_2: U = three; // coerce enum to union
    try expect(u_2 == E.three);

    const u_3: U = .three; // coerce enum literal to union
    try expect(u_3 == E.three);

    const u_4: U2 = .a; // coerce enum literal to union with inferred enum tag type.
    try expect(u_4.tag() == 1);

    // The following example is invalid.
    // error: coercion from enum &#39;@TypeOf(.enum_literal)&#39; to union &#39;test_coerce_unions_enum.U2&#39; must initialize &#39;f32&#39; field &#39;b&#39;
    //var u_5: U2 = .b;
    //try expect(u_5.tag() == 2);
}</code></pre>
<figcaption>test_coerce_unions_enums.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_unions_enums.zig
1/1 test_coerce_unions_enums.test.coercion between unions and enums...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [union](#union)
- [enum](#enum)

#### [Type Coercion: undefined](#toc-Type-Coercion-undefined) <a href="#Type-Coercion-undefined" class="hdr">§</a>

[undefined](#undefined) can be coerced to any type.

#### [Type Coercion: Tuples to Arrays](#toc-Type-Coercion-Tuples-to-Arrays) <a href="#Type-Coercion-Tuples-to-Arrays" class="hdr">§</a>

[Tuples](#Tuples) can be coerced to arrays, if all of the fields have the same type.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Tuple = struct { u8, u8 };
test &quot;coercion from homogeneous tuple to array&quot; {
    const tuple: Tuple = .{ 5, 6 };
    const array: [2]u8 = tuple;
    _ = array;
}</code></pre>
<figcaption>test_coerce_tuples_arrays.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_coerce_tuples_arrays.zig
1/1 test_coerce_tuples_arrays.test.coercion from homogeneous tuple to array...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Explicit Casts](#toc-Explicit-Casts) <a href="#Explicit-Casts" class="hdr">§</a>

Explicit casts are performed via [Builtin Functions](#Builtin-Functions).
Some explicit casts are safe; some are not.
Some explicit casts perform language-level assertions; some do not.
Some explicit casts are no-ops at runtime; some are not.

- [@bitCast](#bitCast) - change type but maintain bit representation
- [@alignCast](#alignCast) - make a pointer have more alignment
- [@enumFromInt](#enumFromInt) - obtain an enum value based on its integer tag value
- [@errorFromInt](#errorFromInt) - obtain an error code based on its integer value
- [@errorCast](#errorCast) - convert to a smaller error set
- [@floatCast](#floatCast) - convert a larger float to a smaller float
- [@floatFromInt](#floatFromInt) - convert an integer to a float value
- [@intCast](#intCast) - convert between integer types
- [@intFromBool](#intFromBool) - convert true to 1 and false to 0
- [@intFromEnum](#intFromEnum) - obtain the integer tag value of an enum or tagged union
- [@intFromError](#intFromError) - obtain the integer value of an error code
- [@intFromFloat](#intFromFloat) - obtain the integer part of a float value
- [@intFromPtr](#intFromPtr) - obtain the address of a pointer
- [@ptrFromInt](#ptrFromInt) - convert an address to a pointer
- [@ptrCast](#ptrCast) - convert between pointer types
- [@truncate](#truncate) - convert between integer types, chopping off bits

### [Peer Type Resolution](#toc-Peer-Type-Resolution) <a href="#Peer-Type-Resolution" class="hdr">§</a>

Peer Type Resolution occurs in these places:

- [switch](#switch) expressions
- [if](#if) expressions
- [while](#while) expressions
- [for](#for) expressions
- Multiple break statements in a block
- Some [binary operations](#Table-of-Operators)

This kind of type resolution chooses a type that all peer types can coerce into. Here are
some examples:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const mem = std.mem;

test &quot;peer resolve int widening&quot; {
    const a: i8 = 12;
    const b: i16 = 34;
    const c = a + b;
    try expect(c == 46);
    try expect(@TypeOf(c) == i16);
}

test &quot;peer resolve arrays of different size to const slice&quot; {
    try expect(mem.eql(u8, boolToStr(true), &quot;true&quot;));
    try expect(mem.eql(u8, boolToStr(false), &quot;false&quot;));
    try comptime expect(mem.eql(u8, boolToStr(true), &quot;true&quot;));
    try comptime expect(mem.eql(u8, boolToStr(false), &quot;false&quot;));
}
fn boolToStr(b: bool) []const u8 {
    return if (b) &quot;true&quot; else &quot;false&quot;;
}

test &quot;peer resolve array and const slice&quot; {
    try testPeerResolveArrayConstSlice(true);
    try comptime testPeerResolveArrayConstSlice(true);
}
fn testPeerResolveArrayConstSlice(b: bool) !void {
    const value1 = if (b) &quot;aoeu&quot; else @as([]const u8, &quot;zz&quot;);
    const value2 = if (b) @as([]const u8, &quot;zz&quot;) else &quot;aoeu&quot;;
    try expect(mem.eql(u8, value1, &quot;aoeu&quot;));
    try expect(mem.eql(u8, value2, &quot;zz&quot;));
}

test &quot;peer type resolution: ?T and T&quot; {
    try expect(peerTypeTAndOptionalT(true, false).? == 0);
    try expect(peerTypeTAndOptionalT(false, false).? == 3);
    comptime {
        try expect(peerTypeTAndOptionalT(true, false).? == 0);
        try expect(peerTypeTAndOptionalT(false, false).? == 3);
    }
}
fn peerTypeTAndOptionalT(c: bool, b: bool) ?usize {
    if (c) {
        return if (b) null else @as(usize, 0);
    }

    return @as(usize, 3);
}

test &quot;peer type resolution: *[0]u8 and []const u8&quot; {
    try expect(peerTypeEmptyArrayAndSlice(true, &quot;hi&quot;).len == 0);
    try expect(peerTypeEmptyArrayAndSlice(false, &quot;hi&quot;).len == 1);
    comptime {
        try expect(peerTypeEmptyArrayAndSlice(true, &quot;hi&quot;).len == 0);
        try expect(peerTypeEmptyArrayAndSlice(false, &quot;hi&quot;).len == 1);
    }
}
fn peerTypeEmptyArrayAndSlice(a: bool, slice: []const u8) []const u8 {
    if (a) {
        return &amp;[_]u8{};
    }

    return slice[0..1];
}
test &quot;peer type resolution: *[0]u8, []const u8, and anyerror![]u8&quot; {
    {
        var data = &quot;hi&quot;.*;
        const slice = data[0..];
        try expect((try peerTypeEmptyArrayAndSliceAndError(true, slice)).len == 0);
        try expect((try peerTypeEmptyArrayAndSliceAndError(false, slice)).len == 1);
    }
    comptime {
        var data = &quot;hi&quot;.*;
        const slice = data[0..];
        try expect((try peerTypeEmptyArrayAndSliceAndError(true, slice)).len == 0);
        try expect((try peerTypeEmptyArrayAndSliceAndError(false, slice)).len == 1);
    }
}
fn peerTypeEmptyArrayAndSliceAndError(a: bool, slice: []u8) anyerror![]u8 {
    if (a) {
        return &amp;[_]u8{};
    }

    return slice[0..1];
}

test &quot;peer type resolution: *const T and ?*T&quot; {
    const a: *const usize = @ptrFromInt(0x123456780);
    const b: ?*usize = @ptrFromInt(0x123456780);
    try expect(a == b);
    try expect(b == a);
}

test &quot;peer type resolution: error union switch&quot; {
    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `if (x) {...} else |err| blk: { switch (err) {...} }` does not consider the
    // non-error and error case to be peers.
    var a: error{ A, B, C }!u32 = 0;
    _ = &amp;a;
    const b = if (a) |x|
        x + 3
    else |err| switch (err) {
        error.A =&gt; 0,
        error.B =&gt; 1,
        error.C =&gt; null,
    };
    try expect(@TypeOf(b) == ?u32);

    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `x catch |err| blk: { switch (err) {...} }` does not consider the unwrapped `x`
    // and error case to be peers.
    const c = a catch |err| switch (err) {
        error.A =&gt; 0,
        error.B =&gt; 1,
        error.C =&gt; null,
    };
    try expect(@TypeOf(c) == ?u32);
}</code></pre>
<figcaption>test_peer_type_resolution.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_peer_type_resolution.zig
1/8 test_peer_type_resolution.test.peer resolve int widening...OK
2/8 test_peer_type_resolution.test.peer resolve arrays of different size to const slice...OK
3/8 test_peer_type_resolution.test.peer resolve array and const slice...OK
4/8 test_peer_type_resolution.test.peer type resolution: ?T and T...OK
5/8 test_peer_type_resolution.test.peer type resolution: *[0]u8 and []const u8...OK
6/8 test_peer_type_resolution.test.peer type resolution: *[0]u8, []const u8, and anyerror![]u8...OK
7/8 test_peer_type_resolution.test.peer type resolution: *const T and ?*T...OK
8/8 test_peer_type_resolution.test.peer type resolution: error union switch...OK
All 8 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Zero Bit Types](#toc-Zero-Bit-Types) <a href="#Zero-Bit-Types" class="hdr">§</a>

For some types, [@sizeOf](#sizeOf) is 0:

- [void](#void)
- The [Integers](#Integers) <span class="tok-type">`u0`</span> and <span class="tok-type">`i0`</span>.
- [Arrays](#Arrays) and [Vectors](#Vectors) with len 0, or with an element type that is a zero bit type.
- An [enum](#enum) with only 1 tag.
- A [struct](#struct) with all fields being zero bit types.
- A [union](#union) with only 1 field which is a zero bit type.

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
body of `entry`, even in [Debug](#Debug) mode. For example, on x86_64:

    0000000000000010 <entry>:
      10:   55                      push   %rbp
      11:   48 89 e5                mov    %rsp,%rbp
      14:   5d                      pop    %rbp
      15:   c3                      retq   

These assembly instructions do not have any code associated with the void values -
they only perform the function call prologue and epilogue.

### [void](#toc-void) <a href="#void" class="hdr">§</a>

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

## [Result Location Semantics](#toc-Result-Location-Semantics) <a href="#Result-Location-Semantics" class="hdr">§</a>

During compilation, every Zig expression and sub-expression is assigned optional result location
information. This information dictates what type the expression should have (its result type), and
where the resulting value should be placed in memory (its result location). The information is
optional in the sense that not every expression has this information: assignment to
`_`, for instance, does not provide any information about the type of an
expression, nor does it provide a concrete memory location to place it in.

As a motivating example, consider the statement <span class="tok-kw">`const`</span>` x: `<span class="tok-type">`u32`</span>` = `<span class="tok-number">`42`</span>`;`. The type
annotation here provides a result type of <span class="tok-type">`u32`</span> to the initialization expression
<span class="tok-number">`42`</span>, instructing the compiler to coerce this integer (initially of type
<span class="tok-type">`comptime_int`</span>) to this type. We will see more examples shortly.

This is not an implementation detail: the logic outlined above is codified into the Zig language
specification, and is the primary mechanism of type inference in the language. This system is
collectively referred to as "Result Location Semantics".

### [Result Types](#toc-Result-Types) <a href="#Result-Types" class="hdr">§</a>

Result types are propagated recursively through expressions where possible. For instance, if the
expression `&e` has result type `*`<span class="tok-type">`u32`</span>, then
`e` is given a result type of <span class="tok-type">`u32`</span>, allowing the
language to perform this coercion before taking a reference.

The result type mechanism is utilized by casting builtins such as <span class="tok-builtin">`@intCast`</span>.
Rather than taking as an argument the type to cast to, these builtins use their result type to
determine this information. The result type is often known from context; where it is not, the
<span class="tok-builtin">`@as`</span> builtin can be used to explicitly provide a result type.

We can break down the result types for each component of a simple expression as follows:

<figure>
<pre><code>const expectEqual = @import(&quot;std&quot;).testing.expectEqual;
test &quot;result type propagates through struct initializer&quot; {
    const S = struct { x: u32 };
    const val: u64 = 123;
    const s: S = .{ .x = @intCast(val) };
    // .{ .x = @intCast(val) }   has result type `S` due to the type annotation
    //         @intCast(val)     has result type `u32` due to the type of the field `S.x`
    //                  val      has no result type, as it is permitted to be any integer type
    try expectEqual(@as(u32, 123), s.x);
}</code></pre>
<figcaption>result_type_propagation.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test result_type_propagation.zig
1/1 result_type_propagation.test.result type propagates through struct initializer...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This result type information is useful for the aforementioned cast builtins, as well as to avoid
the construction of pre-coercion values, and to avoid the need for explicit type coercions in some
cases. The following table details how some common expressions propagate result types, where
`x` and `y` are arbitrary sub-expressions.

<div class="table-wrapper">

| Expression | Parent Result Type | Sub-expression Result Type |
|----|----|----|
| <span class="tok-kw">`const`</span>` val: T = x` | \- | `x` is a `T` |
| <span class="tok-kw">`var`</span>` val: T = x` | \- | `x` is a `T` |
| `val = x` | \- | `x` is a <span class="tok-builtin">`@TypeOf`</span>`(val)` |
| <span class="tok-builtin">`@as`</span>`(T, x)` | \- | `x` is a `T` |
| `&x` | `*T` | `x` is a `T` |
| `&x` | `[]T` | `x` is some array of `T` |
| `f(x)` | \- | `x` has the type of the first parameter of `f` |
| `.{x}` | `T` | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"0"`</span>`)` |
| `.{ .a = x }` | `T` | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"a"`</span>`)` |
| `T{x}` | \- | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"0"`</span>`)` |
| `T{ .a = x }` | \- | `x` is a <span class="tok-builtin">`@FieldType`</span>`(T, `<span class="tok-str">`"a"`</span>`)` |
| <span class="tok-builtin">`@Type`</span>`(x)` | \- | `x` is a `std.builtin.Type` |
| <span class="tok-builtin">`@typeInfo`</span>`(x)` | \- | `x` is a <span class="tok-type">`type`</span> |
| `x << y` | \- | `y` is a `std.math.Log2IntCeil(`<span class="tok-builtin">`@TypeOf`</span>`(x))` |

</div>

### [Result Locations](#toc-Result-Locations) <a href="#Result-Locations" class="hdr">§</a>

In addition to result type information, every expression may be optionally assigned a result
location: a pointer to which the value must be directly written. This system can be used to prevent
intermediate copies when initializing data structures, which can be important for types which must
have a fixed memory address ("pinned" types).

When compiling the simple assignment expression `x = e`, many languages would
create the temporary value `e` on the stack, and then assign it to
`x`, potentially performing a type coercion in the process. Zig approaches this
differently. The expression `e` is given a result type matching the type of
`x`, and a result location of `&x`. For many syntactic
forms of `e`, this has no practical impact. However, it can have important
semantic effects when working with more complex syntax forms.

For instance, if the expression `.{ .a = x, .b = y }` has a result location of
`ptr`, then `x` is given a result location of
`&ptr.a`, and `y` a result location of `&ptr.b`.
Without this system, this expression would construct a temporary struct value entirely on the stack, and
only then copy it to the destination address. In essence, Zig desugars the assignment
`foo = .{ .a = x, .b = y }` to the two statements `foo.a = x; foo.b = y;`.

This can sometimes be important when assigning an aggregate value where the initialization
expression depends on the previous value of the aggregate. The easiest way to demonstrate this is by
attempting to swap fields of a struct or array - the following logic looks sound, but in fact is not:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;
test &quot;attempt to swap array elements with array initializer&quot; {
    var arr: [2]u32 = .{ 1, 2 };
    arr = .{ arr[1], arr[0] };
    // The previous line is equivalent to the following two lines:
    //   arr[0] = arr[1];
    //   arr[1] = arr[0];
    // So this fails!
    try expect(arr[0] == 2); // succeeds
    try expect(arr[1] == 1); // fails
}</code></pre>
<figcaption>result_location_interfering_with_swap.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test result_location_interfering_with_swap.zig
1/1 result_location_interfering_with_swap.test.attempt to swap array elements with array initializer...FAIL (TestUnexpectedResult)
/home/andy/dev/zig/lib/std/testing.zig:607:14: 0x102f019 in expect (std.zig)
    if (!ok) return error.TestUnexpectedResult;
             ^
/home/andy/dev/zig/doc/langref/result_location_interfering_with_swap.zig:10:5: 0x102f144 in test.attempt to swap array elements with array initializer (result_location_interfering_with_swap.zig)
    try expect(arr[1] == 1); // fails
    ^
0 passed; 0 skipped; 1 failed.
error: the following test command failed with exit code 1:
/home/andy/dev/zig/.zig-cache/o/a8056b54531d62dabec9b7d39a01cdc4/test --seed=0x22452da4</code></pre>
<figcaption>Shell</figcaption>
</figure>

The following table details how some common expressions propagate result locations, where
`x` and `y` are arbitrary sub-expressions. Note that
some expressions cannot provide meaningful result locations to sub-expressions, even if they
themselves have a result location.

<div class="table-wrapper">

| Expression | Result Location | Sub-expression Result Locations |
|----|----|----|
| <span class="tok-kw">`const`</span>` val: T = x` | \- | `x` has result location `&val` |
| <span class="tok-kw">`var`</span>` val: T = x` | \- | `x` has result location `&val` |
| `val = x` | \- | `x` has result location `&val` |
| <span class="tok-builtin">`@as`</span>`(T, x)` | `ptr` | `x` has no result location |
| `&x` | `ptr` | `x` has no result location |
| `f(x)` | `ptr` | `x` has no result location |
| `.{x}` | `ptr` | `x` has result location `&ptr[`<span class="tok-number">`0`</span>`]` |
| `.{ .a = x }` | `ptr` | `x` has result location `&ptr.a` |
| `T{x}` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| `T{ .a = x }` | `ptr` | `x` has no result location (typed initializers do not propagate result locations) |
| <span class="tok-builtin">`@Type`</span>`(x)` | `ptr` | `x` has no result location |
| <span class="tok-builtin">`@typeInfo`</span>`(x)` | `ptr` | `x` has no result location |
| `x << y` | `ptr` | `x` and `y` do not have result locations |

</div>

## [comptime](#toc-comptime) <a href="#comptime" class="hdr">§</a>

Zig places importance on the concept of whether an expression is known at compile-time.
There are a few different places this concept is used, and these building blocks are used
to keep the language small, readable, and powerful.

### [Introducing the Compile-Time Concept](#toc-Introducing-the-Compile-Time-Concept) <a href="#Introducing-the-Compile-Time-Concept" class="hdr">§</a>

#### [Compile-Time Parameters](#toc-Compile-Time-Parameters) <a href="#Compile-Time-Parameters" class="hdr">§</a>

Compile-time parameters is how Zig implements generics. It is compile-time duck typing.

<figure>
<pre><code>fn max(comptime T: type, a: T, b: T) T {
    return if (a &gt; b) a else b;
}
fn gimmeTheBiggerFloat(a: f32, b: f32) f32 {
    return max(f32, a, b);
}
fn gimmeTheBiggerInteger(a: u64, b: u64) u64 {
    return max(u64, a, b);
}</code></pre>
<figcaption>compile-time_duck_typing.zig</figcaption>
</figure>

In Zig, types are first-class citizens. They can be assigned to variables, passed as parameters to functions,
and returned from functions. However, they can only be used in expressions which are known at *compile-time*,
which is why the parameter `T` in the above snippet must be marked with <span class="tok-kw">`comptime`</span>.

A <span class="tok-kw">`comptime`</span> parameter means that:

- At the callsite, the value must be known at compile-time, or it is a compile error.
- In the function definition, the value is known at compile-time.

For example, if we were to introduce another function to the above snippet:

<figure>
<pre><code>fn max(comptime T: type, a: T, b: T) T {
    return if (a &gt; b) a else b;
}
test &quot;try to pass a runtime type&quot; {
    foo(false);
}
fn foo(condition: bool) void {
    const result = max(if (condition) f32 else u64, 1234, 5678);
    _ = result;
}</code></pre>
<figcaption>test_unresolved_comptime_value.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_unresolved_comptime_value.zig
/home/andy/dev/zig/doc/langref/test_unresolved_comptime_value.zig:8:28: error: unable to resolve comptime value
    const result = max(if (condition) f32 else u64, 1234, 5678);
                           ^~~~~~~~~
/home/andy/dev/zig/doc/langref/test_unresolved_comptime_value.zig:8:24: note: argument to comptime parameter must be comptime-known
    const result = max(if (condition) f32 else u64, 1234, 5678);
                       ^~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_unresolved_comptime_value.zig:1:8: note: parameter declared comptime here
fn max(comptime T: type, a: T, b: T) T {
       ^~~~~~~~
referenced by:
    test.try to pass a runtime type: /home/andy/dev/zig/doc/langref/test_unresolved_comptime_value.zig:5:8
</code></pre>
<figcaption>Shell</figcaption>
</figure>

This is an error because the programmer attempted to pass a value only known at run-time
to a function which expects a value known at compile-time.

Another way to get an error is if we pass a type that violates the type checker when the
function is analyzed. This is what it means to have *compile-time duck typing*.

For example:

<figure>
<pre><code>fn max(comptime T: type, a: T, b: T) T {
    return if (a &gt; b) a else b;
}
test &quot;try to compare bools&quot; {
    _ = max(bool, true, false);
}</code></pre>
<figcaption>test_comptime_mismatched_type.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_mismatched_type.zig
/home/andy/dev/zig/doc/langref/test_comptime_mismatched_type.zig:2:18: error: operator &gt; not allowed for type &#39;bool&#39;
    return if (a &gt; b) a else b;
               ~~^~~
referenced by:
    test.try to compare bools: /home/andy/dev/zig/doc/langref/test_comptime_mismatched_type.zig:5:12
</code></pre>
<figcaption>Shell</figcaption>
</figure>

On the flip side, inside the function definition with the <span class="tok-kw">`comptime`</span> parameter, the
value is known at compile-time. This means that we actually could make this work for the bool type
if we wanted to:

<figure>
<pre><code>fn max(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a &gt; b) {
        return a;
    } else {
        return b;
    }
}
test &quot;try to compare bools&quot; {
    try @import(&quot;std&quot;).testing.expect(max(bool, false, true) == true);
}</code></pre>
<figcaption>test_comptime_max_with_bool.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_max_with_bool.zig
1/1 test_comptime_max_with_bool.test.try to compare bools...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This works because Zig implicitly inlines <span class="tok-kw">`if`</span> expressions when the condition
is known at compile-time, and the compiler guarantees that it will skip analysis of
the branch not taken.

This means that the actual function generated for `max` in this situation looks like
this:

<figure>
<pre><code>fn max(a: bool, b: bool) bool {
    {
        return a or b;
    }
}</code></pre>
<figcaption>compiler_generated_function.zig</figcaption>
</figure>

All the code that dealt with compile-time known values is eliminated and we are left with only
the necessary run-time code to accomplish the task.

This works the same way for <span class="tok-kw">`switch`</span> expressions - they are implicitly inlined
when the target expression is compile-time known.

#### [Compile-Time Variables](#toc-Compile-Time-Variables) <a href="#Compile-Time-Variables" class="hdr">§</a>

In Zig, the programmer can label variables as <span class="tok-kw">`comptime`</span>. This guarantees to the compiler
that every load and store of the variable is performed at compile-time. Any violation of this results in a
compile error.

This combined with the fact that we can <span class="tok-kw">`inline`</span> loops allows us to write
a function which is partially evaluated at compile-time and partially at run-time.

For example:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

const CmdFn = struct {
    name: []const u8,
    func: fn (i32) i32,
};

const cmd_fns = [_]CmdFn{
    CmdFn{ .name = &quot;one&quot;, .func = one },
    CmdFn{ .name = &quot;two&quot;, .func = two },
    CmdFn{ .name = &quot;three&quot;, .func = three },
};
fn one(value: i32) i32 {
    return value + 1;
}
fn two(value: i32) i32 {
    return value + 2;
}
fn three(value: i32) i32 {
    return value + 3;
}

fn performFn(comptime prefix_char: u8, start_value: i32) i32 {
    var result: i32 = start_value;
    comptime var i = 0;
    inline while (i &lt; cmd_fns.len) : (i += 1) {
        if (cmd_fns[i].name[0] == prefix_char) {
            result = cmd_fns[i].func(result);
        }
    }
    return result;
}

test &quot;perform fn&quot; {
    try expect(performFn(&#39;t&#39;, 1) == 6);
    try expect(performFn(&#39;o&#39;, 0) == 1);
    try expect(performFn(&#39;w&#39;, 99) == 99);
}</code></pre>
<figcaption>test_comptime_evaluation.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_evaluation.zig
1/1 test_comptime_evaluation.test.perform fn...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

This example is a bit contrived, because the compile-time evaluation component is unnecessary;
this code would work fine if it was all done at run-time. But it does end up generating
different code. In this example, the function `performFn` is generated three different times,
for the different values of `prefix_char` provided:

<figure>
<pre><code>// From the line:
// expect(performFn(&#39;t&#39;, 1) == 6);
fn performFn(start_value: i32) i32 {
    var result: i32 = start_value;
    result = two(result);
    result = three(result);
    return result;
}</code></pre>
<figcaption>performFn_1</figcaption>
</figure>

<figure>
<pre><code>// From the line:
// expect(performFn(&#39;o&#39;, 0) == 1);
fn performFn(start_value: i32) i32 {
    var result: i32 = start_value;
    result = one(result);
    return result;
}</code></pre>
<figcaption>performFn_2</figcaption>
</figure>

<figure>
<pre><code>// From the line:
// expect(performFn(&#39;w&#39;, 99) == 99);
fn performFn(start_value: i32) i32 {
    var result: i32 = start_value;
    _ = &amp;result;
    return result;
}</code></pre>
<figcaption>performFn_3</figcaption>
</figure>

Note that this happens even in a debug build.
This is not a way to write more optimized code, but it is a way to make sure that what *should* happen
at compile-time, *does* happen at compile-time. This catches more errors and allows expressiveness
that in other languages requires using macros, generated code, or a preprocessor to accomplish.

#### [Compile-Time Expressions](#toc-Compile-Time-Expressions) <a href="#Compile-Time-Expressions" class="hdr">§</a>

In Zig, it matters whether a given expression is known at compile-time or run-time. A programmer can
use a <span class="tok-kw">`comptime`</span> expression to guarantee that the expression will be evaluated at compile-time.
If this cannot be accomplished, the compiler will emit an error. For example:

<figure>
<pre><code>extern fn exit() noreturn;

test &quot;foo&quot; {
    comptime {
        exit();
    }
}</code></pre>
<figcaption>test_comptime_call_extern_function.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_call_extern_function.zig
/home/andy/dev/zig/doc/langref/test_comptime_call_extern_function.zig:5:13: error: comptime call of extern function
        exit();
        ~~~~^~
/home/andy/dev/zig/doc/langref/test_comptime_call_extern_function.zig:4:5: note: &#39;comptime&#39; keyword forces comptime evaluation
    comptime {
    ^~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

It doesn't make sense that a program could call `exit()` (or any other external function)
at compile-time, so this is a compile error. However, a <span class="tok-kw">`comptime`</span> expression does much
more than sometimes cause a compile error.

Within a <span class="tok-kw">`comptime`</span> expression:

- All variables are <span class="tok-kw">`comptime`</span> variables.
- All <span class="tok-kw">`if`</span>, <span class="tok-kw">`while`</span>, <span class="tok-kw">`for`</span>, and <span class="tok-kw">`switch`</span>
  expressions are evaluated at compile-time, or emit a compile error if this is not possible.
- All <span class="tok-kw">`return`</span> and <span class="tok-kw">`try`</span> expressions are invalid (unless the function itself is called at compile-time).
- All code with runtime side effects or depending on runtime values emits a compile error.
- All function calls cause the compiler to interpret the function at compile-time, emitting a
  compile error if the function tries to do something that has global runtime side effects.

This means that a programmer can create a function which is called both at compile-time and run-time, with
no modification to the function required.

Let's look at an example:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

fn fibonacci(index: u32) u32 {
    if (index &lt; 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test &quot;fibonacci&quot; {
    // test fibonacci at run-time
    try expect(fibonacci(7) == 13);

    // test fibonacci at compile-time
    try comptime expect(fibonacci(7) == 13);
}</code></pre>
<figcaption>test_fibonacci_recursion.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fibonacci_recursion.zig
1/1 test_fibonacci_recursion.test.fibonacci...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Imagine if we had forgotten the base case of the recursive function and tried to run the tests:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

fn fibonacci(index: u32) u32 {
    //if (index &lt; 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test &quot;fibonacci&quot; {
    try comptime expect(fibonacci(7) == 13);
}</code></pre>
<figcaption>test_fibonacci_comptime_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fibonacci_comptime_overflow.zig
/home/andy/dev/zig/doc/langref/test_fibonacci_comptime_overflow.zig:5:28: error: overflow of integer type &#39;u32&#39; with value &#39;-1&#39;
    return fibonacci(index - 1) + fibonacci(index - 2);
                     ~~~~~~^~~
/home/andy/dev/zig/doc/langref/test_fibonacci_comptime_overflow.zig:5:21: note: called at comptime here (7 times)
    return fibonacci(index - 1) + fibonacci(index - 2);
           ~~~~~~~~~^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_fibonacci_comptime_overflow.zig:9:34: note: called at comptime here
    try comptime expect(fibonacci(7) == 13);
                        ~~~~~~~~~^~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

The compiler produces an error which is a stack trace from trying to evaluate the
function at compile-time.

Luckily, we used an unsigned integer, and so when we tried to subtract 1 from 0, it triggered
[Illegal Behavior](#Illegal-Behavior), which is always a compile error if the compiler knows it happened.
But what would have happened if we used a signed integer?

<figure>
<pre><code>const assert = @import(&quot;std&quot;).debug.assert;

fn fibonacci(index: i32) i32 {
    //if (index &lt; 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test &quot;fibonacci&quot; {
    try comptime assert(fibonacci(7) == 13);
}</code></pre>
<figcaption>fibonacci_comptime_infinite_recursion.zig</figcaption>
</figure>

The compiler is supposed to notice that evaluating this function at
compile-time took more than 1000 branches, and thus emits an error and
gives up. If the programmer wants to increase the budget for compile-time
computation, they can use a built-in function called
[@setEvalBranchQuota](#setEvalBranchQuota) to change the default number 1000 to
something else.

However, there is a [design
flaw in the compiler](https://github.com/ziglang/zig/issues/13724) causing it to stack overflow instead of having the proper
behavior here. I'm terribly sorry about that. I hope to get this resolved
before the next release.

What if we fix the base case, but put the wrong value in the
`expect` line?

<figure>
<pre><code>const assert = @import(&quot;std&quot;).debug.assert;

fn fibonacci(index: i32) i32 {
    if (index &lt; 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test &quot;fibonacci&quot; {
    try comptime assert(fibonacci(7) == 99999);
}</code></pre>
<figcaption>test_fibonacci_comptime_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_fibonacci_comptime_unreachable.zig
/home/andy/dev/zig/lib/std/debug.zig:559:14: error: reached unreachable code
    if (!ok) unreachable; // assertion failure
             ^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_fibonacci_comptime_unreachable.zig:9:24: note: called at comptime here
    try comptime assert(fibonacci(7) == 99999);
                 ~~~~~~^~~~~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At [container](#Containers) level (outside of any function), all expressions are implicitly
<span class="tok-kw">`comptime`</span> expressions. This means that we can use functions to
initialize complex static data. For example:

<figure>
<pre><code>const first_25_primes = firstNPrimes(25);
const sum_of_first_25_primes = sum(&amp;first_25_primes);

fn firstNPrimes(comptime n: usize) [n]i32 {
    var prime_list: [n]i32 = undefined;
    var next_index: usize = 0;
    var test_number: i32 = 2;
    while (next_index &lt; prime_list.len) : (test_number += 1) {
        var test_prime_index: usize = 0;
        var is_prime = true;
        while (test_prime_index &lt; next_index) : (test_prime_index += 1) {
            if (test_number % prime_list[test_prime_index] == 0) {
                is_prime = false;
                break;
            }
        }
        if (is_prime) {
            prime_list[next_index] = test_number;
            next_index += 1;
        }
    }
    return prime_list;
}

fn sum(numbers: []const i32) i32 {
    var result: i32 = 0;
    for (numbers) |x| {
        result += x;
    }
    return result;
}

test &quot;variable values&quot; {
    try @import(&quot;std&quot;).testing.expect(sum_of_first_25_primes == 1060);
}</code></pre>
<figcaption>test_container-level_comptime_expressions.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_container-level_comptime_expressions.zig
1/1 test_container-level_comptime_expressions.test.variable values...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When we compile this program, Zig generates the constants
with the answer pre-computed. Here are the lines from the generated LLVM IR:

``` llvm
@0 = internal unnamed_addr constant [25 x i32] [i32 2, i32 3, i32 5, i32 7, i32 11, i32 13, i32 17, i32 19, i32 23, i32 29, i32 31, i32 37, i32 41, i32 43, i32 47, i32 53, i32 59, i32 61, i32 67, i32 71, i32 73, i32 79, i32 83, i32 89, i32 97]
@1 = internal unnamed_addr constant i32 1060
```

Note that we did not have to do anything special with the syntax of these functions. For example,
we could call the `sum` function as is with a slice of numbers whose length and values were
only known at run-time.

### [Generic Data Structures](#toc-Generic-Data-Structures) <a href="#Generic-Data-Structures" class="hdr">§</a>

Zig uses comptime capabilities to implement generic data structures without introducing any
special-case syntax.

Here is an example of a generic `List` data structure.

<figure>
<pre><code>fn List(comptime T: type) type {
    return struct {
        items: []T,
        len: usize,
    };
}

// The generic List data structure can be instantiated by passing in a type:
var buffer: [10]i32 = undefined;
var list = List(i32){
    .items = &amp;buffer,
    .len = 0,
};</code></pre>
<figcaption>generic_data_structure.zig</figcaption>
</figure>

That's it. It's a function that returns an anonymous <span class="tok-kw">`struct`</span>.
For the purposes of error messages and debugging, Zig infers the name
<span class="tok-str">`"List(i32)"`</span> from the function name and parameters invoked when creating
the anonymous struct.

To explicitly give a type a name, we assign it to a constant.

<figure>
<pre><code>const Node = struct {
    next: ?*Node,
    name: []const u8,
};

var node_a = Node{
    .next = null,
    .name = &quot;Node A&quot;,
};

var node_b = Node{
    .next = &amp;node_a,
    .name = &quot;Node B&quot;,
};</code></pre>
<figcaption>anonymous_struct_name.zig</figcaption>
</figure>

In this example, the `Node` struct refers to itself.
This works because all top level declarations are order-independent.
As long as the compiler can determine the size of the struct, it is free to refer to itself.
In this case, `Node` refers to itself as a pointer, which has a
well-defined size at compile time, so it works fine.

### [Case Study: print in Zig](#toc-Case-Study-print-in-Zig) <a href="#Case-Study-print-in-Zig" class="hdr">§</a>

Putting all of this together, let's see how `print` works in Zig.

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

const a_number: i32 = 1234;
const a_string = &quot;foobar&quot;;

pub fn main() void {
    print(&quot;here is a string: &#39;{s}&#39; here is a number: {}\n&quot;, .{ a_string, a_number });
}</code></pre>
<figcaption>print.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe print.zig
$ ./print
here is a string: &#39;foobar&#39; here is a number: 1234</code></pre>
<figcaption>Shell</figcaption>
</figure>

Let's crack open the implementation of this and see how it works:

<figure>
<pre><code>const Writer = struct {
    /// Calls print and then flushes the buffer.
    pub fn print(self: *Writer, comptime format: []const u8, args: anytype) anyerror!void {
        const State = enum {
            start,
            open_brace,
            close_brace,
        };

        comptime var start_index: usize = 0;
        comptime var state = State.start;
        comptime var next_arg: usize = 0;

        inline for (format, 0..) |c, i| {
            switch (state) {
                State.start =&gt; switch (c) {
                    &#39;{&#39; =&gt; {
                        if (start_index &lt; i) try self.write(format[start_index..i]);
                        state = State.open_brace;
                    },
                    &#39;}&#39; =&gt; {
                        if (start_index &lt; i) try self.write(format[start_index..i]);
                        state = State.close_brace;
                    },
                    else =&gt; {},
                },
                State.open_brace =&gt; switch (c) {
                    &#39;{&#39; =&gt; {
                        state = State.start;
                        start_index = i;
                    },
                    &#39;}&#39; =&gt; {
                        try self.printValue(args[next_arg]);
                        next_arg += 1;
                        state = State.start;
                        start_index = i + 1;
                    },
                    &#39;s&#39; =&gt; {
                        continue;
                    },
                    else =&gt; @compileError(&quot;Unknown format character: &quot; ++ [1]u8{c}),
                },
                State.close_brace =&gt; switch (c) {
                    &#39;}&#39; =&gt; {
                        state = State.start;
                        start_index = i;
                    },
                    else =&gt; @compileError(&quot;Single &#39;}&#39; encountered in format string&quot;),
                },
            }
        }
        comptime {
            if (args.len != next_arg) {
                @compileError(&quot;Unused arguments&quot;);
            }
            if (state != State.start) {
                @compileError(&quot;Incomplete format string: &quot; ++ format);
            }
        }
        if (start_index &lt; format.len) {
            try self.write(format[start_index..format.len]);
        }
        try self.flush();
    }

    fn write(self: *Writer, value: []const u8) !void {
        _ = self;
        _ = value;
    }
    pub fn printValue(self: *Writer, value: anytype) !void {
        _ = self;
        _ = value;
    }
    fn flush(self: *Writer) !void {
        _ = self;
    }
};</code></pre>
<figcaption>poc_print_fn.zig</figcaption>
</figure>

This is a proof of concept implementation; the actual function in the standard library has more
formatting capabilities.

Note that this is not hard-coded into the Zig compiler; this is userland code in the standard library.

When this function is analyzed from our example code above, Zig partially evaluates the function
and emits a function that actually looks like this:

<figure>
<pre><code>pub fn print(self: *Writer, arg0: []const u8, arg1: i32) !void {
    try self.write(&quot;here is a string: &#39;&quot;);
    try self.printValue(arg0);
    try self.write(&quot;&#39; here is a number: &quot;);
    try self.printValue(arg1);
    try self.write(&quot;\n&quot;);
    try self.flush();
}</code></pre>
<figcaption>Emitted print Function</figcaption>
</figure>

`printValue` is a function that takes a parameter of any type, and does different things depending
on the type:

<figure>
<pre><code>const Writer = struct {
    pub fn printValue(self: *Writer, value: anytype) !void {
        switch (@typeInfo(@TypeOf(value))) {
            .int =&gt; {
                return self.writeInt(value);
            },
            .float =&gt; {
                return self.writeFloat(value);
            },
            .pointer =&gt; {
                return self.write(value);
            },
            else =&gt; {
                @compileError(&quot;Unable to print type &#39;&quot; ++ @typeName(@TypeOf(value)) ++ &quot;&#39;&quot;);
            },
        }
    }

    fn write(self: *Writer, value: []const u8) !void {
        _ = self;
        _ = value;
    }
    fn writeInt(self: *Writer, value: anytype) !void {
        _ = self;
        _ = value;
    }
    fn writeFloat(self: *Writer, value: anytype) !void {
        _ = self;
        _ = value;
    }
};</code></pre>
<figcaption>poc_printValue_fn.zig</figcaption>
</figure>

And now, what happens if we give too many arguments to `print`?

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

const a_number: i32 = 1234;
const a_string = &quot;foobar&quot;;

test &quot;print too many arguments&quot; {
    print(&quot;here is a string: &#39;{s}&#39; here is a number: {}\n&quot;, .{
        a_string,
        a_number,
        a_number,
    });
}</code></pre>
<figcaption>test_print_too_many_args.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_print_too_many_args.zig
/home/andy/dev/zig/lib/std/Io/Writer.zig:717:18: error: unused argument in &#39;here is a string: &#39;{s}&#39; here is a number: {}
                                                        &#39;
            1 =&gt; @compileError(&quot;unused argument in &#39;&quot; ++ fmt ++ &quot;&#39;&quot;),
                 ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    print__anon_454: /home/andy/dev/zig/lib/std/debug.zig:231:23
    test.print too many arguments: /home/andy/dev/zig/doc/langref/test_print_too_many_args.zig:7:10
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Zig gives programmers the tools needed to protect themselves against their own mistakes.

Zig doesn't care whether the format argument is a string literal,
only that it is a compile-time known value that can be coerced to a `[]`<span class="tok-kw">`const`</span>` `<span class="tok-type">`u8`</span>:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

const a_number: i32 = 1234;
const a_string = &quot;foobar&quot;;
const fmt = &quot;here is a string: &#39;{s}&#39; here is a number: {}\n&quot;;

pub fn main() void {
    print(fmt, .{ a_string, a_number });
}</code></pre>
<figcaption>print_comptime-known_format.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe print_comptime-known_format.zig
$ ./print_comptime-known_format
here is a string: &#39;foobar&#39; here is a number: 1234</code></pre>
<figcaption>Shell</figcaption>
</figure>

This works fine.

Zig does not special case string formatting in the compiler and instead exposes enough power to accomplish this
task in userland. It does so without introducing another language on top of Zig, such as
a macro language or a preprocessor language. It's Zig all the way down.

See also:

- [inline while](#inline-while)
- [inline for](#inline-for)

## [Assembly](#toc-Assembly) <a href="#Assembly" class="hdr">§</a>

For some use cases, it may be necessary to directly control the machine code generated
by Zig programs, rather than relying on Zig's code generation. For these cases, one
can use inline assembly. Here is an example of implementing Hello, World on x86_64 Linux
using inline assembly:

<figure>
<pre><code>pub fn main() noreturn {
    const msg = &quot;hello world\n&quot;;
    _ = syscall3(SYS_write, STDOUT_FILENO, @intFromPtr(msg), msg.len);
    _ = syscall1(SYS_exit, 0);
    unreachable;
}

pub const SYS_write = 1;
pub const SYS_exit = 60;

pub const STDOUT_FILENO = 1;

pub fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile (&quot;syscall&quot;
        : [ret] &quot;={rax}&quot; (-&gt; usize),
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
        : .{ .rcx = true, .r11 = true });
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile (&quot;syscall&quot;
        : [ret] &quot;={rax}&quot; (-&gt; usize),
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
          [arg2] &quot;{rsi}&quot; (arg2),
          [arg3] &quot;{rdx}&quot; (arg3),
        : .{ .rcx = true, .r11 = true });
}</code></pre>
<figcaption>inline_assembly.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe inline_assembly.zig -target x86_64-linux
$ ./inline_assembly
hello world</code></pre>
<figcaption>Shell</figcaption>
</figure>

Dissecting the syntax:

<figure>
<pre><code>pub fn syscall1(number: usize, arg1: usize) usize {
    // Inline assembly is an expression which returns a value.
    // the `asm` keyword begins the expression.
    return asm
    // `volatile` is an optional modifier that tells Zig this
    // inline assembly expression has side-effects. Without
    // `volatile`, Zig is allowed to delete the inline assembly
    // code if the result is unused.
    volatile (
    // Next is a comptime string which is the assembly code.
    // Inside this string one may use `%[ret]`, `%[number]`,
    // or `%[arg1]` where a register is expected, to specify
    // the register that Zig uses for the argument or return value,
    // if the register constraint strings are used. However in
    // the below code, this is not used. A literal `%` can be
    // obtained by escaping it with a double percent: `%%`.
    // Often multiline string syntax comes in handy here.
        \\syscall
        // Next is the output. It is possible in the future Zig will
        // support multiple outputs, depending on how
        // https://github.com/ziglang/zig/issues/215 is resolved.
        // It is allowed for there to be no outputs, in which case
        // this colon would be directly followed by the colon for the inputs.
        :
        // This specifies the name to be used in `%[ret]` syntax in
        // the above assembly string. This example does not use it,
        // but the syntax is mandatory.
          [ret]
          // Next is the output constraint string. This feature is still
          // considered unstable in Zig, and so LLVM/GCC documentation
          // must be used to understand the semantics.
          // http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string
          // https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html
          // In this example, the constraint string means &quot;the result value of
          // this inline assembly instruction is whatever is in $rax&quot;.
          &quot;={rax}&quot;
          // Next is either a value binding, or `-&gt;` and then a type. The
          // type is the result type of the inline assembly expression.
          // If it is a value binding, then `%[ret]` syntax would be used
          // to refer to the register bound to the value.
          (-&gt; usize),
          // Next is the list of inputs.
          // The constraint for these inputs means, &quot;when the assembly code is
          // executed, $rax shall have the value of `number` and $rdi shall have
          // the value of `arg1`&quot;. Any number of input parameters is allowed,
          // including none.
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
          // Next is the list of clobbers. These declare a set of registers whose
          // values will not be preserved by the execution of this assembly code.
          // These do not include output or input registers. The special clobber
          // value of &quot;memory&quot; means that the assembly writes to arbitrary undeclared
          // memory locations - not only the memory pointed to by a declared indirect
          // output. In this example we list $rcx and $r11 because it is known the
          // kernel syscall does not preserve these registers.
        : .{ .rcx = true, .r11 = true });
}</code></pre>
<figcaption>Assembly Syntax Explained.zig</figcaption>
</figure>

For x86 and x86_64 targets, the syntax is AT&T syntax, rather than the more
popular Intel syntax. This is due to technical constraints; assembly parsing is
provided by LLVM and its support for Intel syntax is buggy and not well tested.

Some day Zig may have its own assembler. This would allow it to integrate more seamlessly
into the language, as well as be compatible with the popular NASM syntax. This documentation
section will be updated before 1.0.0 is released, with a conclusive statement about the status
of AT&T vs Intel/NASM syntax.

### [Output Constraints](#toc-Output-Constraints) <a href="#Output-Constraints" class="hdr">§</a>

Output constraints are still considered to be unstable in Zig, and
so
[LLVM documentation](http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string)
and
[GCC documentation](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html)
must be used to understand the semantics.

Note that some breaking changes to output constraints are planned with
[issue \#215](https://github.com/ziglang/zig/issues/215).

### [Input Constraints](#toc-Input-Constraints) <a href="#Input-Constraints" class="hdr">§</a>

Input constraints are still considered to be unstable in Zig, and
so
[LLVM documentation](http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string)
and
[GCC documentation](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html)
must be used to understand the semantics.

Note that some breaking changes to input constraints are planned with
[issue \#215](https://github.com/ziglang/zig/issues/215).

### [Clobbers](#toc-Clobbers) <a href="#Clobbers" class="hdr">§</a>

Clobbers are the set of registers whose values will not be preserved by the execution of
the assembly code. These do not include output or input registers. The special clobber
value of <span class="tok-str">`"memory"`</span> means that the assembly causes writes to
arbitrary undeclared memory locations - not only the memory pointed to by a declared
indirect output.

Failure to declare the full set of clobbers for a given inline assembly
expression is unchecked [Illegal Behavior](#Illegal-Behavior).

### [Global Assembly](#toc-Global-Assembly) <a href="#Global-Assembly" class="hdr">§</a>

When an assembly expression occurs in a [container](#Containers) level [comptime](#comptime) block, this is
**global assembly**.

This kind of assembly has different rules than inline assembly. First, <span class="tok-kw">`volatile`</span>
is not valid because all global assembly is unconditionally included.
Second, there are no inputs, outputs, or clobbers. All global assembly is concatenated
verbatim into one long string and assembled together. There are no template substitution rules regarding
`%` as there are in inline assembly expressions.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

comptime {
    asm (
        \\.global my_func;
        \\.type my_func, @function;
        \\my_func:
        \\  lea (%rdi,%rsi,1),%eax
        \\  retq
    );
}

extern fn my_func(a: i32, b: i32) i32;

test &quot;global assembly&quot; {
    try expect(my_func(12, 34) == 46);
}</code></pre>
<figcaption>test_global_assembly.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_global_assembly.zig -target x86_64-linux -fllvm
1/1 test_global_assembly.test.global assembly...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Atomics](#toc-Atomics) <a href="#Atomics" class="hdr">§</a>

TODO: @atomic rmw

TODO: builtin atomic memory ordering enum

See also:

- [@atomicLoad](#atomicLoad)
- [@atomicStore](#atomicStore)
- [@atomicRmw](#atomicRmw)
- [@cmpxchgWeak](#cmpxchgWeak)
- [@cmpxchgStrong](#cmpxchgStrong)

## [Async Functions](#toc-Async-Functions) <a href="#Async-Functions" class="hdr">§</a>

Async functions regressed with the release of 0.11.0. The current plan is to
reintroduce them as a lower level primitive that powers I/O implementations.

Tracking issue: [Proposal: stackless coroutines as low-level primitives](https://github.com/ziglang/zig/issues/23446)

## [Builtin Functions](#toc-Builtin-Functions) <a href="#Builtin-Functions" class="hdr">§</a>

Builtin functions are provided by the compiler and are prefixed with `@`.
The <span class="tok-kw">`comptime`</span> keyword on a parameter means that the parameter must be known
at compile time.

### [@addrSpaceCast](#toc-addrSpaceCast) <a href="#addrSpaceCast" class="hdr">§</a>

    @addrSpaceCast(ptr: anytype) anytype

Converts a pointer from one address space to another. The new address space is inferred
based on the result type. Depending on the current target and address spaces, this cast
may be a no-op, a complex operation, or illegal. If the cast is legal, then the resulting
pointer points to the same memory location as the pointer operand. It is always valid to
cast a pointer between the same address spaces.

### [@addWithOverflow](#toc-addWithOverflow) <a href="#addWithOverflow" class="hdr">§</a>

    @addWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a + b` and returns a tuple with the result and a possible overflow bit.

### [@alignCast](#toc-alignCast) <a href="#alignCast" class="hdr">§</a>

    @alignCast(ptr: anytype) anytype

`ptr` can be `*T`, `?*T`, or `[]T`.
Changes the alignment of a pointer. The alignment to use is inferred based on the result type.

A [pointer alignment safety check](#Incorrect-Pointer-Alignment) is added
to the generated code to make sure the pointer is aligned as promised.

### [@alignOf](#toc-alignOf) <a href="#alignOf" class="hdr">§</a>

    @alignOf(comptime T: type) comptime_int

This function returns the number of bytes that this type should be aligned to
for the current target to match the C ABI. When the child type of a pointer has
this alignment, the alignment can be omitted from the type.

    const assert = @import("std").debug.assert;
    comptime {
        assert(*u32 == *align(@alignOf(u32)) u32);
    }

The result is a target-specific compile time constant. It is guaranteed to be
less than or equal to [@sizeOf(T)](#sizeOf).

See also:

- [Alignment](#Alignment)

### [@as](#toc-as) <a href="#as" class="hdr">§</a>

    @as(comptime T: type, expression) T

Performs [Type Coercion](#Type-Coercion). This cast is allowed when the conversion is unambiguous and safe,
and is the preferred way to convert between types, whenever possible.

### [@atomicLoad](#toc-atomicLoad) <a href="#atomicLoad" class="hdr">§</a>

    @atomicLoad(comptime T: type, ptr: *const T, comptime ordering: AtomicOrder) T

This builtin function atomically dereferences a pointer to a `T` and returns the value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](#atomicStore)
- [@atomicRmw](#atomicRmw)
- [@cmpxchgWeak](#cmpxchgWeak)
- [@cmpxchgStrong](#cmpxchgStrong)

### [@atomicRmw](#toc-atomicRmw) <a href="#atomicRmw" class="hdr">§</a>

    @atomicRmw(comptime T: type, ptr: *T, comptime op: AtomicRmwOp, operand: T, comptime ordering: AtomicOrder) T

This builtin function dereferences a pointer to a `T` and atomically
modifies the value and returns the previous value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

`AtomicRmwOp` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicRmwOp`.

See also:

- [@atomicStore](#atomicStore)
- [@atomicLoad](#atomicLoad)
- [@cmpxchgWeak](#cmpxchgWeak)
- [@cmpxchgStrong](#cmpxchgStrong)

### [@atomicStore](#toc-atomicStore) <a href="#atomicStore" class="hdr">§</a>

    @atomicStore(comptime T: type, ptr: *T, value: T, comptime ordering: AtomicOrder) void

This builtin function dereferences a pointer to a `T` and atomically stores the given value.

`T` must be a pointer, a <span class="tok-type">`bool`</span>, a float,
an integer, an enum, or a packed struct.

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicLoad](#atomicLoad)
- [@atomicRmw](#atomicRmw)
- [@cmpxchgWeak](#cmpxchgWeak)
- [@cmpxchgStrong](#cmpxchgStrong)

### [@bitCast](#toc-bitCast) <a href="#bitCast" class="hdr">§</a>

    @bitCast(value: anytype) anytype

Converts a value of one type to another type. The return type is the
inferred result type.

Asserts that <span class="tok-builtin">`@sizeOf`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(value)) == `<span class="tok-builtin">`@sizeOf`</span>`(DestType)`.

Asserts that <span class="tok-builtin">`@typeInfo`</span>`(DestType) != .pointer`. Use <span class="tok-builtin">`@ptrCast`</span> or <span class="tok-builtin">`@ptrFromInt`</span> if you need this.

Can be used for these things for example:

- Convert <span class="tok-type">`f32`</span> to <span class="tok-type">`u32`</span> bits
- Convert <span class="tok-type">`i32`</span> to <span class="tok-type">`u32`</span> preserving twos complement

Works at compile-time if `value` is known at compile time. It's a compile error to bitcast a value of undefined layout; this means that, besides the restriction from types which possess dedicated casting builtins (enums, pointers, error sets), bare structs, error unions, slices, optionals, and any other type without a well-defined memory layout, also cannot be used in this operation.

### [@bitOffsetOf](#toc-bitOffsetOf) <a href="#bitOffsetOf" class="hdr">§</a>

    @bitOffsetOf(comptime T: type, comptime field_name: []const u8) comptime_int

Returns the bit offset of a field relative to its containing struct.

For non [packed structs](#packed-struct), this will always be divisible by <span class="tok-number">`8`</span>.
For packed structs, non-byte-aligned fields will share a byte offset, but they will have different
bit offsets.

See also:

- [@offsetOf](#offsetOf)

### [@bitSizeOf](#toc-bitSizeOf) <a href="#bitSizeOf" class="hdr">§</a>

    @bitSizeOf(comptime T: type) comptime_int

This function returns the number of bits it takes to store `T` in memory if the type
were a field in a packed struct/union.
The result is a target-specific compile time constant.

This function measures the size at runtime. For types that are disallowed at runtime, such as
<span class="tok-type">`comptime_int`</span> and <span class="tok-type">`type`</span>, the result is <span class="tok-number">`0`</span>.

See also:

- [@sizeOf](#sizeOf)
- [@typeInfo](#typeInfo)

### [@branchHint](#toc-branchHint) <a href="#branchHint" class="hdr">§</a>

    @branchHint(hint: BranchHint) void

Hints to the optimizer how likely a given branch of control flow is to be reached.

`BranchHint` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.BranchHint`.

This function is only valid as the first statement in a control flow branch, or the first statement in a function.

### [@breakpoint](#toc-breakpoint) <a href="#breakpoint" class="hdr">§</a>

    @breakpoint() void

This function inserts a platform-specific debug trap instruction which causes
debuggers to break there.
Unlike for <span class="tok-builtin">`@trap`</span>`()`, execution may continue after this point if the program is resumed.

This function is only valid within function scope.

See also:

- [@trap](#trap)

### [@mulAdd](#toc-mulAdd) <a href="#mulAdd" class="hdr">§</a>

    @mulAdd(comptime T: type, a: T, b: T, c: T) T

Fused multiply-add, similar to `(a * b) + c`, except
only rounds once, and is thus more accurate.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@byteSwap](#toc-byteSwap) <a href="#byteSwap" class="hdr">§</a>

    @byteSwap(operand: anytype) T

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type with bit count evenly divisible by 8.

`operand` may be an [integer](#Integers) or [vector](#Vectors).

Swaps the byte order of the integer. This converts a big endian integer to a little endian integer,
and converts a little endian integer to a big endian integer.

Note that for the purposes of memory layout with respect to endianness, the integer type should be
related to the number of bytes reported by [@sizeOf](#sizeOf) bytes. This is demonstrated with
<span class="tok-type">`u24`</span>. <span class="tok-builtin">`@sizeOf`</span>`(`<span class="tok-type">`u24`</span>`) == `<span class="tok-number">`4`</span>, which means that a
<span class="tok-type">`u24`</span> stored in memory takes 4 bytes, and those 4 bytes are what are swapped on
a little vs big endian system. On the other hand, if `T` is specified to
be <span class="tok-type">`u24`</span>, then only 3 bytes are reversed.

### [@bitReverse](#toc-bitReverse) <a href="#bitReverse" class="hdr">§</a>

    @bitReverse(integer: anytype) T

<span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-kw">`anytype`</span>`)` accepts any integer type or integer vector type.

Reverses the bitpattern of an integer value, including the sign bit if applicable.

For example 0b10110110 (<span class="tok-type">`u8`</span>` = `<span class="tok-number">`182`</span>, <span class="tok-type">`i8`</span>` = -`<span class="tok-number">`74`</span>)
becomes 0b01101101 (<span class="tok-type">`u8`</span>` = `<span class="tok-number">`109`</span>, <span class="tok-type">`i8`</span>` = `<span class="tok-number">`109`</span>).

### [@offsetOf](#toc-offsetOf) <a href="#offsetOf" class="hdr">§</a>

    @offsetOf(comptime T: type, comptime field_name: []const u8) comptime_int

Returns the byte offset of a field relative to its containing struct.

See also:

- [@bitOffsetOf](#bitOffsetOf)

### [@call](#toc-call) <a href="#call" class="hdr">§</a>

    @call(modifier: std.builtin.CallModifier, function: anytype, args: anytype) anytype

Calls a function, in the same way that invoking an expression with parentheses does:

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;noinline function call&quot; {
    try expect(@call(.auto, add, .{ 3, 9 }) == 12);
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}</code></pre>
<figcaption>test_call_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_call_builtin.zig
1/1 test_call_builtin.test.noinline function call...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

<span class="tok-builtin">`@call`</span> allows more flexibility than normal function call syntax does. The
`CallModifier` enum is reproduced here:

<figure>
<pre><code>pub const CallModifier = enum {
    /// Equivalent to function call syntax.
    auto,

    /// Equivalent to async keyword used with function call syntax.
    async_kw,

    /// Prevents tail call optimization. This guarantees that the return
    /// address will point to the callsite, as opposed to the callsite&#39;s
    /// callsite. If the call is otherwise required to be tail-called
    /// or inlined, a compile error is emitted instead.
    never_tail,

    /// Guarantees that the call will not be inlined. If the call is
    /// otherwise required to be inlined, a compile error is emitted instead.
    never_inline,

    /// Asserts that the function call will not suspend. This allows a
    /// non-async function to call an async function.
    no_async,

    /// Guarantees that the call will be generated with tail call optimization.
    /// If this is not possible, a compile error is emitted instead.
    always_tail,

    /// Guarantees that the call will be inlined at the callsite.
    /// If this is not possible, a compile error is emitted instead.
    always_inline,

    /// Evaluates the call at compile-time. If the call cannot be completed at
    /// compile-time, a compile error is emitted instead.
    compile_time,
};</code></pre>
<figcaption>builtin.CallModifier struct.zig</figcaption>
</figure>

### [@cDefine](#toc-cDefine) <a href="#cDefine" class="hdr">§</a>

    @cDefine(comptime name: []const u8, value) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#define $name $value` to the <span class="tok-builtin">`@cImport`</span>
temporary buffer.

To define without a value, like this:

``` c
#define _GNU_SOURCE
```

Use the void value, like this:

    @cDefine("_GNU_SOURCE", {})

See also:

- [Import from C Header File](#Import-from-C-Header-File)
- [@cInclude](#cInclude)
- [@cImport](#cImport)
- [@cUndef](#cUndef)
- [void](#void)

### [@cImport](#toc-cImport) <a href="#cImport" class="hdr">§</a>

    @cImport(expression) type

This function parses C code and imports the functions, types, variables,
and compatible macro definitions into a new empty struct type, and then
returns that type.

`expression` is interpreted at compile time. The builtin functions
<span class="tok-builtin">`@cInclude`</span>, <span class="tok-builtin">`@cDefine`</span>, and <span class="tok-builtin">`@cUndef`</span> work
within this expression, appending to a temporary buffer which is then parsed as C code.

Usually you should only have one <span class="tok-builtin">`@cImport`</span> in your entire application, because it saves the compiler
from invoking clang multiple times, and prevents inline functions from being duplicated.

Reasons for having multiple <span class="tok-builtin">`@cImport`</span> expressions would be:

- To avoid a symbol collision, for example if foo.h and bar.h both `#define CONNECTION_COUNT`
- To analyze the C code with different preprocessor defines

See also:

- [Import from C Header File](#Import-from-C-Header-File)
- [@cInclude](#cInclude)
- [@cDefine](#cDefine)
- [@cUndef](#cUndef)

### [@cInclude](#toc-cInclude) <a href="#cInclude" class="hdr">§</a>

    @cInclude(comptime path: []const u8) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#include <$path>\n` to the `c_import`
temporary buffer.

See also:

- [Import from C Header File](#Import-from-C-Header-File)
- [@cImport](#cImport)
- [@cDefine](#cDefine)
- [@cUndef](#cUndef)

### [@clz](#toc-clz) <a href="#clz" class="hdr">§</a>

    @clz(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type.

`operand` may be an [integer](#Integers) or [vector](#Vectors).

Counts the number of most-significant (leading in a big-endian sense) zeroes in an integer - "count leading zeroes".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

If `operand` is zero, <span class="tok-builtin">`@clz`</span> returns the bit width
of integer type `T`.

See also:

- [@ctz](#ctz)
- [@popCount](#popCount)

### [@cmpxchgStrong](#toc-cmpxchgStrong) <a href="#cmpxchgStrong" class="hdr">§</a>

    @cmpxchgStrong(comptime T: type, ptr: *T, expected_value: T, new_value: T, success_order: AtomicOrder, fail_order: AtomicOrder) ?T

This function performs a strong atomic compare-and-exchange operation, returning <span class="tok-null">`null`</span>
if the current value is the given expected value. It's the equivalent of this code,
except atomic:

<figure>
<pre><code>fn cmpxchgStrongButNotAtomic(comptime T: type, ptr: *T, expected_value: T, new_value: T) ?T {
    const old_value = ptr.*;
    if (old_value == expected_value) {
        ptr.* = new_value;
        return null;
    } else {
        return old_value;
    }
}</code></pre>
<figcaption>not_atomic_cmpxchgStrong.zig</figcaption>
</figure>

If you are using cmpxchg in a retry loop, [@cmpxchgWeak](#cmpxchgWeak) is the better choice, because it can be implemented
more efficiently in machine instructions.

`T` must be a pointer, a <span class="tok-type">`bool`</span>,
an integer, an enum, or a packed struct.

<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(ptr)).pointer.alignment` must be `>= `<span class="tok-builtin">`@sizeOf`</span>`(T).`

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](#atomicStore)
- [@atomicLoad](#atomicLoad)
- [@atomicRmw](#atomicRmw)
- [@cmpxchgWeak](#cmpxchgWeak)

### [@cmpxchgWeak](#toc-cmpxchgWeak) <a href="#cmpxchgWeak" class="hdr">§</a>

    @cmpxchgWeak(comptime T: type, ptr: *T, expected_value: T, new_value: T, success_order: AtomicOrder, fail_order: AtomicOrder) ?T

This function performs a weak atomic compare-and-exchange operation, returning <span class="tok-null">`null`</span>
if the current value is the given expected value. It's the equivalent of this code,
except atomic:

<figure>
<pre><code>fn cmpxchgWeakButNotAtomic(comptime T: type, ptr: *T, expected_value: T, new_value: T) ?T {
    const old_value = ptr.*;
    if (old_value == expected_value and usuallyTrueButSometimesFalse()) {
        ptr.* = new_value;
        return null;
    } else {
        return old_value;
    }
}</code></pre>
<figcaption>cmpxchgWeakButNotAtomic</figcaption>
</figure>

If you are using cmpxchg in a retry loop, the sporadic failure will be no problem, and `cmpxchgWeak`
is the better choice, because it can be implemented more efficiently in machine instructions.
However if you need a stronger guarantee, use [@cmpxchgStrong](#cmpxchgStrong).

`T` must be a pointer, a <span class="tok-type">`bool`</span>,
an integer, an enum, or a packed struct.

<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(ptr)).pointer.alignment` must be `>= `<span class="tok-builtin">`@sizeOf`</span>`(T).`

`AtomicOrder` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.AtomicOrder`.

See also:

- [@atomicStore](#atomicStore)
- [@atomicLoad](#atomicLoad)
- [@atomicRmw](#atomicRmw)
- [@cmpxchgStrong](#cmpxchgStrong)

### [@compileError](#toc-compileError) <a href="#compileError" class="hdr">§</a>

    @compileError(comptime msg: []const u8) noreturn

This function, when semantically analyzed, causes a compile error with the
message `msg`.

There are several ways that code avoids being semantically checked, such as
using <span class="tok-kw">`if`</span> or <span class="tok-kw">`switch`</span> with compile time constants,
and <span class="tok-kw">`comptime`</span> functions.

### [@compileLog](#toc-compileLog) <a href="#compileLog" class="hdr">§</a>

    @compileLog(...) void

This function prints the arguments passed to it at compile-time.

To prevent accidentally leaving compile log statements in a codebase,
a compilation error is added to the build, pointing to the compile
log statement. This error prevents code from being generated, but
does not otherwise interfere with analysis.

This function can be used to do "printf debugging" on
compile-time executing code.

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

const num1 = blk: {
    var val1: i32 = 99;
    @compileLog(&quot;comptime val1 = &quot;, val1);
    val1 = val1 + 1;
    break :blk val1;
};

test &quot;main&quot; {
    @compileLog(&quot;comptime in main&quot;);

    print(&quot;Runtime in main, num1 = {}.\n&quot;, .{num1});
}</code></pre>
<figcaption>test_compileLog_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_compileLog_builtin.zig
/home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:5:5: error: found compile log statement
    @compileLog(&quot;comptime val1 = &quot;, val1);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:11:5: note: also here
    @compileLog(&quot;comptime in main&quot;);
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    test.main: /home/andy/dev/zig/doc/langref/test_compileLog_builtin.zig:13:46

Compile Log Output:
@as(*const [16:0]u8, &quot;comptime val1 = &quot;), @as(i32, 99)
@as(*const [16:0]u8, &quot;comptime in main&quot;)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@constCast](#toc-constCast) <a href="#constCast" class="hdr">§</a>

    @constCast(value: anytype) DestType

Remove <span class="tok-kw">`const`</span> qualifier from a pointer.

### [@ctz](#toc-ctz) <a href="#ctz" class="hdr">§</a>

    @ctz(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type or an integer vector type.

`operand` may be an [integer](#Integers) or [vector](#Vectors).

Counts the number of least-significant (trailing in a big-endian sense) zeroes in an integer - "count trailing zeroes".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

If `operand` is zero, <span class="tok-builtin">`@ctz`</span> returns
the bit width of integer type `T`.

See also:

- [@clz](#clz)
- [@popCount](#popCount)

### [@cUndef](#toc-cUndef) <a href="#cUndef" class="hdr">§</a>

    @cUndef(comptime name: []const u8) void

This function can only occur inside <span class="tok-builtin">`@cImport`</span>.

This appends `#undef $name` to the <span class="tok-builtin">`@cImport`</span>
temporary buffer.

See also:

- [Import from C Header File](#Import-from-C-Header-File)
- [@cImport](#cImport)
- [@cDefine](#cDefine)
- [@cInclude](#cInclude)

### [@cVaArg](#toc-cVaArg) <a href="#cVaArg" class="hdr">§</a>

    @cVaArg(operand: *std.builtin.VaList, comptime T: type) T

Implements the C macro `va_arg`.

See also:

- [@cVaCopy](#cVaCopy)
- [@cVaEnd](#cVaEnd)
- [@cVaStart](#cVaStart)

### [@cVaCopy](#toc-cVaCopy) <a href="#cVaCopy" class="hdr">§</a>

    @cVaCopy(src: *std.builtin.VaList) std.builtin.VaList

Implements the C macro `va_copy`.

See also:

- [@cVaArg](#cVaArg)
- [@cVaEnd](#cVaEnd)
- [@cVaStart](#cVaStart)

### [@cVaEnd](#toc-cVaEnd) <a href="#cVaEnd" class="hdr">§</a>

    @cVaEnd(src: *std.builtin.VaList) void

Implements the C macro `va_end`.

See also:

- [@cVaArg](#cVaArg)
- [@cVaCopy](#cVaCopy)
- [@cVaStart](#cVaStart)

### [@cVaStart](#toc-cVaStart) <a href="#cVaStart" class="hdr">§</a>

    @cVaStart() std.builtin.VaList

Implements the C macro `va_start`. Only valid inside a variadic function.

See also:

- [@cVaArg](#cVaArg)
- [@cVaCopy](#cVaCopy)
- [@cVaEnd](#cVaEnd)

### [@divExact](#toc-divExact) <a href="#divExact" class="hdr">§</a>

    @divExact(numerator: T, denominator: T) T

Exact division. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
<span class="tok-builtin">`@divTrunc`</span>`(numerator, denominator) * denominator == numerator`.

- <span class="tok-builtin">`@divExact`</span>`(`<span class="tok-number">`6`</span>`, `<span class="tok-number">`3`</span>`) == `<span class="tok-number">`2`</span>
- <span class="tok-builtin">`@divExact`</span>`(a, b) * b == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divExact`.

See also:

- [@divTrunc](#divTrunc)
- [@divFloor](#divFloor)

### [@divFloor](#toc-divFloor) <a href="#divFloor" class="hdr">§</a>

    @divFloor(numerator: T, denominator: T) T

Floored division. Rounds toward negative infinity. For unsigned integers it is
the same as `numerator / denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
`!(`<span class="tok-builtin">`@typeInfo`</span>`(T) == .int `<span class="tok-kw">`and`</span>` T.is_signed `<span class="tok-kw">`and`</span>` numerator == std.math.minInt(T) `<span class="tok-kw">`and`</span>` denominator == -`<span class="tok-number">`1`</span>`)`.

- <span class="tok-builtin">`@divFloor`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`2`</span>
- `(`<span class="tok-builtin">`@divFloor`</span>`(a, b) * b) + `<span class="tok-builtin">`@mod`</span>`(a, b) == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divFloor`.

See also:

- [@divTrunc](#divTrunc)
- [@divExact](#divExact)

### [@divTrunc](#toc-divTrunc) <a href="#divTrunc" class="hdr">§</a>

    @divTrunc(numerator: T, denominator: T) T

Truncated division. Rounds toward zero. For unsigned integers it is
the same as `numerator / denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span> and
`!(`<span class="tok-builtin">`@typeInfo`</span>`(T) == .int `<span class="tok-kw">`and`</span>` T.is_signed `<span class="tok-kw">`and`</span>` numerator == std.math.minInt(T) `<span class="tok-kw">`and`</span>` denominator == -`<span class="tok-number">`1`</span>`)`.

- <span class="tok-builtin">`@divTrunc`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`1`</span>
- `(`<span class="tok-builtin">`@divTrunc`</span>`(a, b) * b) + `<span class="tok-builtin">`@rem`</span>`(a, b) == a`

For a function that returns a possible error code, use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divTrunc`.

See also:

- [@divFloor](#divFloor)
- [@divExact](#divExact)

### [@embedFile](#toc-embedFile) <a href="#embedFile" class="hdr">§</a>

    @embedFile(comptime path: []const u8) *const [N:0]u8

This function returns a compile time constant pointer to null-terminated,
fixed-size array with length equal to the byte count of the file given by
`path`. The contents of the array are the contents of the file.
This is equivalent to a [string literal](#String-Literals-and-Unicode-Code-Point-Literals)
with the file contents.

`path` is absolute or relative to the current file, just like <span class="tok-builtin">`@import`</span>.

See also:

- [@import](#import)

### [@enumFromInt](#toc-enumFromInt) <a href="#enumFromInt" class="hdr">§</a>

    @enumFromInt(integer: anytype) anytype

Converts an integer into an [enum](#enum) value. The return type is the inferred result type.

Attempting to convert an integer with no corresponding value in the enum invokes
safety-checked [Illegal Behavior](#Illegal-Behavior).
Note that a [non-exhaustive enum](#Non-exhaustive-enum) has corresponding values for all
integers in the enum's integer tag type: the `_` value represents all
the remaining unnamed integers in the enum's tag type.

See also:

- [@intFromEnum](#intFromEnum)

### [@errorFromInt](#toc-errorFromInt) <a href="#errorFromInt" class="hdr">§</a>

    @errorFromInt(value: std.meta.Int(.unsigned, @bitSizeOf(anyerror))) anyerror

Converts from the integer representation of an error into [The Global Error Set](#The-Global-Error-Set) type.

It is generally recommended to avoid this
cast, as the integer representation of an error is not stable across source code changes.

Attempting to convert an integer that does not correspond to any error results in
safety-checked [Illegal Behavior](#Illegal-Behavior).

See also:

- [@intFromError](#intFromError)

### [@errorName](#toc-errorName) <a href="#errorName" class="hdr">§</a>

    @errorName(err: anyerror) [:0]const u8

This function returns the string representation of an error. The string representation
of <span class="tok-kw">`error`</span>`.OutOfMem` is <span class="tok-str">`"OutOfMem"`</span>.

If there are no calls to <span class="tok-builtin">`@errorName`</span> in an entire application,
or all calls have a compile-time known value for `err`, then no
error name table will be generated.

### [@errorReturnTrace](#toc-errorReturnTrace) <a href="#errorReturnTrace" class="hdr">§</a>

    @errorReturnTrace() ?*builtin.StackTrace

If the binary is built with error return tracing, and this function is invoked in a
function that calls a function with an error or error union return type, returns a
stack trace object. Otherwise returns [null](#null).

### [@errorCast](#toc-errorCast) <a href="#errorCast" class="hdr">§</a>

    @errorCast(value: anytype) anytype

Converts an error set or error union value from one error set to another error set. The return type is the
inferred result type. Attempting to convert an error which is not in the destination error
set results in safety-checked [Illegal Behavior](#Illegal-Behavior).

### [@export](#toc-export) <a href="#export" class="hdr">§</a>

    @export(comptime ptr: *const anyopaque, comptime options: std.builtin.ExportOptions) void

Creates a symbol in the output object file which refers to the target of `ptr`.

`ptr` must point to a global variable or a comptime-known constant.

This builtin can be called from a [comptime](#comptime) block to conditionally export symbols.
When `ptr` points to a function with the C calling convention and
`options.linkage` is `.strong`, this is equivalent to
the <span class="tok-kw">`export`</span> keyword used on a function:

<figure>
<pre><code>comptime {
    @export(&amp;internalName, .{ .name = &quot;foo&quot;, .linkage = .strong });
}

fn internalName() callconv(.c) void {}</code></pre>
<figcaption>export_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_builtin.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

This is equivalent to:

<figure>
<pre><code>export fn foo() void {}</code></pre>
<figcaption>export_builtin_equivalent_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_builtin_equivalent_code.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note that even when using <span class="tok-kw">`export`</span>, the `@"foo"` syntax for
[identifiers](#Identifiers) can be used to choose any string for the symbol name:

<figure>
<pre><code>export fn @&quot;A function name that is a complete sentence.&quot;() void {}</code></pre>
<figcaption>export_any_symbol_name.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-obj export_any_symbol_name.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

When looking at the resulting object, you can see the symbol is used verbatim:

    00000000000001f0 T A function name that is a complete sentence.

See also:

- [Exporting a C Library](#Exporting-a-C-Library)

### [@extern](#toc-extern) <a href="#extern" class="hdr">§</a>

    @extern(T: type, comptime options: std.builtin.ExternOptions) T

Creates a reference to an external symbol in the output object file.
T must be a pointer type.

See also:

- [@export](#export)

### [@field](#toc-field) <a href="#field" class="hdr">§</a>

    @field(lhs: anytype, comptime field_name: []const u8) (field)

Performs field access by a compile-time string. Works on both fields and declarations.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Point = struct {
    x: u32,
    y: u32,

    pub var z: u32 = 1;
};

test &quot;field access by string&quot; {
    const expect = std.testing.expect;
    var p = Point{ .x = 0, .y = 0 };

    @field(p, &quot;x&quot;) = 4;
    @field(p, &quot;y&quot;) = @field(p, &quot;x&quot;) + 1;

    try expect(@field(p, &quot;x&quot;) == 4);
    try expect(@field(p, &quot;y&quot;) == 5);
}

test &quot;decl access by string&quot; {
    const expect = std.testing.expect;

    try expect(@field(Point, &quot;z&quot;) == 1);

    @field(Point, &quot;z&quot;) = 2;
    try expect(@field(Point, &quot;z&quot;) == 2);
}</code></pre>
<figcaption>test_field_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_field_builtin.zig
1/2 test_field_builtin.test.field access by string...OK
2/2 test_field_builtin.test.decl access by string...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@fieldParentPtr](#toc-fieldParentPtr) <a href="#fieldParentPtr" class="hdr">§</a>

    @fieldParentPtr(comptime field_name: []const u8, field_ptr: *T) anytype

Given a pointer to a struct field, returns a pointer to the struct containing that field.
The return type (and struct in question) is the inferred result type.

If `field_ptr` does not point to the `field_name` field of an instance of
the result type, and the result type has ill-defined layout, invokes unchecked [Illegal Behavior](#Illegal-Behavior).

### [@FieldType](#toc-FieldType) <a href="#FieldType" class="hdr">§</a>

    @FieldType(comptime Type: type, comptime field_name: []const u8) type

Given a type and the name of one of its fields, returns the type of that field.

### [@floatCast](#toc-floatCast) <a href="#floatCast" class="hdr">§</a>

    @floatCast(value: anytype) anytype

Convert from one float type to another. This cast is safe, but may cause the
numeric value to lose precision. The return type is the inferred result type.

### [@floatFromInt](#toc-floatFromInt) <a href="#floatFromInt" class="hdr">§</a>

    @floatFromInt(int: anytype) anytype

Converts an integer to the closest floating point representation. The return type is the inferred result type.
To convert the other way, use [@intFromFloat](#intFromFloat). This operation is legal
for all values of all integer types.

### [@frameAddress](#toc-frameAddress) <a href="#frameAddress" class="hdr">§</a>

    @frameAddress() usize

This function returns the base pointer of the current stack frame.

The implications of this are target-specific and not consistent across all
platforms. The frame address may not be available in release mode due to
aggressive optimizations.

This function is only valid within function scope.

### [@hasDecl](#toc-hasDecl) <a href="#hasDecl" class="hdr">§</a>

    @hasDecl(comptime Container: type, comptime name: []const u8) bool

Returns whether or not a [container](#Containers) has a declaration
matching `name`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

const Foo = struct {
    nope: i32,

    pub var blah = &quot;xxx&quot;;
    const hi = 1;
};

test &quot;@hasDecl&quot; {
    try expect(@hasDecl(Foo, &quot;blah&quot;));

    // Even though `hi` is private, @hasDecl returns true because this test is
    // in the same file scope as Foo. It would return false if Foo was declared
    // in a different file.
    try expect(@hasDecl(Foo, &quot;hi&quot;));

    // @hasDecl is for declarations; not fields.
    try expect(!@hasDecl(Foo, &quot;nope&quot;));
    try expect(!@hasDecl(Foo, &quot;nope1234&quot;));
}</code></pre>
<figcaption>test_hasDecl_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_hasDecl_builtin.zig
1/1 test_hasDecl_builtin.test.@hasDecl...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@hasField](#hasField)

### [@hasField](#toc-hasField) <a href="#hasField" class="hdr">§</a>

    @hasField(comptime Container: type, comptime name: []const u8) bool

Returns whether the field name of a struct, union, or enum exists.

The result is a compile time constant.

It does not include functions, variables, or constants.

See also:

- [@hasDecl](#hasDecl)

### [@import](#toc-import) <a href="#import" class="hdr">§</a>

    @import(comptime target: []const u8) anytype

Imports the file at `target`, adding it to the compilation if it is not already
added. `target` is either a relative path to another file from the file containing
the <span class="tok-builtin">`@import`</span> call, or it is the name of a [module](#Compilation-Model), with
the import referring to the root source file of that module. Either way, the file path must end in
either `.zig` (for a Zig source file) or `.zon` (for a ZON data file).

If `target` refers to a Zig source file, then <span class="tok-builtin">`@import`</span> returns
that file's [corresponding struct type](#Source-File-Structs), essentially as if the builtin call was
replaced by <span class="tok-kw">`struct`</span>` { FILE_CONTENTS }`. The return type is <span class="tok-type">`type`</span>.

If `target` refers to a ZON file, then <span class="tok-builtin">`@import`</span> returns the value
of the literal in the file. If there is an inferred [result type](#Result-Types), then the return type
is that type, and the ZON literal is interpreted as that type ([Result Types](#Result-Types) are propagated through
the ZON expression). Otherwise, the return type is the type of the equivalent Zig expression, essentially as
if the builtin call was replaced by the ZON file contents.

The following modules are always available for import:

- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`)` - Zig Standard Library
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`)` - Target-specific information. The command `zig build-exe --show-builtin` outputs the source to stdout for reference.
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)` - Alias for the root module. In typical project structures, this means it refers back to `src/main.zig`.

See also:

- [Compile Variables](#Compile-Variables)
- [@embedFile](#embedFile)

### [@inComptime](#toc-inComptime) <a href="#inComptime" class="hdr">§</a>

    @inComptime() bool

Returns whether the builtin was run in a <span class="tok-kw">`comptime`</span> context. The result is a compile-time constant.

This can be used to provide alternative, comptime-friendly implementations of functions. It should not be used, for instance, to exclude certain functions from being evaluated at comptime.

See also:

- [comptime](#comptime)

### [@intCast](#toc-intCast) <a href="#intCast" class="hdr">§</a>

    @intCast(int: anytype) anytype

Converts an integer to another integer while keeping the same numerical value.
The return type is the inferred result type.
Attempting to convert a number which is out of range of the destination type results in
safety-checked [Illegal Behavior](#Illegal-Behavior).

<figure>
<pre><code>test &quot;integer cast panic&quot; {
    var a: u16 = 0xabcd; // runtime-known
    _ = &amp;a;
    const b: u8 = @intCast(a);
    _ = b;
}</code></pre>
<figcaption>test_intCast_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_intCast_builtin.zig
1/1 test_intCast_builtin.test.integer cast panic...thread 1097950 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/test_intCast_builtin.zig:4:19: 0x102c020 in test.integer cast panic (test_intCast_builtin.zig)
    const b: u8 = @intCast(a);
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
/home/andy/dev/zig/.zig-cache/o/f8f5d23c1adeea76700e35886c1e4bcf/test --seed=0x8786b231</code></pre>
<figcaption>Shell</figcaption>
</figure>

To truncate the significant bits of a number out of range of the destination type, use [@truncate](#truncate).

If `T` is <span class="tok-type">`comptime_int`</span>,
then this is semantically equivalent to [Type Coercion](#Type-Coercion).

### [@intFromBool](#toc-intFromBool) <a href="#intFromBool" class="hdr">§</a>

    @intFromBool(value: bool) u1

Converts <span class="tok-null">`true`</span> to <span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`u1`</span>`, `<span class="tok-number">`1`</span>`)` and <span class="tok-null">`false`</span> to
<span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`u1`</span>`, `<span class="tok-number">`0`</span>`)`.

### [@intFromEnum](#toc-intFromEnum) <a href="#intFromEnum" class="hdr">§</a>

    @intFromEnum(enum_or_tagged_union: anytype) anytype

Converts an enumeration value into its integer tag type. When a tagged union is passed,
the tag value is used as the enumeration value.

If there is only one possible enum value, the result is a <span class="tok-type">`comptime_int`</span>
known at [comptime](#comptime).

See also:

- [@enumFromInt](#enumFromInt)

### [@intFromError](#toc-intFromError) <a href="#intFromError" class="hdr">§</a>

    @intFromError(err: anytype) std.meta.Int(.unsigned, @bitSizeOf(anyerror))

Supports the following types:

- [The Global Error Set](#The-Global-Error-Set)
- [Error Set Type](#Error-Set-Type)
- [Error Union Type](#Error-Union-Type)

Converts an error to the integer representation of an error.

It is generally recommended to avoid this
cast, as the integer representation of an error is not stable across source code changes.

See also:

- [@errorFromInt](#errorFromInt)

### [@intFromFloat](#toc-intFromFloat) <a href="#intFromFloat" class="hdr">§</a>

    @intFromFloat(float: anytype) anytype

Converts the integer part of a floating point number to the inferred result type.

If the integer part of the floating point number cannot fit in the destination type,
it invokes safety-checked [Illegal Behavior](#Illegal-Behavior).

See also:

- [@floatFromInt](#floatFromInt)

### [@intFromPtr](#toc-intFromPtr) <a href="#intFromPtr" class="hdr">§</a>

    @intFromPtr(value: anytype) usize

Converts `value` to a <span class="tok-type">`usize`</span> which is the address of the pointer.
`value` can be `*T` or `?*T`.

To convert the other way, use [@ptrFromInt](#ptrFromInt)

### [@max](#toc-max) <a href="#max" class="hdr">§</a>

    @max(...) T

Takes two or more arguments and returns the biggest value included (the maximum). This builtin accepts integers, floats, and vectors of either. In the latter case, the operation is performed element wise.

NaNs are handled as follows: return the biggest non-NaN value included. If all operands are NaN, return NaN.

See also:

- [@min](#min)
- [Vectors](#Vectors)

### [@memcpy](#toc-memcpy) <a href="#memcpy" class="hdr">§</a>

    @memcpy(noalias dest, noalias source) void

This function copies bytes from one region of memory to another.

`dest` must be a mutable slice, a mutable pointer to an array, or
a mutable many-item [pointer](#Pointers). It may have any
alignment, and it may have any element type.

`source` must be a slice, a pointer to
an array, or a many-item [pointer](#Pointers). It may
have any alignment, and it may have any element type.

The `source` element type must have the same in-memory
representation as the `dest` element type.

Similar to [for](#for) loops, at least one of `source` and
`dest` must provide a length, and if two lengths are provided,
they must be equal.

Finally, the two memory regions must not overlap.

### [@memset](#toc-memset) <a href="#memset" class="hdr">§</a>

    @memset(dest, elem) void

This function sets all the elements of a memory region to `elem`.

`dest` must be a mutable slice or a mutable pointer to an array.
It may have any alignment, and it may have any element type.

`elem` is coerced to the element type of `dest`.

For securely zeroing out sensitive contents from memory, you should use
`std.crypto.secureZero`

### [@memmove](#toc-memmove) <a href="#memmove" class="hdr">§</a>

    @memmove(dest, source) void

This function copies bytes from one region of memory to another, but unlike
[@memcpy](#memcpy) the regions may overlap.

`dest` must be a mutable slice, a mutable pointer to an array, or
a mutable many-item [pointer](#Pointers). It may have any
alignment, and it may have any element type.

`source` must be a slice, a pointer to
an array, or a many-item [pointer](#Pointers). It may
have any alignment, and it may have any element type.

The `source` element type must have the same in-memory
representation as the `dest` element type.

Similar to [for](#for) loops, at least one of `source` and
`dest` must provide a length, and if two lengths are provided,
they must be equal.

### [@min](#toc-min) <a href="#min" class="hdr">§</a>

    @min(...) T

Takes two or more arguments and returns the smallest value included (the minimum). This builtin accepts integers, floats, and vectors of either. In the latter case, the operation is performed element wise.

NaNs are handled as follows: return the smallest non-NaN value included. If all operands are NaN, return NaN.

See also:

- [@max](#max)
- [Vectors](#Vectors)

### [@wasmMemorySize](#toc-wasmMemorySize) <a href="#wasmMemorySize" class="hdr">§</a>

    @wasmMemorySize(index: u32) usize

This function returns the size of the Wasm memory identified by `index` as
an unsigned value in units of Wasm pages. Note that each Wasm page is 64KB in size.

This function is a low level intrinsic with no safety mechanisms usually useful for allocator
designers targeting Wasm. So unless you are writing a new allocator from scratch, you should use
something like <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).heap.WasmPageAllocator`.

See also:

- [@wasmMemoryGrow](#wasmMemoryGrow)

### [@wasmMemoryGrow](#toc-wasmMemoryGrow) <a href="#wasmMemoryGrow" class="hdr">§</a>

    @wasmMemoryGrow(index: u32, delta: usize) isize

This function increases the size of the Wasm memory identified by `index` by
`delta` in units of unsigned number of Wasm pages. Note that each Wasm page
is 64KB in size. On success, returns previous memory size; on failure, if the allocation fails,
returns -1.

This function is a low level intrinsic with no safety mechanisms usually useful for allocator
designers targeting Wasm. So unless you are writing a new allocator from scratch, you should use
something like <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).heap.WasmPageAllocator`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const native_arch = @import(&quot;builtin&quot;).target.cpu.arch;
const expect = std.testing.expect;

test &quot;@wasmMemoryGrow&quot; {
    if (native_arch != .wasm32) return error.SkipZigTest;

    const prev = @wasmMemorySize(0);
    try expect(prev == @wasmMemoryGrow(0, 1));
    try expect(prev + 1 == @wasmMemorySize(0));
}</code></pre>
<figcaption>test_wasmMemoryGrow_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wasmMemoryGrow_builtin.zig
1/1 test_wasmMemoryGrow_builtin.test.@wasmMemoryGrow...SKIP
0 passed; 1 skipped; 0 failed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [@wasmMemorySize](#wasmMemorySize)

### [@mod](#toc-mod) <a href="#mod" class="hdr">§</a>

    @mod(numerator: T, denominator: T) T

Modulus division. For unsigned integers this is the same as
`numerator % denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span>, otherwise the
operation will result in a [Remainder Division by Zero](#Remainder-Division-by-Zero) when runtime safety checks are enabled.

- <span class="tok-builtin">`@mod`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == `<span class="tok-number">`1`</span>
- `(`<span class="tok-builtin">`@divFloor`</span>`(a, b) * b) + `<span class="tok-builtin">`@mod`</span>`(a, b) == a`

For a function that returns an error code, see <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.mod`.

See also:

- [@rem](#rem)

### [@mulWithOverflow](#toc-mulWithOverflow) <a href="#mulWithOverflow" class="hdr">§</a>

    @mulWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a * b` and returns a tuple with the result and a possible overflow bit.

### [@panic](#toc-panic) <a href="#panic" class="hdr">§</a>

    @panic(message: []const u8) noreturn

Invokes the panic handler function. By default the panic handler function
calls the public `panic` function exposed in the root source file, or
if there is not one specified, the `std.builtin.default_panic`
function from `std/builtin.zig`.

Generally it is better to use <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).debug.panic`.
However, <span class="tok-builtin">`@panic`</span> can be useful for 2 scenarios:

- From library code, calling the programmer's panic function if they exposed one in the root source file.
- When mixing C and Zig code, calling the canonical panic implementation across multiple .o files.

See also:

- [Panic Handler](#Panic-Handler)

### [@popCount](#toc-popCount) <a href="#popCount" class="hdr">§</a>

    @popCount(operand: anytype) anytype

<span class="tok-builtin">`@TypeOf`</span>`(operand)` must be an integer type.

`operand` may be an [integer](#Integers) or [vector](#Vectors).

Counts the number of bits set in an integer - "population count".

The return type is an unsigned integer or vector of unsigned integers with the minimum number
of bits that can represent the bit count of the integer type.

See also:

- [@ctz](#ctz)
- [@clz](#clz)

### [@prefetch](#toc-prefetch) <a href="#prefetch" class="hdr">§</a>

    @prefetch(ptr: anytype, comptime options: PrefetchOptions) void

This builtin tells the compiler to emit a prefetch instruction if supported by the
target CPU. If the target CPU does not support the requested prefetch instruction,
this builtin is a no-op. This function has no effect on the behavior of the program,
only on the performance characteristics.

The `ptr` argument may be any pointer type and determines the memory
address to prefetch. This function does not dereference the pointer, it is perfectly legal
to pass a pointer to invalid memory to this function and no Illegal Behavior will result.

`PrefetchOptions` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.PrefetchOptions`.

### [@ptrCast](#toc-ptrCast) <a href="#ptrCast" class="hdr">§</a>

    @ptrCast(value: anytype) anytype

Converts a pointer of one type to a pointer of another type. The return type is the inferred result type.

[Optional Pointers](#Optional-Pointers) are allowed. Casting an optional pointer which is [null](#null)
to a non-optional pointer invokes safety-checked [Illegal Behavior](#Illegal-Behavior).

<span class="tok-builtin">`@ptrCast`</span> cannot be used for:

- Removing <span class="tok-kw">`const`</span> qualifier, use [@constCast](#constCast).
- Removing <span class="tok-kw">`volatile`</span> qualifier, use [@volatileCast](#volatileCast).
- Changing pointer address space, use [@addrSpaceCast](#addrSpaceCast).
- Increasing pointer alignment, use [@alignCast](#alignCast).
- Casting a non-slice pointer to a slice, use slicing syntax `ptr[start..end]`.

### [@ptrFromInt](#toc-ptrFromInt) <a href="#ptrFromInt" class="hdr">§</a>

    @ptrFromInt(address: usize) anytype

Converts an integer to a [pointer](#Pointers). The return type is the inferred result type.
To convert the other way, use [@intFromPtr](#intFromPtr). Casting an address of 0 to a destination type
which in not [optional](#Optional-Pointers) and does not have the <span class="tok-kw">`allowzero`</span> attribute will result in a
[Pointer Cast Invalid Null](#Pointer-Cast-Invalid-Null) panic when runtime safety checks are enabled.

If the destination pointer type does not allow address zero and `address`
is zero, this invokes safety-checked [Illegal Behavior](#Illegal-Behavior).

### [@rem](#toc-rem) <a href="#rem" class="hdr">§</a>

    @rem(numerator: T, denominator: T) T

Remainder division. For unsigned integers this is the same as
`numerator % denominator`. Caller guarantees `denominator != `<span class="tok-number">`0`</span>, otherwise the
operation will result in a [Remainder Division by Zero](#Remainder-Division-by-Zero) when runtime safety checks are enabled.

- <span class="tok-builtin">`@rem`</span>`(-`<span class="tok-number">`5`</span>`, `<span class="tok-number">`3`</span>`) == -`<span class="tok-number">`2`</span>
- `(`<span class="tok-builtin">`@divTrunc`</span>`(a, b) * b) + `<span class="tok-builtin">`@rem`</span>`(a, b) == a`

For a function that returns an error code, see <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.rem`.

See also:

- [@mod](#mod)

### [@returnAddress](#toc-returnAddress) <a href="#returnAddress" class="hdr">§</a>

    @returnAddress() usize

This function returns the address of the next machine code instruction that will be executed
when the current function returns.

The implications of this are target-specific and not consistent across
all platforms.

This function is only valid within function scope. If the function gets inlined into
a calling function, the returned address will apply to the calling function.

### [@select](#toc-select) <a href="#select" class="hdr">§</a>

    @select(comptime T: type, pred: @Vector(len, bool), a: @Vector(len, T), b: @Vector(len, T)) @Vector(len, T)

Selects values element-wise from `a` or `b` based on `pred`. If `pred[i]` is <span class="tok-null">`true`</span>, the corresponding element in the result will be `a[i]` and otherwise `b[i]`.

See also:

- [Vectors](#Vectors)

### [@setEvalBranchQuota](#toc-setEvalBranchQuota) <a href="#setEvalBranchQuota" class="hdr">§</a>

    @setEvalBranchQuota(comptime new_quota: u32) void

Increase the maximum number of backwards branches that compile-time code
execution can use before giving up and making a compile error.

If the `new_quota` is smaller than the default quota (<span class="tok-number">`1000`</span>) or
a previously explicitly set quota, it is ignored.

Example:

<figure>
<pre><code>test &quot;foo&quot; {
    comptime {
        var i = 0;
        while (i &lt; 1001) : (i += 1) {}
    }
}</code></pre>
<figcaption>test_without_setEvalBranchQuota_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_without_setEvalBranchQuota_builtin.zig
/home/andy/dev/zig/doc/langref/test_without_setEvalBranchQuota_builtin.zig:4:9: error: evaluation exceeded 1000 backwards branches
        while (i &lt; 1001) : (i += 1) {}
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_without_setEvalBranchQuota_builtin.zig:4:9: note: use @setEvalBranchQuota() to raise the branch limit from 1000
</code></pre>
<figcaption>Shell</figcaption>
</figure>

Now we use <span class="tok-builtin">`@setEvalBranchQuota`</span>:

<figure>
<pre><code>test &quot;foo&quot; {
    comptime {
        @setEvalBranchQuota(1001);
        var i = 0;
        while (i &lt; 1001) : (i += 1) {}
    }
}</code></pre>
<figcaption>test_setEvalBranchQuota_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_setEvalBranchQuota_builtin.zig
1/1 test_setEvalBranchQuota_builtin.test.foo...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [comptime](#comptime)

### [@setFloatMode](#toc-setFloatMode) <a href="#setFloatMode" class="hdr">§</a>

    @setFloatMode(comptime mode: FloatMode) void

Changes the current scope's rules about how floating point operations are defined.

- `Strict` (default) - Floating point operations follow strict IEEE compliance.
- `Optimized` - Floating point operations may do all of the following:
  - Assume the arguments and result are not NaN. Optimizations are required to retain legal behavior over NaNs, but the value of the result is undefined.
  - Assume the arguments and result are not +/-Inf. Optimizations are required to retain legal behavior over +/-Inf, but the value of the result is undefined.
  - Treat the sign of a zero argument or result as insignificant.
  - Use the reciprocal of an argument rather than perform division.
  - Perform floating-point contraction (e.g. fusing a multiply followed by an addition into a fused multiply-add).
  - Perform algebraically equivalent transformations that may change results in floating point (e.g. reassociate).

  This is equivalent to `-ffast-math` in GCC.

The floating point mode is inherited by child scopes, and can be overridden in any scope.
You can set the floating point mode in a struct or module scope by using a comptime block.

`FloatMode` can be found with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).builtin.FloatMode`.

See also:

- [Floating Point Operations](#Floating-Point-Operations)

### [@setRuntimeSafety](#toc-setRuntimeSafety) <a href="#setRuntimeSafety" class="hdr">§</a>

    @setRuntimeSafety(comptime safety_on: bool) void

Sets whether runtime safety checks are enabled for the scope that contains the function call.

<figure>
<pre><code>test &quot;@setRuntimeSafety&quot; {
    // The builtin applies to the scope that it is called in. So here, integer overflow
    // will not be caught in ReleaseFast and ReleaseSmall modes:
    // var x: u8 = 255;
    // x += 1; // Unchecked Illegal Behavior in ReleaseFast/ReleaseSmall modes.
    {
        // However this block has safety enabled, so safety checks happen here,
        // even in ReleaseFast and ReleaseSmall modes.
        @setRuntimeSafety(true);
        var x: u8 = 255;
        x += 1;

        {
            // The value can be overridden at any scope. So here integer overflow
            // would not be caught in any build mode.
            @setRuntimeSafety(false);
            // var x: u8 = 255;
            // x += 1; // Unchecked Illegal Behavior in all build modes.
        }
    }
}</code></pre>
<figcaption>test_setRuntimeSafety_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_setRuntimeSafety_builtin.zig -OReleaseFast
1/1 test_setRuntimeSafety_builtin.test.@setRuntimeSafety...thread 1101377 panic: integer overflow
/home/andy/dev/zig/doc/langref/test_setRuntimeSafety_builtin.zig:11:11: 0x103eb98 in test.@setRuntimeSafety (test)
        x += 1;
          ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x10323df in main (test)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x102ff7d in posixCallMainAndExit (test)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x102fa7d in _start (test)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/2d6906f7b8821b0f5d6faa657d7405fc/test --seed=0xbd188e37</code></pre>
<figcaption>Shell</figcaption>
</figure>

Note: it is [planned](https://github.com/ziglang/zig/issues/978) to replace
<span class="tok-builtin">`@setRuntimeSafety`</span> with `@optimizeFor`

### [@shlExact](#toc-shlExact) <a href="#shlExact" class="hdr">§</a>

    @shlExact(value: T, shift_amt: Log2T) T

Performs the left shift operation (`<<`).
For unsigned integers, the result is [undefined](#undefined) if any 1 bits
are shifted out. For signed integers, the result is [undefined](#undefined) if
any bits that disagree with the resultant sign bit are shifted out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](#Illegal-Behavior).

<span class="tok-type">`comptime_int`</span> is modeled as an integer with an infinite number of bits,
meaning that in such case, <span class="tok-builtin">`@shlExact`</span> always produces a result and
cannot produce a compile error.

See also:

- [@shrExact](#shrExact)
- [@shlWithOverflow](#shlWithOverflow)

### [@shlWithOverflow](#toc-shlWithOverflow) <a href="#shlWithOverflow" class="hdr">§</a>

    @shlWithOverflow(a: anytype, shift_amt: Log2T) struct { @TypeOf(a), u1 }

Performs `a << b` and returns a tuple with the result and a possible overflow bit.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(`<span class="tok-builtin">`@TypeOf`</span>`(a)).int.bits` triggers safety-checked [Illegal Behavior](#Illegal-Behavior).

See also:

- [@shlExact](#shlExact)
- [@shrExact](#shrExact)

### [@shrExact](#toc-shrExact) <a href="#shrExact" class="hdr">§</a>

    @shrExact(value: T, shift_amt: Log2T) T

Performs the right shift operation (`>>`). Caller guarantees
that the shift will not shift any 1 bits out.

The type of `shift_amt` is an unsigned integer with `log2(`<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits)` bits.
This is because `shift_amt >= `<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits` triggers safety-checked [Illegal Behavior](#Illegal-Behavior).

See also:

- [@shlExact](#shlExact)
- [@shlWithOverflow](#shlWithOverflow)

### [@shuffle](#toc-shuffle) <a href="#shuffle" class="hdr">§</a>

    @shuffle(comptime E: type, a: @Vector(a_len, E), b: @Vector(b_len, E), comptime mask: @Vector(mask_len, i32)) @Vector(mask_len, E)

Constructs a new [vector](#Vectors) by selecting elements from `a` and
`b` based on `mask`.

Each element in `mask` selects an element from either `a` or
`b`. Positive numbers select from `a` starting at 0.
Negative values select from `b`, starting at `-`<span class="tok-number">`1`</span> and going down.
It is recommended to use the `~` operator for indexes from `b`
so that both indexes can start from <span class="tok-number">`0`</span> (i.e. `~`<span class="tok-builtin">`@as`</span>`(`<span class="tok-type">`i32`</span>`, `<span class="tok-number">`0`</span>`)` is
`-`<span class="tok-number">`1`</span>).

For each element of `mask`, if it or the selected value from
`a` or `b` is <span class="tok-null">`undefined`</span>,
then the resulting element is <span class="tok-null">`undefined`</span>.

`a_len` and `b_len` may differ in length. Out-of-bounds element
indexes in `mask` result in compile errors.

If `a` or `b` is <span class="tok-null">`undefined`</span>, it
is equivalent to a vector of all <span class="tok-null">`undefined`</span> with the same length as the other vector.
If both vectors are <span class="tok-null">`undefined`</span>, <span class="tok-builtin">`@shuffle`</span> returns
a vector with all elements <span class="tok-null">`undefined`</span>.

`E` must be an [integer](#Integers), [float](#Floats),
[pointer](#Pointers), or <span class="tok-type">`bool`</span>. The mask may be any vector length, and its
length determines the result length.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @shuffle&quot; {
    const a = @Vector(7, u8){ &#39;o&#39;, &#39;l&#39;, &#39;h&#39;, &#39;e&#39;, &#39;r&#39;, &#39;z&#39;, &#39;w&#39; };
    const b = @Vector(4, u8){ &#39;w&#39;, &#39;d&#39;, &#39;!&#39;, &#39;x&#39; };

    // To shuffle within a single vector, pass undefined as the second argument.
    // Notice that we can re-order, duplicate, or omit elements of the input vector
    const mask1 = @Vector(5, i32){ 2, 3, 1, 1, 0 };
    const res1: @Vector(5, u8) = @shuffle(u8, a, undefined, mask1);
    try expect(std.mem.eql(u8, &amp;@as([5]u8, res1), &quot;hello&quot;));

    // Combining two vectors
    const mask2 = @Vector(6, i32){ -1, 0, 4, 1, -2, -3 };
    const res2: @Vector(6, u8) = @shuffle(u8, a, b, mask2);
    try expect(std.mem.eql(u8, &amp;@as([6]u8, res2), &quot;world!&quot;));
}</code></pre>
<figcaption>test_shuffle_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_shuffle_builtin.zig
1/1 test_shuffle_builtin.test.vector @shuffle...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Vectors](#Vectors)

### [@sizeOf](#toc-sizeOf) <a href="#sizeOf" class="hdr">§</a>

    @sizeOf(comptime T: type) comptime_int

This function returns the number of bytes it takes to store `T` in memory.
The result is a target-specific compile time constant.

This size may contain padding bytes. If there were two consecutive T in memory, the padding would be the offset
in bytes between element at index 0 and the element at index 1. For [integer](#Integers),
consider whether you want to use <span class="tok-builtin">`@sizeOf`</span>`(T)` or
<span class="tok-builtin">`@typeInfo`</span>`(T).int.bits`.

This function measures the size at runtime. For types that are disallowed at runtime, such as
<span class="tok-type">`comptime_int`</span> and <span class="tok-type">`type`</span>, the result is <span class="tok-number">`0`</span>.

See also:

- [@bitSizeOf](#bitSizeOf)
- [@typeInfo](#typeInfo)

### [@splat](#toc-splat) <a href="#splat" class="hdr">§</a>

    @splat(scalar: anytype) anytype

Produces an array or vector where each element is the value
`scalar`. The return type and thus the length of the
vector is inferred.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @splat&quot; {
    const scalar: u32 = 5;
    const result: @Vector(4, u32) = @splat(scalar);
    try expect(std.mem.eql(u32, &amp;@as([4]u32, result), &amp;[_]u32{ 5, 5, 5, 5 }));
}

test &quot;array @splat&quot; {
    const scalar: u32 = 5;
    const result: [4]u32 = @splat(scalar);
    try expect(std.mem.eql(u32, &amp;@as([4]u32, result), &amp;[_]u32{ 5, 5, 5, 5 }));
}</code></pre>
<figcaption>test_splat_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_splat_builtin.zig
1/2 test_splat_builtin.test.vector @splat...OK
2/2 test_splat_builtin.test.array @splat...OK
All 2 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

`scalar` must be an [integer](#Integers), [bool](#Primitive-Types),
[float](#Floats), or [pointer](#Pointers).

See also:

- [Vectors](#Vectors)
- [@shuffle](#shuffle)

### [@reduce](#toc-reduce) <a href="#reduce" class="hdr">§</a>

    @reduce(comptime op: std.builtin.ReduceOp, value: anytype) E

Transforms a [vector](#Vectors) into a scalar value (of type `E`)
by performing a sequential horizontal reduction of its elements using the
specified operator `op`.

Not every operator is available for every vector element type:

- Every operator is available for [integer](#Integers) vectors.
- `.And`, `.Or`,
  `.Xor` are additionally available for
  <span class="tok-type">`bool`</span> vectors,
- `.Min`, `.Max`,
  `.Add`, `.Mul` are
  additionally available for [floating point](#Floats) vectors,

Note that `.Add` and `.Mul`
reductions on integral types are wrapping; when applied on floating point
types the operation associativity is preserved, unless the float mode is
set to `Optimized`.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;vector @reduce&quot; {
    const V = @Vector(4, i32);
    const value = V{ 1, -1, 1, -1 };
    const result = value &gt; @as(V, @splat(0));
    // result is { true, false, true, false };
    try comptime expect(@TypeOf(result) == @Vector(4, bool));
    const is_all_true = @reduce(.And, result);
    try comptime expect(@TypeOf(is_all_true) == bool);
    try expect(is_all_true == false);
}</code></pre>
<figcaption>test_reduce_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_reduce_builtin.zig
1/1 test_reduce_builtin.test.vector @reduce...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Vectors](#Vectors)
- [@setFloatMode](#setFloatMode)

### [@src](#toc-src) <a href="#src" class="hdr">§</a>

    @src() std.builtin.SourceLocation

Returns a `SourceLocation` struct representing the function's name and location in the source code. This must be called in a function.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;@src&quot; {
    try doTheTest();
}

fn doTheTest() !void {
    const src = @src();

    try expect(src.line == 9);
    try expect(src.column == 17);
    try expect(std.mem.endsWith(u8, src.fn_name, &quot;doTheTest&quot;));
    try expect(std.mem.endsWith(u8, src.file, &quot;test_src_builtin.zig&quot;));
}</code></pre>
<figcaption>test_src_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_src_builtin.zig
1/1 test_src_builtin.test.@src...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@sqrt](#toc-sqrt) <a href="#sqrt" class="hdr">§</a>

    @sqrt(value: anytype) @TypeOf(value)

Performs the square root of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@sin](#toc-sin) <a href="#sin" class="hdr">§</a>

    @sin(value: anytype) @TypeOf(value)

Sine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@cos](#toc-cos) <a href="#cos" class="hdr">§</a>

    @cos(value: anytype) @TypeOf(value)

Cosine trigonometric function on a floating point number in radians. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@tan](#toc-tan) <a href="#tan" class="hdr">§</a>

    @tan(value: anytype) @TypeOf(value)

Tangent trigonometric function on a floating point number in radians.
Uses a dedicated hardware instruction when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@exp](#toc-exp) <a href="#exp" class="hdr">§</a>

    @exp(value: anytype) @TypeOf(value)

Base-e exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@exp2](#toc-exp2) <a href="#exp2" class="hdr">§</a>

    @exp2(value: anytype) @TypeOf(value)

Base-2 exponential function on a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@log](#toc-log) <a href="#log" class="hdr">§</a>

    @log(value: anytype) @TypeOf(value)

Returns the natural logarithm of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@log2](#toc-log2) <a href="#log2" class="hdr">§</a>

    @log2(value: anytype) @TypeOf(value)

Returns the logarithm to the base 2 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@log10](#toc-log10) <a href="#log10" class="hdr">§</a>

    @log10(value: anytype) @TypeOf(value)

Returns the logarithm to the base 10 of a floating point number. Uses a dedicated hardware instruction
when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@abs](#toc-abs) <a href="#abs" class="hdr">§</a>

    @abs(value: anytype) anytype

Returns the absolute value of an integer or a floating point number. Uses a dedicated hardware instruction
when available.
The return type is always an unsigned integer of the same bit width as the operand if the operand is an integer.
Unsigned integer operands are supported. The builtin cannot overflow for signed integer operands.

Supports [Floats](#Floats), [Integers](#Integers) and [Vectors](#Vectors) of floats or integers.

### [@floor](#toc-floor) <a href="#floor" class="hdr">§</a>

    @floor(value: anytype) @TypeOf(value)

Returns the largest integral value not greater than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@ceil](#toc-ceil) <a href="#ceil" class="hdr">§</a>

    @ceil(value: anytype) @TypeOf(value)

Returns the smallest integral value not less than the given floating point number.
Uses a dedicated hardware instruction when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@trunc](#toc-trunc) <a href="#trunc" class="hdr">§</a>

    @trunc(value: anytype) @TypeOf(value)

Rounds the given floating point number to an integer, towards zero.
Uses a dedicated hardware instruction when available.

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@round](#toc-round) <a href="#round" class="hdr">§</a>

    @round(value: anytype) @TypeOf(value)

Rounds the given floating point number to the nearest integer. If two integers are equally close, rounds away from zero.
Uses a dedicated hardware instruction when available.

<figure>
<pre><code>const expect = @import(&quot;std&quot;).testing.expect;

test &quot;@round&quot; {
    try expect(@round(1.4) == 1);
    try expect(@round(1.5) == 2);
    try expect(@round(-1.4) == -1);
    try expect(@round(-2.5) == -3);
}</code></pre>
<figcaption>test_round_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_round_builtin.zig
1/1 test_round_builtin.test.@round...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Supports [Floats](#Floats) and [Vectors](#Vectors) of floats.

### [@subWithOverflow](#toc-subWithOverflow) <a href="#subWithOverflow" class="hdr">§</a>

    @subWithOverflow(a: anytype, b: anytype) struct { @TypeOf(a, b), u1 }

Performs `a - b` and returns a tuple with the result and a possible overflow bit.

### [@tagName](#toc-tagName) <a href="#tagName" class="hdr">§</a>

    @tagName(value: anytype) [:0]const u8

Converts an enum value or union value to a string literal representing the name.

If the enum is non-exhaustive and the tag value does not map to a name, it invokes safety-checked [Illegal Behavior](#Illegal-Behavior).

### [@This](#toc-This) <a href="#This" class="hdr">§</a>

    @This() type

Returns the innermost struct, enum, or union that this function call is inside.
This can be useful for an anonymous struct that needs to refer to itself:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;@This()&quot; {
    var items = [_]i32{ 1, 2, 3, 4 };
    const list = List(i32){ .items = items[0..] };
    try expect(list.length() == 4);
}

fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,

        fn length(self: Self) usize {
            return self.items.len;
        }
    };
}</code></pre>
<figcaption>test_this_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_this_builtin.zig
1/1 test_this_builtin.test.@This()...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

When <span class="tok-builtin">`@This`</span>`()` is used at file scope, it returns a reference to the
struct that corresponds to the current file.

### [@trap](#toc-trap) <a href="#trap" class="hdr">§</a>

    @trap() noreturn

This function inserts a platform-specific trap/jam instruction which can be used to exit the program abnormally.
This may be implemented by explicitly emitting an invalid instruction which may cause an illegal instruction exception of some sort.
Unlike for <span class="tok-builtin">`@breakpoint`</span>`()`, execution does not continue after this point.

Outside function scope, this builtin causes a compile error.

See also:

- [@breakpoint](#breakpoint)

### [@truncate](#toc-truncate) <a href="#truncate" class="hdr">§</a>

    @truncate(integer: anytype) anytype

This function truncates bits from an integer type, resulting in a smaller
or same-sized integer type. The return type is the inferred result type.

This function always truncates the significant bits of the integer, regardless
of endianness on the target platform.

Calling <span class="tok-builtin">`@truncate`</span> on a number out of range of the destination type is well defined and working code:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;integer truncation&quot; {
    const a: u16 = 0xabcd;
    const b: u8 = @truncate(a);
    try expect(b == 0xcd);
}</code></pre>
<figcaption>test_truncate_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_truncate_builtin.zig
1/1 test_truncate_builtin.test.integer truncation...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Use [@intCast](#intCast) to convert numbers guaranteed to fit the destination type.

### [@Type](#toc-Type) <a href="#Type" class="hdr">§</a>

    @Type(comptime info: std.builtin.Type) type

This function is the inverse of [@typeInfo](#typeInfo). It reifies type information
into a <span class="tok-type">`type`</span>.

It is available for the following types:

- <span class="tok-type">`type`</span>
- <span class="tok-type">`noreturn`</span>
- <span class="tok-type">`void`</span>
- <span class="tok-type">`bool`</span>
- [Integers](#Integers) - The maximum bit count for an integer type is <span class="tok-number">`65535`</span>.
- [Floats](#Floats)
- [Pointers](#Pointers)
- <span class="tok-type">`comptime_int`</span>
- <span class="tok-type">`comptime_float`</span>
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`undefined`</span>`)`
- <span class="tok-builtin">`@TypeOf`</span>`(`<span class="tok-null">`null`</span>`)`
- [Arrays](#Arrays)
- [Optionals](#Optionals)
- [Error Set Type](#Error-Set-Type)
- [Error Union Type](#Error-Union-Type)
- [Vectors](#Vectors)
- [opaque](#opaque)
- <span class="tok-kw">`anyframe`</span>
- [struct](#struct)
- [enum](#enum)
- [Enum Literals](#Enum-Literals)
- [union](#union)
- [Functions](#Functions)

### [@typeInfo](#toc-typeInfo) <a href="#typeInfo" class="hdr">§</a>

    @typeInfo(comptime T: type) std.builtin.Type

Provides type reflection.

Type information of [structs](#struct), [unions](#union), [enums](#enum), and
[error sets](#Error-Set-Type) has fields which are guaranteed to be in the same
order as appearance in the source file.

Type information of [structs](#struct), [unions](#union), [enums](#enum), and
[opaques](#opaque) has declarations, which are also guaranteed to be in the same
order as appearance in the source file.

### [@typeName](#toc-typeName) <a href="#typeName" class="hdr">§</a>

    @typeName(T: type) *const [N:0]u8

This function returns the string representation of a type, as
an array. It is equivalent to a string literal of the type name.
The returned type name is fully qualified with the parent namespace included
as part of the type name with a series of dots.

### [@TypeOf](#toc-TypeOf) <a href="#TypeOf" class="hdr">§</a>

    @TypeOf(...) type

<span class="tok-builtin">`@TypeOf`</span> is a special builtin function that takes any (non-zero) number of expressions
as parameters and returns the type of the result, using [Peer Type Resolution](#Peer-Type-Resolution).

The expressions are evaluated, however they are guaranteed to have no *runtime* side-effects:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

test &quot;no runtime side effects&quot; {
    var data: i32 = 0;
    const T = @TypeOf(foo(i32, &amp;data));
    try comptime expect(T == i32);
    try expect(data == 0);
}

fn foo(comptime T: type, ptr: *T) T {
    ptr.* += 1;
    return ptr.*;
}</code></pre>
<figcaption>test_TypeOf_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_TypeOf_builtin.zig
1/1 test_TypeOf_builtin.test.no runtime side effects...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [@unionInit](#toc-unionInit) <a href="#unionInit" class="hdr">§</a>

    @unionInit(comptime Union: type, comptime active_field_name: []const u8, init_expr) Union

This is the same thing as [union](#union) initialization syntax, except that the field name is a
[comptime](#comptime)-known value rather than an identifier token.

<span class="tok-builtin">`@unionInit`</span> forwards its [result location](#Result-Location-Semantics) to `init_expr`.

### [@Vector](#toc-Vector) <a href="#Vector" class="hdr">§</a>

    @Vector(len: comptime_int, Element: type) type

Creates [Vectors](#Vectors).

### [@volatileCast](#toc-volatileCast) <a href="#volatileCast" class="hdr">§</a>

    @volatileCast(value: anytype) DestType

Remove <span class="tok-kw">`volatile`</span> qualifier from a pointer.

### [@workGroupId](#toc-workGroupId) <a href="#workGroupId" class="hdr">§</a>

    @workGroupId(comptime dimension: u32) u32

Returns the index of the work group in the current kernel invocation in dimension `dimension`.

### [@workGroupSize](#toc-workGroupSize) <a href="#workGroupSize" class="hdr">§</a>

    @workGroupSize(comptime dimension: u32) u32

Returns the number of work items that a work group has in dimension `dimension`.

### [@workItemId](#toc-workItemId) <a href="#workItemId" class="hdr">§</a>

    @workItemId(comptime dimension: u32) u32

Returns the index of the work item in the work group in dimension `dimension`. This function returns values between <span class="tok-number">`0`</span> (inclusive) and <span class="tok-builtin">`@workGroupSize`</span>`(dimension)` (exclusive).

## [Build Mode](#toc-Build-Mode) <a href="#Build-Mode" class="hdr">§</a>

Zig has four build modes:

- [Debug](#Debug) (default)
- [ReleaseFast](#ReleaseFast)
- [ReleaseSafe](#ReleaseSafe)
- [ReleaseSmall](#ReleaseSmall)

To add standard build options to a `build.zig` file:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;example&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;example.zig&quot;),
            .optimize = optimize,
        }),
    });
    b.default_step.dependOn(&amp;exe.step);
}</code></pre>
<figcaption>build.zig</figcaption>
</figure>

This causes these options to be available:

<span class="kbd">-Doptimize=Debug</span>  
Optimizations off and safety on (default)

<span class="kbd">-Doptimize=ReleaseSafe</span>  
Optimizations on and safety on

<span class="kbd">-Doptimize=ReleaseFast</span>  
Optimizations on and safety off

<span class="kbd">-Doptimize=ReleaseSmall</span>  
Size optimizations on and safety off

### [Debug](#toc-Debug) <a href="#Debug" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Fast compilation speed
- Safety checks enabled
- Slow runtime performance
- Large binary size
- No reproducible build requirement

### [ReleaseFast](#toc-ReleaseFast) <a href="#ReleaseFast" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseFast</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Fast runtime performance
- Safety checks disabled
- Slow compilation speed
- Large binary size
- Reproducible build

### [ReleaseSafe](#toc-ReleaseSafe) <a href="#ReleaseSafe" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseSafe</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Medium runtime performance
- Safety checks enabled
- Slow compilation speed
- Large binary size
- Reproducible build

### [ReleaseSmall](#toc-ReleaseSmall) <a href="#ReleaseSmall" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseSmall</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Medium runtime performance
- Safety checks disabled
- Slow compilation speed
- Small binary size
- Reproducible build

See also:

- [Compile Variables](#Compile-Variables)
- [Zig Build System](#Zig-Build-System)
- [Illegal Behavior](#Illegal-Behavior)

## [Single Threaded Builds](#toc-Single-Threaded-Builds) <a href="#Single-Threaded-Builds" class="hdr">§</a>

Zig has a compile option <span class="kbd">-fsingle-threaded</span> which has the following effects:

- All [Thread Local Variables](#Thread-Local-Variables) are treated as regular [Container Level Variables](#Container-Level-Variables).
- The overhead of [Async Functions](#Async-Functions) becomes equivalent to function call overhead.
- The <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`).single_threaded` becomes <span class="tok-null">`true`</span>
  and therefore various userland APIs which read this variable become more efficient.
  For example `std.Mutex` becomes
  an empty data structure and all of its functions become no-ops.

## [Illegal Behavior](#toc-Illegal-Behavior) <a href="#Illegal-Behavior" class="hdr">§</a>

Many operations in Zig trigger what is known as "Illegal Behavior" (IB). If Illegal Behavior is detected at
compile-time, Zig emits a compile error and refuses to continue. Otherwise, when Illegal Behavior is not caught
at compile-time, it falls into one of two categories.

Some Illegal Behavior is *safety-checked*: this means that the compiler will insert "safety checks"
anywhere that the Illegal Behavior may occur at runtime, to determine whether it is about to happen. If it
is, the safety check "fails", which triggers a panic.

All other Illegal Behavior is *unchecked*, meaning the compiler is unable to insert safety checks for
it. If Unchecked Illegal Behavior is invoked at runtime, anything can happen: usually that will be some kind of
crash, but the optimizer is free to make Unchecked Illegal Behavior do anything, such as calling arbitrary functions
or clobbering arbitrary data. This is similar to the concept of "undefined behavior" in some other languages. Note that
Unchecked Illegal Behavior still always results in a compile error if evaluated at [comptime](#comptime), because the Zig
compiler is able to perform more sophisticated checks at compile-time than at runtime.

Most Illegal Behavior is safety-checked. However, to facilitate optimizations, safety checks are disabled by default
in the [ReleaseFast](#ReleaseFast) and [ReleaseSmall](#ReleaseSmall) optimization modes. Safety checks can also be enabled or disabled
on a per-block basis, overriding the default for the current optimization mode, using [@setRuntimeSafety](#setRuntimeSafety). When
safety checks are disabled, Safety-Checked Illegal Behavior behaves like Unchecked Illegal Behavior; that is, any behavior
may result from invoking it.

When a safety check fails, Zig's default panic handler crashes with a stack trace, like this:

<figure>
<pre><code>test &quot;safety check&quot; {
    unreachable;
}</code></pre>
<figcaption>test_illegal_behavior.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_illegal_behavior.zig
1/1 test_illegal_behavior.test.safety check...thread 1095219 panic: reached unreachable code
/home/andy/dev/zig/doc/langref/test_illegal_behavior.zig:2:5: 0x102c00c in test.safety check (test_illegal_behavior.zig)
    unreachable;
    ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:218:25: 0x115cb00 in mainTerminal (test_runner.zig)
        if (test_fn.func()) |_| {
                        ^
/home/andy/dev/zig/lib/compiler/test_runner.zig:66:28: 0x1155d21 in main (test_runner.zig)
        return mainTerminal();
                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x114fabd in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x114f351 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
error: the following test command crashed:
/home/andy/dev/zig/.zig-cache/o/65a0232d3a5c4bf204eadafcbceee32c/test --seed=0xb567ab3d</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Reaching Unreachable Code](#toc-Reaching-Unreachable-Code) <a href="#Reaching-Unreachable-Code" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    assert(false);
}
fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}</code></pre>
<figcaption>test_comptime_reaching_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_reaching_unreachable.zig
/home/andy/dev/zig/doc/langref/test_comptime_reaching_unreachable.zig:5:14: error: reached unreachable code
    if (!ok) unreachable; // assertion failure
             ^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_reaching_unreachable.zig:2:11: note: called at comptime here
    assert(false);
    ~~~~~~^~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    std.debug.assert(false);
}</code></pre>
<figcaption>runtime_reaching_unreachable.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_reaching_unreachable.zig
$ ./runtime_reaching_unreachable
thread 1098849 panic: reached unreachable code
/home/andy/dev/zig/lib/std/debug.zig:559:14: 0x1044179 in assert (std.zig)
    if (!ok) unreachable; // assertion failure
             ^
/home/andy/dev/zig/doc/langref/runtime_reaching_unreachable.zig:4:21: 0x113e84e in main (runtime_reaching_unreachable.zig)
    std.debug.assert(false);
                    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Index out of Bounds](#toc-Index-out-of-Bounds) <a href="#Index-out-of-Bounds" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const array: [5]u8 = &quot;hello&quot;.*;
    const garbage = array[5];
    _ = garbage;
}</code></pre>
<figcaption>test_comptime_index_out_of_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_index_out_of_bounds.zig
/home/andy/dev/zig/doc/langref/test_comptime_index_out_of_bounds.zig:3:27: error: index 5 outside array of length 5
    const garbage = array[5];
                          ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    const x = foo(&quot;hello&quot;);
    _ = x;
}

fn foo(x: []const u8) u8 {
    return x[5];
}</code></pre>
<figcaption>runtime_index_out_of_bounds.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_index_out_of_bounds.zig
$ ./runtime_index_out_of_bounds
thread 1098063 panic: index out of bounds: index 5, len 5
/home/andy/dev/zig/doc/langref/runtime_index_out_of_bounds.zig:7:13: 0x113fac6 in foo (runtime_index_out_of_bounds.zig)
    return x[5];
            ^
/home/andy/dev/zig/doc/langref/runtime_index_out_of_bounds.zig:2:18: 0x113e85a in main (runtime_index_out_of_bounds.zig)
    const x = foo(&quot;hello&quot;);
                 ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Cast Negative Number to Unsigned Integer](#toc-Cast-Negative-Number-to-Unsigned-Integer) <a href="#Cast-Negative-Number-to-Unsigned-Integer" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const value: i32 = -1;
    const unsigned: u32 = @intCast(value);
    _ = unsigned;
}</code></pre>
<figcaption>test_comptime_invalid_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_cast.zig:3:36: error: type &#39;u32&#39; cannot represent integer value &#39;-1&#39;
    const unsigned: u32 = @intCast(value);
                                   ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var value: i32 = -1; // runtime-known
    _ = &amp;value;
    const unsigned: u32 = @intCast(value);
    std.debug.print(&quot;value: {}\n&quot;, .{unsigned});
}</code></pre>
<figcaption>runtime_invalid_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_cast.zig
$ ./runtime_invalid_cast
thread 1099031 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/runtime_invalid_cast.zig:6:27: 0x113e85f in main (runtime_invalid_cast.zig)
    const unsigned: u32 = @intCast(value);
                          ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

To obtain the maximum value of an unsigned integer, use `std.math.maxInt`.

### [Cast Truncates Data](#toc-Cast-Truncates-Data) <a href="#Cast-Truncates-Data" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const spartan_count: u16 = 300;
    const byte: u8 = @intCast(spartan_count);
    _ = byte;
}</code></pre>
<figcaption>test_comptime_invalid_cast_truncate.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_cast_truncate.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_cast_truncate.zig:3:31: error: type &#39;u8&#39; cannot represent integer value &#39;300&#39;
    const byte: u8 = @intCast(spartan_count);
                              ^~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var spartan_count: u16 = 300; // runtime-known
    _ = &amp;spartan_count;
    const byte: u8 = @intCast(spartan_count);
    std.debug.print(&quot;value: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>runtime_invalid_cast_truncate.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_cast_truncate.zig
$ ./runtime_invalid_cast_truncate
thread 1101249 panic: integer does not fit in destination type
/home/andy/dev/zig/doc/langref/runtime_invalid_cast_truncate.zig:6:22: 0x113e860 in main (runtime_invalid_cast_truncate.zig)
    const byte: u8 = @intCast(spartan_count);
                     ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

To truncate bits, use [@truncate](#truncate).

### [Integer Overflow](#toc-Integer-Overflow) <a href="#Integer-Overflow" class="hdr">§</a>

#### [Default Operations](#toc-Default-Operations) <a href="#Default-Operations" class="hdr">§</a>

The following operators can cause integer overflow:

- `+` (addition)
- `-` (subtraction)
- `-` (negation)
- `*` (multiplication)
- `/` (division)
- [@divTrunc](#divTrunc) (division)
- [@divFloor](#divFloor) (division)
- [@divExact](#divExact) (division)

Example with addition at compile-time:

<figure>
<pre><code>comptime {
    var byte: u8 = 255;
    byte += 1;
}</code></pre>
<figcaption>test_comptime_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_overflow.zig:3:10: error: overflow of integer type &#39;u8&#39; with value &#39;256&#39;
    byte += 1;
    ~~~~~^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var byte: u8 = 255;
    byte += 1;
    std.debug.print(&quot;value: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>runtime_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_overflow.zig
$ ./runtime_overflow
thread 1095998 panic: integer overflow
/home/andy/dev/zig/doc/langref/runtime_overflow.zig:5:10: 0x113e875 in main (runtime_overflow.zig)
    byte += 1;
         ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Standard Library Math Functions](#toc-Standard-Library-Math-Functions) <a href="#Standard-Library-Math-Functions" class="hdr">§</a>

These functions provided by the standard library return possible errors.

- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.add`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.sub`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.mul`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divTrunc`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divFloor`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.divExact`
- <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`).math.shl`

Example of catching an overflow for addition:

<figure>
<pre><code>const math = @import(&quot;std&quot;).math;
const print = @import(&quot;std&quot;).debug.print;
pub fn main() !void {
    var byte: u8 = 255;

    byte = if (math.add(u8, byte, 1)) |result| result else |err| {
        print(&quot;unable to add one: {s}\n&quot;, .{@errorName(err)});
        return err;
    };

    print(&quot;result: {}\n&quot;, .{byte});
}</code></pre>
<figcaption>math_add.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe math_add.zig
$ ./math_add
unable to add one: Overflow
error: Overflow
/home/andy/dev/zig/lib/std/math.zig:570:21: 0x113eb8e in add__anon_22554 (std.zig)
    if (ov[1] != 0) return error.Overflow;
                    ^
/home/andy/dev/zig/doc/langref/math_add.zig:8:9: 0x113d402 in main (math_add.zig)
        return err;
        ^</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Builtin Overflow Functions](#toc-Builtin-Overflow-Functions) <a href="#Builtin-Overflow-Functions" class="hdr">§</a>

These builtins return a tuple containing whether there was an overflow
(as a <span class="tok-type">`u1`</span>) and the possibly overflowed bits of the operation:

- [@addWithOverflow](#addWithOverflow)
- [@subWithOverflow](#subWithOverflow)
- [@mulWithOverflow](#mulWithOverflow)
- [@shlWithOverflow](#shlWithOverflow)

Example of [@addWithOverflow](#addWithOverflow):

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;
pub fn main() void {
    const byte: u8 = 255;

    const ov = @addWithOverflow(byte, 10);
    if (ov[1] != 0) {
        print(&quot;overflowed result: {}\n&quot;, .{ov[0]});
    } else {
        print(&quot;result: {}\n&quot;, .{ov[0]});
    }
}</code></pre>
<figcaption>addWithOverflow_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe addWithOverflow_builtin.zig
$ ./addWithOverflow_builtin
overflowed result: 9</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [Wrapping Operations](#toc-Wrapping-Operations) <a href="#Wrapping-Operations" class="hdr">§</a>

These operations have guaranteed wraparound semantics.

- `+%` (wraparound addition)
- `-%` (wraparound subtraction)
- `-%` (wraparound negation)
- `*%` (wraparound multiplication)

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;

test &quot;wraparound addition and subtraction&quot; {
    const x: i32 = maxInt(i32);
    const min_val = x +% 1;
    try expect(min_val == minInt(i32));
    const max_val = min_val -% 1;
    try expect(max_val == maxInt(i32));
}</code></pre>
<figcaption>test_wraparound_semantics.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_wraparound_semantics.zig
1/1 test_wraparound_semantics.test.wraparound addition and subtraction...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Left Shift Overflow](#toc-Exact-Left-Shift-Overflow) <a href="#Exact-Left-Shift-Overflow" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const x = @shlExact(@as(u8, 0b01010101), 2);
    _ = x;
}</code></pre>
<figcaption>test_comptime_shlExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_shlExact_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_shlExact_overflow.zig:2:15: error: overflow of integer type &#39;u8&#39; with value &#39;340&#39;
    const x = @shlExact(@as(u8, 0b01010101), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var x: u8 = 0b01010101; // runtime-known
    _ = &amp;x;
    const y = @shlExact(x, 2);
    std.debug.print(&quot;value: {}\n&quot;, .{y});
}</code></pre>
<figcaption>runtime_shlExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_shlExact_overflow.zig
$ ./runtime_shlExact_overflow
thread 1097953 panic: left shift overflowed bits
/home/andy/dev/zig/doc/langref/runtime_shlExact_overflow.zig:6:5: 0x113e881 in main (runtime_shlExact_overflow.zig)
    const y = @shlExact(x, 2);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Right Shift Overflow](#toc-Exact-Right-Shift-Overflow) <a href="#Exact-Right-Shift-Overflow" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const x = @shrExact(@as(u8, 0b10101010), 2);
    _ = x;
}</code></pre>
<figcaption>test_comptime_shrExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_shrExact_overflow.zig
/home/andy/dev/zig/doc/langref/test_comptime_shrExact_overflow.zig:2:15: error: exact shift shifted out 1 bits
    const x = @shrExact(@as(u8, 0b10101010), 2);
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const builtin = @import(&quot;builtin&quot;);
const std = @import(&quot;std&quot;);

pub fn main() void {
    var x: u8 = 0b10101010; // runtime-known
    _ = &amp;x;
    const y = @shrExact(x, 2);
    std.debug.print(&quot;value: {}\n&quot;, .{y});

    if (builtin.cpu.arch.isRISCV() and builtin.zig_backend == .stage2_llvm) @panic(&quot;https://github.com/ziglang/zig/issues/24304&quot;);
}</code></pre>
<figcaption>runtime_shrExact_overflow.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_shrExact_overflow.zig
$ ./runtime_shrExact_overflow
thread 1099637 panic: right shift overflowed bits
/home/andy/dev/zig/doc/langref/runtime_shrExact_overflow.zig:7:5: 0x113e86a in main (runtime_shrExact_overflow.zig)
    const y = @shrExact(x, 2);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Division by Zero](#toc-Division-by-Zero) <a href="#Division-by-Zero" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: i32 = 1;
    const b: i32 = 0;
    const c = a / b;
    _ = c;
}</code></pre>
<figcaption>test_comptime_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_division_by_zero.zig
/home/andy/dev/zig/doc/langref/test_comptime_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a / b;
                  ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 1;
    var b: u32 = 0;
    _ = .{ &amp;a, &amp;b };
    const c = a / b;
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_division_by_zero.zig
$ ./runtime_division_by_zero
thread 1091859 panic: division by zero
/home/andy/dev/zig/doc/langref/runtime_division_by_zero.zig:7:17: 0x113e870 in main (runtime_division_by_zero.zig)
    const c = a / b;
                ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Remainder Division by Zero](#toc-Remainder-Division-by-Zero) <a href="#Remainder-Division-by-Zero" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: i32 = 10;
    const b: i32 = 0;
    const c = a % b;
    _ = c;
}</code></pre>
<figcaption>test_comptime_remainder_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_remainder_division_by_zero.zig
/home/andy/dev/zig/doc/langref/test_comptime_remainder_division_by_zero.zig:4:19: error: division by zero here causes illegal behavior
    const c = a % b;
                  ^
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 0;
    _ = .{ &amp;a, &amp;b };
    const c = a % b;
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_remainder_division_by_zero.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_remainder_division_by_zero.zig
$ ./runtime_remainder_division_by_zero
thread 1099159 panic: division by zero
/home/andy/dev/zig/doc/langref/runtime_remainder_division_by_zero.zig:7:17: 0x113e870 in main (runtime_remainder_division_by_zero.zig)
    const c = a % b;
                ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exact Division Remainder](#toc-Exact-Division-Remainder) <a href="#Exact-Division-Remainder" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const a: u32 = 10;
    const b: u32 = 3;
    const c = @divExact(a, b);
    _ = c;
}</code></pre>
<figcaption>test_comptime_divExact_remainder.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_divExact_remainder.zig
/home/andy/dev/zig/doc/langref/test_comptime_divExact_remainder.zig:4:15: error: exact division produced remainder
    const c = @divExact(a, b);
              ^~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var a: u32 = 10;
    var b: u32 = 3;
    _ = .{ &amp;a, &amp;b };
    const c = @divExact(a, b);
    std.debug.print(&quot;value: {}\n&quot;, .{c});
}</code></pre>
<figcaption>runtime_divExact_remainder.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_divExact_remainder.zig
$ ./runtime_divExact_remainder
thread 1093460 panic: exact division produced remainder
/home/andy/dev/zig/doc/langref/runtime_divExact_remainder.zig:7:15: 0x113e8a7 in main (runtime_divExact_remainder.zig)
    const c = @divExact(a, b);
              ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Attempt to Unwrap Null](#toc-Attempt-to-Unwrap-Null) <a href="#Attempt-to-Unwrap-Null" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const optional_number: ?i32 = null;
    const number = optional_number.?;
    _ = number;
}</code></pre>
<figcaption>test_comptime_unwrap_null.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_unwrap_null.zig
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_null.zig:3:35: error: unable to unwrap null
    const number = optional_number.?;
                   ~~~~~~~~~~~~~~~^~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    var optional_number: ?i32 = null;
    _ = &amp;optional_number;
    const number = optional_number.?;
    std.debug.print(&quot;value: {}\n&quot;, .{number});
}</code></pre>
<figcaption>runtime_unwrap_null.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_unwrap_null.zig
$ ./runtime_unwrap_null
thread 1094411 panic: attempt to use null value
/home/andy/dev/zig/doc/langref/runtime_unwrap_null.zig:6:35: 0x113e894 in main (runtime_unwrap_null.zig)
    const number = optional_number.?;
                                  ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

One way to avoid this crash is to test for null instead of assuming non-null, with
the <span class="tok-kw">`if`</span> expression:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;
pub fn main() void {
    const optional_number: ?i32 = null;

    if (optional_number) |number| {
        print(&quot;got number: {}\n&quot;, .{number});
    } else {
        print(&quot;it&#39;s null\n&quot;, .{});
    }
}</code></pre>
<figcaption>testing_null_with_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe testing_null_with_if.zig
$ ./testing_null_with_if
it&#39;s null</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Optionals](#Optionals)

### [Attempt to Unwrap Error](#toc-Attempt-to-Unwrap-Error) <a href="#Attempt-to-Unwrap-Error" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const number = getNumberOrFail() catch unreachable;
    _ = number;
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>test_comptime_unwrap_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_unwrap_error.zig
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_error.zig:2:44: error: caught unexpected error &#39;UnableToReturnNumber&#39;
    const number = getNumberOrFail() catch unreachable;
                                           ^~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_unwrap_error.zig:7:18: note: error returned here
    return error.UnableToReturnNumber;
                 ^~~~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const number = getNumberOrFail() catch unreachable;
    std.debug.print(&quot;value: {}\n&quot;, .{number});
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>runtime_unwrap_error.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_unwrap_error.zig
$ ./runtime_unwrap_error
thread 1091973 panic: attempt to unwrap error: UnableToReturnNumber
/home/andy/dev/zig/doc/langref/runtime_unwrap_error.zig:9:5: 0x113e84c in getNumberOrFail (runtime_unwrap_error.zig)
    return error.UnableToReturnNumber;
    ^
/home/andy/dev/zig/doc/langref/runtime_unwrap_error.zig:4:44: 0x113e8b3 in main (runtime_unwrap_error.zig)
    const number = getNumberOrFail() catch unreachable;
                                           ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

One way to avoid this crash is to test for an error instead of assuming a successful result, with
the <span class="tok-kw">`if`</span> expression:

<figure>
<pre><code>const print = @import(&quot;std&quot;).debug.print;

pub fn main() void {
    const result = getNumberOrFail();

    if (result) |number| {
        print(&quot;got number: {}\n&quot;, .{number});
    } else |err| {
        print(&quot;got error: {s}\n&quot;, .{@errorName(err)});
    }
}

fn getNumberOrFail() !i32 {
    return error.UnableToReturnNumber;
}</code></pre>
<figcaption>testing_error_with_if.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe testing_error_with_if.zig
$ ./testing_error_with_if
got error: UnableToReturnNumber</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Errors](#Errors)

### [Invalid Error Code](#toc-Invalid-Error-Code) <a href="#Invalid-Error-Code" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const err = error.AnError;
    const number = @intFromError(err) + 10;
    const invalid_err = @errorFromInt(number);
    _ = invalid_err;
}</code></pre>
<figcaption>test_comptime_invalid_error_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_error_code.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_error_code.zig:4:39: error: integer value &#39;11&#39; represents no error
    const invalid_err = @errorFromInt(number);
                                      ^~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() void {
    const err = error.AnError;
    var number = @intFromError(err) + 500;
    _ = &amp;number;
    const invalid_err = @errorFromInt(number);
    std.debug.print(&quot;value: {}\n&quot;, .{invalid_err});
}</code></pre>
<figcaption>runtime_invalid_error_code.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_error_code.zig
$ ./runtime_invalid_error_code
thread 1091971 panic: invalid error code
/home/andy/dev/zig/doc/langref/runtime_invalid_error_code.zig:7:5: 0x113e887 in main (runtime_invalid_error_code.zig)
    const invalid_err = @errorFromInt(number);
    ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Invalid Enum Cast](#toc-Invalid-Enum-Cast) <a href="#Invalid-Enum-Cast" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>const Foo = enum {
    a,
    b,
    c,
};
comptime {
    const a: u2 = 3;
    const b: Foo = @enumFromInt(a);
    _ = b;
}</code></pre>
<figcaption>test_comptime_invalid_enum_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_enum_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_enum_cast.zig:8:20: error: enum &#39;test_comptime_invalid_enum_cast.Foo&#39; has no tag with value &#39;3&#39;
    const b: Foo = @enumFromInt(a);
                   ^~~~~~~~~~~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_invalid_enum_cast.zig:1:13: note: enum declared here
const Foo = enum {
            ^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = enum {
    a,
    b,
    c,
};

pub fn main() void {
    var a: u2 = 3;
    _ = &amp;a;
    const b: Foo = @enumFromInt(a);
    std.debug.print(&quot;value: {s}\n&quot;, .{@tagName(b)});
}</code></pre>
<figcaption>runtime_invalid_enum_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_enum_cast.zig
$ ./runtime_invalid_enum_cast
thread 1092133 panic: invalid enum value
/home/andy/dev/zig/doc/langref/runtime_invalid_enum_cast.zig:12:20: 0x113e8d0 in main (runtime_invalid_enum_cast.zig)
    const b: Foo = @enumFromInt(a);
                   ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Invalid Error Set Cast](#toc-Invalid-Error-Set-Cast) <a href="#Invalid-Error-Set-Cast" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
comptime {
    _ = @as(Set2, @errorCast(Set1.B));
}</code></pre>
<figcaption>test_comptime_invalid_error_set_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_error_set_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_error_set_cast.zig:10:19: error: &#39;error.B&#39; not a member of error set &#39;error{A,C}&#39;
    _ = @as(Set2, @errorCast(Set1.B));
                  ^~~~~~~~~~~~~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Set1 = error{
    A,
    B,
};
const Set2 = error{
    A,
    C,
};
pub fn main() void {
    foo(Set1.B);
}
fn foo(set1: Set1) void {
    const x: Set2 = @errorCast(set1);
    std.debug.print(&quot;value: {}\n&quot;, .{x});
}</code></pre>
<figcaption>runtime_invalid_error_set_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_error_set_cast.zig
$ ./runtime_invalid_error_set_cast
thread 1096585 panic: invalid error code
/home/andy/dev/zig/doc/langref/runtime_invalid_error_set_cast.zig:15:21: 0x113fb1c in foo (runtime_invalid_error_set_cast.zig)
    const x: Set2 = @errorCast(set1);
                    ^
/home/andy/dev/zig/doc/langref/runtime_invalid_error_set_cast.zig:12:8: 0x113e857 in main (runtime_invalid_error_set_cast.zig)
    foo(Set1.B);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Incorrect Pointer Alignment](#toc-Incorrect-Pointer-Alignment) <a href="#Incorrect-Pointer-Alignment" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    const ptr: *align(1) i32 = @ptrFromInt(0x1);
    const aligned: *align(4) i32 = @alignCast(ptr);
    _ = aligned;
}</code></pre>
<figcaption>test_comptime_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_incorrect_pointer_alignment.zig
/home/andy/dev/zig/doc/langref/test_comptime_incorrect_pointer_alignment.zig:3:47: error: pointer address 0x1 is not aligned to 4 bytes
    const aligned: *align(4) i32 = @alignCast(ptr);
                                              ^~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const mem = @import(&quot;std&quot;).mem;
pub fn main() !void {
    var array align(4) = [_]u32{ 0x11111111, 0x11111111 };
    const bytes = mem.sliceAsBytes(array[0..]);
    if (foo(bytes) != 0x11111111) return error.Wrong;
}
fn foo(bytes: []u8) u32 {
    const slice4 = bytes[1..5];
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
    return int_slice[0];
}</code></pre>
<figcaption>runtime_incorrect_pointer_alignment.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_incorrect_pointer_alignment.zig
$ ./runtime_incorrect_pointer_alignment
thread 1097866 panic: incorrect alignment
/home/andy/dev/zig/doc/langref/runtime_incorrect_pointer_alignment.zig:9:64: 0x113ebe8 in foo (runtime_incorrect_pointer_alignment.zig)
    const int_slice = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                               ^
/home/andy/dev/zig/doc/langref/runtime_incorrect_pointer_alignment.zig:5:12: 0x113d3d2 in main (runtime_incorrect_pointer_alignment.zig)
    if (foo(bytes) != 0x11111111) return error.Wrong;
           ^
/home/andy/dev/zig/lib/std/start.zig:627:37: 0x113dba9 in posixCallMainAndExit (std.zig)
            const result = root.main() catch |err| {
                                    ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Wrong Union Field Access](#toc-Wrong-Union-Field-Access) <a href="#Wrong-Union-Field-Access" class="hdr">§</a>

At compile-time:

<figure>
<pre><code>comptime {
    var f = Foo{ .int = 42 };
    f.float = 12.34;
}

const Foo = union {
    float: f32,
    int: u32,
};</code></pre>
<figcaption>test_comptime_wrong_union_field_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_wrong_union_field_access.zig
/home/andy/dev/zig/doc/langref/test_comptime_wrong_union_field_access.zig:3:6: error: access of union field &#39;float&#39; while field &#39;int&#39; is active
    f.float = 12.34;
    ~^~~~~~
/home/andy/dev/zig/doc/langref/test_comptime_wrong_union_field_access.zig:6:13: note: union declared here
const Foo = union {
            ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&amp;f);
}

fn bar(f: *Foo) void {
    f.float = 12.34;
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}</code></pre>
<figcaption>runtime_wrong_union_field_access.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_wrong_union_field_access.zig
$ ./runtime_wrong_union_field_access
thread 1093352 panic: access of union field &#39;float&#39; while field &#39;int&#39; is active
/home/andy/dev/zig/doc/langref/runtime_wrong_union_field_access.zig:14:6: 0x113fafe in bar (runtime_wrong_union_field_access.zig)
    f.float = 12.34;
     ^
/home/andy/dev/zig/doc/langref/runtime_wrong_union_field_access.zig:10:8: 0x113e87f in main (runtime_wrong_union_field_access.zig)
    bar(&amp;f);
       ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

This safety is not available for <span class="tok-kw">`extern`</span> or <span class="tok-kw">`packed`</span> unions.

To change the active field of a union, assign the entire union, like this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    bar(&amp;f);
}

fn bar(f: *Foo) void {
    f.* = Foo{ .float = 12.34 };
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}</code></pre>
<figcaption>change_active_union_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe change_active_union_field.zig
$ ./change_active_union_field
value: 12.34</code></pre>
<figcaption>Shell</figcaption>
</figure>

To change the active field of a union when a meaningful value for the field is not known,
use [undefined](#undefined), like this:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

const Foo = union {
    float: f32,
    int: u32,
};

pub fn main() void {
    var f = Foo{ .int = 42 };
    f = Foo{ .float = undefined };
    bar(&amp;f);
    std.debug.print(&quot;value: {}\n&quot;, .{f.float});
}

fn bar(f: *Foo) void {
    f.float = 12.34;
}</code></pre>
<figcaption>undefined_active_union_field.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe undefined_active_union_field.zig
$ ./undefined_active_union_field
value: 12.34</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [union](#union)
- [extern union](#extern-union)

### [Out of Bounds Float to Integer Cast](#toc-Out-of-Bounds-Float-to-Integer-Cast) <a href="#Out-of-Bounds-Float-to-Integer-Cast" class="hdr">§</a>

This happens when casting a float to an integer where the float has a value outside the
integer type's range.

At compile-time:

<figure>
<pre><code>comptime {
    const float: f32 = 4294967296;
    const int: i32 = @intFromFloat(float);
    _ = int;
}</code></pre>
<figcaption>test_comptime_out_of_bounds_float_to_integer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_out_of_bounds_float_to_integer_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_out_of_bounds_float_to_integer_cast.zig:3:36: error: float value &#39;4294967296&#39; cannot be stored in integer type &#39;i32&#39;
    const int: i32 = @intFromFloat(float);
                                   ^~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    var float: f32 = 4294967296; // runtime-known
    _ = &amp;float;
    const int: i32 = @intFromFloat(float);
    _ = int;
}</code></pre>
<figcaption>runtime_out_of_bounds_float_to_integer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_out_of_bounds_float_to_integer_cast.zig
$ ./runtime_out_of_bounds_float_to_integer_cast
thread 1101276 panic: integer part of floating point value out of bounds
/home/andy/dev/zig/doc/langref/runtime_out_of_bounds_float_to_integer_cast.zig:4:22: 0x113e8b2 in main (runtime_out_of_bounds_float_to_integer_cast.zig)
    const int: i32 = @intFromFloat(float);
                     ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Pointer Cast Invalid Null](#toc-Pointer-Cast-Invalid-Null) <a href="#Pointer-Cast-Invalid-Null" class="hdr">§</a>

This happens when casting a pointer with the address 0 to a pointer which may not have the address 0.
For example, [C Pointers](#C-Pointers), [Optional Pointers](#Optional-Pointers), and [allowzero](#allowzero) pointers
allow address zero, but normal [Pointers](#Pointers) do not.

At compile-time:

<figure>
<pre><code>comptime {
    const opt_ptr: ?*i32 = null;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}</code></pre>
<figcaption>test_comptime_invalid_null_pointer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_comptime_invalid_null_pointer_cast.zig
/home/andy/dev/zig/doc/langref/test_comptime_invalid_null_pointer_cast.zig:3:32: error: null pointer casted to type &#39;*i32&#39;
    const ptr: *i32 = @ptrCast(opt_ptr);
                               ^~~~~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

At runtime:

<figure>
<pre><code>pub fn main() void {
    var opt_ptr: ?*i32 = null;
    _ = &amp;opt_ptr;
    const ptr: *i32 = @ptrCast(opt_ptr);
    _ = ptr;
}</code></pre>
<figcaption>runtime_invalid_null_pointer_cast.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe runtime_invalid_null_pointer_cast.zig
$ ./runtime_invalid_null_pointer_cast
thread 1100207 panic: cast causes pointer to be null
/home/andy/dev/zig/doc/langref/runtime_invalid_null_pointer_cast.zig:4:23: 0x113e86a in main (runtime_invalid_null_pointer_cast.zig)
    const ptr: *i32 = @ptrCast(opt_ptr);
                      ^
/home/andy/dev/zig/lib/std/start.zig:618:22: 0x113da9d in posixCallMainAndExit (std.zig)
            root.main();
                     ^
/home/andy/dev/zig/lib/std/start.zig:232:5: 0x113d331 in _start (std.zig)
    asm volatile (switch (native_arch) {
    ^
???:?:?: 0x0 in ??? (???)
(process terminated by signal)</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Memory](#toc-Memory) <a href="#Memory" class="hdr">§</a>

The Zig language performs no memory management on behalf of the programmer. This is
why Zig has no runtime, and why Zig code works seamlessly in so many environments,
including real-time software, operating system kernels, embedded devices, and
low latency servers. As a consequence, Zig programmers must always be able to answer
the question:

[Where are the bytes?](#Where-are-the-bytes)

Like Zig, the C programming language has manual memory management. However, unlike Zig,
C has a default allocator - `malloc`, `realloc`, and `free`.
When linking against libc, Zig exposes this allocator with `std.heap.c_allocator`.
However, by convention, there is no default allocator in Zig. Instead, functions which need to
allocate accept an `Allocator` parameter. Likewise, some data structures
accept an `Allocator` parameter in their initialization functions:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

test &quot;using an allocator&quot; {
    var buffer: [100]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&amp;buffer);
    const allocator = fba.allocator();
    const result = try concat(allocator, &quot;foo&quot;, &quot;bar&quot;);
    try expect(std.mem.eql(u8, &quot;foobar&quot;, result));
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}</code></pre>
<figcaption>test_allocator.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_allocator.zig
1/1 test_allocator.test.using an allocator...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

In the above example, 100 bytes of stack memory are used to initialize a
`FixedBufferAllocator`, which is then passed to a function.
As a convenience there is a global `FixedBufferAllocator`
available for quick tests at `std.testing.allocator`,
which will also perform basic leak detection.

Zig has a general purpose allocator available to be imported
with `std.heap.GeneralPurposeAllocator`. However, it is still recommended to
follow the [Choosing an Allocator](#Choosing-an-Allocator) guide.

### [Choosing an Allocator](#toc-Choosing-an-Allocator) <a href="#Choosing-an-Allocator" class="hdr">§</a>

What allocator to use depends on a number of factors. Here is a flow chart to help you decide:

1.  Are you making a library? In this case, best to accept an `Allocator`
    as a parameter and allow your library's users to decide what allocator to use.
2.  Are you linking libc? In this case, `std.heap.c_allocator` is likely
    the right choice, at least for your main allocator.
3.  Need to use the same allocator in multiple threads? Use one of your choice
    wrapped around `std.heap.ThreadSafeAllocator`
4.  Is the maximum number of bytes that you will need bounded by a number known at
    [comptime](#comptime)? In this case, use `std.heap.FixedBufferAllocator`.
5.  Is your program a command line application which runs from start to end without any fundamental
    cyclical pattern (such as a video game main loop, or a web server request handler),
    such that it would make sense to free everything at once at the end?
    In this case, it is recommended to follow this pattern:
    <figure>
    <pre><code>const std = @import(&quot;std&quot;);

    pub fn main() !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const allocator = arena.allocator();

        const ptr = try allocator.create(i32);
        std.debug.print(&quot;ptr={*}\n&quot;, .{ptr});
    }</code></pre>
    <figcaption>cli_allocation.zig</figcaption>
    </figure>

    <figure>
    <pre><code>$ zig build-exe cli_allocation.zig
    $ ./cli_allocation
    ptr=i32@7f512777b010</code></pre>
    <figcaption>Shell</figcaption>
    </figure>

    When using this kind of allocator, there is no need to free anything manually. Everything
    gets freed at once with the call to `arena.deinit()`.
6.  Are the allocations part of a cyclical pattern such as a video game main loop, or a web
    server request handler? If the allocations can all be freed at once, at the end of the cycle,
    for example once the video game frame has been fully rendered, or the web server request has
    been served, then `std.heap.ArenaAllocator` is a great candidate. As
    demonstrated in the previous bullet point, this allows you to free entire arenas at once.
    Note also that if an upper bound of memory can be established, then
    `std.heap.FixedBufferAllocator` can be used as a further optimization.
7.  Are you writing a test, and you want to make sure <span class="tok-kw">`error`</span>`.OutOfMemory`
    is handled correctly? In this case, use `std.testing.FailingAllocator`.
8.  Are you writing a test? In this case, use `std.testing.allocator`.
9.  Finally, if none of the above apply, you need a general purpose allocator.
    Zig's general purpose allocator is available as a function that takes a [comptime](#comptime)
    [struct](#struct) of configuration options and returns a type.
    Generally, you will set up one `std.heap.GeneralPurposeAllocator` in
    your main function, and then pass it or sub-allocators around to various parts of your
    application.
10. You can also consider [Implementing an Allocator](#Implementing-an-Allocator).

### [Where are the bytes?](#toc-Where-are-the-bytes) <a href="#Where-are-the-bytes" class="hdr">§</a>

String literals such as <span class="tok-str">`"hello"`</span> are in the global constant data section.
This is why it is an error to pass a string literal to a mutable slice, like this:

<figure>
<pre><code>fn foo(s: []u8) void {
    _ = s;
}

test &quot;string literal to mutable slice&quot; {
    foo(&quot;hello&quot;);
}</code></pre>
<figcaption>test_string_literal_to_slice.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_string_literal_to_slice.zig
/home/andy/dev/zig/doc/langref/test_string_literal_to_slice.zig:6:9: error: expected type &#39;[]u8&#39;, found &#39;*const [5:0]u8&#39;
    foo(&quot;hello&quot;);
        ^~~~~~~
/home/andy/dev/zig/doc/langref/test_string_literal_to_slice.zig:6:9: note: cast discards const qualifier
/home/andy/dev/zig/doc/langref/test_string_literal_to_slice.zig:1:11: note: parameter type declared here
fn foo(s: []u8) void {
          ^~~~
</code></pre>
<figcaption>Shell</figcaption>
</figure>

However if you make the slice constant, then it works:

<figure>
<pre><code>fn foo(s: []const u8) void {
    _ = s;
}

test &quot;string literal to constant slice&quot; {
    foo(&quot;hello&quot;);
}</code></pre>
<figcaption>test_string_literal_to_const_slice.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_string_literal_to_const_slice.zig
1/1 test_string_literal_to_const_slice.test.string literal to constant slice...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

Just like string literals, <span class="tok-kw">`const`</span> declarations, when the value is known at [comptime](#comptime),
are stored in the global constant data section. Also [Compile Time Variables](#Compile-Time-Variables) are stored
in the global constant data section.

<span class="tok-kw">`var`</span> declarations inside functions are stored in the function's stack frame. Once a function returns,
any [Pointers](#Pointers) to variables in the function's stack frame become invalid references, and
dereferencing them becomes unchecked [Illegal Behavior](#Illegal-Behavior).

<span class="tok-kw">`var`</span> declarations at the top level or in [struct](#struct) declarations are stored in the global
data section.

The location of memory allocated with `allocator.alloc` or
`allocator.create` is determined by the allocator's implementation.

TODO: thread local variables

### [Implementing an Allocator](#toc-Implementing-an-Allocator) <a href="#Implementing-an-Allocator" class="hdr">§</a>

Zig programmers can implement their own allocators by fulfilling the Allocator interface.
In order to do this one must read carefully the documentation comments in std/mem.zig and
then supply a `allocFn` and a `resizeFn`.

There are many example allocators to look at for inspiration. Look at std/heap.zig and
`std.heap.GeneralPurposeAllocator`.

### [Heap Allocation Failure](#toc-Heap-Allocation-Failure) <a href="#Heap-Allocation-Failure" class="hdr">§</a>

Many programming languages choose to handle the possibility of heap allocation failure by
unconditionally crashing. By convention, Zig programmers do not consider this to be a
satisfactory solution. Instead, <span class="tok-kw">`error`</span>`.OutOfMemory` represents
heap allocation failure, and Zig libraries return this error code whenever heap allocation
failure prevented an operation from completing successfully.

Some have argued that because some operating systems such as Linux have memory overcommit enabled by
default, it is pointless to handle heap allocation failure. There are many problems with this reasoning:

- Only some operating systems have an overcommit feature.
  - Linux has it enabled by default, but it is configurable.
  - Windows does not overcommit.
  - Embedded systems do not have overcommit.
  - Hobby operating systems may or may not have overcommit.
- For real-time systems, not only is there no overcommit, but typically the maximum amount
  of memory per application is determined ahead of time.
- When writing a library, one of the main goals is code reuse. By making code handle
  allocation failure correctly, a library becomes eligible to be reused in
  more contexts.
- Although some software has grown to depend on overcommit being enabled, its existence
  is the source of countless user experience disasters. When a system with overcommit enabled,
  such as Linux on default settings, comes close to memory exhaustion, the system locks up
  and becomes unusable. At this point, the OOM Killer selects an application to kill
  based on heuristics. This non-deterministic decision often results in an important process
  being killed, and often fails to return the system back to working order.

### [Recursion](#toc-Recursion) <a href="#Recursion" class="hdr">§</a>

Recursion is a fundamental tool in modeling software. However it has an often-overlooked problem:
unbounded memory allocation.

Recursion is an area of active experimentation in Zig and so the documentation here is not final.
You can read a
[summary of recursion status in the 0.3.0 release notes](https://ziglang.org/download/0.3.0/release-notes.html#recursion).

The short summary is that currently recursion works normally as you would expect. Although Zig code
is not yet protected from stack overflow, it is planned that a future version of Zig will provide
such protection, with some degree of cooperation from Zig code required.

### [Lifetime and Ownership](#toc-Lifetime-and-Ownership) <a href="#Lifetime-and-Ownership" class="hdr">§</a>

It is the Zig programmer's responsibility to ensure that a [pointer](#Pointers) is not
accessed when the memory pointed to is no longer available. Note that a [slice](#Slices)
is a form of pointer, in that it references other memory.

In order to prevent bugs, there are some helpful conventions to follow when dealing with pointers.
In general, when a function returns a pointer, the documentation for the function should explain
who "owns" the pointer. This concept helps the programmer decide when it is appropriate, if ever,
to free the pointer.

For example, the function's documentation may say "caller owns the returned memory", in which case
the code that calls the function must have a plan for when to free that memory. Probably in this situation,
the function will accept an `Allocator` parameter.

Sometimes the lifetime of a pointer may be more complicated. For example, the
`std.ArrayList(T).items` slice has a lifetime that remains
valid until the next time the list is resized, such as by appending new elements.

The API documentation for functions and data structures should take great care to explain
the ownership and lifetime semantics of pointers. Ownership determines whose responsibility it
is to free the memory referenced by the pointer, and lifetime determines the point at which
the memory becomes inaccessible (lest [Illegal Behavior](#Illegal-Behavior) occur).

## [Compile Variables](#toc-Compile-Variables) <a href="#Compile-Variables" class="hdr">§</a>

Compile variables are accessible by importing the <span class="tok-str">`"builtin"`</span> package,
which the compiler makes available to every Zig source file. It contains
compile-time constants such as the current target, endianness, and release mode.

<figure>
<pre><code>const builtin = @import(&quot;builtin&quot;);
const separator = if (builtin.os.tag == .windows) &#39;\\&#39; else &#39;/&#39;;</code></pre>
<figcaption>compile_variables.zig</figcaption>
</figure>

Example of what is imported with <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`)`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
/// Zig version. When writing code that supports multiple versions of Zig, prefer
/// feature detection (i.e. with `@hasDecl` or `@hasField`) over version checks.
pub const zig_version = std.SemanticVersion.parse(zig_version_string) catch unreachable;
pub const zig_version_string = &quot;0.16.0-dev.1+cf5f8113c&quot;;
pub const zig_backend = std.builtin.CompilerBackend.stage2_x86_64;

pub const output_mode: std.builtin.OutputMode = .Exe;
pub const link_mode: std.builtin.LinkMode = .static;
pub const unwind_tables: std.builtin.UnwindTables = .async;
pub const is_test = false;
pub const single_threaded = false;
pub const abi: std.Target.Abi = .gnu;
pub const cpu: std.Target.Cpu = .{
    .arch = .x86_64,
    .model = &amp;std.Target.x86.cpu.znver4,
    .features = std.Target.x86.featureSet(&amp;.{
        .@&quot;64bit&quot;,
        .adx,
        .aes,
        .allow_light_256_bit,
        .avx,
        .avx2,
        .avx512bf16,
        .avx512bitalg,
        .avx512bw,
        .avx512cd,
        .avx512dq,
        .avx512f,
        .avx512ifma,
        .avx512vbmi,
        .avx512vbmi2,
        .avx512vl,
        .avx512vnni,
        .avx512vpopcntdq,
        .bmi,
        .bmi2,
        .branchfusion,
        .clflushopt,
        .clwb,
        .clzero,
        .cmov,
        .crc32,
        .cx16,
        .cx8,
        .evex512,
        .f16c,
        .fast_15bytenop,
        .fast_bextr,
        .fast_dpwssd,
        .fast_imm16,
        .fast_lzcnt,
        .fast_movbe,
        .fast_scalar_fsqrt,
        .fast_scalar_shift_masks,
        .fast_variable_perlane_shuffle,
        .fast_vector_fsqrt,
        .fma,
        .fsgsbase,
        .fsrm,
        .fxsr,
        .gfni,
        .idivq_to_divl,
        .invpcid,
        .lzcnt,
        .macrofusion,
        .mmx,
        .movbe,
        .mwaitx,
        .nopl,
        .pclmul,
        .pku,
        .popcnt,
        .prfchw,
        .rdpid,
        .rdpru,
        .rdrnd,
        .rdseed,
        .sahf,
        .sbb_dep_breaking,
        .sha,
        .shstk,
        .slow_shld,
        .smap,
        .smep,
        .sse,
        .sse2,
        .sse3,
        .sse4_1,
        .sse4_2,
        .sse4a,
        .ssse3,
        .vaes,
        .vpclmulqdq,
        .vzeroupper,
        .wbnoinvd,
        .x87,
        .xsave,
        .xsavec,
        .xsaveopt,
        .xsaves,
    }),
};
pub const os: std.Target.Os = .{
    .tag = .linux,
    .version_range = .{ .linux = .{
        .range = .{
            .min = .{
                .major = 6,
                .minor = 16,
                .patch = 0,
            },
            .max = .{
                .major = 6,
                .minor = 16,
                .patch = 0,
            },
        },
        .glibc = .{
            .major = 2,
            .minor = 39,
            .patch = 0,
        },
        .android = 29,
    }},
};
pub const target: std.Target = .{
    .cpu = cpu,
    .os = os,
    .abi = abi,
    .ofmt = object_format,
    .dynamic_linker = .init(&quot;/nix/store/zdpby3l6azi78sl83cpad2qjpfj25aqx-glibc-2.40-66/lib/ld-linux-x86-64.so.2&quot;),
};
pub const object_format: std.Target.ObjectFormat = .elf;
pub const mode: std.builtin.OptimizeMode = .Debug;
pub const link_libc = false;
pub const link_libcpp = false;
pub const have_error_return_tracing = true;
pub const valgrind_support = true;
pub const sanitize_thread = false;
pub const fuzz = false;
pub const position_independent_code = false;
pub const position_independent_executable = false;
pub const strip_debug_info = false;
pub const code_model: std.builtin.CodeModel = .default;
pub const omit_frame_pointer = false;</code></pre>
<figcaption>@import("builtin")</figcaption>
</figure>

See also:

- [Build Mode](#Build-Mode)

## [Compilation Model](#toc-Compilation-Model) <a href="#Compilation-Model" class="hdr">§</a>

A Zig compilation is separated into *modules*. Each module is a collection of Zig source files,
one of which is the module's *root source file*. Each module can *depend* on any number of
other modules, forming a directed graph (dependency loops between modules are allowed). If module A
depends on module B, then any Zig source file in module A can import the *root source file* of
module B using <span class="tok-builtin">`@import`</span> with the module's name. In essence, a module acts as an
alias to import a Zig source file (which might exist in a completely separate part of the filesystem).

A simple Zig program compiled with `zig build-exe` has two key modules: the one containing your
code, known as the "main" or "root" module, and the standard library. Your module *depends on*
the standard library module under the name "std", which is what allows you to write
<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`)`! In fact, every single module in a Zig compilation — including
the standard library itself — implicitly depends on the standard library module under the name "std".

The "root module" (the one provided by you in the `zig build-exe` example) has a special
property. Like the standard library, it is implicitly made available to all modules (including itself),
this time under the name "root". So, <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)` will always be equivalent to
<span class="tok-builtin">`@import`</span> of your "main" source file (often, but not necessarily, named
`main.zig`).

### [Source File Structs](#toc-Source-File-Structs) <a href="#Source-File-Structs" class="hdr">§</a>

Every Zig source file is implicitly a <span class="tok-kw">`struct`</span> declaration; you can imagine that
the file's contents are literally surrounded by <span class="tok-kw">`struct`</span>` { ... }`. This means that
as well as declarations, the top level of a file is permitted to contain fields:

<figure>
<pre><code>//! Because this file contains fields, it is a type which is intended to be instantiated, and so
//! is named in TitleCase instead of snake_case by convention.

foo: u32,
bar: u64,

/// `@This()` can be used to refer to this struct type. In files with fields, it is quite common to
/// name the type here, so it can be easily referenced by other declarations in this file.
const TopLevelFields = @This();

pub fn init(val: u32) TopLevelFields {
    return .{
        .foo = val,
        .bar = val * 10,
    };
}</code></pre>
<figcaption>TopLevelFields.zig</figcaption>
</figure>

Such files can be instantiated just like any other <span class="tok-kw">`struct`</span> type. A file's "root
struct type" can be referred to within that file using [@This](#This).

### [File and Declaration Discovery](#toc-File-and-Declaration-Discovery) <a href="#File-and-Declaration-Discovery" class="hdr">§</a>

Zig places importance on the concept of whether any piece of code is *semantically analyzed*; in
essence, whether the compiler "looks at" it. What code is analyzed is based on what files and
declarations are "discovered" from a certain point. This process of "discovery" is based on a simple set
of recursive rules:

- If a call to <span class="tok-builtin">`@import`</span> is analyzed, the file being imported is analyzed.
- If a type (including a file) is analyzed, all <span class="tok-kw">`comptime`</span> and <span class="tok-kw">`export`</span> declarations within it are analyzed.
- If a type (including a file) is analyzed, and the compilation is for a [test](#Zig-Test), and the module the type is within is the root module of the compilation, then all <span class="tok-kw">`test`</span> declarations within it are also analyzed.
- If a reference to a named declaration (i.e. a usage of it) is analyzed, the declaration being referenced is analyzed. Declarations are order-independent, so this reference may be above or below the declaration being referenced, or even in another file entirely.

That's it! Those rules define how Zig files and declarations are discovered. All that remains is to
understand where this process *starts*.

The answer to that is the root of the standard library: every Zig compilation begins by analyzing the
file `lib/std/std.zig`. This file contains a <span class="tok-kw">`comptime`</span> declaration
which imports `lib/std/start.zig`, and that file in turn uses
<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)` to reference the "root module"; so, the file you provide as your
main module's root source file is effectively also a root, because the standard library will always
reference it.

It is often desirable to make sure that certain declarations — particularly <span class="tok-kw">`test`</span>
or <span class="tok-kw">`export`</span> declarations — are discovered. Based on the above rules, a common
strategy for this is to use <span class="tok-builtin">`@import`</span> within a <span class="tok-kw">`comptime`</span> or
<span class="tok-kw">`test`</span> block:

<figure>
<pre><code>comptime {
    // This will ensure that the file &#39;api.zig&#39; is always discovered (as long as this file is discovered).
    // It is useful if &#39;api.zig&#39; contains important exported declarations.
    _ = @import(&quot;api.zig&quot;);

    // We could also have a file which contains declarations we only want to export depending on a comptime
    // condition. In that case, we can use an `if` statement here:
    if (builtin.os.tag == .windows) {
        _ = @import(&quot;windows_api.zig&quot;);
    }
}

test {
    // This will ensure that the file &#39;tests.zig&#39; is always discovered (as long as this file is discovered),
    // if this compilation is a test. It is useful if &#39;tests.zig&#39; contains tests we want to ensure are run.
    _ = @import(&quot;tests.zig&quot;);

    // We could also have a file which contains tests we only want to run depending on a comptime condition.
    // In that case, we can use an `if` statement here:
    if (builtin.os.tag == .windows) {
        _ = @import(&quot;windows_tests.zig&quot;);
    }
}

const builtin = @import(&quot;builtin&quot;);</code></pre>
<figcaption>force_file_discovery.zig</figcaption>
</figure>

### [Special Root Declarations](#toc-Special-Root-Declarations) <a href="#Special-Root-Declarations" class="hdr">§</a>

Because the root module's root source file is always accessible using
<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)`, is is sometimes used by libraries — including the Zig Standard
Library — as a place for the program to expose some "global" information to that library. The Zig
Standard Library will look for several declarations in this file.

#### [Entry Point](#toc-Entry-Point) <a href="#Entry-Point" class="hdr">§</a>

When building an executable, the most important thing to be looked up in this file is the program's
*entry point*. Most commonly, this is a function named `main`, which
`std.start` will call just after performing important initialization work.

Alternatively, the presence of a declaration named `_start` (for instance,
<span class="tok-kw">`pub`</span>` `<span class="tok-kw">`const`</span>` _start = {};`) will disable the default `std.start`
logic, allowing your root source file to export a low-level entry point as needed.

<figure>
<pre><code>/// `std.start` imports this file using `@import(&quot;root&quot;)`, and uses this declaration as the program&#39;s
/// user-provided entry point. It can return any of the following types:
/// * `void`
/// * `E!void`, for any error set `E`
/// * `u8`
/// * `E!u8`, for any error set `E`
/// Returning a `void` value from this function will exit with code 0.
/// Returning a `u8` value from this function will exit with the given status code.
/// Returning an error value from this function will print an Error Return Trace and exit with code 1.
pub fn main() void {
    std.debug.print(&quot;Hello, World!\n&quot;, .{});
}

// If uncommented, this declaration would suppress the usual std.start logic, causing
// the `main` declaration above to be ignored.
//pub const _start = {};

const std = @import(&quot;std&quot;);</code></pre>
<figcaption>entry_point.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe entry_point.zig
$ ./entry_point
Hello, World!</code></pre>
<figcaption>Shell</figcaption>
</figure>

If the Zig compilation links libc, the `main` function can optionally be an
<span class="tok-kw">`export`</span>` `<span class="tok-kw">`fn`</span> which matches the signature of the C `main` function:

<figure>
<pre><code>pub export fn main(argc: c_int, argv: [*]const [*:0]const u8) c_int {
    const args = argv[0..@intCast(argc)];
    std.debug.print(&quot;Hello! argv[0] is &#39;{s}&#39;\n&quot;, .{args[0]});
    return 0;
}

const std = @import(&quot;std&quot;);</code></pre>
<figcaption>libc_export_entry_point.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe libc_export_entry_point.zig -lc
$ ./libc_export_entry_point
Hello! argv[0] is &#39;./libc_export_entry_point&#39;</code></pre>
<figcaption>Shell</figcaption>
</figure>

`std.start` may also use other entry point declarations in certain situations, such
as `wWinMain` or `EfiMain`. Refer to the
`lib/std/start.zig` logic for details of these declarations.

#### [Standard Library Options](#toc-Standard-Library-Options) <a href="#Standard-Library-Options" class="hdr">§</a>

The standard library also looks for a declaration in the root module's root source file named
`std_options`. If present, this declaration is expected to be a struct of type
`std.Options`, and allows the program to customize some standard library
functionality, such as the `std.log` implementation.

<figure>
<pre><code>/// The presence of this declaration allows the program to override certain behaviors of the standard library.
/// For a full list of available options, see the documentation for `std.Options`.
pub const std_options: std.Options = .{
    // By default, in safe build modes, the standard library will attach a segfault handler to the program to
    // print a helpful stack trace if a segmentation fault occurs. Here, we can disable this, or even enable
    // it in unsafe build modes.
    .enable_segfault_handler = true,
    // This is the logging function used by `std.log`.
    .logFn = myLogFn,
};

fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // We could do anything we want here!
    // ...but actually, let&#39;s just call the default implementation.
    std.log.defaultLog(level, scope, format, args);
}

const std = @import(&quot;std&quot;);</code></pre>
<figcaption>std_options.zig</figcaption>
</figure>

#### [Panic Handler](#toc-Panic-Handler) <a href="#Panic-Handler" class="hdr">§</a>

The Zig Standard Library looks for a declaration named `panic` in the root module's
root source file. If present, it is expected to be a namespace (container type) with declarations
providing different panic handlers.

See `std.debug.simple_panic` for a basic implementation of this namespace.

Overriding how the panic handler actually outputs messages, but keeping the formatted safety panics
which are enabled by default, can be easily achieved with `std.debug.FullPanic`:

<figure>
<pre><code>pub fn main() void {
    @setRuntimeSafety(true);
    var x: u8 = 255;
    // Let&#39;s overflow this integer!
    x += 1;
}

pub const panic = std.debug.FullPanic(myPanic);

fn myPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    std.debug.print(&quot;Panic! {s}\n&quot;, .{msg});
    std.process.exit(1);
}

const std = @import(&quot;std&quot;);</code></pre>
<figcaption>panic_handler.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe panic_handler.zig
$ ./panic_handler
Panic! integer overflow</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Zig Build System](#toc-Zig-Build-System) <a href="#Zig-Build-System" class="hdr">§</a>

The Zig Build System provides a cross-platform, dependency-free way to declare
the logic required to build a project. With this system, the logic to build
a project is written in a build.zig file, using the Zig Build System API to
declare and configure build artifacts and other tasks.

Some examples of tasks the build system can help with:

- Performing tasks in parallel and caching the results.
- Depending on other projects.
- Providing a package for other projects to depend on.
- Creating build artifacts by executing the Zig compiler. This includes
  building Zig source code as well as C and C++ source code.
- Capturing user-configured options and using those options to configure
  the build.
- Surfacing build configuration as [comptime](#comptime) values by providing a
  file that can be [imported](#import) by Zig code.
- Caching build artifacts to avoid unnecessarily repeating steps.
- Executing build artifacts or system-installed tools.
- Running tests and verifying the output of executing a build artifact matches
  the expected value.
- Running `zig fmt` on a codebase or a subset of it.
- Custom tasks.

To use the build system, run <span class="kbd">zig build --help</span>
to see a command-line usage help menu. This will include project-specific
options that were declared in the build.zig script.

For the time being, the build system documentation is hosted externally:
[Build System Documentation](https://ziglang.org/learn/build-system/)

## [C](#toc-C) <a href="#C" class="hdr">§</a>

Although Zig is independent of C, and, unlike most other languages, does not depend on libc,
Zig acknowledges the importance of interacting with existing C code.

There are a few ways that Zig facilitates C interop.

### [C Type Primitives](#toc-C-Type-Primitives) <a href="#C-Type-Primitives" class="hdr">§</a>

These have guaranteed C ABI compatibility and can be used like any other type.

- <span class="tok-type">`c_char`</span>
- <span class="tok-type">`c_short`</span>
- <span class="tok-type">`c_ushort`</span>
- <span class="tok-type">`c_int`</span>
- <span class="tok-type">`c_uint`</span>
- <span class="tok-type">`c_long`</span>
- <span class="tok-type">`c_ulong`</span>
- <span class="tok-type">`c_longlong`</span>
- <span class="tok-type">`c_ulonglong`</span>
- <span class="tok-type">`c_longdouble`</span>

To interop with the C <span class="tok-type">`void`</span> type, use <span class="tok-type">`anyopaque`</span>.

See also:

- [Primitive Types](#Primitive-Types)

### [Import from C Header File](#toc-Import-from-C-Header-File) <a href="#Import-from-C-Header-File" class="hdr">§</a>

The <span class="tok-builtin">`@cImport`</span> builtin function can be used
to directly import symbols from `.h` files:

<figure>
<pre><code>const c = @cImport({
    // See https://github.com/ziglang/zig/issues/515
    @cDefine(&quot;_NO_CRT_STDIO_INLINE&quot;, &quot;1&quot;);
    @cInclude(&quot;stdio.h&quot;);
});
pub fn main() void {
    _ = c.printf(&quot;hello\n&quot;);
}</code></pre>
<figcaption>cImport_builtin.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe cImport_builtin.zig -lc
$ ./cImport_builtin
hello</code></pre>
<figcaption>Shell</figcaption>
</figure>

The <span class="tok-builtin">`@cImport`</span> function takes an expression as a parameter.
This expression is evaluated at compile-time and is used to control
preprocessor directives and include multiple `.h` files:

<figure>
<pre><code>const builtin = @import(&quot;builtin&quot;);

const c = @cImport({
    @cDefine(&quot;NDEBUG&quot;, builtin.mode == .ReleaseFast);
    if (something) {
        @cDefine(&quot;_GNU_SOURCE&quot;, {});
    }
    @cInclude(&quot;stdlib.h&quot;);
    if (something) {
        @cUndef(&quot;_GNU_SOURCE&quot;);
    }
    @cInclude(&quot;soundio.h&quot;);
});</code></pre>
<figcaption>@cImport Expression</figcaption>
</figure>

See also:

- [@cImport](#cImport)
- [@cInclude](#cInclude)
- [@cDefine](#cDefine)
- [@cUndef](#cUndef)
- [@import](#import)

### [C Translation CLI](#toc-C-Translation-CLI) <a href="#C-Translation-CLI" class="hdr">§</a>

Zig's C translation capability is available as a CLI tool via <span class="kbd">zig translate-c</span>.
It requires a single filename as an argument. It may also take a set of optional flags that are
forwarded to clang. It writes the translated file to stdout.

#### [Command line flags](#toc-Command-line-flags) <a href="#Command-line-flags" class="hdr">§</a>

- <span class="kbd">-I</span>:
  Specify a search directory for include files. May be used multiple times. Equivalent to
  [clang's <span class="kbd">-I</span> flag](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-i-dir). The current directory is *not* included by default;
  use <span class="kbd">-I.</span> to include it.
- <span class="kbd">-D</span>: Define a preprocessor macro. Equivalent to
  [clang's <span class="kbd">-D</span> flag](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-d-macro).
- <span class="kbd">-cflags \[flags\] --</span>: Pass arbitrary additional
  [command line
  flags](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html) to clang. Note: the list of flags must end with <span class="kbd">--</span>
- <span class="kbd">-target</span>: The [target triple](#Targets) for the translated Zig code.
  If no target is specified, the current host target will be used.

#### [Using -target and -cflags](#toc-Using--target-and--cflags) <a href="#Using--target-and--cflags" class="hdr">§</a>

**Important!** When translating C code with <span class="kbd">zig translate-c</span>,
you **must** use the same <span class="kbd">-target</span> triple that you will use when compiling
the translated code. In addition, you **must** ensure that the <span class="kbd">-cflags</span> used,
if any, match the cflags used by code on the target system. Using the incorrect <span class="kbd">-target</span>
or <span class="kbd">-cflags</span> could result in clang or Zig parse failures, or subtle ABI incompatibilities
when linking with C code.

<figure>
<pre><code>long FOO = __LONG_MAX__;</code></pre>
<figcaption>varytarget.h</figcaption>
</figure>

<figure>
<pre><code>$ zig translate-c -target thumb-freestanding-gnueabihf varytarget.h|grep FOO
pub export var FOO: c_long = 2147483647;
$ zig translate-c -target x86_64-macos-gnu varytarget.h|grep FOO
pub export var FOO: c_long = 9223372036854775807;</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>enum FOO { BAR };
int do_something(enum FOO foo);</code></pre>
<figcaption>varycflags.h</figcaption>
</figure>

<figure>
<pre><code>$ zig translate-c varycflags.h|grep -B1 do_something
pub const enum_FOO = c_uint;
pub extern fn do_something(foo: enum_FOO) c_int;
$ zig translate-c -cflags -fshort-enums -- varycflags.h|grep -B1 do_something
pub const enum_FOO = u8;
pub extern fn do_something(foo: enum_FOO) c_int;</code></pre>
<figcaption>Shell</figcaption>
</figure>

#### [@cImport vs translate-c](#toc-cImport-vs-translate-c) <a href="#cImport-vs-translate-c" class="hdr">§</a>

<span class="tok-builtin">`@cImport`</span> and <span class="kbd">zig translate-c</span> use the same underlying
C translation functionality, so on a technical level they are equivalent. In practice,
<span class="tok-builtin">`@cImport`</span> is useful as a way to quickly and easily access numeric constants, typedefs,
and record types without needing any extra setup. If you need to pass [cflags](#Using--target-and--cflags)
to clang, or if you would like to edit the translated code, it is recommended to use
<span class="kbd">zig translate-c</span> and save the results to a file. Common reasons for editing
the generated code include: changing <span class="tok-kw">`anytype`</span> parameters in function-like macros to more
specific types; changing `[*c]T` pointers to `[*]T` or
`*T` pointers for improved type safety; and
[enabling or disabling runtime safety](#setRuntimeSafety) within specific functions.

See also:

- [Targets](#Targets)
- [C Type Primitives](#C-Type-Primitives)
- [Pointers](#Pointers)
- [C Pointers](#C-Pointers)
- [Import from C Header File](#Import-from-C-Header-File)
- [@cInclude](#cInclude)
- [@cImport](#cImport)
- [@setRuntimeSafety](#setRuntimeSafety)

### [C Translation Caching](#toc-C-Translation-Caching) <a href="#C-Translation-Caching" class="hdr">§</a>

The C translation feature (whether used via <span class="kbd">zig translate-c</span> or
<span class="tok-builtin">`@cImport`</span>) integrates with the Zig caching system. Subsequent runs with
the same source file, target, and cflags will use the cache instead of repeatedly translating
the same code.

To see where the cached files are stored when compiling code that uses <span class="tok-builtin">`@cImport`</span>,
use the <span class="kbd">--verbose-cimport</span> flag:

<figure>
<pre><code>const c = @cImport({
    @cDefine(&quot;_NO_CRT_STDIO_INLINE&quot;, &quot;1&quot;);
    @cInclude(&quot;stdio.h&quot;);
});
pub fn main() void {
    _ = c;
}</code></pre>
<figcaption>verbose_cimport_flag.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe verbose_cimport_flag.zig -lc --verbose-cimport
info(compilation): C import source: /home/andy/dev/zig/.zig-cache/o/d8ccd8e60bde2d5dcdf32a3cdef64999/cimport.h
info(compilation): C import .d file: /home/andy/dev/zig/.zig-cache/o/d8ccd8e60bde2d5dcdf32a3cdef64999/cimport.h.d
$ ./verbose_cimport_flag</code></pre>
<figcaption>Shell</figcaption>
</figure>

`cimport.h` contains the file to translate (constructed from calls to
<span class="tok-builtin">`@cInclude`</span>, <span class="tok-builtin">`@cDefine`</span>, and <span class="tok-builtin">`@cUndef`</span>),
`cimport.h.d` is the list of file dependencies, and
`cimport.zig` contains the translated output.

See also:

- [Import from C Header File](#Import-from-C-Header-File)
- [C Translation CLI](#C-Translation-CLI)
- [@cInclude](#cInclude)
- [@cImport](#cImport)

### [Translation failures](#toc-Translation-failures) <a href="#Translation-failures" class="hdr">§</a>

Some C constructs cannot be translated to Zig - for example, *goto*,
structs with bitfields, and token-pasting macros. Zig employs *demotion* to allow translation
to continue in the face of non-translatable entities.

Demotion comes in three varieties - [opaque](#opaque), *extern*, and
<span class="tok-builtin">`@compileError`</span>.
C structs and unions that cannot be translated correctly will be translated as <span class="tok-kw">`opaque`</span>`{}`.
Functions that contain opaque types or code constructs that cannot be translated will be demoted
to <span class="tok-kw">`extern`</span> declarations.
Thus, non-translatable types can still be used as pointers, and non-translatable functions
can be called so long as the linker is aware of the compiled function.

<span class="tok-builtin">`@compileError`</span> is used when top-level definitions (global variables,
function prototypes, macros) cannot be translated or demoted. Since Zig uses lazy analysis for
top-level declarations, untranslatable entities will not cause a compile error in your code unless
you actually use them.

See also:

- [opaque](#opaque)
- [extern](#extern)
- [@compileError](#compileError)

### [C Macros](#toc-C-Macros) <a href="#C-Macros" class="hdr">§</a>

C Translation makes a best-effort attempt to translate function-like macros into equivalent
Zig functions. Since C macros operate at the level of lexical tokens, not all C macros
can be translated to Zig. Macros that cannot be translated will be demoted to
<span class="tok-builtin">`@compileError`</span>. Note that C code which *uses* macros will be
translated without any additional issues (since Zig operates on the pre-processed source
with macros expanded). It is merely the macros themselves which may not be translatable to
Zig.

Consider the following example:

<figure>
<pre><code>#define MAKELOCAL(NAME, INIT) int NAME = INIT
int foo(void) {
   MAKELOCAL(a, 1);
   MAKELOCAL(b, 2);
   return a + b;
}</code></pre>
<figcaption>macro.c</figcaption>
</figure>

<figure>
<pre><code>$ zig translate-c macro.c &gt; macro.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>pub export fn foo() c_int {
    var a: c_int = 1;
    _ = &amp;a;
    var b: c_int = 2;
    _ = &amp;b;
    return a + b;
}
pub const MAKELOCAL = @compileError(&quot;unable to translate C expr: unexpected token .Equal&quot;); // macro.c:1:9</code></pre>
<figcaption>macro.zig</figcaption>
</figure>

Note that `foo` was translated correctly despite using a non-translatable
macro. `MAKELOCAL` was demoted to <span class="tok-builtin">`@compileError`</span> since
it cannot be expressed as a Zig function; this simply means that you cannot directly use
`MAKELOCAL` from Zig.

See also:

- [@compileError](#compileError)

### [C Pointers](#toc-C-Pointers) <a href="#C-Pointers" class="hdr">§</a>

This type is to be avoided whenever possible. The only valid reason for using a C pointer is in
auto-generated code from translating C code.

When importing C header files, it is ambiguous whether pointers should be translated as
single-item pointers (`*T`) or many-item pointers (`[*]T`).
C pointers are a compromise so that Zig code can utilize translated header files directly.

`[*c]T` - C pointer.

- Supports all the syntax of the other two pointer types (`*T`) and (`[*]T`).
- Coerces to other pointer types, as well as [Optional Pointers](#Optional-Pointers).
  When a C pointer is coerced to a non-optional pointer, safety-checked
  [Illegal Behavior](#Illegal-Behavior) occurs if the address is 0.
- Allows address 0. On non-freestanding targets, dereferencing address 0 is safety-checked
  [Illegal Behavior](#Illegal-Behavior). Optional C pointers introduce another bit to keep track of
  null, just like `?`<span class="tok-type">`usize`</span>. Note that creating an optional C pointer
  is unnecessary as one can use normal [Optional Pointers](#Optional-Pointers).
- Supports [Type Coercion](#Type-Coercion) to and from integers.
- Supports comparison with integers.
- Does not support Zig-only pointer attributes such as alignment. Use normal [Pointers](#Pointers)
  please!

When a C pointer is pointing to a single struct (not an array), dereference the C pointer to
access the struct's fields or member data. That syntax looks like
this:

`ptr_to_struct.*.struct_member`

This is comparable to doing `->` in C.

When a C pointer is pointing to an array of structs, the syntax reverts to this:

`ptr_to_struct_array[index].struct_member`

### [C Variadic Functions](#toc-C-Variadic-Functions) <a href="#C-Variadic-Functions" class="hdr">§</a>

Zig supports extern variadic functions.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const testing = std.testing;

pub extern &quot;c&quot; fn printf(format: [*:0]const u8, ...) c_int;

test &quot;variadic function&quot; {
    try testing.expect(printf(&quot;Hello, world!\n&quot;) == 14);
    try testing.expect(@typeInfo(@TypeOf(printf)).@&quot;fn&quot;.is_var_args);
}</code></pre>
<figcaption>test_variadic_function.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_variadic_function.zig -lc
1/1 test_variadic_function.test.variadic function...OK
All 1 tests passed.
Hello, world!</code></pre>
<figcaption>Shell</figcaption>
</figure>

Variadic functions can be implemented using [@cVaStart](#cVaStart), [@cVaEnd](#cVaEnd), [@cVaArg](#cVaArg) and [@cVaCopy](#cVaCopy).

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const testing = std.testing;
const builtin = @import(&quot;builtin&quot;);

fn add(count: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&amp;ap);
    var i: usize = 0;
    var sum: c_int = 0;
    while (i &lt; count) : (i += 1) {
        sum += @cVaArg(&amp;ap, c_int);
    }
    return sum;
}

test &quot;defining a variadic function&quot; {
    if (builtin.cpu.arch == .aarch64 and builtin.os.tag != .macos) {
        // https://github.com/ziglang/zig/issues/14096
        return error.SkipZigTest;
    }
    if (builtin.cpu.arch == .x86_64 and builtin.os.tag == .windows) {
        // https://github.com/ziglang/zig/issues/16961
        return error.SkipZigTest;
    }

    try std.testing.expectEqual(@as(c_int, 0), add(0));
    try std.testing.expectEqual(@as(c_int, 1), add(1, @as(c_int, 1)));
    try std.testing.expectEqual(@as(c_int, 3), add(2, @as(c_int, 1), @as(c_int, 2)));
}</code></pre>
<figcaption>test_defining_variadic_function.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_defining_variadic_function.zig
1/1 test_defining_variadic_function.test.defining a variadic function...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [Exporting a C Library](#toc-Exporting-a-C-Library) <a href="#Exporting-a-C-Library" class="hdr">§</a>

One of the primary use cases for Zig is exporting a library with the C ABI for other programming languages
to call into. The <span class="tok-kw">`export`</span> keyword in front of functions, variables, and types causes them to
be part of the library API:

<figure>
<pre><code>export fn add(a: i32, b: i32) i32 {
    return a + b;
}</code></pre>
<figcaption>mathtest.zig</figcaption>
</figure>

To make a static library:

<figure>
<pre><code>$ zig build-lib mathtest.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

To make a shared library:

<figure>
<pre><code>$ zig build-lib mathtest.zig -dynamic</code></pre>
<figcaption>Shell</figcaption>
</figure>

Here is an example with the [Zig Build System](#Zig-Build-System):

<figure>
<pre><code>// This header is generated by zig from mathtest.zig
#include &quot;mathtest.h&quot;
#include &lt;stdio.h&gt;

int main(int argc, char **argv) {
    int32_t result = add(42, 1337);
    printf(&quot;%d\n&quot;, result);
    return 0;
}</code></pre>
<figcaption>test.c</figcaption>
</figure>

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = &quot;mathtest&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;mathtest.zig&quot;),
        }),
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    const exe = b.addExecutable(.{
        .name = &quot;test&quot;,
        .root_module = b.createModule(.{
            .link_libc = true,
        }),
    });
    exe.root_module.addCSourceFile(.{ .file = b.path(&quot;test.c&quot;), .flags = &amp;.{&quot;-std=c99&quot;} });
    exe.root_module.linkLibrary(lib);

    b.default_step.dependOn(&amp;exe.step);

    const run_cmd = exe.run();

    const test_step = b.step(&quot;test&quot;, &quot;Test the program&quot;);
    test_step.dependOn(&amp;run_cmd.step);
}</code></pre>
<figcaption>build_c.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build test
1379</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [export](#export)

### [Mixing Object Files](#toc-Mixing-Object-Files) <a href="#Mixing-Object-Files" class="hdr">§</a>

You can mix Zig object files with any other object files that respect the C ABI. Example:

<figure>
<pre><code>const base64 = @import(&quot;std&quot;).base64;

export fn decode_base_64(
    dest_ptr: [*]u8,
    dest_len: usize,
    source_ptr: [*]const u8,
    source_len: usize,
) usize {
    const src = source_ptr[0..source_len];
    const dest = dest_ptr[0..dest_len];
    const base64_decoder = base64.standard.Decoder;
    const decoded_size = base64_decoder.calcSizeForSlice(src) catch unreachable;
    base64_decoder.decode(dest[0..decoded_size], src) catch unreachable;
    return decoded_size;
}</code></pre>
<figcaption>base64.zig</figcaption>
</figure>

<figure>
<pre><code>// This header is generated by zig from base64.zig
#include &quot;base64.h&quot;

#include &lt;string.h&gt;
#include &lt;stdio.h&gt;

int main(int argc, char **argv) {
    const char *encoded = &quot;YWxsIHlvdXIgYmFzZSBhcmUgYmVsb25nIHRvIHVz&quot;;
    char buf[200];

    size_t len = decode_base_64(buf, 200, encoded, strlen(encoded));
    buf[len] = 0;
    puts(buf);

    return 0;
}</code></pre>
<figcaption>test.c</figcaption>
</figure>

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const obj = b.addObject(.{
        .name = &quot;base64&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;base64.zig&quot;),
        }),
    });

    const exe = b.addExecutable(.{
        .name = &quot;test&quot;,
        .root_module = b.createModule(.{
            .link_libc = true,
        }),
    });
    exe.root_module.addCSourceFile(.{ .file = b.path(&quot;test.c&quot;), .flags = &amp;.{&quot;-std=c99&quot;} });
    exe.root_module.addObject(obj);
    b.installArtifact(exe);
}</code></pre>
<figcaption>build_object.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build
$ ./zig-out/bin/test
all your base are belong to us</code></pre>
<figcaption>Shell</figcaption>
</figure>

See also:

- [Targets](#Targets)
- [Zig Build System](#Zig-Build-System)

## [WebAssembly](#toc-WebAssembly) <a href="#WebAssembly" class="hdr">§</a>

Zig supports building for WebAssembly out of the box.

### [Freestanding](#toc-Freestanding) <a href="#Freestanding" class="hdr">§</a>

For host environments like the web browser and nodejs, build as an executable using the freestanding
OS target. Here's an example of running Zig code compiled to WebAssembly with nodejs.

<figure>
<pre><code>extern fn print(i32) void;

export fn add(a: i32, b: i32) void {
    print(a + b);
}</code></pre>
<figcaption>math.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe math.zig -target wasm32-freestanding -fno-entry --export=add</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>const fs = require(&#39;fs&#39;);
const source = fs.readFileSync(&quot;./math.wasm&quot;);
const typedArray = new Uint8Array(source);

WebAssembly.instantiate(typedArray, {
  env: {
    print: (result) =&gt; { console.log(`The result is ${result}`); }
  }}).then(result =&gt; {
  const add = result.instance.exports.add;
  add(1, 2);
});</code></pre>
<figcaption>test.js</figcaption>
</figure>

<figure>
<pre><code>$ node test.js
The result is 3</code></pre>
<figcaption>Shell</figcaption>
</figure>

### [WASI](#toc-WASI) <a href="#WASI" class="hdr">§</a>

Zig's support for WebAssembly System Interface (WASI) is under active development.
Example of using the standard library and reading command line arguments:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    for (args, 0..) |arg, i| {
        std.debug.print(&quot;{}: {s}\n&quot;, .{ i, arg });
    }
}</code></pre>
<figcaption>wasi_args.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe wasi_args.zig -target wasm32-wasi</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>$ wasmtime wasi_args.wasm 123 hello
0: wasi_args.wasm
1: 123
2: hello</code></pre>
<figcaption>Shell</figcaption>
</figure>

A more interesting example would be extracting the list of preopens from the runtime.
This is now supported in the standard library via `std.fs.wasi.Preopens`:

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const fs = std.fs;

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const preopens = try fs.wasi.preopensAlloc(arena);

    for (preopens.names, 0..) |preopen, i| {
        std.debug.print(&quot;{}: {s}\n&quot;, .{ i, preopen });
    }
}</code></pre>
<figcaption>wasi_preopens.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe wasi_preopens.zig -target wasm32-wasi</code></pre>
<figcaption>Shell</figcaption>
</figure>

<figure>
<pre><code>$ wasmtime --dir=. wasi_preopens.wasm
0: stdin
1: stdout
2: stderr
3: .</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Targets](#toc-Targets) <a href="#Targets" class="hdr">§</a>

**Target** refers to the computer that will be used to run an executable.
It is composed of the CPU architecture, the set of enabled CPU features, operating system,
minimum and maximum operating system version, ABI, and ABI version.

Zig is a general-purpose programming language which means that it is designed to
generate optimal code for a large set of targets. The command `zig targets`
provides information about all of the targets the compiler is aware of.

When no target option is provided to the compiler, the default choice
is to target the **host computer**, meaning that the
resulting executable will be *unsuitable for copying to a different
computer*. In order to copy an executable to another computer, the compiler
needs to know about the target requirements via the `-target` option.

The Zig Standard Library (<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"std"`</span>`)`) has
cross-platform abstractions, making the same source code viable on many targets.
Some code is more portable than other code. In general, Zig code is extremely
portable compared to other programming languages.

Each platform requires its own implementations to make Zig's
cross-platform abstractions work. These implementations are at various
degrees of completion. Each tagged release of the compiler comes with
release notes that provide the full support table for each target.

## [Style Guide](#toc-Style-Guide) <a href="#Style-Guide" class="hdr">§</a>

These coding conventions are not enforced by the compiler, but they are shipped in
this documentation along with the compiler in order to provide a point of
reference, should anyone wish to point to an authority on agreed upon Zig
coding style.

### [Avoid Redundancy in Names](#toc-Avoid-Redundancy-in-Names) <a href="#Avoid-Redundancy-in-Names" class="hdr">§</a>

Avoid these words in type names:

- Value
- Data
- Context
- Manager
- utils, misc, or somebody's initials

Everything is a value, all types are data, everything is context, all logic manages state.
Nothing is communicated by using a word that applies to all types.

Temptation to use "utilities", "miscellaneous", or somebody's initials
is a failure to categorize, or more commonly, overcategorization. Such
declarations can live at the root of a module that needs them with no
namespace needed.

### [Avoid Redundant Names in Fully-Qualified Namespaces](#toc-Avoid-Redundant-Names-in-Fully-Qualified-Namespaces) <a href="#Avoid-Redundant-Names-in-Fully-Qualified-Namespaces" class="hdr">§</a>

Every declaration is assigned a **fully qualified
namespace** by the compiler, creating a tree structure. Choose names based
on the fully-qualified namespace, and avoid redundant name segments.

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub const json = struct {
    pub const JsonValue = union(enum) {
        number: f64,
        boolean: bool,
        // ...
    };
};

pub fn main() void {
    std.debug.print(&quot;{s}\n&quot;, .{@typeName(json.JsonValue)});
}</code></pre>
<figcaption>redundant_fqn.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe redundant_fqn.zig
$ ./redundant_fqn
redundant_fqn.json.JsonValue</code></pre>
<figcaption>Shell</figcaption>
</figure>

In this example, "json" is repeated in the fully-qualified namespace. The solution
is to delete `Json` from `JsonValue`. In this example we have
an empty struct named `json` but remember that files also act
as part of the fully-qualified namespace.

This example is an exception to the rule specified in [Avoid Redundancy in Names](#Avoid-Redundancy-in-Names).
The meaning of the type has been reduced to its core: it is a json value. The name
cannot be any more specific without being incorrect.

### [Whitespace](#toc-Whitespace) <a href="#Whitespace" class="hdr">§</a>

- 4 space indentation
- Open braces on same line, unless you need to wrap.
- If a list of things is longer than 2, put each item on its own line and
  exercise the ability to put an extra comma at the end.
- Line length: aim for 100; use common sense.

### [Names](#toc-Names) <a href="#Names" class="hdr">§</a>

Roughly speaking: `camelCaseFunctionName`, `TitleCaseTypeName`,
`snake_case_variable_name`. More precisely:

- If `x` is a <span class="tok-type">`type`</span>
  then `x` should be `TitleCase`, unless it
  is a <span class="tok-kw">`struct`</span> with 0 fields and is never meant to be instantiated,
  in which case it is considered to be a "namespace" and uses `snake_case`.
- If `x` is callable, and `x`'s return type is
  <span class="tok-type">`type`</span>, then `x` should be `TitleCase`.
- If `x` is otherwise callable, then `x` should
  be `camelCase`.
- Otherwise, `x` should be `snake_case`.

Acronyms, initialisms, proper nouns, or any other word that has capitalization
rules in written English are subject to naming conventions just like any other
word. Even acronyms that are only 2 letters long are subject to these
conventions.

File names fall into two categories: types and namespaces. If the file
(implicitly a struct) has top level fields, it should be named like any
other struct with fields using `TitleCase`. Otherwise,
it should use `snake_case`. Directory names should be
`snake_case`.

These are general rules of thumb; if it makes sense to do something different,
do what makes sense. For example, if there is an established convention such as
`ENOENT`, follow the established convention.

### [Examples](#toc-Examples) <a href="#Examples" class="hdr">§</a>

<figure>
<pre><code>const namespace_name = @import(&quot;dir_name/file_name.zig&quot;);
const TypeName = @import(&quot;dir_name/TypeName.zig&quot;);
var global_var: i32 = undefined;
const const_name = 42;
const primitive_type_alias = f32;
const string_alias = []u8;

const StructName = struct {
    field: i32,
};
const StructAlias = StructName;

fn functionName(param_name: TypeName) void {
    var functionPointer = functionName;
    functionPointer();
    functionPointer = otherFunction;
    functionPointer();
}
const functionAlias = functionName;

fn ListTemplateFunction(comptime ChildType: type, comptime fixed_size: usize) type {
    return List(ChildType, fixed_size);
}

fn ShortList(comptime T: type, comptime n: usize) type {
    return struct {
        field_name: [n]T,
        fn methodName() void {}
    };
}

// The word XML loses its casing when used in Zig identifiers.
const xml_document =
    \\&lt;?xml version=&quot;1.0&quot; encoding=&quot;UTF-8&quot;?&gt;
    \\&lt;document&gt;
    \\&lt;/document&gt;
;
const XmlParser = struct {
    field: i32,
};

// The initials BE (Big Endian) are just another word in Zig identifier names.
fn readU32Be() u32 {}</code></pre>
<figcaption>style_example.zig</figcaption>
</figure>

See the [Zig Standard Library](#Zig-Standard-Library) for more examples.

### [Doc Comment Guidance](#toc-Doc-Comment-Guidance) <a href="#Doc-Comment-Guidance" class="hdr">§</a>

- Omit any information that is redundant based on the name of the thing being documented.
- Duplicating information onto multiple similar functions is encouraged because it helps IDEs and other tools provide better help text.
- Use the word **assume** to indicate invariants that cause *unchecked* [Illegal Behavior](#Illegal-Behavior) when violated.
- Use the word **assert** to indicate invariants that cause *safety-checked* [Illegal Behavior](#Illegal-Behavior) when violated.

## [Source Encoding](#toc-Source-Encoding) <a href="#Source-Encoding" class="hdr">§</a>

Zig source code is encoded in UTF-8. An invalid UTF-8 byte sequence results in a compile error.

Throughout all zig source code (including in comments), some code points are never allowed:

- Ascii control characters, except for U+000a (LF), U+000d (CR), and U+0009 (HT): U+0000 - U+0008, U+000b - U+000c, U+000e - U+0001f, U+007f.
- Non-Ascii Unicode line endings: U+0085 (NEL), U+2028 (LS), U+2029 (PS).

LF (byte value 0x0a, code point U+000a, <span class="tok-str">`'\n'`</span>) is the line terminator in Zig source code.
This byte value terminates every line of zig source code except the last line of the file.
It is recommended that non-empty source files end with an empty line, which means the last byte would be 0x0a (LF).

Each LF may be immediately preceded by a single CR (byte value 0x0d, code point U+000d, <span class="tok-str">`'\r'`</span>)
to form a Windows style line ending, but this is discouraged. Note that in multiline strings, CRLF sequences will
be encoded as LF when compiled into a zig program.
A CR in any other context is not allowed.

HT hard tabs (byte value 0x09, code point U+0009, <span class="tok-str">`'\t'`</span>) are interchangeable with
SP spaces (byte value 0x20, code point U+0020, <span class="tok-str">`' '`</span>) as a token separator,
but use of hard tabs is discouraged. See [Grammar](#Grammar).

For compatibility with other tools, the compiler ignores a UTF-8-encoded byte order mark (U+FEFF)
if it is the first Unicode code point in the source text. A byte order mark is not allowed anywhere else in the source.

Note that running <span class="kbd">zig fmt</span> on a source file will implement all recommendations mentioned here.

Note that a tool reading Zig source code can make assumptions if the source code is assumed to be correct Zig code.
For example, when identifying the ends of lines, a tool can use a naive search such as `/\n/`,
or an [advanced](https://msdn.microsoft.com/en-us/library/dd409797.aspx)
search such as `/\r\n?|[\n\u0085\u2028\u2029]/`, and in either case line endings will be correctly identified.
For another example, when identifying the whitespace before the first token on a line,
a tool can either use a naive search such as `/[ \t]/`,
or an [advanced](https://tc39.es/ecma262/#sec-characterclassescape) search such as `/\s/`,
and in either case whitespace will be correctly identified.

## [Keyword Reference](#toc-Keyword-Reference) <a href="#Keyword-Reference" class="hdr">§</a>

<div class="table-wrapper">

<table>
<colgroup>
<col style="width: 50%" />
<col style="width: 50%" />
</colgroup>
<thead>
<tr>
<th scope="col">Keyword</th>
<th scope="col">Description</th>
</tr>
</thead>
<tbody>
<tr>
<th scope="row"><pre><code>addrspace</code></pre></th>
<td>The <span class="tok-kw"><code>addrspace</code></span> keyword.
<ul>
<li>TODO add documentation for addrspace</li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>align</code></pre></th>
<td><span class="tok-kw"><code>align</code></span> can be used to specify the alignment of a pointer.
It can also be used after a variable or function declaration to specify the alignment of pointers to that variable or function.
<ul>
<li>See also <a href="#Alignment">Alignment</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>allowzero</code></pre></th>
<td>The pointer attribute <span class="tok-kw"><code>allowzero</code></span> allows a pointer to have address zero.
<ul>
<li>See also <a href="#allowzero">allowzero</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>and</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>and</code></span>.
<ul>
<li>See also <a href="#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anyframe</code></pre></th>
<td><span class="tok-kw"><code>anyframe</code></span> can be used as a type for variables which hold pointers to function frames.
<ul>
<li>See also <a href="#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anytype</code></pre></th>
<td>Function parameters can be declared with <span class="tok-kw"><code>anytype</code></span> in place of the type.
The type will be inferred where the function is called.
<ul>
<li>See also <a href="#Function-Parameter-Type-Inference">Function Parameter Type Inference</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>asm</code></pre></th>
<td><span class="tok-kw"><code>asm</code></span> begins an inline assembly expression. This allows for directly controlling the machine code generated on compilation.
<ul>
<li>See also <a href="#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>break</code></pre></th>
<td><span class="tok-kw"><code>break</code></span> can be used with a block label to return a value from the block.
It can also be used to exit a loop before iteration completes naturally.
<ul>
<li>See also <a href="#Blocks">Blocks</a>, <a href="#while">while</a>, <a href="#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>callconv</code></pre></th>
<td><span class="tok-kw"><code>callconv</code></span> can be used to specify the calling convention in a function type.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>catch</code></pre></th>
<td><span class="tok-kw"><code>catch</code></span> can be used to evaluate an expression if the expression before it evaluates to an error.
The expression after the <span class="tok-kw"><code>catch</code></span> can optionally capture the error value.
<ul>
<li>See also <a href="#catch">catch</a>, <a href="#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>comptime</code></pre></th>
<td><span class="tok-kw"><code>comptime</code></span> before a declaration can be used to label variables or function parameters as known at compile time.
It can also be used to guarantee an expression is run at compile time.
<ul>
<li>See also <a href="#comptime">comptime</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>const</code></pre></th>
<td><span class="tok-kw"><code>const</code></span> declares a variable that can not be modified.
Used as a pointer attribute, it denotes the value referenced by the pointer cannot be modified.
<ul>
<li>See also <a href="#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>continue</code></pre></th>
<td><span class="tok-kw"><code>continue</code></span> can be used in a loop to jump back to the beginning of the loop.
<ul>
<li>See also <a href="#while">while</a>, <a href="#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>defer</code></pre></th>
<td><span class="tok-kw"><code>defer</code></span> will execute an expression when control flow leaves the current block.
<ul>
<li>See also <a href="#defer">defer</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>else</code></pre></th>
<td><span class="tok-kw"><code>else</code></span> can be used to provide an alternate branch for <span class="tok-kw"><code>if</code></span>, <span class="tok-kw"><code>switch</code></span>,
<span class="tok-kw"><code>while</code></span>, and <span class="tok-kw"><code>for</code></span> expressions.
<ul>
<li>If used after an if expression, the else branch will be executed if the test value returns false, null, or an error.</li>
<li>If used within a switch expression, the else branch will be executed if the test value matches no other cases.</li>
<li>If used after a loop expression, the else branch will be executed if the loop finishes without breaking.</li>
<li>See also <a href="#if">if</a>, <a href="#switch">switch</a>, <a href="#while">while</a>, <a href="#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>enum</code></pre></th>
<td><span class="tok-kw"><code>enum</code></span> defines an enum type.
<ul>
<li>See also <a href="#enum">enum</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>errdefer</code></pre></th>
<td><span class="tok-kw"><code>errdefer</code></span> will execute an expression when control flow leaves the current block if the function returns an error, the errdefer expression can capture the unwrapped value.
<ul>
<li>See also <a href="#errdefer">errdefer</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>error</code></pre></th>
<td><span class="tok-kw"><code>error</code></span> defines an error type.
<ul>
<li>See also <a href="#Errors">Errors</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>export</code></pre></th>
<td><span class="tok-kw"><code>export</code></span> makes a function or variable externally visible in the generated object file.
Exported functions default to the C calling convention.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>extern</code></pre></th>
<td><span class="tok-kw"><code>extern</code></span> can be used to declare a function or variable that will be resolved at link time, when linking statically
or at runtime, when linking dynamically.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>fn</code></pre></th>
<td><span class="tok-kw"><code>fn</code></span> declares a function.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>for</code></pre></th>
<td>A <span class="tok-kw"><code>for</code></span> expression can be used to iterate over the elements of a slice, array, or tuple.
<ul>
<li>See also <a href="#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>if</code></pre></th>
<td>An <span class="tok-kw"><code>if</code></span> expression can test boolean expressions, optional values, or error unions.
For optional values or error unions, the if expression can capture the unwrapped value.
<ul>
<li>See also <a href="#if">if</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>inline</code></pre></th>
<td><span class="tok-kw"><code>inline</code></span> can be used to label a loop expression such that it will be unrolled at compile time.
It can also be used to force a function to be inlined at all call sites.
<ul>
<li>See also <a href="#inline-while">inline while</a>, <a href="#inline-for">inline for</a>, <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>linksection</code></pre></th>
<td>The <span class="tok-kw"><code>linksection</code></span> keyword can be used to specify what section the function or global variable will be put into (e.g. <code>.text</code>).</td>
</tr>
<tr>
<th scope="row"><pre><code>noalias</code></pre></th>
<td>The <span class="tok-kw"><code>noalias</code></span> keyword.
<ul>
<li>TODO add documentation for noalias</li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>noinline</code></pre></th>
<td><span class="tok-kw"><code>noinline</code></span> disallows function to be inlined in all call sites.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>nosuspend</code></pre></th>
<td>The <span class="tok-kw"><code>nosuspend</code></span> keyword can be used in front of a block, statement or expression, to mark a scope where no suspension points are reached.
In particular, inside a <span class="tok-kw"><code>nosuspend</code></span> scope:
<ul>
<li>Using the <span class="tok-kw"><code>suspend</code></span> keyword results in a compile error.</li>
<li>Using <code>await</code> on a function frame which hasn't completed yet results in safety-checked <a href="#Illegal-Behavior">Illegal Behavior</a>.</li>
<li>Calling an async function may result in safety-checked <a href="#Illegal-Behavior">Illegal Behavior</a>, because it's equivalent to <code>await async some_async_fn()</code>, which contains an <code>await</code>.</li>
</ul>
Code inside a <span class="tok-kw"><code>nosuspend</code></span> scope does not cause the enclosing function to become an <a href="#Async-Functions">async function</a>.
<ul>
<li>See also <a href="#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>opaque</code></pre></th>
<td><span class="tok-kw"><code>opaque</code></span> defines an opaque type.
<ul>
<li>See also <a href="#opaque">opaque</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>or</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>or</code></span>.
<ul>
<li>See also <a href="#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>orelse</code></pre></th>
<td><span class="tok-kw"><code>orelse</code></span> can be used to evaluate an expression if the expression before it evaluates to null.
<ul>
<li>See also <a href="#Optionals">Optionals</a>, <a href="#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>packed</code></pre></th>
<td>The <span class="tok-kw"><code>packed</code></span> keyword before a struct definition changes the struct's in-memory layout
to the guaranteed <span class="tok-kw"><code>packed</code></span> layout.
<ul>
<li>See also <a href="#packed-struct">packed struct</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>pub</code></pre></th>
<td>The <span class="tok-kw"><code>pub</code></span> in front of a top level declaration makes the declaration available
to reference from a different file than the one it is declared in.
<ul>
<li>See also <a href="#import">import</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>resume</code></pre></th>
<td><span class="tok-kw"><code>resume</code></span> will continue execution of a function frame after the point the function was suspended.</td>
</tr>
<tr>
<th scope="row"><pre><code>return</code></pre></th>
<td><span class="tok-kw"><code>return</code></span> exits a function with a value.
<ul>
<li>See also <a href="#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>struct</code></pre></th>
<td><span class="tok-kw"><code>struct</code></span> defines a struct.
<ul>
<li>See also <a href="#struct">struct</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>suspend</code></pre></th>
<td><span class="tok-kw"><code>suspend</code></span> will cause control flow to return to the call site or resumer of the function.
<span class="tok-kw"><code>suspend</code></span> can also be used before a block within a function,
to allow the function access to its frame before control flow returns to the call site.</td>
</tr>
<tr>
<th scope="row"><pre><code>switch</code></pre></th>
<td>A <span class="tok-kw"><code>switch</code></span> expression can be used to test values of a common type.
<span class="tok-kw"><code>switch</code></span> cases can capture field values of a <a href="#Tagged-union">Tagged union</a>.
<ul>
<li>See also <a href="#switch">switch</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>test</code></pre></th>
<td>The <span class="tok-kw"><code>test</code></span> keyword can be used to denote a top-level block of code
used to make sure behavior meets expectations.
<ul>
<li>See also <a href="#Zig-Test">Zig Test</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>threadlocal</code></pre></th>
<td><span class="tok-kw"><code>threadlocal</code></span> can be used to specify a variable as thread-local.
<ul>
<li>See also <a href="#Thread-Local-Variables">Thread Local Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>try</code></pre></th>
<td><span class="tok-kw"><code>try</code></span> evaluates an error union expression.
If it is an error, it returns from the current function with the same error.
Otherwise, the expression results in the unwrapped value.
<ul>
<li>See also <a href="#try">try</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>union</code></pre></th>
<td><span class="tok-kw"><code>union</code></span> defines a union.
<ul>
<li>See also <a href="#union">union</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>unreachable</code></pre></th>
<td><span class="tok-kw"><code>unreachable</code></span> can be used to assert that control flow will never happen upon a particular location.
Depending on the build mode, <span class="tok-kw"><code>unreachable</code></span> may emit a panic.
<ul>
<li>Emits a panic in <code>Debug</code> and <code>ReleaseSafe</code> mode, or when using <kbd>zig test</kbd>.</li>
<li>Does not emit a panic in <code>ReleaseFast</code> and <code>ReleaseSmall</code> mode.</li>
<li>See also <a href="#unreachable">unreachable</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>var</code></pre></th>
<td><span class="tok-kw"><code>var</code></span> declares a variable that may be modified.
<ul>
<li>See also <a href="#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>volatile</code></pre></th>
<td><span class="tok-kw"><code>volatile</code></span> can be used to denote loads or stores of a pointer have side effects.
It can also modify an inline assembly expression to denote it has side effects.
<ul>
<li>See also <a href="#volatile">volatile</a>, <a href="#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>while</code></pre></th>
<td>A <span class="tok-kw"><code>while</code></span> expression can be used to repeatedly test a boolean, optional, or error union expression,
and cease looping when that expression evaluates to false, null, or an error, respectively.
<ul>
<li>See also <a href="#while">while</a></li>
</ul></td>
</tr>
</tbody>
</table>

</div>

## [Appendix](#toc-Appendix) <a href="#Appendix" class="hdr">§</a>

### [Containers](#toc-Containers) <a href="#Containers" class="hdr">§</a>

A *container* in Zig is any syntactical construct that acts as a namespace to hold [variable](#Container-Level-Variables) and [function](#Functions) declarations.
Containers are also type definitions which can be instantiated.
[Structs](#struct), [enums](#enum), [unions](#union), [opaques](#opaque), and even Zig source files themselves are containers.

Although containers (except Zig source files) use curly braces to surround their definition, they should not be confused with [blocks](#Blocks) or functions.
Containers do not contain statements.

### [Grammar](#toc-Grammar) <a href="#Grammar" class="hdr">§</a>

<figure>
<pre><code>Root &lt;- skip container_doc_comment? ContainerMembers eof

# *** Top level ***
ContainerMembers &lt;- ContainerDeclaration* (ContainerField COMMA)* (ContainerField / ContainerDeclaration*)

ContainerDeclaration &lt;- TestDecl / ComptimeDecl / doc_comment? KEYWORD_pub? Decl

TestDecl &lt;- KEYWORD_test (STRINGLITERALSINGLE / IDENTIFIER)? Block

ComptimeDecl &lt;- KEYWORD_comptime Block

Decl
    &lt;- (KEYWORD_export / KEYWORD_extern STRINGLITERALSINGLE? / KEYWORD_inline / KEYWORD_noinline)? FnProto (SEMICOLON / Block)
     / (KEYWORD_export / KEYWORD_extern STRINGLITERALSINGLE?)? KEYWORD_threadlocal? GlobalVarDecl

FnProto &lt;- KEYWORD_fn IDENTIFIER? LPAREN ParamDeclList RPAREN ByteAlign? AddrSpace? LinkSection? CallConv? EXCLAMATIONMARK? TypeExpr

VarDeclProto &lt;- (KEYWORD_const / KEYWORD_var) IDENTIFIER (COLON TypeExpr)? ByteAlign? AddrSpace? LinkSection?

GlobalVarDecl &lt;- VarDeclProto (EQUAL Expr)? SEMICOLON

ContainerField &lt;- doc_comment? KEYWORD_comptime? !KEYWORD_fn (IDENTIFIER COLON)? TypeExpr ByteAlign? (EQUAL Expr)?

# *** Block Level ***
Statement
    &lt;- KEYWORD_comptime ComptimeStatement
     / KEYWORD_nosuspend BlockExprStatement
     / KEYWORD_suspend BlockExprStatement
     / KEYWORD_defer BlockExprStatement
     / KEYWORD_errdefer Payload? BlockExprStatement
     / IfStatement
     / LabeledStatement
     / SwitchExpr
     / VarDeclExprStatement

ComptimeStatement
    &lt;- BlockExpr
     / VarDeclExprStatement

IfStatement
    &lt;- IfPrefix BlockExpr ( KEYWORD_else Payload? Statement )?
     / IfPrefix AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )

LabeledStatement &lt;- BlockLabel? (Block / LoopStatement)

LoopStatement &lt;- KEYWORD_inline? (ForStatement / WhileStatement)

ForStatement
    &lt;- ForPrefix BlockExpr ( KEYWORD_else Statement )?
     / ForPrefix AssignExpr ( SEMICOLON / KEYWORD_else Statement )

WhileStatement
    &lt;- WhilePrefix BlockExpr ( KEYWORD_else Payload? Statement )?
     / WhilePrefix AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )

BlockExprStatement
    &lt;- BlockExpr
     / AssignExpr SEMICOLON

BlockExpr &lt;- BlockLabel? Block

# An expression, assignment, or any destructure, as a statement.
VarDeclExprStatement
    &lt;- VarDeclProto (COMMA (VarDeclProto / Expr))* EQUAL Expr SEMICOLON
     / Expr (AssignOp Expr / (COMMA (VarDeclProto / Expr))+ EQUAL Expr)? SEMICOLON

# *** Expression Level ***

# An assignment or a destructure whose LHS are all lvalue expressions.
AssignExpr &lt;- Expr (AssignOp Expr / (COMMA Expr)+ EQUAL Expr)?

SingleAssignExpr &lt;- Expr (AssignOp Expr)?

Expr &lt;- BoolOrExpr

BoolOrExpr &lt;- BoolAndExpr (KEYWORD_or BoolAndExpr)*

BoolAndExpr &lt;- CompareExpr (KEYWORD_and CompareExpr)*

CompareExpr &lt;- BitwiseExpr (CompareOp BitwiseExpr)?

BitwiseExpr &lt;- BitShiftExpr (BitwiseOp BitShiftExpr)*

BitShiftExpr &lt;- AdditionExpr (BitShiftOp AdditionExpr)*

AdditionExpr &lt;- MultiplyExpr (AdditionOp MultiplyExpr)*

MultiplyExpr &lt;- PrefixExpr (MultiplyOp PrefixExpr)*

PrefixExpr &lt;- PrefixOp* PrimaryExpr

PrimaryExpr
    &lt;- AsmExpr
     / IfExpr
     / KEYWORD_break BreakLabel? Expr?
     / KEYWORD_comptime Expr
     / KEYWORD_nosuspend Expr
     / KEYWORD_continue BreakLabel?
     / KEYWORD_resume Expr
     / KEYWORD_return Expr?
     / BlockLabel? LoopExpr
     / Block
     / CurlySuffixExpr

IfExpr &lt;- IfPrefix Expr (KEYWORD_else Payload? Expr)?

Block &lt;- LBRACE Statement* RBRACE

LoopExpr &lt;- KEYWORD_inline? (ForExpr / WhileExpr)

ForExpr &lt;- ForPrefix Expr (KEYWORD_else Expr)?

WhileExpr &lt;- WhilePrefix Expr (KEYWORD_else Payload? Expr)?

CurlySuffixExpr &lt;- TypeExpr InitList?

InitList
    &lt;- LBRACE FieldInit (COMMA FieldInit)* COMMA? RBRACE
     / LBRACE Expr (COMMA Expr)* COMMA? RBRACE
     / LBRACE RBRACE

TypeExpr &lt;- PrefixTypeOp* ErrorUnionExpr

ErrorUnionExpr &lt;- SuffixExpr (EXCLAMATIONMARK TypeExpr)?

SuffixExpr
    &lt;- PrimaryTypeExpr (SuffixOp / FnCallArguments)*

PrimaryTypeExpr
    &lt;- BUILTINIDENTIFIER FnCallArguments
     / CHAR_LITERAL
     / ContainerDecl
     / DOT IDENTIFIER
     / DOT InitList
     / ErrorSetDecl
     / FLOAT
     / FnProto
     / GroupedExpr
     / LabeledTypeExpr
     / IDENTIFIER
     / IfTypeExpr
     / INTEGER
     / KEYWORD_comptime TypeExpr
     / KEYWORD_error DOT IDENTIFIER
     / KEYWORD_anyframe
     / KEYWORD_unreachable
     / STRINGLITERAL
     / SwitchExpr

ContainerDecl &lt;- (KEYWORD_extern / KEYWORD_packed)? ContainerDeclAuto

ErrorSetDecl &lt;- KEYWORD_error LBRACE IdentifierList RBRACE

GroupedExpr &lt;- LPAREN Expr RPAREN

IfTypeExpr &lt;- IfPrefix TypeExpr (KEYWORD_else Payload? TypeExpr)?

LabeledTypeExpr
    &lt;- BlockLabel Block
     / BlockLabel? LoopTypeExpr

LoopTypeExpr &lt;- KEYWORD_inline? (ForTypeExpr / WhileTypeExpr)

ForTypeExpr &lt;- ForPrefix TypeExpr (KEYWORD_else TypeExpr)?

WhileTypeExpr &lt;- WhilePrefix TypeExpr (KEYWORD_else Payload? TypeExpr)?

SwitchExpr &lt;- KEYWORD_switch LPAREN Expr RPAREN LBRACE SwitchProngList RBRACE

# *** Assembly ***
AsmExpr &lt;- KEYWORD_asm KEYWORD_volatile? LPAREN Expr AsmOutput? RPAREN

AsmOutput &lt;- COLON AsmOutputList AsmInput?

AsmOutputItem &lt;- LBRACKET IDENTIFIER RBRACKET STRINGLITERAL LPAREN (MINUSRARROW TypeExpr / IDENTIFIER) RPAREN

AsmInput &lt;- COLON AsmInputList AsmClobbers?

AsmInputItem &lt;- LBRACKET IDENTIFIER RBRACKET STRINGLITERAL LPAREN Expr RPAREN

AsmClobbers &lt;- COLON Expr

# *** Helper grammar ***
BreakLabel &lt;- COLON IDENTIFIER

BlockLabel &lt;- IDENTIFIER COLON

FieldInit &lt;- DOT IDENTIFIER EQUAL Expr

WhileContinueExpr &lt;- COLON LPAREN AssignExpr RPAREN

LinkSection &lt;- KEYWORD_linksection LPAREN Expr RPAREN

AddrSpace &lt;- KEYWORD_addrspace LPAREN Expr RPAREN

# Fn specific
CallConv &lt;- KEYWORD_callconv LPAREN Expr RPAREN

ParamDecl
    &lt;- doc_comment? (KEYWORD_noalias / KEYWORD_comptime)? (IDENTIFIER COLON)? ParamType
     / DOT3

ParamType
    &lt;- KEYWORD_anytype
     / TypeExpr

# Control flow prefixes
IfPrefix &lt;- KEYWORD_if LPAREN Expr RPAREN PtrPayload?

WhilePrefix &lt;- KEYWORD_while LPAREN Expr RPAREN PtrPayload? WhileContinueExpr?

ForPrefix &lt;- KEYWORD_for LPAREN ForArgumentsList RPAREN PtrListPayload

# Payloads
Payload &lt;- PIPE IDENTIFIER PIPE

PtrPayload &lt;- PIPE ASTERISK? IDENTIFIER PIPE

PtrIndexPayload &lt;- PIPE ASTERISK? IDENTIFIER (COMMA IDENTIFIER)? PIPE

PtrListPayload &lt;- PIPE ASTERISK? IDENTIFIER (COMMA ASTERISK? IDENTIFIER)* COMMA? PIPE

# Switch specific
SwitchProng &lt;- KEYWORD_inline? SwitchCase EQUALRARROW PtrIndexPayload? SingleAssignExpr

SwitchCase
    &lt;- SwitchItem (COMMA SwitchItem)* COMMA?
     / KEYWORD_else

SwitchItem &lt;- Expr (DOT3 Expr)?

# For specific
ForArgumentsList &lt;- ForItem (COMMA ForItem)* COMMA?

ForItem &lt;- Expr (DOT2 Expr?)?

# Operators
AssignOp
    &lt;- ASTERISKEQUAL
     / ASTERISKPIPEEQUAL
     / SLASHEQUAL
     / PERCENTEQUAL
     / PLUSEQUAL
     / PLUSPIPEEQUAL
     / MINUSEQUAL
     / MINUSPIPEEQUAL
     / LARROW2EQUAL
     / LARROW2PIPEEQUAL
     / RARROW2EQUAL
     / AMPERSANDEQUAL
     / CARETEQUAL
     / PIPEEQUAL
     / ASTERISKPERCENTEQUAL
     / PLUSPERCENTEQUAL
     / MINUSPERCENTEQUAL
     / EQUAL

CompareOp
    &lt;- EQUALEQUAL
     / EXCLAMATIONMARKEQUAL
     / LARROW
     / RARROW
     / LARROWEQUAL
     / RARROWEQUAL

BitwiseOp
    &lt;- AMPERSAND
     / CARET
     / PIPE
     / KEYWORD_orelse
     / KEYWORD_catch Payload?

BitShiftOp
    &lt;- LARROW2
     / RARROW2
     / LARROW2PIPE

AdditionOp
    &lt;- PLUS
     / MINUS
     / PLUS2
     / PLUSPERCENT
     / MINUSPERCENT
     / PLUSPIPE
     / MINUSPIPE

MultiplyOp
    &lt;- PIPE2
     / ASTERISK
     / SLASH
     / PERCENT
     / ASTERISK2
     / ASTERISKPERCENT
     / ASTERISKPIPE

PrefixOp
    &lt;- EXCLAMATIONMARK
     / MINUS
     / TILDE
     / MINUSPERCENT
     / AMPERSAND
     / KEYWORD_try

PrefixTypeOp
    &lt;- QUESTIONMARK
     / KEYWORD_anyframe MINUSRARROW
     / SliceTypeStart (ByteAlign / AddrSpace / KEYWORD_const / KEYWORD_volatile / KEYWORD_allowzero)*
     / PtrTypeStart (AddrSpace / KEYWORD_align LPAREN Expr (COLON Expr COLON Expr)? RPAREN / KEYWORD_const / KEYWORD_volatile / KEYWORD_allowzero)*
     / ArrayTypeStart

SuffixOp
    &lt;- LBRACKET Expr (DOT2 (Expr? (COLON Expr)?)?)? RBRACKET
     / DOT IDENTIFIER
     / DOTASTERISK
     / DOTQUESTIONMARK

FnCallArguments &lt;- LPAREN ExprList RPAREN

# Ptr specific
SliceTypeStart &lt;- LBRACKET (COLON Expr)? RBRACKET

PtrTypeStart
    &lt;- ASTERISK
     / ASTERISK2
     / LBRACKET ASTERISK (LETTERC / COLON Expr)? RBRACKET

ArrayTypeStart &lt;- LBRACKET Expr (COLON Expr)? RBRACKET

# ContainerDecl specific
ContainerDeclAuto &lt;- ContainerDeclType LBRACE container_doc_comment? ContainerMembers RBRACE

ContainerDeclType
    &lt;- KEYWORD_struct (LPAREN Expr RPAREN)?
     / KEYWORD_opaque
     / KEYWORD_enum (LPAREN Expr RPAREN)?
     / KEYWORD_union (LPAREN (KEYWORD_enum (LPAREN Expr RPAREN)? / Expr) RPAREN)?

# Alignment
ByteAlign &lt;- KEYWORD_align LPAREN Expr RPAREN

# Lists
IdentifierList &lt;- (doc_comment? IDENTIFIER COMMA)* (doc_comment? IDENTIFIER)?

SwitchProngList &lt;- (SwitchProng COMMA)* SwitchProng?

AsmOutputList &lt;- (AsmOutputItem COMMA)* AsmOutputItem?

AsmInputList &lt;- (AsmInputItem COMMA)* AsmInputItem?

StringList &lt;- (STRINGLITERAL COMMA)* STRINGLITERAL?

ParamDeclList &lt;- (ParamDecl COMMA)* ParamDecl?

ExprList &lt;- (Expr COMMA)* Expr?

# *** Tokens ***
eof &lt;- !.
bin &lt;- [01]
bin_ &lt;- &#39;_&#39;? bin
oct &lt;- [0-7]
oct_ &lt;- &#39;_&#39;? oct
hex &lt;- [0-9a-fA-F]
hex_ &lt;- &#39;_&#39;? hex
dec &lt;- [0-9]
dec_ &lt;- &#39;_&#39;? dec

bin_int &lt;- bin bin_*
oct_int &lt;- oct oct_*
dec_int &lt;- dec dec_*
hex_int &lt;- hex hex_*

ox80_oxBF &lt;- [\200-\277]
oxF4 &lt;- &#39;\364&#39;
ox80_ox8F &lt;- [\200-\217]
oxF1_oxF3 &lt;- [\361-\363]
oxF0 &lt;- &#39;\360&#39;
ox90_0xBF &lt;- [\220-\277]
oxEE_oxEF &lt;- [\356-\357]
oxED &lt;- &#39;\355&#39;
ox80_ox9F &lt;- [\200-\237]
oxE1_oxEC &lt;- [\341-\354]
oxE0 &lt;- &#39;\340&#39;
oxA0_oxBF &lt;- [\240-\277]
oxC2_oxDF &lt;- [\302-\337]

# From https://lemire.me/blog/2018/05/09/how-quickly-can-you-check-that-a-string-is-valid-unicode-utf-8/
# First Byte      Second Byte     Third Byte      Fourth Byte
# [0x00,0x7F]
# [0xC2,0xDF]     [0x80,0xBF]
#    0xE0         [0xA0,0xBF]     [0x80,0xBF]
# [0xE1,0xEC]     [0x80,0xBF]     [0x80,0xBF]
#    0xED         [0x80,0x9F]     [0x80,0xBF]
# [0xEE,0xEF]     [0x80,0xBF]     [0x80,0xBF]
#    0xF0         [0x90,0xBF]     [0x80,0xBF]     [0x80,0xBF]
# [0xF1,0xF3]     [0x80,0xBF]     [0x80,0xBF]     [0x80,0xBF]
#    0xF4         [0x80,0x8F]     [0x80,0xBF]     [0x80,0xBF]

mb_utf8_literal &lt;-
       oxF4      ox80_ox8F ox80_oxBF ox80_oxBF
     / oxF1_oxF3 ox80_oxBF ox80_oxBF ox80_oxBF
     / oxF0      ox90_0xBF ox80_oxBF ox80_oxBF
     / oxEE_oxEF ox80_oxBF ox80_oxBF
     / oxED      ox80_ox9F ox80_oxBF
     / oxE1_oxEC ox80_oxBF ox80_oxBF
     / oxE0      oxA0_oxBF ox80_oxBF
     / oxC2_oxDF ox80_oxBF

ascii_char_not_nl_slash_squote &lt;- [\000-\011\013-\046\050-\133\135-\177]

char_escape
    &lt;- &quot;\\x&quot; hex hex
     / &quot;\\u{&quot; hex+ &quot;}&quot;
     / &quot;\\&quot; [nr\\t&#39;&quot;]
char_char
    &lt;- mb_utf8_literal
     / char_escape
     / ascii_char_not_nl_slash_squote

string_char
    &lt;- char_escape
     / [^\\&quot;\n]

container_doc_comment &lt;- (&#39;//!&#39; [^\n]* [ \n]* skip)+
doc_comment &lt;- (&#39;///&#39; [^\n]* [ \n]* skip)+
line_comment &lt;- &#39;//&#39; ![!/][^\n]* / &#39;////&#39; [^\n]*
line_string &lt;- (&quot;\\\\&quot; [^\n]* [ \n]*)+
skip &lt;- ([ \n] / line_comment)*

CHAR_LITERAL &lt;- &quot;&#39;&quot; char_char &quot;&#39;&quot; skip
FLOAT
    &lt;- &quot;0x&quot; hex_int &quot;.&quot; hex_int ([pP] [-+]? dec_int)? skip
     /      dec_int &quot;.&quot; dec_int ([eE] [-+]? dec_int)? skip
     / &quot;0x&quot; hex_int [pP] [-+]? dec_int skip
     /      dec_int [eE] [-+]? dec_int skip
INTEGER
    &lt;- &quot;0b&quot; bin_int skip
     / &quot;0o&quot; oct_int skip
     / &quot;0x&quot; hex_int skip
     /      dec_int   skip
STRINGLITERALSINGLE &lt;- &quot;\&quot;&quot; string_char* &quot;\&quot;&quot; skip
STRINGLITERAL
    &lt;- STRINGLITERALSINGLE
     / (line_string                 skip)+
IDENTIFIER
    &lt;- !keyword [A-Za-z_] [A-Za-z0-9_]* skip
     / &quot;@&quot; STRINGLITERALSINGLE
BUILTINIDENTIFIER &lt;- &quot;@&quot;[A-Za-z_][A-Za-z0-9_]* skip


AMPERSAND            &lt;- &#39;&amp;&#39;      ![=]      skip
AMPERSANDEQUAL       &lt;- &#39;&amp;=&#39;               skip
ASTERISK             &lt;- &#39;*&#39;      ![*%=|]   skip
ASTERISK2            &lt;- &#39;**&#39;               skip
ASTERISKEQUAL        &lt;- &#39;*=&#39;               skip
ASTERISKPERCENT      &lt;- &#39;*%&#39;     ![=]      skip
ASTERISKPERCENTEQUAL &lt;- &#39;*%=&#39;              skip
ASTERISKPIPE         &lt;- &#39;*|&#39;     ![=]      skip
ASTERISKPIPEEQUAL    &lt;- &#39;*|=&#39;              skip
CARET                &lt;- &#39;^&#39;      ![=]      skip
CARETEQUAL           &lt;- &#39;^=&#39;               skip
COLON                &lt;- &#39;:&#39;                skip
COMMA                &lt;- &#39;,&#39;                skip
DOT                  &lt;- &#39;.&#39;      ![*.?]    skip
DOT2                 &lt;- &#39;..&#39;     ![.]      skip
DOT3                 &lt;- &#39;...&#39;              skip
DOTASTERISK          &lt;- &#39;.*&#39;               skip
DOTQUESTIONMARK      &lt;- &#39;.?&#39;               skip
EQUAL                &lt;- &#39;=&#39;      ![&gt;=]     skip
EQUALEQUAL           &lt;- &#39;==&#39;               skip
EQUALRARROW          &lt;- &#39;=&gt;&#39;               skip
EXCLAMATIONMARK      &lt;- &#39;!&#39;      ![=]      skip
EXCLAMATIONMARKEQUAL &lt;- &#39;!=&#39;               skip
LARROW               &lt;- &#39;&lt;&#39;      ![&lt;=]     skip
LARROW2              &lt;- &#39;&lt;&lt;&#39;     ![=|]     skip
LARROW2EQUAL         &lt;- &#39;&lt;&lt;=&#39;              skip
LARROW2PIPE          &lt;- &#39;&lt;&lt;|&#39;    ![=]      skip
LARROW2PIPEEQUAL     &lt;- &#39;&lt;&lt;|=&#39;             skip
LARROWEQUAL          &lt;- &#39;&lt;=&#39;               skip
LBRACE               &lt;- &#39;{&#39;                skip
LBRACKET             &lt;- &#39;[&#39;                skip
LPAREN               &lt;- &#39;(&#39;                skip
MINUS                &lt;- &#39;-&#39;      ![%=&gt;|]   skip
MINUSEQUAL           &lt;- &#39;-=&#39;               skip
MINUSPERCENT         &lt;- &#39;-%&#39;     ![=]      skip
MINUSPERCENTEQUAL    &lt;- &#39;-%=&#39;              skip
MINUSPIPE            &lt;- &#39;-|&#39;     ![=]      skip
MINUSPIPEEQUAL       &lt;- &#39;-|=&#39;              skip
MINUSRARROW          &lt;- &#39;-&gt;&#39;               skip
PERCENT              &lt;- &#39;%&#39;      ![=]      skip
PERCENTEQUAL         &lt;- &#39;%=&#39;               skip
PIPE                 &lt;- &#39;|&#39;      ![|=]     skip
PIPE2                &lt;- &#39;||&#39;               skip
PIPEEQUAL            &lt;- &#39;|=&#39;               skip
PLUS                 &lt;- &#39;+&#39;      ![%+=|]   skip
PLUS2                &lt;- &#39;++&#39;               skip
PLUSEQUAL            &lt;- &#39;+=&#39;               skip
PLUSPERCENT          &lt;- &#39;+%&#39;     ![=]      skip
PLUSPERCENTEQUAL     &lt;- &#39;+%=&#39;              skip
PLUSPIPE             &lt;- &#39;+|&#39;     ![=]      skip
PLUSPIPEEQUAL        &lt;- &#39;+|=&#39;              skip
LETTERC              &lt;- &#39;c&#39;                skip
QUESTIONMARK         &lt;- &#39;?&#39;                skip
RARROW               &lt;- &#39;&gt;&#39;      ![&gt;=]     skip
RARROW2              &lt;- &#39;&gt;&gt;&#39;     ![=]      skip
RARROW2EQUAL         &lt;- &#39;&gt;&gt;=&#39;              skip
RARROWEQUAL          &lt;- &#39;&gt;=&#39;               skip
RBRACE               &lt;- &#39;}&#39;                skip
RBRACKET             &lt;- &#39;]&#39;                skip
RPAREN               &lt;- &#39;)&#39;                skip
SEMICOLON            &lt;- &#39;;&#39;                skip
SLASH                &lt;- &#39;/&#39;      ![=]      skip
SLASHEQUAL           &lt;- &#39;/=&#39;               skip
TILDE                &lt;- &#39;~&#39;                skip

end_of_word &lt;- ![a-zA-Z0-9_] skip
KEYWORD_addrspace   &lt;- &#39;addrspace&#39;   end_of_word
KEYWORD_align       &lt;- &#39;align&#39;       end_of_word
KEYWORD_allowzero   &lt;- &#39;allowzero&#39;   end_of_word
KEYWORD_and         &lt;- &#39;and&#39;         end_of_word
KEYWORD_anyframe    &lt;- &#39;anyframe&#39;    end_of_word
KEYWORD_anytype     &lt;- &#39;anytype&#39;     end_of_word
KEYWORD_asm         &lt;- &#39;asm&#39;         end_of_word
KEYWORD_break       &lt;- &#39;break&#39;       end_of_word
KEYWORD_callconv    &lt;- &#39;callconv&#39;    end_of_word
KEYWORD_catch       &lt;- &#39;catch&#39;       end_of_word
KEYWORD_comptime    &lt;- &#39;comptime&#39;    end_of_word
KEYWORD_const       &lt;- &#39;const&#39;       end_of_word
KEYWORD_continue    &lt;- &#39;continue&#39;    end_of_word
KEYWORD_defer       &lt;- &#39;defer&#39;       end_of_word
KEYWORD_else        &lt;- &#39;else&#39;        end_of_word
KEYWORD_enum        &lt;- &#39;enum&#39;        end_of_word
KEYWORD_errdefer    &lt;- &#39;errdefer&#39;    end_of_word
KEYWORD_error       &lt;- &#39;error&#39;       end_of_word
KEYWORD_export      &lt;- &#39;export&#39;      end_of_word
KEYWORD_extern      &lt;- &#39;extern&#39;      end_of_word
KEYWORD_fn          &lt;- &#39;fn&#39;          end_of_word
KEYWORD_for         &lt;- &#39;for&#39;         end_of_word
KEYWORD_if          &lt;- &#39;if&#39;          end_of_word
KEYWORD_inline      &lt;- &#39;inline&#39;      end_of_word
KEYWORD_noalias     &lt;- &#39;noalias&#39;     end_of_word
KEYWORD_nosuspend   &lt;- &#39;nosuspend&#39;   end_of_word
KEYWORD_noinline    &lt;- &#39;noinline&#39;    end_of_word
KEYWORD_opaque      &lt;- &#39;opaque&#39;      end_of_word
KEYWORD_or          &lt;- &#39;or&#39;          end_of_word
KEYWORD_orelse      &lt;- &#39;orelse&#39;      end_of_word
KEYWORD_packed      &lt;- &#39;packed&#39;      end_of_word
KEYWORD_pub         &lt;- &#39;pub&#39;         end_of_word
KEYWORD_resume      &lt;- &#39;resume&#39;      end_of_word
KEYWORD_return      &lt;- &#39;return&#39;      end_of_word
KEYWORD_linksection &lt;- &#39;linksection&#39; end_of_word
KEYWORD_struct      &lt;- &#39;struct&#39;      end_of_word
KEYWORD_suspend     &lt;- &#39;suspend&#39;     end_of_word
KEYWORD_switch      &lt;- &#39;switch&#39;      end_of_word
KEYWORD_test        &lt;- &#39;test&#39;        end_of_word
KEYWORD_threadlocal &lt;- &#39;threadlocal&#39; end_of_word
KEYWORD_try         &lt;- &#39;try&#39;         end_of_word
KEYWORD_union       &lt;- &#39;union&#39;       end_of_word
KEYWORD_unreachable &lt;- &#39;unreachable&#39; end_of_word
KEYWORD_var         &lt;- &#39;var&#39;         end_of_word
KEYWORD_volatile    &lt;- &#39;volatile&#39;    end_of_word
KEYWORD_while       &lt;- &#39;while&#39;       end_of_word

keyword &lt;- KEYWORD_addrspace / KEYWORD_align / KEYWORD_allowzero / KEYWORD_and
         / KEYWORD_anyframe / KEYWORD_anytype / KEYWORD_asm
         / KEYWORD_break / KEYWORD_callconv / KEYWORD_catch
         / KEYWORD_comptime / KEYWORD_const / KEYWORD_continue / KEYWORD_defer
         / KEYWORD_else / KEYWORD_enum / KEYWORD_errdefer / KEYWORD_error / KEYWORD_export
         / KEYWORD_extern / KEYWORD_fn / KEYWORD_for / KEYWORD_if
         / KEYWORD_inline / KEYWORD_noalias / KEYWORD_nosuspend / KEYWORD_noinline
         / KEYWORD_opaque / KEYWORD_or / KEYWORD_orelse / KEYWORD_packed
         / KEYWORD_pub / KEYWORD_resume / KEYWORD_return / KEYWORD_linksection
         / KEYWORD_struct / KEYWORD_suspend / KEYWORD_switch / KEYWORD_test
         / KEYWORD_threadlocal / KEYWORD_try / KEYWORD_union / KEYWORD_unreachable
         / KEYWORD_var / KEYWORD_volatile / KEYWORD_while</code></pre>
<figcaption>grammar.y</figcaption>
</figure>

### [Zen](#toc-Zen) <a href="#Zen" class="hdr">§</a>

- Communicate intent precisely.
- Edge cases matter.
- Favor reading code over writing code.
- Only one obvious way to do things.
- Runtime crashes are better than bugs.
- Compile errors are better than runtime crashes.
- Incremental improvements.
- Avoid local maximums.
- Reduce the amount one must remember.
- Focus on code rather than style.
- Resource allocation may fail; resource deallocation must succeed.
- Memory is a resource.
- Together we serve the users.

</div>
