<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->
[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md

# Interop & Targets

Included sections:
- C
- WebAssembly
- Targets

## [C](../zig-0.15.1.md#toc-C) <a href="../zig-0.15.1.md#C" class="hdr">§</a>

Although Zig is independent of C, and, unlike most other languages, does not depend on libc,
Zig acknowledges the importance of interacting with existing C code.

There are a few ways that Zig facilitates C interop.

### [C Type Primitives](../zig-0.15.1.md#toc-C-Type-Primitives) <a href="../zig-0.15.1.md#C-Type-Primitives" class="hdr">§</a>

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

- [Primitive Types](../zig-0.15.1.md#Primitive-Types)

### [Import from C Header File](../zig-0.15.1.md#toc-Import-from-C-Header-File) <a href="../zig-0.15.1.md#Import-from-C-Header-File" class="hdr">§</a>

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

- [@cImport](../zig-0.15.1.md#cImport)
- [@cInclude](../zig-0.15.1.md#cInclude)
- [@cDefine](../zig-0.15.1.md#cDefine)
- [@cUndef](../zig-0.15.1.md#cUndef)
- [@import](../zig-0.15.1.md#import)

### [C Translation CLI](../zig-0.15.1.md#toc-C-Translation-CLI) <a href="../zig-0.15.1.md#C-Translation-CLI" class="hdr">§</a>

Zig's C translation capability is available as a CLI tool via <span class="kbd">zig translate-c</span>.
It requires a single filename as an argument. It may also take a set of optional flags that are
forwarded to clang. It writes the translated file to stdout.

#### [Command line flags](../zig-0.15.1.md#toc-Command-line-flags) <a href="../zig-0.15.1.md#Command-line-flags" class="hdr">§</a>

- <span class="kbd">-I</span>:
  Specify a search directory for include files. May be used multiple times. Equivalent to
  [clang's <span class="kbd">-I</span> flag](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-i-dir). The current directory is *not* included by default;
  use <span class="kbd">-I.</span> to include it.
- <span class="kbd">-D</span>: Define a preprocessor macro. Equivalent to
  [clang's <span class="kbd">-D</span> flag](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-d-macro).
- <span class="kbd">-cflags \[flags\] --</span>: Pass arbitrary additional
  [command line
  flags](https://releases.llvm.org/12.0.0/tools/clang/docs/ClangCommandLineReference.html) to clang. Note: the list of flags must end with <span class="kbd">--</span>
- <span class="kbd">-target</span>: The [target triple](../zig-0.15.1.md#Targets) for the translated Zig code.
  If no target is specified, the current host target will be used.

#### [Using -target and -cflags](../zig-0.15.1.md#toc-Using--target-and--cflags) <a href="../zig-0.15.1.md#Using--target-and--cflags" class="hdr">§</a>

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

#### [@cImport vs translate-c](../zig-0.15.1.md#toc-cImport-vs-translate-c) <a href="../zig-0.15.1.md#cImport-vs-translate-c" class="hdr">§</a>

<span class="tok-builtin">`@cImport`</span> and <span class="kbd">zig translate-c</span> use the same underlying
C translation functionality, so on a technical level they are equivalent. In practice,
<span class="tok-builtin">`@cImport`</span> is useful as a way to quickly and easily access numeric constants, typedefs,
and record types without needing any extra setup. If you need to pass [cflags](../zig-0.15.1.md#Using--target-and--cflags)
to clang, or if you would like to edit the translated code, it is recommended to use
<span class="kbd">zig translate-c</span> and save the results to a file. Common reasons for editing
the generated code include: changing <span class="tok-kw">`anytype`</span> parameters in function-like macros to more
specific types; changing `[*c]T` pointers to `[*]T` or
`*T` pointers for improved type safety; and
[enabling or disabling runtime safety](../zig-0.15.1.md#setRuntimeSafety) within specific functions.

See also:

- [Targets](../zig-0.15.1.md#Targets)
- [C Type Primitives](../zig-0.15.1.md#C-Type-Primitives)
- [Pointers](../zig-0.15.1.md#Pointers)
- [C Pointers](../zig-0.15.1.md#C-Pointers)
- [Import from C Header File](../zig-0.15.1.md#Import-from-C-Header-File)
- [@cInclude](../zig-0.15.1.md#cInclude)
- [@cImport](../zig-0.15.1.md#cImport)
- [@setRuntimeSafety](../zig-0.15.1.md#setRuntimeSafety)

### [C Translation Caching](../zig-0.15.1.md#toc-C-Translation-Caching) <a href="../zig-0.15.1.md#C-Translation-Caching" class="hdr">§</a>

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

- [Import from C Header File](../zig-0.15.1.md#Import-from-C-Header-File)
- [C Translation CLI](../zig-0.15.1.md#C-Translation-CLI)
- [@cInclude](../zig-0.15.1.md#cInclude)
- [@cImport](../zig-0.15.1.md#cImport)

### [Translation failures](../zig-0.15.1.md#toc-Translation-failures) <a href="../zig-0.15.1.md#Translation-failures" class="hdr">§</a>

Some C constructs cannot be translated to Zig - for example, *goto*,
structs with bitfields, and token-pasting macros. Zig employs *demotion* to allow translation
to continue in the face of non-translatable entities.

Demotion comes in three varieties - [opaque](../zig-0.15.1.md#opaque), *extern*, and
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

- [opaque](../zig-0.15.1.md#opaque)
- [extern](../zig-0.15.1.md#extern)
- [@compileError](../zig-0.15.1.md#compileError)

### [C Macros](../zig-0.15.1.md#toc-C-Macros) <a href="../zig-0.15.1.md#C-Macros" class="hdr">§</a>

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

- [@compileError](../zig-0.15.1.md#compileError)

### [C Pointers](../zig-0.15.1.md#toc-C-Pointers) <a href="../zig-0.15.1.md#C-Pointers" class="hdr">§</a>

This type is to be avoided whenever possible. The only valid reason for using a C pointer is in
auto-generated code from translating C code.

When importing C header files, it is ambiguous whether pointers should be translated as
single-item pointers (`*T`) or many-item pointers (`[*]T`).
C pointers are a compromise so that Zig code can utilize translated header files directly.

`[*c]T` - C pointer.

- Supports all the syntax of the other two pointer types (`*T`) and (`[*]T`).
- Coerces to other pointer types, as well as [Optional Pointers](../zig-0.15.1.md#Optional-Pointers).
  When a C pointer is coerced to a non-optional pointer, safety-checked
  [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior) occurs if the address is 0.
- Allows address 0. On non-freestanding targets, dereferencing address 0 is safety-checked
  [Illegal Behavior](../zig-0.15.1.md#Illegal-Behavior). Optional C pointers introduce another bit to keep track of
  null, just like `?`<span class="tok-type">`usize`</span>. Note that creating an optional C pointer
  is unnecessary as one can use normal [Optional Pointers](../zig-0.15.1.md#Optional-Pointers).
- Supports [Type Coercion](../zig-0.15.1.md#Type-Coercion) to and from integers.
- Supports comparison with integers.
- Does not support Zig-only pointer attributes such as alignment. Use normal [Pointers](../zig-0.15.1.md#Pointers)
  please!

When a C pointer is pointing to a single struct (not an array), dereference the C pointer to
access the struct's fields or member data. That syntax looks like
this:

`ptr_to_struct.*.struct_member`

This is comparable to doing `->` in C.

When a C pointer is pointing to an array of structs, the syntax reverts to this:

`ptr_to_struct_array[index].struct_member`

### [C Variadic Functions](../zig-0.15.1.md#toc-C-Variadic-Functions) <a href="../zig-0.15.1.md#C-Variadic-Functions" class="hdr">§</a>

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

Variadic functions can be implemented using [@cVaStart](../zig-0.15.1.md#cVaStart), [@cVaEnd](../zig-0.15.1.md#cVaEnd), [@cVaArg](../zig-0.15.1.md#cVaArg) and [@cVaCopy](../zig-0.15.1.md#cVaCopy).

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

### [Exporting a C Library](../zig-0.15.1.md#toc-Exporting-a-C-Library) <a href="../zig-0.15.1.md#Exporting-a-C-Library" class="hdr">§</a>

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

Here is an example with the [Zig Build System](../zig-0.15.1.md#Zig-Build-System):

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

- [export](../zig-0.15.1.md#export)

### [Mixing Object Files](../zig-0.15.1.md#toc-Mixing-Object-Files) <a href="../zig-0.15.1.md#Mixing-Object-Files" class="hdr">§</a>

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

- [Targets](../zig-0.15.1.md#Targets)
- [Zig Build System](../zig-0.15.1.md#Zig-Build-System)

## [WebAssembly](../zig-0.15.1.md#toc-WebAssembly) <a href="../zig-0.15.1.md#WebAssembly" class="hdr">§</a>

Zig supports building for WebAssembly out of the box.

### [Freestanding](../zig-0.15.1.md#toc-Freestanding) <a href="../zig-0.15.1.md#Freestanding" class="hdr">§</a>

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

### [WASI](../zig-0.15.1.md#toc-WASI) <a href="../zig-0.15.1.md#WASI" class="hdr">§</a>

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

## [Targets](../zig-0.15.1.md#toc-Targets) <a href="../zig-0.15.1.md#Targets" class="hdr">§</a>

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


