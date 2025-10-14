<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Single Threaded Builds -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Single Threaded Builds](zig-0.15.1.md#toc-Single-Threaded-Builds) <a href="zig-0.15.1.md#Single-Threaded-Builds" class="hdr">§</a>

Zig has a compile option <span class="kbd">-fsingle-threaded</span> which has the following effects:

- All [Thread Local Variables](zig-0.15.1.md#Thread-Local-Variables) are treated as regular [Container Level Variables](zig-0.15.1.md#Container-Level-Variables).
- The overhead of [Async Functions](zig-0.15.1.md#Async-Functions) becomes equivalent to function call overhead.
- The <span class="tok-builtin">`@import`</span>`(`<span class="tok-str">`"builtin"`</span>`).single_threaded` becomes <span class="tok-null">`true`</span>
  and therefore various userland APIs which read this variable become more efficient.
  For example `std.Mutex` becomes
  an empty data structure and all of its functions become no-ops.

