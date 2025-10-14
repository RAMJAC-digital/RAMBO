<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: while -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [while](zig-0.15.1.md#toc-while) <a href="zig-0.15.1.md#while" class="hdr">§</a>

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

### [Labeled while](zig-0.15.1.md#toc-Labeled-while) <a href="zig-0.15.1.md#Labeled-while" class="hdr">§</a>

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

### [while with Optionals](zig-0.15.1.md#toc-while-with-Optionals) <a href="zig-0.15.1.md#while-with-Optionals" class="hdr">§</a>

Just like [if](zig-0.15.1.md#if) expressions, while loops can take an optional as the
condition and capture the payload. When [null](zig-0.15.1.md#null) is encountered the loop
exits.

When the `|x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Optional Type](zig-0.15.1.md#Optional-Type).

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

### [while with Error Unions](zig-0.15.1.md#toc-while-with-Error-Unions) <a href="zig-0.15.1.md#while-with-Error-Unions" class="hdr">§</a>

Just like [if](zig-0.15.1.md#if) expressions, while loops can take an error union as
the condition and capture the payload or the error code. When the
condition results in an error code the else branch is evaluated and
the loop is finished.

When the <span class="tok-kw">`else`</span>` |x|` syntax is present on a <span class="tok-kw">`while`</span> expression,
the while condition must have an [Error Union Type](zig-0.15.1.md#Error-Union-Type).

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

### [inline while](zig-0.15.1.md#toc-inline-while) <a href="zig-0.15.1.md#inline-while" class="hdr">§</a>

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

- You need the loop to execute at [comptime](zig-0.15.1.md#comptime) for the semantics to work.
- You have a benchmark to prove that forcibly unrolling the loop in this way is measurably faster.

See also:

- [if](zig-0.15.1.md#if)
- [Optionals](zig-0.15.1.md#Optionals)
- [Errors](zig-0.15.1.md#Errors)
- [comptime](zig-0.15.1.md#comptime)
- [unreachable](zig-0.15.1.md#unreachable)

