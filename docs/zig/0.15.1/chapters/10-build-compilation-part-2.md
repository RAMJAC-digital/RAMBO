<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Build & Compilation (Part 2)

Included sections:
- Build Mode
- Single Threaded Builds
- Illegal Behavior
- Memory
- Compile Variables
- Compilation Model
- Zig Build System

### [Choosing an Allocator](../zig-0.15.1.md#toc-Choosing-an-Allocator) <a href="../zig-0.15.1.md#Choosing-an-Allocator" class="hdr">§</a>

What allocator to use depends on a number of factors. Here is a flow chart to help you decide:

1.  Are you making a library? In this case, best to accept an `Allocator`
    as a parameter and allow your library's users to decide what allocator to use.
2.  Are you linking libc? In this case, `std.heap.c_allocator` is likely
    the right choice, at least for your main allocator.
3.  Need to use the same allocator in multiple threads? Use one of your choice
    wrapped around `std.heap.ThreadSafeAllocator`
4.  Is the maximum number of bytes that you will need bounded by a number known at
    [comptime](../zig-0.15.1.md#comptime)? In this case, use `std.heap.FixedBufferAllocator`.
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
    Zig's general purpose allocator is available as a function that takes a [comptime](../zig-0.15.1.md#comptime)
    [struct](../zig-0.15.1.md#struct) of configuration options and returns a type.
    Generally, you will set up one `std.heap.GeneralPurposeAllocator` in
    your main function, and then pass it or sub-allocators around to various parts of your
    application.
10. You can also consider [Implementing an Allocator](../zig-0.15.1.md#Implementing-an-Allocator).


### [Where are the bytes?](../zig-0.15.1.md#toc-Where-are-the-bytes) <a href="../zig-0.15.1.md#Where-are-the-bytes" class="hdr">§</a>

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

Just like string literals, <span class="tok-kw">`const`</span> declarations, when the value is known at [comptime](../zig-0.15.1.md#comptime),
are stored in the global constant data section. Also [Compile Time Variables](../zig-0.15.1.md#Compile-Time-Variables) are stored
in the global constant data section.

<span class="tok-kw">`var`</span> declarations inside functions are stored in the function's stack frame. Once a function returns,
any [Pointers](../zig-0.15.1.md#Pointers) to variables in the function's stack frame become invalid references, and
dereferencing them becomes unchecked [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior).

<span class="tok-kw">`var`</span> declarations at the top level or in [struct](../zig-0.15.1.md#struct) declarations are stored in the global
data section.

The location of memory allocated with `allocator.alloc` or
`allocator.create` is determined by the allocator's implementation.

TODO: thread local variables


### [Implementing an Allocator](../zig-0.15.1.md#toc-Implementing-an-Allocator) <a href="../zig-0.15.1.md#Implementing-an-Allocator" class="hdr">§</a>

Zig programmers can implement their own allocators by fulfilling the Allocator interface.
In order to do this one must read carefully the documentation comments in std/mem.zig and
then supply a `allocFn` and a `resizeFn`.

There are many example allocators to look at for inspiration. Look at std/heap.zig and
`std.heap.GeneralPurposeAllocator`.


### [Heap Allocation Failure](../zig-0.15.1.md#toc-Heap-Allocation-Failure) <a href="../zig-0.15.1.md#Heap-Allocation-Failure" class="hdr">§</a>

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


### [Recursion](../zig-0.15.1.md#toc-Recursion) <a href="../zig-0.15.1.md#Recursion" class="hdr">§</a>

Recursion is a fundamental tool in modeling software. However it has an often-overlooked problem:
unbounded memory allocation.

Recursion is an area of active experimentation in Zig and so the documentation here is not final.
You can read a
[summary of recursion status in the 0.3.0 release notes](https://ziglang.org/download/0.3.0/release-notes.html#recursion).

The short summary is that currently recursion works normally as you would expect. Although Zig code
is not yet protected from stack overflow, it is planned that a future version of Zig will provide
such protection, with some degree of cooperation from Zig code required.


### [Lifetime and Ownership](../zig-0.15.1.md#toc-Lifetime-and-Ownership) <a href="../zig-0.15.1.md#Lifetime-and-Ownership" class="hdr">§</a>

It is the Zig programmer's responsibility to ensure that a [pointer](../zig-0.15.1.md#Pointers) is not
accessed when the memory pointed to is no longer available. Note that a [slice](../zig-0.15.1.md#Slices)
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
the memory becomes inaccessible (lest [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) occur).

## [Compile Variables](../zig-0.15.1.md#toc-Compile-Variables) <a href="../zig-0.15.1.md#Compile-Variables" class="hdr">§</a>

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

- [Build Mode](../zig-0.15.1.md#Build-Mode)

## [Compilation Model](../zig-0.15.1.md#toc-Compilation-Model) <a href="../zig-0.15.1.md#Compilation-Model" class="hdr">§</a>

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


### [Source File Structs](../zig-0.15.1.md#toc-Source-File-Structs) <a href="../zig-0.15.1.md#Source-File-Structs" class="hdr">§</a>

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
struct type" can be referred to within that file using [@This](../zig-0.15.1.md#This).


### [File and Declaration Discovery](../zig-0.15.1.md#toc-File-and-Declaration-Discovery) <a href="../zig-0.15.1.md#File-and-Declaration-Discovery" class="hdr">§</a>

Zig places importance on the concept of whether any piece of code is *semantically analyzed*; in
essence, whether the compiler "looks at" it. What code is analyzed is based on what files and
declarations are "discovered" from a certain point. This process of "discovery" is based on a simple set
of recursive rules:

- If a call to <span class="tok-builtin">`@import`</span> is analyzed, the file being imported is analyzed.
- If a type (including a file) is analyzed, all <span class="tok-kw">`comptime`</span> and <span class="tok-kw">`export`</span> declarations within it are analyzed.
- If a type (including a file) is analyzed, and the compilation is for a [test](../zig-0.15.1.md#Zig-Test), and the module the type is within is the root module of the compilation, then all <span class="tok-kw">`test`</span> declarations within it are also analyzed.
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


### [Special Root Declarations](../zig-0.15.1.md#toc-Special-Root-Declarations) <a href="../zig-0.15.1.md#Special-Root-Declarations" class="hdr">§</a>

Because the root module's root source file is always accessible using
<span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"root"`</span>`)`, is is sometimes used by libraries — including the Zig Standard
Library — as a place for the program to expose some "global" information to that library. The Zig
Standard Library will look for several declarations in this file.

#### [Entry Point](../zig-0.15.1.md#toc-Entry-Point) <a href="../zig-0.15.1.md#Entry-Point" class="hdr">§</a>

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

#### [Standard Library Options](../zig-0.15.1.md#toc-Standard-Library-Options) <a href="../zig-0.15.1.md#Standard-Library-Options" class="hdr">§</a>

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

#### [Panic Handler](../zig-0.15.1.md#toc-Panic-Handler) <a href="../zig-0.15.1.md#Panic-Handler" class="hdr">§</a>

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

## [Zig Build System](../zig-0.15.1.md#toc-Zig-Build-System) <a href="../zig-0.15.1.md#Zig-Build-System" class="hdr">§</a>

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
- Surfacing build configuration as [comptime](../zig-0.15.1.md#comptime) values by providing a
  file that can be [imported](../zig-0.15.1.md#import) by Zig code.
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


