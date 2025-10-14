<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Keyword Reference -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Keyword Reference](zig-0.15.1.md#toc-Keyword-Reference) <a href="zig-0.15.1.md#Keyword-Reference" class="hdr">§</a>

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
<li>See also <a href="zig-0.15.1.md#Alignment">Alignment</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>allowzero</code></pre></th>
<td>The pointer attribute <span class="tok-kw"><code>allowzero</code></span> allows a pointer to have address zero.
<ul>
<li>See also <a href="zig-0.15.1.md#allowzero">allowzero</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>and</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>and</code></span>.
<ul>
<li>See also <a href="zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anyframe</code></pre></th>
<td><span class="tok-kw"><code>anyframe</code></span> can be used as a type for variables which hold pointers to function frames.
<ul>
<li>See also <a href="zig-0.15.1.md#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>anytype</code></pre></th>
<td>Function parameters can be declared with <span class="tok-kw"><code>anytype</code></span> in place of the type.
The type will be inferred where the function is called.
<ul>
<li>See also <a href="zig-0.15.1.md#Function-Parameter-Type-Inference">Function Parameter Type Inference</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>asm</code></pre></th>
<td><span class="tok-kw"><code>asm</code></span> begins an inline assembly expression. This allows for directly controlling the machine code generated on compilation.
<ul>
<li>See also <a href="zig-0.15.1.md#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>break</code></pre></th>
<td><span class="tok-kw"><code>break</code></span> can be used with a block label to return a value from the block.
It can also be used to exit a loop before iteration completes naturally.
<ul>
<li>See also <a href="zig-0.15.1.md#Blocks">Blocks</a>, <a href="zig-0.15.1.md#while">while</a>, <a href="zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>callconv</code></pre></th>
<td><span class="tok-kw"><code>callconv</code></span> can be used to specify the calling convention in a function type.
<ul>
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>catch</code></pre></th>
<td><span class="tok-kw"><code>catch</code></span> can be used to evaluate an expression if the expression before it evaluates to an error.
The expression after the <span class="tok-kw"><code>catch</code></span> can optionally capture the error value.
<ul>
<li>See also <a href="zig-0.15.1.md#catch">catch</a>, <a href="zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>comptime</code></pre></th>
<td><span class="tok-kw"><code>comptime</code></span> before a declaration can be used to label variables or function parameters as known at compile time.
It can also be used to guarantee an expression is run at compile time.
<ul>
<li>See also <a href="zig-0.15.1.md#comptime">comptime</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>const</code></pre></th>
<td><span class="tok-kw"><code>const</code></span> declares a variable that can not be modified.
Used as a pointer attribute, it denotes the value referenced by the pointer cannot be modified.
<ul>
<li>See also <a href="zig-0.15.1.md#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>continue</code></pre></th>
<td><span class="tok-kw"><code>continue</code></span> can be used in a loop to jump back to the beginning of the loop.
<ul>
<li>See also <a href="zig-0.15.1.md#while">while</a>, <a href="zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>defer</code></pre></th>
<td><span class="tok-kw"><code>defer</code></span> will execute an expression when control flow leaves the current block.
<ul>
<li>See also <a href="zig-0.15.1.md#defer">defer</a></li>
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
<li>See also <a href="zig-0.15.1.md#if">if</a>, <a href="zig-0.15.1.md#switch">switch</a>, <a href="zig-0.15.1.md#while">while</a>, <a href="zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>enum</code></pre></th>
<td><span class="tok-kw"><code>enum</code></span> defines an enum type.
<ul>
<li>See also <a href="zig-0.15.1.md#enum">enum</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>errdefer</code></pre></th>
<td><span class="tok-kw"><code>errdefer</code></span> will execute an expression when control flow leaves the current block if the function returns an error, the errdefer expression can capture the unwrapped value.
<ul>
<li>See also <a href="zig-0.15.1.md#errdefer">errdefer</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>error</code></pre></th>
<td><span class="tok-kw"><code>error</code></span> defines an error type.
<ul>
<li>See also <a href="zig-0.15.1.md#Errors">Errors</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>export</code></pre></th>
<td><span class="tok-kw"><code>export</code></span> makes a function or variable externally visible in the generated object file.
Exported functions default to the C calling convention.
<ul>
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>extern</code></pre></th>
<td><span class="tok-kw"><code>extern</code></span> can be used to declare a function or variable that will be resolved at link time, when linking statically
or at runtime, when linking dynamically.
<ul>
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>fn</code></pre></th>
<td><span class="tok-kw"><code>fn</code></span> declares a function.
<ul>
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>for</code></pre></th>
<td>A <span class="tok-kw"><code>for</code></span> expression can be used to iterate over the elements of a slice, array, or tuple.
<ul>
<li>See also <a href="zig-0.15.1.md#for">for</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>if</code></pre></th>
<td>An <span class="tok-kw"><code>if</code></span> expression can test boolean expressions, optional values, or error unions.
For optional values or error unions, the if expression can capture the unwrapped value.
<ul>
<li>See also <a href="zig-0.15.1.md#if">if</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>inline</code></pre></th>
<td><span class="tok-kw"><code>inline</code></span> can be used to label a loop expression such that it will be unrolled at compile time.
It can also be used to force a function to be inlined at all call sites.
<ul>
<li>See also <a href="zig-0.15.1.md#inline-while">inline while</a>, <a href="zig-0.15.1.md#inline-for">inline for</a>, <a href="zig-0.15.1.md#Functions">Functions</a></li>
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
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>nosuspend</code></pre></th>
<td>The <span class="tok-kw"><code>nosuspend</code></span> keyword can be used in front of a block, statement or expression, to mark a scope where no suspension points are reached.
In particular, inside a <span class="tok-kw"><code>nosuspend</code></span> scope:
<ul>
<li>Using the <span class="tok-kw"><code>suspend</code></span> keyword results in a compile error.</li>
<li>Using <code>await</code> on a function frame which hasn't completed yet results in safety-checked <a href="zig-0.15.1.md#Illegal-Behavior">Illegal Behavior</a>.</li>
<li>Calling an async function may result in safety-checked <a href="zig-0.15.1.md#Illegal-Behavior">Illegal Behavior</a>, because it's equivalent to <code>await async some_async_fn()</code>, which contains an <code>await</code>.</li>
</ul>
Code inside a <span class="tok-kw"><code>nosuspend</code></span> scope does not cause the enclosing function to become an <a href="zig-0.15.1.md#Async-Functions">async function</a>.
<ul>
<li>See also <a href="zig-0.15.1.md#Async-Functions">Async Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>opaque</code></pre></th>
<td><span class="tok-kw"><code>opaque</code></span> defines an opaque type.
<ul>
<li>See also <a href="zig-0.15.1.md#opaque">opaque</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>or</code></pre></th>
<td>The boolean operator <span class="tok-kw"><code>or</code></span>.
<ul>
<li>See also <a href="zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>orelse</code></pre></th>
<td><span class="tok-kw"><code>orelse</code></span> can be used to evaluate an expression if the expression before it evaluates to null.
<ul>
<li>See also <a href="zig-0.15.1.md#Optionals">Optionals</a>, <a href="zig-0.15.1.md#Operators">Operators</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>packed</code></pre></th>
<td>The <span class="tok-kw"><code>packed</code></span> keyword before a struct definition changes the struct's in-memory layout
to the guaranteed <span class="tok-kw"><code>packed</code></span> layout.
<ul>
<li>See also <a href="zig-0.15.1.md#packed-struct">packed struct</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>pub</code></pre></th>
<td>The <span class="tok-kw"><code>pub</code></span> in front of a top level declaration makes the declaration available
to reference from a different file than the one it is declared in.
<ul>
<li>See also <a href="zig-0.15.1.md#import">import</a></li>
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
<li>See also <a href="zig-0.15.1.md#Functions">Functions</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>struct</code></pre></th>
<td><span class="tok-kw"><code>struct</code></span> defines a struct.
<ul>
<li>See also <a href="zig-0.15.1.md#struct">struct</a></li>
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
<span class="tok-kw"><code>switch</code></span> cases can capture field values of a <a href="zig-0.15.1.md#Tagged-union">Tagged union</a>.
<ul>
<li>See also <a href="zig-0.15.1.md#switch">switch</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>test</code></pre></th>
<td>The <span class="tok-kw"><code>test</code></span> keyword can be used to denote a top-level block of code
used to make sure behavior meets expectations.
<ul>
<li>See also <a href="zig-0.15.1.md#Zig-Test">Zig Test</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>threadlocal</code></pre></th>
<td><span class="tok-kw"><code>threadlocal</code></span> can be used to specify a variable as thread-local.
<ul>
<li>See also <a href="zig-0.15.1.md#Thread-Local-Variables">Thread Local Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>try</code></pre></th>
<td><span class="tok-kw"><code>try</code></span> evaluates an error union expression.
If it is an error, it returns from the current function with the same error.
Otherwise, the expression results in the unwrapped value.
<ul>
<li>See also <a href="zig-0.15.1.md#try">try</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>union</code></pre></th>
<td><span class="tok-kw"><code>union</code></span> defines a union.
<ul>
<li>See also <a href="zig-0.15.1.md#union">union</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>unreachable</code></pre></th>
<td><span class="tok-kw"><code>unreachable</code></span> can be used to assert that control flow will never happen upon a particular location.
Depending on the build mode, <span class="tok-kw"><code>unreachable</code></span> may emit a panic.
<ul>
<li>Emits a panic in <code>Debug</code> and <code>ReleaseSafe</code> mode, or when using <kbd>zig test</kbd>.</li>
<li>Does not emit a panic in <code>ReleaseFast</code> and <code>ReleaseSmall</code> mode.</li>
<li>See also <a href="zig-0.15.1.md#unreachable">unreachable</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>var</code></pre></th>
<td><span class="tok-kw"><code>var</code></span> declares a variable that may be modified.
<ul>
<li>See also <a href="zig-0.15.1.md#Variables">Variables</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>volatile</code></pre></th>
<td><span class="tok-kw"><code>volatile</code></span> can be used to denote loads or stores of a pointer have side effects.
It can also modify an inline assembly expression to denote it has side effects.
<ul>
<li>See also <a href="zig-0.15.1.md#volatile">volatile</a>, <a href="zig-0.15.1.md#Assembly">Assembly</a></li>
</ul></td>
</tr>
<tr>
<th scope="row"><pre><code>while</code></pre></th>
<td>A <span class="tok-kw"><code>while</code></span> expression can be used to repeatedly test a boolean, optional, or error union expression,
and cease looping when that expression evaluates to false, null, or an error, respectively.
<ul>
<li>See also <a href="zig-0.15.1.md#while">while</a></li>
</ul></td>
</tr>
</tbody>
</table>

</div>

