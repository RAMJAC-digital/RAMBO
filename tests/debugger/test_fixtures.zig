//! Shared test fixtures for debugger tests
//!
//! Provides common setup functions used across all debugger test files.

const std = @import("std");
const RAMBO = @import("RAMBO");

const Config = RAMBO.Config.Config;
const EmulationState = RAMBO.EmulationState.EmulationState;

/// Create a test EmulationState with distinctive initial values
pub fn createTestState(config: *const Config) EmulationState {
    var state = EmulationState.init(config);

    // Set distinctive state for debugging
    state.cpu.pc = 0x8000;
    state.cpu.sp = 0xFD;
    state.cpu.a = 0x42;
    state.clock.ppu_cycles = (10 * 89342) + (100 * 341); // Frame 10, scanline 100

    return state;
}
