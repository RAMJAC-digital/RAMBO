<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Style & Appendix

Included sections:
- Style Guide
- Source Encoding
- Keyword Reference
- Appendix

## [Style Guide](../zig-0.15.1.md#toc-Style-Guide) <a href="../zig-0.15.1.md#Style-Guide" class="hdr">§</a>

These coding conventions are not enforced by the compiler, but they are shipped in
this documentation along with the compiler in order to provide a point of
reference, should anyone wish to point to an authority on agreed upon Zig
coding style.

### [Avoid Redundancy in Names](../zig-0.15.1.md#toc-Avoid-Redundancy-in-Names) <a href="../zig-0.15.1.md#Avoid-Redundancy-in-Names" class="hdr">§</a>

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

### [Avoid Redundant Names in Fully-Qualified Namespaces](../zig-0.15.1.md#toc-Avoid-Redundant-Names-in-Fully-Qualified-Namespaces) <a href="../zig-0.15.1.md#Avoid-Redundant-Names-in-Fully-Qualified-Namespaces" class="hdr">§</a>

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

This example is an exception to the rule specified in [Avoid Redundancy in Names](../zig-0.15.1.md#Avoid-Redundancy-in-Names).
The meaning of the type has been reduced to its core: it is a json value. The name
cannot be any more specific without being incorrect.

### [Whitespace](../zig-0.15.1.md#toc-Whitespace) <a href="../zig-0.15.1.md#Whitespace" class="hdr">§</a>

- 4 space indentation
- Open braces on same line, unless you need to wrap.
- If a list of things is longer than 2, put each item on its own line and
  exercise the ability to put an extra comma at the end.
- Line length: aim for 100; use common sense.

### [Names](../zig-0.15.1.md#toc-Names) <a href="../zig-0.15.1.md#Names" class="hdr">§</a>

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

### [Examples](../zig-0.15.1.md#toc-Examples) <a href="../zig-0.15.1.md#Examples" class="hdr">§</a>

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

See the [Zig Standard Library](../zig-0.15.1.md#Zig-Standard-Library) for more examples.

### [Doc Comment Guidance](../zig-0.15.1.md#toc-Doc-Comment-Guidance) <a href="../zig-0.15.1.md#Doc-Comment-Guidance" class="hdr">§</a>

- Omit any information that is redundant based on the name of the thing being documented.
- Duplicating information onto multiple similar functions is encouraged because it helps IDEs and other tools provide better help text.
- Use the word **assume** to indicate invariants that cause *unchecked* [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) when violated.
- Use the word **assert** to indicate invariants that cause *safety-checked* [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) when violated.

## [Source Encoding](../zig-0.15.1.md#toc-Source-Encoding) <a href="../zig-0.15.1.md#Source-Encoding" class="hdr">§</a>

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
but use of hard tabs is discouraged. See [Grammar](../zig-0.15.1.md#Grammar).

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

## [Keyword Reference](../zig-0.15.1.md#toc-Keyword-Reference) <a href="../zig-0.15.1.md#Keyword-Reference" class="hdr">§</a>

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
<li>See also <a href="../zig-0.15.1.md#Alignment">Alignment</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>allowzero</code></pre></th>
<td>The pointer attribute <span class="tok-kw"><code>allowzero</code></span> allows a pointer to have address zero.
<ul>
<li>See also <a href="../zig-0.15.1.md#allowzero">allowzero</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>and</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>and</code></span>.
<ul>
<li>See also <a href="../zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anyframe</code></pre></th>
<td><span class="tok-kw"><code>anyframe</code></span> can be used as a type for variables which hold pointers to function frames.
<ul>
<li>See also <a href="../zig-0.15.1.md#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anytype</code></pre></th>
<td>Function parameters can be declared with <span class="tok-kw"><code>anytype</code></span> in place of the type.
The type will be inferred where the function is called.
<ul>
<li>See also <a href="../zig-0.15.1.md#Function-Parameter-Type-Inference">Function Parameter Type Inference</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>asm</code></pre></th>
<td><span class="tok-kw"><code>asm</code></span> begins an inline assembly expression. This allows for directly controlling the machine code generated on compilation.
<ul>
<li>See also <a href="../zig-0.15.1.md#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>break</code></pre></th>
<td><span class="tok-kw"><code>break</code></span> can be used with a block label to return a value from the block.
It can also be used to exit a loop before iteration completes naturally.
<ul>
<li>See also <a href="../zig-0.15.1.md#Blocks">Blocks</a>, <a href="../zig-0.15.1.md#while">while</a>, <a href="../zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>callconv</code></pre></th>
<td><span class="tok-kw"><code>callconv</code></span> can be used to specify the calling convention in a function type.
<ul>
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>catch</code></pre></th>
<td><span class="tok-kw"><code>catch</code></span> can be used to evaluate an expression if the expression before it evaluates to an error.
The expression after the <span class="tok-kw"><code>catch</code></span> can optionally capture the error value.
<ul>
<li>See also <a href="../zig-0.15.1.md#catch">catch</a>, <a href="../zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>comptime</code></pre></th>
<td><span class="tok-kw"><code>comptime</code></span> before a declaration can be used to label variables or function parameters as known at compile time.
It can also be used to guarantee an expression is run at compile time.
<ul>
<li>See also <a href="../zig-0.15.1.md#comptime">comptime</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>const</code></pre></th>
<td><span class="tok-kw"><code>const</code></span> declares a variable that can not be modified.
Used as a pointer attribute, it denotes the value referenced by the pointer cannot be modified.
<ul>
<li>See also <a href="../zig-0.15.1.md#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>continue</code></pre></th>
<td><span class="tok-kw"><code>continue</code></span> can be used in a loop to jump back to the beginning of the loop.
<ul>
<li>See also <a href="../zig-0.15.1.md#while">while</a>, <a href="../zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>defer</code></pre></th>
<td><span class="tok-kw"><code>defer</code></span> will execute an expression when control flow leaves the current block.
<ul>
<li>See also <a href="../zig-0.15.1.md#defer">defer</a></li>
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
<li>See also <a href="../zig-0.15.1.md#if">if</a>, <a href="../zig-0.15.1.md#switch">switch</a>, <a href="../zig-0.15.1.md#while">while</a>, <a href="../zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>enum</code></pre></th>
<td><span class="tok-kw"><code>enum</code></span> defines an enum type.
<ul>
<li>See also <a href="../zig-0.15.1.md#enum">enum</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>errdefer</code></pre></th>
<td><span class="tok-kw"><code>errdefer</code></span> will execute an expression when control flow leaves the current block if the function returns an error, the errdefer expression can capture the unwrapped value.
<ul>
<li>See also <a href="../zig-0.15.1.md#errdefer">errdefer</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>error</code></pre></th>
<td><span class="tok-kw"><code>error</code></span> defines an error type.
<ul>
<li>See also <a href="../zig-0.15.1.md#Errors">Errors</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>export</code></pre></th>
<td><span class="tok-kw"><code>export</code></span> makes a function or variable externally visible in the generated object file.
Exported functions default to the C calling convention.
<ul>
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>extern</code></pre></th>
<td><span class="tok-kw"><code>extern</code></span> can be used to declare a function or variable that will be resolved at link time, when linking statically
or at runtime, when linking dynamically.
<ul>
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>fn</code></pre></th>
<td><span class="tok-kw"><code>fn</code></span> declares a function.
<ul>
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>for</code></pre></th>
<td>A <span class="tok-kw"><code>for</code></span> expression can be used to iterate over the elements of a slice, array, or tuple.
<ul>
<li>See also <a href="../zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>if</code></pre></th>
<td>An <span class="tok-kw"><code>if</code></span> expression can test boolean expressions, optional values, or error unions.
For optional values or error unions, the if expression can capture the unwrapped value.
<ul>
<li>See also <a href="../zig-0.15.1.md#if">if</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>inline</code></pre></th>
<td><span class="tok-kw"><code>inline</code></span> can be used to label a loop expression such that it will be unrolled at compile time.
It can also be used to force a function to be inlined at all call sites.
<ul>
<li>See also <a href="../zig-0.15.1.md#inline-while">inline while</a>, <a href="../zig-0.15.1.md#inline-for">inline for</a>, <a href="../zig-0.15.1.md#Functions">Functions</a></li>
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
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>nosuspend</code></pre></th>
<td>The <span class="tok-kw"><code>nosuspend</code></span> keyword can be used in front of a block, statement or expression, to mark a scope where no suspension points are reached.
In particular, inside a <span class="tok-kw"><code>nosuspend</code></span> scope:
<ul>
<li>Using the <span class="tok-kw"><code>suspend</code></span> keyword results in a compile error.</li>
<li>Using <code>await</code> on a function frame which hasn't completed yet results in safety-checked <a href="../zig-0.15.1.md#Illegal-Behavior">Illegal Behavior</a>.</li>
<li>Calling an async function may result in safety-checked <a href="../zig-0.15.1.md#Illegal-Behavior">Illegal Behavior</a>, because it's equivalent to <code>await async some_async_fn()</code>, which contains an <code>await</code>.</li>
</ul>
Code inside a <span class="tok-kw"><code>nosuspend</code></span> scope does not cause the enclosing function to become an <a href="../zig-0.15.1.md#Async-Functions">async function</a>.
<ul>
<li>See also <a href="../zig-0.15.1.md#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>opaque</code></pre></th>
<td><span class="tok-kw"><code>opaque</code></span> defines an opaque type.
<ul>
<li>See also <a href="../zig-0.15.1.md#opaque">opaque</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>or</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>or</code></span>.
<ul>
<li>See also <a href="../zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>orelse</code></pre></th>
<td><span class="tok-kw"><code>orelse</code></span> can be used to evaluate an expression if the expression before it evaluates to null.
<ul>
<li>See also <a href="../zig-0.15.1.md#Optionals">Optionals</a>, <a href="../zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>packed</code></pre></th>
<td>The <span class="tok-kw"><code>packed</code></span> keyword before a struct definition changes the struct's in-memory layout
to the guaranteed <span class="tok-kw"><code>packed</code></span> layout.
<ul>
<li>See also <a href="../zig-0.15.1.md#packed-struct">packed struct</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>pub</code></pre></th>
<td>The <span class="tok-kw"><code>pub</code></span> in front of a top level declaration makes the declaration available
to reference from a different file than the one it is declared in.
<ul>
<li>See also <a href="../zig-0.15.1.md#import">import</a></li>
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
<li>See also <a href="../zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>struct</code></pre></th>
<td><span class="tok-kw"><code>struct</code></span> defines a struct.
<ul>
<li>See also <a href="../zig-0.15.1.md#struct">struct</a></li>
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
<span class="tok-kw"><code>switch</code></span> cases can capture field values of a <a href="../zig-0.15.1.md#Tagged-union">Tagged union</a>.
<ul>
<li>See also <a href="../zig-0.15.1.md#switch">switch</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>test</code></pre></th>
<td>The <span class="tok-kw"><code>test</code></span> keyword can be used to denote a top-level block of code
used to make sure behavior meets expectations.
<ul>
<li>See also <a href="../zig-0.15.1.md#Zig-Test">Zig Test</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>threadlocal</code></pre></th>
<td><span class="tok-kw"><code>threadlocal</code></span> can be used to specify a variable as thread-local.
<ul>
<li>See also <a href="../zig-0.15.1.md#Thread-Local-Variables">Thread Local Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>try</code></pre></th>
<td><span class="tok-kw"><code>try</code></span> evaluates an error union expression.
If it is an error, it returns from the current function with the same error.
Otherwise, the expression results in the unwrapped value.
<ul>
<li>See also <a href="../zig-0.15.1.md#try">try</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>union</code></pre></th>
<td><span class="tok-kw"><code>union</code></span> defines a union.
<ul>
<li>See also <a href="../zig-0.15.1.md#union">union</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>unreachable</code></pre></th>
<td><span class="tok-kw"><code>unreachable</code></span> can be used to assert that control flow will never happen upon a particular location.
Depending on the build mode, <span class="tok-kw"><code>unreachable</code></span> may emit a panic.
<ul>
<li>Emits a panic in <code>Debug</code> and <code>ReleaseSafe</code> mode, or when using <kbd>zig test</kbd>.</li>
<li>Does not emit a panic in <code>ReleaseFast</code> and <code>ReleaseSmall</code> mode.</li>
<li>See also <a href="../zig-0.15.1.md#unreachable">unreachable</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>var</code></pre></th>
<td><span class="tok-kw"><code>var</code></span> declares a variable that may be modified.
<ul>
<li>See also <a href="../zig-0.15.1.md#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>volatile</code></pre></th>
<td><span class="tok-kw"><code>volatile</code></span> can be used to denote loads or stores of a pointer have side effects.
It can also modify an inline assembly expression to denote it has side effects.
<ul>
<li>See also <a href="../zig-0.15.1.md#volatile">volatile</a>, <a href="../zig-0.15.1.md#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>while</code></pre></th>
<td>A <span class="tok-kw"><code>while</code></span> expression can be used to repeatedly test a boolean, optional, or error union expression,
and cease looping when that expression evaluates to false, null, or an error, respectively.
<ul>
<li>See also <a href="../zig-0.15.1.md#while">while</a></li>
</ul></td>
</tr>
</tbody>
</table>

</div>

## [Appendix](../zig-0.15.1.md#toc-Appendix) <a href="../zig-0.15.1.md#Appendix" class="hdr">§</a>

### [Containers](../zig-0.15.1.md#toc-Containers) <a href="../zig-0.15.1.md#Containers" class="hdr">§</a>

A *container* in Zig is any syntactical construct that acts as a namespace to hold [variable](../zig-0.15.1.md#Container-Level-Variables) and [function](../zig-0.15.1.md#Functions) declarations.
Containers are also type definitions which can be instantiated.
[Structs](../zig-0.15.1.md#struct), [enums](../zig-0.15.1.md#enum), [unions](../zig-0.15.1.md#union), [opaques](../zig-0.15.1.md#opaque), and even Zig source files themselves are containers.

Although containers (except Zig source files) use curly braces to surround their definition, they should not be confused with [blocks](../zig-0.15.1.md#Blocks) or functions.
Containers do not contain statements.

### [Grammar](../zig-0.15.1.md#toc-Grammar) <a href="../zig-0.15.1.md#Grammar" class="hdr">§</a>

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

### [Zen](../zig-0.15.1.md#toc-Zen) <a href="../zig-0.15.1.md#Zen" class="hdr">§</a>

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


