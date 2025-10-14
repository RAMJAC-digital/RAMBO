<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Zig Test -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Zig Test](zig-0.15.1.md#toc-Zig-Test) <a href="zig-0.15.1.md#Zig-Test" class="hdr">§</a>

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

The `testing_introduction.zig` code sample tests the [function](zig-0.15.1.md#Functions)
`addOne` to ensure that it returns <span class="tok-number">`42`</span> given the input
<span class="tok-number">`41`</span>. From this test's perspective, the `addOne` function is
said to be *code under test*.

<span class="kbd">zig test</span> is a tool that creates and runs a test build. By default, it builds and runs an
executable program using the *default test runner* provided by the [Zig Standard Library](zig-0.15.1.md#Zig-Standard-Library)
as its main entry point. During the build, <span class="tok-kw">`test`</span> declarations found while
[resolving](zig-0.15.1.md#File-and-Declaration-Discovery) the given Zig source file are included for the default test runner
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

### [Test Declarations](zig-0.15.1.md#toc-Test-Declarations) <a href="zig-0.15.1.md#Test-Declarations" class="hdr">§</a>

Test declarations contain the [keyword](zig-0.15.1.md#Keyword-Reference) <span class="tok-kw">`test`</span>, followed by an
optional name written as a [string literal](zig-0.15.1.md#String-Literals-and-Unicode-Code-Point-Literals) or an
[identifier](zig-0.15.1.md#Identifiers), followed by a [block](zig-0.15.1.md#Blocks) containing any valid Zig code that
is allowed in a [function](zig-0.15.1.md#Functions).

Non-named test blocks always run during test builds and are exempt from
[Skip Tests](zig-0.15.1.md#Skip-Tests).

Test declarations are similar to [Functions](zig-0.15.1.md#Functions): they have a return type and a block of code. The implicit
return type of <span class="tok-kw">`test`</span> is the [Error Union Type](zig-0.15.1.md#Error-Union-Type) <span class="tok-type">`anyerror`</span>`!`<span class="tok-type">`void`</span>,
and it cannot be changed. When a Zig source file is not built using the <span class="kbd">zig test</span> tool, the test
declarations are omitted from the build.

Test declarations can be written in the same file, where code under test is written, or in a separate Zig source file.
Since test declarations are top-level declarations, they are order-independent and can
be written before or after the code under test.

See also:

- [The Global Error Set](zig-0.15.1.md#The-Global-Error-Set)
- [Grammar](zig-0.15.1.md#Grammar)

#### [Doctests](zig-0.15.1.md#toc-Doctests) <a href="zig-0.15.1.md#Doctests" class="hdr">§</a>

Test declarations named using an identifier are *doctests*. The identifier must refer to another declaration in
scope. A doctest, like a [doc comment](zig-0.15.1.md#Doc-Comments), serves as documentation for the associated declaration, and
will appear in the generated documentation for the declaration.

An effective doctest should be self-contained and focused on the declaration being tested, answering questions a new
user might have about its interface or intended usage, while avoiding unnecessary or confusing details. A doctest is not
a substitute for a doc comment, but rather a supplement and companion providing a testable, code-driven example, verified
by <span class="kbd">zig test</span>.

### [Test Failure](zig-0.15.1.md#toc-Test-Failure) <a href="zig-0.15.1.md#Test-Failure" class="hdr">§</a>

The default test runner checks for an [error](zig-0.15.1.md#Errors) returned from a test.
When a test returns an error, the test is considered a failure and its [error return trace](zig-0.15.1.md#Error-Return-Traces)
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

### [Skip Tests](zig-0.15.1.md#toc-Skip-Tests) <a href="zig-0.15.1.md#Skip-Tests" class="hdr">§</a>

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

### [Report Memory Leaks](zig-0.15.1.md#toc-Report-Memory-Leaks) <a href="zig-0.15.1.md#Report-Memory-Leaks" class="hdr">§</a>

When code allocates [Memory](zig-0.15.1.md#Memory) using the [Zig Standard Library](zig-0.15.1.md#Zig-Standard-Library)'s testing allocator,
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

- [defer](zig-0.15.1.md#defer)
- [Memory](zig-0.15.1.md#Memory)

### [Detecting Test Build](zig-0.15.1.md#toc-Detecting-Test-Build) <a href="zig-0.15.1.md#Detecting-Test-Build" class="hdr">§</a>

Use the [compile variable](zig-0.15.1.md#Compile-Variables) <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`).is_test`
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

### [Test Output and Logging](zig-0.15.1.md#toc-Test-Output-and-Logging) <a href="zig-0.15.1.md#Test-Output-and-Logging" class="hdr">§</a>

The default test runner and the Zig Standard Library's testing namespace output messages to standard error.

### [The Testing Namespace](zig-0.15.1.md#toc-The-Testing-Namespace) <a href="zig-0.15.1.md#The-Testing-Namespace" class="hdr">§</a>

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

The Zig Standard Library also contains functions to compare [Slices](zig-0.15.1.md#Slices), strings, and more. See the rest of the
`std.testing` namespace in the [Zig Standard Library](zig-0.15.1.md#Zig-Standard-Library) for more available functions.

### [Test Tool Documentation](zig-0.15.1.md#toc-Test-Tool-Documentation) <a href="zig-0.15.1.md#Test-Tool-Documentation" class="hdr">§</a>

<span class="kbd">zig test</span> has a few command line parameters which affect the compilation.
See <span class="kbd">zig test --help</span> for a full list.

