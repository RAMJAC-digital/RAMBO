<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Memory -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Memory](zig-0.15.1.md#toc-Memory) <a href="zig-0.15.1.md#Memory" class="hdr">§</a>

The Zig language performs no memory management on behalf of the programmer. This is
why Zig has no runtime, and why Zig code works seamlessly in so many environments,
including real-time software, operating system kernels, embedded devices, and
low latency servers. As a consequence, Zig programmers must always be able to answer
the question:

[Where are the bytes?](zig-0.15.1.md#Where-are-the-bytes)

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
follow the [Choosing an Allocator](zig-0.15.1.md#Choosing-an-Allocator) guide.

### [Choosing an Allocator](zig-0.15.1.md#toc-Choosing-an-Allocator) <a href="zig-0.15.1.md#Choosing-an-Allocator" class="hdr">§</a>

What allocator to use depends on a number of factors. Here is a flow chart to help you decide:

1.  Are you making a library? In this case, best to accept an `Allocator`
    as a parameter and allow your library's users to decide what allocator to use.
2.  Are you linking libc? In this case, `std.heap.c_allocator` is likely
    the right choice, at least for your main allocator.
3.  Need to use the same allocator in multiple threads? Use one of your choice
    wrapped around `std.heap.ThreadSafeAllocator`
4.  Is the maximum number of bytes that you will need bounded by a number known at
    [comptime](zig-0.15.1.md#comptime)? In this case, use `std.heap.FixedBufferAllocator`.
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
    Zig's general purpose allocator is available as a function that takes a [comptime](zig-0.15.1.md#comptime)
    [struct](zig-0.15.1.md#struct) of configuration options and returns a type.
    Generally, you will set up one `std.heap.GeneralPurposeAllocator` in
    your main function, and then pass it or sub-allocators around to various parts of your
    application.
10. You can also consider [Implementing an Allocator](zig-0.15.1.md#Implementing-an-Allocator).

### [Where are the bytes?](zig-0.15.1.md#toc-Where-are-the-bytes) <a href="zig-0.15.1.md#Where-are-the-bytes" class="hdr">§</a>

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

Just like string literals, <span class="tok-kw">`const`</span> declarations, when the value is known at [comptime](zig-0.15.1.md#comptime),
are stored in the global constant data section. Also [Compile Time Variables](zig-0.15.1.md#Compile-Time-Variables) are stored
in the global constant data section.

<span class="tok-kw">`var`</span> declarations inside functions are stored in the function's stack frame. Once a function returns,
any [Pointers](zig-0.15.1.md#Pointers) to variables in the function's stack frame become invalid references, and
dereferencing them becomes unchecked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

<span class="tok-kw">`var`</span> declarations at the top level or in [struct](zig-0.15.1.md#struct) declarations are stored in the global
data section.

The location of memory allocated with `allocator.alloc` or
`allocator.create` is determined by the allocator's implementation.

TODO: thread local variables

### [Implementing an Allocator](zig-0.15.1.md#toc-Implementing-an-Allocator) <a href="zig-0.15.1.md#Implementing-an-Allocator" class="hdr">§</a>

Zig programmers can implement their own allocators by fulfilling the Allocator interface.
In order to do this one must read carefully the documentation comments in std/mem.zig and
then supply a `allocFn` and a `resizeFn`.

There are many example allocators to look at for inspiration. Look at std/heap.zig and
`std.heap.GeneralPurposeAllocator`.

### [Heap Allocation Failure](zig-0.15.1.md#toc-Heap-Allocation-Failure) <a href="zig-0.15.1.md#Heap-Allocation-Failure" class="hdr">§</a>

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

### [Recursion](zig-0.15.1.md#toc-Recursion) <a href="zig-0.15.1.md#Recursion" class="hdr">§</a>

Recursion is a fundamental tool in modeling software. However it has an often-overlooked problem:
unbounded memory allocation.

Recursion is an area of active experimentation in Zig and so the documentation here is not final.
You can read a
[summary of recursion status in the 0.3.0 release notes](https://ziglang.org/download/0.3.0/release-notes.html#recursion).

The short summary is that currently recursion works normally as you would expect. Although Zig code
is not yet protected from stack overflow, it is planned that a future version of Zig will provide
such protection, with some degree of cooperation from Zig code required.

### [Lifetime and Ownership](zig-0.15.1.md#toc-Lifetime-and-Ownership) <a href="zig-0.15.1.md#Lifetime-and-Ownership" class="hdr">§</a>

It is the Zig programmer's responsibility to ensure that a [pointer](zig-0.15.1.md#Pointers) is not
accessed when the memory pointed to is no longer available. Note that a [slice](zig-0.15.1.md#Slices)
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
the memory becomes inaccessible (lest [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior) occur).

