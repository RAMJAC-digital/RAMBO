<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Style Guide -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Style Guide](zig-0.15.1.md#toc-Style-Guide) <a href="zig-0.15.1.md#Style-Guide" class="hdr">§</a>

These coding conventions are not enforced by the compiler, but they are shipped in
this documentation along with the compiler in order to provide a point of
reference, should anyone wish to point to an authority on agreed upon Zig
coding style.

### [Avoid Redundancy in Names](zig-0.15.1.md#toc-Avoid-Redundancy-in-Names) <a href="zig-0.15.1.md#Avoid-Redundancy-in-Names" class="hdr">§</a>

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

### [Avoid Redundant Names in Fully-Qualified Namespaces](zig-0.15.1.md#toc-Avoid-Redundant-Names-in-Fully-Qualified-Namespaces) <a href="zig-0.15.1.md#Avoid-Redundant-Names-in-Fully-Qualified-Namespaces" class="hdr">§</a>

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

This example is an exception to the rule specified in [Avoid Redundancy in Names](zig-0.15.1.md#Avoid-Redundancy-in-Names).
The meaning of the type has been reduced to its core: it is a json value. The name
cannot be any more specific without being incorrect.

### [Whitespace](zig-0.15.1.md#toc-Whitespace) <a href="zig-0.15.1.md#Whitespace" class="hdr">§</a>

- 4 space indentation
- Open braces on same line, unless you need to wrap.
- If a list of things is longer than 2, put each item on its own line and
  exercise the ability to put an extra comma at the end.
- Line length: aim for 100; use common sense.

### [Names](zig-0.15.1.md#toc-Names) <a href="zig-0.15.1.md#Names" class="hdr">§</a>

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

### [Examples](zig-0.15.1.md#toc-Examples) <a href="zig-0.15.1.md#Examples" class="hdr">§</a>

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

See the [Zig Standard Library](zig-0.15.1.md#Zig-Standard-Library) for more examples.

### [Doc Comment Guidance](zig-0.15.1.md#toc-Doc-Comment-Guidance) <a href="zig-0.15.1.md#Doc-Comment-Guidance" class="hdr">§</a>

- Omit any information that is redundant based on the name of the thing being documented.
- Duplicating information onto multiple similar functions is encouraged because it helps IDEs and other tools provide better help text.
- Use the word **assume** to indicate invariants that cause *unchecked* [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior) when violated.
- Use the word **assert** to indicate invariants that cause *safety-checked* [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior) when violated.

