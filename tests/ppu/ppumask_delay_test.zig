const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Ppu = RAMBO.Ppu;
const PpuState = Ppu.PpuState;
const PpuMask = Ppu.PpuMask;

// Hardware Specification: PPUMASK register changes take 3-4 dots to propagate
// to rendering logic due to pipeline delay in the NES PPU.
//
// Source: nesdev.org/wiki/PPU_registers#PPUMASK
// "Toggling rendering takes effect approximately 3-4 dots after write"
//
// Implementation: 4-entry circular buffer in PpuState.mask_delay_buffer
// Access via getEffectiveMask() returns mask from 3 dots ago

test "PPUMASK: Delay buffer initialization" {
    var ppu = PpuState{};

    // Initial state: all masks should be default (disabled)
    try testing.expect(!ppu.getEffectiveMask().show_bg);
    try testing.expect(!ppu.getEffectiveMask().show_sprites);
    try testing.expect(!ppu.getEffectiveMask().greyscale);
}

test "PPUMASK: 3-dot delay for rendering enable" {
    var ppu = PpuState{};

    // Fill delay buffer with disabled state
    const disabled_mask = PpuMask{};
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = disabled_mask;
    }
    ppu.mask_delay_index = 0;

    // Verify rendering disabled
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Enable rendering (write to mask register)
    const enabled_mask = PpuMask{
        .show_bg = true,
        .show_sprites = true,
    };
    ppu.mask = enabled_mask;

    // Dot 0: Write to buffer, effective mask still old
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Dot 1: Still old
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Dot 2: Still old
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Dot 3: Now new mask takes effect (3 dots later)
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(ppu.getEffectiveMask().show_bg);
    try testing.expect(ppu.getEffectiveMask().show_sprites);
}

test "PPUMASK: 3-dot delay for rendering disable" {
    var ppu = PpuState{};

    // Fill delay buffer with enabled state
    const enabled_mask = PpuMask{
        .show_bg = true,
        .show_sprites = true,
    };
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = enabled_mask;
    }
    ppu.mask_delay_index = 0;

    // Verify rendering enabled
    try testing.expect(ppu.getEffectiveMask().show_bg);

    // Disable rendering
    const disabled_mask = PpuMask{};
    ppu.mask = disabled_mask;

    // Advance 3 dots with old mask still effective
    for (0..3) |_| {
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
        try testing.expect(ppu.getEffectiveMask().show_bg);
    }

    // Dot 3: Now disabled
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(!ppu.getEffectiveMask().show_bg);
}

test "PPUMASK: Greyscale mode delay" {
    var ppu = PpuState{};

    // Initialize with greyscale disabled
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = PpuMask{};
    }
    ppu.mask_delay_index = 0;

    try testing.expect(!ppu.getEffectiveMask().greyscale);

    // Enable greyscale
    ppu.mask = PpuMask{ .greyscale = true };

    // Should not take effect for 3 dots
    for (0..3) |_| {
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
        try testing.expect(!ppu.getEffectiveMask().greyscale);
    }

    // Dot 3: Now enabled
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(ppu.getEffectiveMask().greyscale);
}

test "PPUMASK: Emphasis bits delay" {
    var ppu = PpuState{};

    // Initialize with no emphasis
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = PpuMask{};
    }
    ppu.mask_delay_index = 0;

    try testing.expect(!ppu.getEffectiveMask().emphasize_red);

    // Enable red emphasis
    ppu.mask = PpuMask{ .emphasize_red = true };

    // Should not take effect for 3 dots
    for (0..3) |_| {
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
        try testing.expect(!ppu.getEffectiveMask().emphasize_red);
    }

    // Dot 3: Now enabled
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(ppu.getEffectiveMask().emphasize_red);
}

test "PPUMASK: Circular buffer wrapping" {
    var ppu = PpuState{};

    // Test that circular buffer wraps correctly at index 4
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = PpuMask{};
    }
    ppu.mask_delay_index = 3; // Start near wrap point

    // Enable rendering
    ppu.mask = PpuMask{ .show_bg = true };

    // Write at index 3
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1; // Should wrap to 0
    try testing.expectEqual(@as(u2, 0), ppu.mask_delay_index);

    // Effective mask should still be disabled (looking back 3 indices)
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Continue filling with enabled state
    for (0..3) |_| {
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
    }

    // After wrapping and filling, effective mask should be enabled
    try testing.expect(ppu.getEffectiveMask().show_bg);
}

test "PPUMASK: Multiple rapid changes" {
    var ppu = PpuState{};

    // Initialize disabled
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = PpuMask{};
    }
    ppu.mask_delay_index = 0;

    // Rapid toggle: OFF -> ON -> OFF -> ON
    const states = [_]bool{ false, true, false, true };
    for (states) |enable| {
        ppu.mask = PpuMask{ .show_bg = enable };
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
    }

    // After 4 rapid changes, effective mask should show first state (OFF)
    // because we're looking 3 indices back
    try testing.expect(!ppu.getEffectiveMask().show_bg);

    // Advance one more
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;

    // Now should show second state (ON)
    try testing.expect(ppu.getEffectiveMask().show_bg);
}

test "PPUMASK: Show left 8 pixels delay" {
    var ppu = PpuState{};

    // Initialize with left 8 pixels disabled
    for (0..4) |i| {
        ppu.mask_delay_buffer[i] = PpuMask{ .show_bg = true };
    }
    ppu.mask_delay_index = 0;

    try testing.expect(!ppu.getEffectiveMask().show_sprites_left);

    // Enable left 8 pixels for sprites
    ppu.mask = PpuMask{
        .show_bg = true,
        .show_sprites_left = true,
    };

    // Should not take effect for 3 dots
    for (0..3) |_| {
        ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
        ppu.mask_delay_index +%= 1;
        try testing.expect(!ppu.getEffectiveMask().show_sprites_left);
    }

    // Dot 3: Now enabled
    ppu.mask_delay_buffer[ppu.mask_delay_index] = ppu.mask;
    ppu.mask_delay_index +%= 1;
    try testing.expect(ppu.getEffectiveMask().show_sprites_left);
}
