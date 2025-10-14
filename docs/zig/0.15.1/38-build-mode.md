<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Build Mode -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Build Mode](zig-0.15.1.md#toc-Build-Mode) <a href="zig-0.15.1.md#Build-Mode" class="hdr">§</a>

Zig has four build modes:

- [Debug](zig-0.15.1.md#Debug) (default)
- [ReleaseFast](zig-0.15.1.md#ReleaseFast)
- [ReleaseSafe](zig-0.15.1.md#ReleaseSafe)
- [ReleaseSmall](zig-0.15.1.md#ReleaseSmall)

To add standard build options to a `build.zig` file:

<figure>
<pre><code>const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;example&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;example.zig&quot;),
            .optimize = optimize,
        }),
    });
    b.default_step.dependOn(&amp;exe.step);
}</code></pre>
<figcaption>build.zig</figcaption>
</figure>

This causes these options to be available:

<span class="kbd">-Doptimize=Debug</span>  
Optimizations off and safety on (default)

<span class="kbd">-Doptimize=ReleaseSafe</span>  
Optimizations on and safety on

<span class="kbd">-Doptimize=ReleaseFast</span>  
Optimizations on and safety off

<span class="kbd">-Doptimize=ReleaseSmall</span>  
Size optimizations on and safety off

### [Debug](zig-0.15.1.md#toc-Debug) <a href="zig-0.15.1.md#Debug" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Fast compilation speed
- Safety checks enabled
- Slow runtime performance
- Large binary size
- No reproducible build requirement

### [ReleaseFast](zig-0.15.1.md#toc-ReleaseFast) <a href="zig-0.15.1.md#ReleaseFast" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseFast</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Fast runtime performance
- Safety checks disabled
- Slow compilation speed
- Large binary size
- Reproducible build

### [ReleaseSafe](zig-0.15.1.md#toc-ReleaseSafe) <a href="zig-0.15.1.md#ReleaseSafe" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseSafe</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Medium runtime performance
- Safety checks enabled
- Slow compilation speed
- Large binary size
- Reproducible build

### [ReleaseSmall](zig-0.15.1.md#toc-ReleaseSmall) <a href="zig-0.15.1.md#ReleaseSmall" class="hdr">§</a>

<figure>
<pre><code>$ zig build-exe example.zig -O ReleaseSmall</code></pre>
<figcaption>Shell</figcaption>
</figure>

- Medium runtime performance
- Safety checks disabled
- Slow compilation speed
- Small binary size
- Reproducible build

See also:

- [Compile Variables](zig-0.15.1.md#Compile-Variables)
- [Zig Build System](zig-0.15.1.md#Zig-Build-System)
- [Illegal Behavior](zig-0.15.1.md#Illegal-Behavior)

