<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Introduction & Basics

Included sections:
- Introduction
- Zig Standard Library
- Hello World
- Comments
- Values
- Zig Test
- Variables

## [Introduction](../zig-0.15.1.md#toc-Introduction) <a href="../zig-0.15.1.md#Introduction" class="hdr">§</a>

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

## [Zig Standard Library](../zig-0.15.1.md#toc-Zig-Standard-Library) <a href="../zig-0.15.1.md#Zig-Standard-Library" class="hdr">§</a>

The [Zig Standard Library](https://ziglang.org/documentation/0.15.1/std/) has its own documentation.

Zig's Standard Library contains commonly used algorithms, data structures, and definitions to help you build programs or libraries.
You will see many examples of Zig's Standard Library used in this documentation. To learn more about the Zig Standard Library,
visit the link above.

Alternatively, the Zig Standard Library documentation is provided with each Zig distribution. It can be rendered via a local webserver with:

<figure>
<pre><code>zig std</code></pre>
<figcaption>Shell</figcaption>
</figure>

## [Hello World](../zig-0.15.1.md#toc-Hello-World) <a href="../zig-0.15.1.md#Hello-World" class="hdr">§</a>

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

- [Values](../zig-0.15.1.md#Values)
- [Tuples](../zig-0.15.1.md#Tuples)
- [@import](../zig-0.15.1.md#import)
- [Errors](../zig-0.15.1.md#Errors)
- [Entry Point](../zig-0.15.1.md#Entry-Point)
- [Source Encoding](../zig-0.15.1.md#Source-Encoding)
- [try](../zig-0.15.1.md#try)

## [Comments](../zig-0.15.1.md#toc-Comments) <a href="../zig-0.15.1.md#Comments" class="hdr">§</a>

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

### [Doc Comments](../zig-0.15.1.md#toc-Doc-Comments) <a href="../zig-0.15.1.md#Doc-Comments" class="hdr">§</a>

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

### [Top-Level Doc Comments](../zig-0.15.1.md#toc-Top-Level-Doc-Comments) <a href="../zig-0.15.1.md#Top-Level-Doc-Comments" class="hdr">§</a>

A top-level doc comment is one that begins with two slashes and an exclamation
point: <span class="tok-comment">`//!`</span>; it documents the current module.

It is a compile error if a top-level doc comment is not placed at the start
of a [container](../zig-0.15.1.md#Containers), before any expressions.

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

## [Values](../zig-0.15.1.md#toc-Values) <a href="../zig-0.15.1.md#Values" class="hdr">§</a>

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

### [Primitive Types](../zig-0.15.1.md#toc-Primitive-Types) <a href="../zig-0.15.1.md#Primitive-Types" class="hdr">§</a>

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
| <span class="tok-type">`comptime_int`</span> | (none) | Only allowed for [comptime](../zig-0.15.1.md#comptime)-known values. The type of integer literals. |
| <span class="tok-type">`comptime_float`</span> | (none) | Only allowed for [comptime](../zig-0.15.1.md#comptime)-known values. The type of float literals. |

Primitive Types

</div>

In addition to the integer types above, arbitrary bit-width integers can be referenced by using
an identifier of `i` or `u` followed by digits. For example, the identifier
<span class="tok-type">`i7`</span> refers to a signed 7-bit integer. The maximum allowed bit-width of an
integer type is <span class="tok-number">`65535`</span>.

See also:

- [Integers](../zig-0.15.1.md#Integers)
- [Floats](../zig-0.15.1.md#Floats)
- [void](../zig-0.15.1.md#void)
- [Errors](../zig-0.15.1.md#Errors)
- [@Type](../zig-0.15.1.md#Type)

### [Primitive Values](../zig-0.15.1.md#toc-Primitive-Values) <a href="../zig-0.15.1.md#Primitive-Values" class="hdr">§</a>

<div class="table-wrapper">

| Name | Description |
|----|----|
| <span class="tok-null">`true`</span> and <span class="tok-null">`false`</span> | <span class="tok-type">`bool`</span> values |
| <span class="tok-null">`null`</span> | used to set an optional type to <span class="tok-null">`null`</span> |
| <span class="tok-null">`undefined`</span> | used to leave a value unspecified |

Primitive Values

</div>

See also:

- [Optionals](../zig-0.15.1.md#Optionals)
- [undefined](../zig-0.15.1.md#undefined)

### [String Literals and Unicode Code Point Literals](../zig-0.15.1.md#toc-String-Literals-and-Unicode-Code-Point-Literals) <a href="../zig-0.15.1.md#String-Literals-and-Unicode-Code-Point-Literals" class="hdr">§</a>

String literals are constant single-item [Pointers](../zig-0.15.1.md#Pointers) to null-terminated byte arrays.
The type of string literals encodes both the length, and the fact that they are null-terminated,
and thus they can be [coerced](../zig-0.15.1.md#Type-Coercion) to both [Slices](../zig-0.15.1.md#Slices) and
[Null-Terminated Pointers](../zig-0.15.1.md#Sentinel-Terminated-Pointers).
Dereferencing string literals converts them to [Arrays](../zig-0.15.1.md#Arrays).

Because Zig source code is [UTF-8 encoded](../zig-0.15.1.md#Source-Encoding), any
non-ASCII bytes appearing within a string literal in source code carry
their UTF-8 meaning into the content of the string in the Zig program;
the bytes are not modified by the compiler. It is possible to embed
non-UTF-8 bytes into a string literal using `\xNN` notation.

Indexing into a string containing non-ASCII bytes returns individual
bytes, whether valid UTF-8 or not.

Unicode code point literals have type <span class="tok-type">`comptime_int`</span>, the same as
[Integer Literals](../zig-0.15.1.md#Integer-Literals). All [Escape Sequences](../zig-0.15.1.md#Escape-Sequences) are valid in both string literals
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

- [Arrays](../zig-0.15.1.md#Arrays)
- [Source Encoding](../zig-0.15.1.md#Source-Encoding)

#### [Escape Sequences](../zig-0.15.1.md#toc-Escape-Sequences) <a href="../zig-0.15.1.md#Escape-Sequences" class="hdr">§</a>

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

#### [Multiline String Literals](../zig-0.15.1.md#toc-Multiline-String-Literals) <a href="../zig-0.15.1.md#Multiline-String-Literals" class="hdr">§</a>

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

- [@embedFile](../zig-0.15.1.md#embedFile)

### [Assignment](../zig-0.15.1.md#toc-Assignment) <a href="../zig-0.15.1.md#Assignment" class="hdr">§</a>

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

<span class="tok-kw">`const`</span> applies to all of the bytes that the identifier immediately addresses. [Pointers](../zig-0.15.1.md#Pointers) have their own const-ness.

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

#### [undefined](../zig-0.15.1.md#toc-undefined) <a href="../zig-0.15.1.md#undefined" class="hdr">§</a>

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

<span class="tok-null">`undefined`</span> can be [coerced](../zig-0.15.1.md#Type-Coercion) to any type.
Once this happens, it is no longer possible to detect that the value is <span class="tok-null">`undefined`</span>.
<span class="tok-null">`undefined`</span> means the value could be anything, even something that is nonsense
according to the type. Translated into English, <span class="tok-null">`undefined`</span> means "Not a meaningful
value. Using this value would be a bug. The value will be unused, or overwritten before being used."

In [Debug](../zig-0.15.1.md#Debug) and [ReleaseSafe](../zig-0.15.1.md#ReleaseSafe) mode, Zig writes <span class="tok-number">`0xaa`</span> bytes to undefined memory. This is to catch
bugs early, and to help detect use of undefined memory in a debugger. However, this behavior is only an
implementation feature, not a language semantic, so it is not guaranteed to be observable to code.

#### [Destructuring](../zig-0.15.1.md#toc-Destructuring) <a href="../zig-0.15.1.md#Destructuring" class="hdr">§</a>

A destructuring assignment can separate elements of indexable aggregate types
([Tuples](../zig-0.15.1.md#Tuples), [Arrays](../zig-0.15.1.md#Arrays), [Vectors](../zig-0.15.1.md#Vectors)):

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
destructure expression is evaluated at [comptime](../zig-0.15.1.md#comptime). All <span class="tok-kw">`var`</span>s declared would
be <span class="tok-kw">`comptime`</span>` `<span class="tok-kw">`var`</span>s and all expressions (both result locations and the assignee
expression) are evaluated at [comptime](../zig-0.15.1.md#comptime).

See also:

- [Destructuring Tuples](../zig-0.15.1.md#Destructuring-Tuples)
- [Destructuring Arrays](../zig-0.15.1.md#Destructuring-Arrays)
- [Destructuring Vectors](../zig-0.15.1.md#Destructuring-Vectors)

## [Zig Test](../zig-0.15.1.md#toc-Zig-Test) <a href="../zig-0.15.1.md#Zig-Test" class="hdr">§</a>

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

The `testing_introduction.zig` code sample tests the [function](../zig-0.15.1.md#Functions)
`addOne` to ensure that it returns <span class="tok-number">`42`</span> given the input
<span class="tok-number">`41`</span>. From this test's perspective, the `addOne` function is
said to be *code under test*.

<span class="kbd">zig test</span> is a tool that creates and runs a test build. By default, it builds and runs an
executable program using the *default test runner* provided by the [Zig Standard Library](../zig-0.15.1.md#Zig-Standard-Library)
as its main entry point. During the build, <span class="tok-kw">`test`</span> declarations found while
[resolving](../zig-0.15.1.md#File-and-Declaration-Discovery) the given Zig source file are included for the default test runner
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

### [Test Declarations](../zig-0.15.1.md#toc-Test-Declarations) <a href="../zig-0.15.1.md#Test-Declarations" class="hdr">§</a>

Test declarations contain the [keyword](../zig-0.15.1.md#Keyword-Reference) <span class="tok-kw">`test`</span>, followed by an
optional name written as a [string literal](../zig-0.15.1.md#String-Literals-and-Unicode-Code-Point-Literals) or an
[identifier](../zig-0.15.1.md#Identifiers), followed by a [block](../zig-0.15.1.md#Blocks) containing any valid Zig code that
is allowed in a [function](../zig-0.15.1.md#Functions).

Non-named test blocks always run during test builds and are exempt from
[Skip Tests](../zig-0.15.1.md#Skip-Tests).

Test declarations are similar to [Functions](../zig-0.15.1.md#Functions): they have a return type and a block of code. The implicit
return type of <span class="tok-kw">`test`</span> is the [Error Union Type](../zig-0.15.1.md#Error-Union-Type) <span class="tok-type">`anyerror`</span>`!`<span class="tok-type">`void`</span>,
and it cannot be changed. When a Zig source file is not built using the <span class="kbd">zig test</span> tool, the test
declarations are omitted from the build.

Test declarations can be written in the same file, where code under test is written, or in a separate Zig source file.
Since test declarations are top-level declarations, they are order-independent and can
be written before or after the code under test.

See also:

- [The Global Error Set](../zig-0.15.1.md#The-Global-Error-Set)
- [Grammar](../zig-0.15.1.md#Grammar)

#### [Doctests](../zig-0.15.1.md#toc-Doctests) <a href="../zig-0.15.1.md#Doctests" class="hdr">§</a>

Test declarations named using an identifier are *doctests*. The identifier must refer to another declaration in
scope. A doctest, like a [doc comment](../zig-0.15.1.md#Doc-Comments), serves as documentation for the associated declaration, and
will appear in the generated documentation for the declaration.

An effective doctest should be self-contained and focused on the declaration being tested, answering questions a new
user might have about its interface or intended usage, while avoiding unnecessary or confusing details. A doctest is not
a substitute for a doc comment, but rather a supplement and companion providing a testable, code-driven example, verified
by <span class="kbd">zig test</span>.

### [Test Failure](../zig-0.15.1.md#toc-Test-Failure) <a href="../zig-0.15.1.md#Test-Failure" class="hdr">§</a>

The default test runner checks for an [error](../zig-0.15.1.md#Errors) returned from a test.
When a test returns an error, the test is considered a failure and its [error return trace](../zig-0.15.1.md#Error-Return-Traces)
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

### [Skip Tests](../zig-0.15.1.md#toc-Skip-Tests) <a href="../zig-0.15.1.md#Skip-Tests" class="hdr">§</a>

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

### [Report Memory Leaks](../zig-0.15.1.md#toc-Report-Memory-Leaks) <a href="../zig-0.15.1.md#Report-Memory-Leaks" class="hdr">§</a>

When code allocates [Memory](../zig-0.15.1.md#Memory) using the [Zig Standard Library](../zig-0.15.1.md#Zig-Standard-Library)'s testing allocator,
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

- [defer](../zig-0.15.1.md#defer)
- [Memory](../zig-0.15.1.md#Memory)

### [Detecting Test Build](../zig-0.15.1.md#toc-Detecting-Test-Build) <a href="../zig-0.15.1.md#Detecting-Test-Build" class="hdr">§</a>

Use the [compile variable](../zig-0.15.1.md#Compile-Variables) <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`).is_test`
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

### [Test Output and Logging](../zig-0.15.1.md#toc-Test-Output-and-Logging) <a href="../zig-0.15.1.md#Test-Output-and-Logging" class="hdr">§</a>

The default test runner and the Zig Standard Library's testing namespace output messages to standard error.

### [The Testing Namespace](../zig-0.15.1.md#toc-The-Testing-Namespace) <a href="../zig-0.15.1.md#The-Testing-Namespace" class="hdr">§</a>

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

The Zig Standard Library also contains functions to compare [Slices](../zig-0.15.1.md#Slices), strings, and more. See the rest of the
`std.testing` namespace in the [Zig Standard Library](../zig-0.15.1.md#Zig-Standard-Library) for more available functions.

### [Test Tool Documentation](../zig-0.15.1.md#toc-Test-Tool-Documentation) <a href="../zig-0.15.1.md#Test-Tool-Documentation" class="hdr">§</a>

<span class="kbd">zig test</span> has a few command line parameters which affect the compilation.
See <span class="kbd">zig test --help</span> for a full list.

## [Variables](../zig-0.15.1.md#toc-Variables) <a href="../zig-0.15.1.md#Variables" class="hdr">§</a>

A variable is a unit of [Memory](../zig-0.15.1.md#Memory) storage.

It is generally preferable to use <span class="tok-kw">`const`</span> rather than
<span class="tok-kw">`var`</span> when declaring a variable. This causes less work for both
humans and computers to do when reading code, and creates more optimization opportunities.

The <span class="tok-kw">`extern`</span> keyword or [@extern](../zig-0.15.1.md#extern) builtin function can be used to link against a variable that is exported
from another object. The <span class="tok-kw">`export`</span> keyword or [@export](../zig-0.15.1.md#export) builtin function
can be used to make a variable available to other objects at link time. In both cases,
the type of the variable must be C ABI compatible.

See also:

- [Exporting a C Library](../zig-0.15.1.md#Exporting-a-C-Library)

### [Identifiers](../zig-0.15.1.md#toc-Identifiers) <a href="../zig-0.15.1.md#Identifiers" class="hdr">§</a>

Variable identifiers are never allowed to shadow identifiers from an outer scope.

Identifiers must start with an alphabetic character or underscore and may be followed
by any number of alphanumeric characters or underscores.
They must not overlap with any keywords. See [Keyword Reference](../zig-0.15.1.md#Keyword-Reference).

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

### [Container Level Variables](../zig-0.15.1.md#toc-Container-Level-Variables) <a href="../zig-0.15.1.md#Container-Level-Variables" class="hdr">§</a>

[Container](../zig-0.15.1.md#Containers) level variables have static lifetime and are order-independent and lazily analyzed.
The initialization value of container level variables is implicitly
[comptime](../zig-0.15.1.md#comptime). If a container level variable is <span class="tok-kw">`const`</span> then its value is
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

Container level variables may be declared inside a [struct](../zig-0.15.1.md#struct), [union](../zig-0.15.1.md#union), [enum](../zig-0.15.1.md#enum), or [opaque](../zig-0.15.1.md#opaque):

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

### [Static Local Variables](../zig-0.15.1.md#toc-Static-Local-Variables) <a href="../zig-0.15.1.md#Static-Local-Variables" class="hdr">§</a>

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

### [Thread Local Variables](../zig-0.15.1.md#toc-Thread-Local-Variables) <a href="../zig-0.15.1.md#Thread-Local-Variables" class="hdr">§</a>

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

For [Single Threaded Builds](../zig-0.15.1.md#Single-Threaded-Builds), all thread local variables are treated as regular [Container Level Variables](../zig-0.15.1.md#Container-Level-Variables).

Thread local variables may not be <span class="tok-kw">`const`</span>.

### [Local Variables](../zig-0.15.1.md#toc-Local-Variables) <a href="../zig-0.15.1.md#Local-Variables" class="hdr">§</a>

Local variables occur inside [Functions](../zig-0.15.1.md#Functions), [comptime](../zig-0.15.1.md#comptime) blocks, and [@cImport](../zig-0.15.1.md#cImport) blocks.

When a local variable is <span class="tok-kw">`const`</span>, it means that after initialization, the variable's
value will not change. If the initialization value of a <span class="tok-kw">`const`</span> variable is
[comptime](../zig-0.15.1.md#comptime)-known, then the variable is also <span class="tok-kw">`comptime`</span>-known.

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


