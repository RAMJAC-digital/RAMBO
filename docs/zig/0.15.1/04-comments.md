<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Comments -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Comments](zig-0.15.1.md#toc-Comments) <a href="zig-0.15.1.md#Comments" class="hdr">§</a>

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

### [Doc Comments](zig-0.15.1.md#toc-Doc-Comments) <a href="zig-0.15.1.md#Doc-Comments" class="hdr">§</a>

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

### [Top-Level Doc Comments](zig-0.15.1.md#toc-Top-Level-Doc-Comments) <a href="zig-0.15.1.md#Top-Level-Doc-Comments" class="hdr">§</a>

A top-level doc comment is one that begins with two slashes and an exclamation
point: <span class="tok-comment">`//!`</span>; it documents the current module.

It is a compile error if a top-level doc comment is not placed at the start
of a [container](zig-0.15.1.md#Containers), before any expressions.

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

