# Test Commands Reference

## Adapt this pattern to run singular tests 

```bash
/home/colin/.local/bin/zig test -ODebug --dep RAMBO -Mroot=tests/integration/mmc3_visual_regression_test.zig --dep build_options --dep wayland_client --dep xev --dep zli -MRAMBO=src/root.zig -Mbuild_options=.zig-cache/c/5957a99b7f28bd8d699802025e91c10c/options.zig -Mwayland_client=.zig-cache/o/ed05cd47c3a7e9b949af2e7577b2539c/wayland.zig -Mxev=/home/colin/.cache/zig/p/libxev-0.0.0-86vtc4IcEwCqEYxEYoN_3KXmc6A9VLcm22aVImfvecYs/src/main.zig -Mzli=/home/colin/.cache/zig/p/zli-4.1.1-LeUjpljfAAAak_E3L4NPowuzPs_FUF9-jYyxuTSNSthM/src/zli.zig --cache-dir .zig-cache --global-cache-dir /home/colin/.cache/zig --name mmc3_viz --zig-lib-dir /home/colin/.local/lib/zig/
```

## Short form (via build system)

```bash
zig build test-integration
```
