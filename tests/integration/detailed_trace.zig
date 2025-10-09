const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const AnyCartridge = RAMBO.AnyCartridge;
const loadRom = RAMBO.loadInesRom;

test "Detailed trace of Bomberman $2002 polling" {
    const rom_path = "/home/colin/Development/RAMBO/tests/data/Bomberman/Bomberman (USA).nes";
    const rom_data = try std.fs.cwd().readFileAlloc(testing.allocator, rom_path, 10 * 1024 * 1024);
    defer testing.allocator.free(rom_data);

    const cart = try loadRom(testing.allocator, rom_data);

    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.reset();
    state.ppu.warmup_complete = true;

    std.debug.print("\n\n=== BOMBERMAN DETAILED TRACE ===\n", .{});
    std.debug.print("Reset PC: 0x{X:0>4}\n\n", .{state.cpu.pc});

    var cycle: usize = 0;
    const max_cycles: usize = 200_000;
    var last_pc: u16 = 0;
    var same_pc_count: usize = 0;
    var vblank_set_cycle: ?usize = null;
    var vblank_cleared_cycle: ?usize = null;

    while (cycle < max_cycles) : (cycle += 1) {
        const scanline_before = state.clock.scanline();
        const dot_before = state.clock.dot();
        const pc_before = state.cpu.pc;
        const cpu_state_before = state.cpu.state;
        const vblank_before = state.ppu.status.vblank;
        const is_cpu_tick = state.clock.isCpuTick();

        // Execute one tick
        state.tick();

        const scanline_after = state.clock.scanline();
        const dot_after = state.clock.dot();
        const vblank_after = state.ppu.status.vblank;

        // Track VBlank transitions
        if (!vblank_before and vblank_after) {
            vblank_set_cycle = cycle;
            std.debug.print("\n>>> VBlank SET at cycle {}\n", .{cycle});
            std.debug.print("    Position BEFORE tick: {}.{}\n", .{scanline_before, dot_before});
            std.debug.print("    Position AFTER tick: {}.{}\n", .{scanline_after, dot_after});
            std.debug.print("    CPU tick: {}\n", .{is_cpu_tick});
            std.debug.print("    PC: 0x{X:0>4}, State: {s}\n\n", .{pc_before, @tagName(cpu_state_before)});
        }

        if (vblank_before and !vblank_after) {
            vblank_cleared_cycle = cycle;
            std.debug.print("\n<<< VBlank CLEARED at cycle {}\n", .{cycle});
            std.debug.print("    Position BEFORE tick: {}.{}\n", .{scanline_before, dot_before});
            std.debug.print("    Position AFTER tick: {}.{}\n", .{scanline_after, dot_after});
            std.debug.print("    CPU tick: {}\n", .{is_cpu_tick});
            std.debug.print("    PC: 0x{X:0>4}, State: {s}\n", .{pc_before, @tagName(cpu_state_before)});

            // This is KEY - VBlank cleared means $2002 was read
            // What instruction caused this?
            std.debug.print("    CRITICAL: VBlank cleared - $2002 was read!\n\n");
        }

        // Detect hang
        if (pc_before == last_pc and pc_before != 0) {
            same_pc_count += 1;
            if (same_pc_count == 50) {
                std.debug.print("\n!!! HUNG at PC 0x{X:0>4} after {} cycles !!!\n", .{pc_before, cycle});
                std.debug.print("Position: {}.{}\n", .{scanline_after, dot_after});
                std.debug.print("VBlank: {}\n", .{vblank_after});
                std.debug.print("CPU State: {s}\n", .{@tagName(state.cpu.state)});

                const opcode = state.peekMemory(pc_before);
                std.debug.print("Opcode: 0x{X:0>2}\n", .{opcode});

                if (vblank_set_cycle) |set_c| {
                    std.debug.print("\nVBlank was set at cycle {} ({} cycles ago)\n", .{set_c, cycle - set_c});
                } else {
                    std.debug.print("\nVBlank was NEVER set!\n", .{});
                }

                if (vblank_cleared_cycle) |clear_c| {
                    std.debug.print("VBlank was cleared at cycle {} ({} cycles ago)\n", .{clear_c, cycle - clear_c});
                } else {
                    std.debug.print("VBlank was NEVER cleared (never read $2002)!\n", .{});
                }

                break;
            }
        } else {
            same_pc_count = 0;
        }

        last_pc = pc_before;
    }

    // Fail test to show output
    try testing.expect(false);
}
