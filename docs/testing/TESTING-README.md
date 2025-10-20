# Test Commands Reference

## Adapt this pattern to run singular tests, this is simply an example.

```bash
 zig test -ODebug --dep RAMBO -Mroot=tests/integration/mmc3_visual_regression_test.zig -MRAMBO=src/root.zig
```

## Short form (via build system)

```bash
zig build test-integration
```
