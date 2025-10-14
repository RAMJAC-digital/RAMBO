<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Compilation Model -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Compilation Model](zig-0.15.1.md#toc-Compilation-Model) <a href="zig-0.15.1.md#Compilation-Model" class="hdr">§</a>

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

### [Source File Structs](zig-0.15.1.md#toc-Source-File-Structs) <a href="zig-0.15.1.md#Source-File-Structs" class="hdr">§</a>

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
struct type" can be referred to within that file using [@This](zig-0.15.1.md#This).

### [File and Declaration Discovery](zig-0.15.1.md#toc-File-and-Declaration-Discovery) <a href="zig-0.15.1.md#File-and-Declaration-Discovery" class="hdr">§</a>

Zig places importance on the concept of whether any piece of code is *semantically analyzed*; in
essence, whether the compiler "looks at" it. What code is analyzed is based on what files and
declarations are "discovered" from a certain point. This process of "discovery" is based on a simple set
of recursive rules:

- If a call to <span class="tok-builtin">`@import`</span> is analyzed, the file being imported is analyzed.
- If a type (including a file) is analyzed, all <span class="tok-kw">`comptime`</span> and <span class="tok-kw">`export`</span> declarations within it are analyzed.
- If a type (including a file) is analyzed, and the compilation is for a [test](zig-0.15.1.md#Zig-Test), and the module the type is within is the root module of the compilation, then all <span class="tok-kw">`test`</span> declarations within it are also analyzed.
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

### [Special Root Declarations](zig-0.15.1.md#toc-Special-Root-Declarations) <a href="zig-0.15.1.md#Special-Root-Declarations" class="hdr">§</a>

Because the root module's root source file is always accessible using
<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)`, is is sometimes used by libraries — including the Zig Standard
Library — as a place for the program to expose some "global" information to that library. The Zig
Standard Library will look for several declarations in this file.

#### [Entry Point](zig-0.15.1.md#toc-Entry-Point) <a href="zig-0.15.1.md#Entry-Point" class="hdr">§</a>

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

#### [Standard Library Options](zig-0.15.1.md#toc-Standard-Library-Options) <a href="zig-0.15.1.md#Standard-Library-Options" class="hdr">§</a>

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

#### [Panic Handler](zig-0.15.1.md#toc-Panic-Handler) <a href="zig-0.15.1.md#Panic-Handler" class="hdr">§</a>

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

