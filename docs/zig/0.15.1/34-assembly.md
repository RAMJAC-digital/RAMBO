<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Assembly -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Assembly](zig-0.15.1.md#toc-Assembly) <a href="zig-0.15.1.md#Assembly" class="hdr">§</a>

For some use cases, it may be necessary to directly control the machine code generated
by Zig programs, rather than relying on Zig's code generation. For these cases, one
can use inline assembly. Here is an example of implementing Hello, World on x86_64 Linux
using inline assembly:

<figure>
<pre><code>pub fn main() noreturn {
    const msg = &quot;hello world\n&quot;;
    _ = syscall3(SYS_write, STDOUT_FILENO, @intFromPtr(msg), msg.len);
    _ = syscall1(SYS_exit, 0);
    unreachable;
}

pub const SYS_write = 1;
pub const SYS_exit = 60;

pub const STDOUT_FILENO = 1;

pub fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile (&quot;syscall&quot;
        : [ret] &quot;={rax}&quot; (-&gt; usize),
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
        : .{ .rcx = true, .r11 = true });
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile (&quot;syscall&quot;
        : [ret] &quot;={rax}&quot; (-&gt; usize),
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
          [arg2] &quot;{rsi}&quot; (arg2),
          [arg3] &quot;{rdx}&quot; (arg3),
        : .{ .rcx = true, .r11 = true });
}</code></pre>
<figcaption>inline_assembly.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig build-exe inline_assembly.zig -target x86_64-linux
$ ./inline_assembly
hello world</code></pre>
<figcaption>Shell</figcaption>
</figure>

Dissecting the syntax:

<figure>
<pre><code>pub fn syscall1(number: usize, arg1: usize) usize {
    // Inline assembly is an expression which returns a value.
    // the `asm` keyword begins the expression.
    return asm
    // `volatile` is an optional modifier that tells Zig this
    // inline assembly expression has side-effects. Without
    // `volatile`, Zig is allowed to delete the inline assembly
    // code if the result is unused.
    volatile (
    // Next is a comptime string which is the assembly code.
    // Inside this string one may use `%[ret]`, `%[number]`,
    // or `%[arg1]` where a register is expected, to specify
    // the register that Zig uses for the argument or return value,
    // if the register constraint strings are used. However in
    // the below code, this is not used. A literal `%` can be
    // obtained by escaping it with a double percent: `%%`.
    // Often multiline string syntax comes in handy here.
        \\syscall
        // Next is the output. It is possible in the future Zig will
        // support multiple outputs, depending on how
        // https://github.com/ziglang/zig/issues/215 is resolved.
        // It is allowed for there to be no outputs, in which case
        // this colon would be directly followed by the colon for the inputs.
        :
        // This specifies the name to be used in `%[ret]` syntax in
        // the above assembly string. This example does not use it,
        // but the syntax is mandatory.
          [ret]
          // Next is the output constraint string. This feature is still
          // considered unstable in Zig, and so LLVM/GCC documentation
          // must be used to understand the semantics.
          // http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string
          // https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html
          // In this example, the constraint string means &quot;the result value of
          // this inline assembly instruction is whatever is in $rax&quot;.
          &quot;={rax}&quot;
          // Next is either a value binding, or `-&gt;` and then a type. The
          // type is the result type of the inline assembly expression.
          // If it is a value binding, then `%[ret]` syntax would be used
          // to refer to the register bound to the value.
          (-&gt; usize),
          // Next is the list of inputs.
          // The constraint for these inputs means, &quot;when the assembly code is
          // executed, $rax shall have the value of `number` and $rdi shall have
          // the value of `arg1`&quot;. Any number of input parameters is allowed,
          // including none.
        : [number] &quot;{rax}&quot; (number),
          [arg1] &quot;{rdi}&quot; (arg1),
          // Next is the list of clobbers. These declare a set of registers whose
          // values will not be preserved by the execution of this assembly code.
          // These do not include output or input registers. The special clobber
          // value of &quot;memory&quot; means that the assembly writes to arbitrary undeclared
          // memory locations - not only the memory pointed to by a declared indirect
          // output. In this example we list $rcx and $r11 because it is known the
          // kernel syscall does not preserve these registers.
        : .{ .rcx = true, .r11 = true });
}</code></pre>
<figcaption>Assembly Syntax Explained.zig</figcaption>
</figure>

For x86 and x86_64 targets, the syntax is AT&T syntax, rather than the more
popular Intel syntax. This is due to technical constraints; assembly parsing is
provided by LLVM and its support for Intel syntax is buggy and not well tested.

Some day Zig may have its own assembler. This would allow it to integrate more seamlessly
into the language, as well as be compatible with the popular NASM syntax. This documentation
section will be updated before 1.0.0 is released, with a conclusive statement about the status
of AT&T vs Intel/NASM syntax.

### [Output Constraints](zig-0.15.1.md#toc-Output-Constraints) <a href="zig-0.15.1.md#Output-Constraints" class="hdr">§</a>

Output constraints are still considered to be unstable in Zig, and
so
[LLVM documentation](http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string)
and
[GCC documentation](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html)
must be used to understand the semantics.

Note that some breaking changes to output constraints are planned with
[issue \#215](https://github.com/ziglang/zig/issues/215).

### [Input Constraints](zig-0.15.1.md#toc-Input-Constraints) <a href="zig-0.15.1.md#Input-Constraints" class="hdr">§</a>

Input constraints are still considered to be unstable in Zig, and
so
[LLVM documentation](http://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string)
and
[GCC documentation](https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html)
must be used to understand the semantics.

Note that some breaking changes to input constraints are planned with
[issue \#215](https://github.com/ziglang/zig/issues/215).

### [Clobbers](zig-0.15.1.md#toc-Clobbers) <a href="zig-0.15.1.md#Clobbers" class="hdr">§</a>

Clobbers are the set of registers whose values will not be preserved by the execution of
the assembly code. These do not include output or input registers. The special clobber
value of <span class="tok-str">`"memory"`</span> means that the assembly causes writes to
arbitrary undeclared memory locations - not only the memory pointed to by a declared
indirect output.

Failure to declare the full set of clobbers for a given inline assembly
expression is unchecked [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior).

### [Global Assembly](zig-0.15.1.md#toc-Global-Assembly) <a href="zig-0.15.1.md#Global-Assembly" class="hdr">§</a>

When an assembly expression occurs in a [container](zig-0.15.1.md#Containers) level [comptime](zig-0.15.1.md#comptime) block, this is
**global assembly**.

This kind of assembly has different rules than inline assembly. First, <span class="tok-kw">`volatile`</span>
is not valid because all global assembly is unconditionally included.
Second, there are no inputs, outputs, or clobbers. All global assembly is concatenated
verbatim into one long string and assembled together. There are no template substitution rules regarding
`%` as there are in inline assembly expressions.

<figure>
<pre><code>const std = @import(&quot;std&quot;);
const expect = std.testing.expect;

comptime {
    asm (
        \\.global my_func;
        \\.type my_func, @function;
        \\my_func:
        \\  lea (%rdi,%rsi,1),%eax
        \\  retq
    );
}

extern fn my_func(a: i32, b: i32) i32;

test &quot;global assembly&quot; {
    try expect(my_func(12, 34) == 46);
}</code></pre>
<figcaption>test_global_assembly.zig</figcaption>
</figure>

<figure>
<pre><code>$ zig test test_global_assembly.zig -target x86_64-linux -fllvm
1/1 test_global_assembly.test.global assembly...OK
All 1 tests passed.</code></pre>
<figcaption>Shell</figcaption>
</figure>

