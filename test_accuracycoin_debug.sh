#!/bin/bash
# Debug helper for AccuracyCoin tests

export RAMBO_DEBUG_VBLANK=1

# Run specific AccuracyCoin test with debug output
zig build test 2>&1 | grep -A 200 "test.Accuracy: VBLANK BEGINNING"
