const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.CpuType;
const Bus = RAMBO.BusType;

test "NOP immediate - cycle trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Use RAM address since cartridge not implemented yet
    bus.ram[0] = 0x80; // Unofficial NOP immediate
    bus.ram[1] = 0x42;
    cpu.pc = 0x0000; // Start in RAM

    std.debug.print("\n=== NOP Immediate (0x80) Trace ===\n", .{});
    std.debug.print("Expected: 2 cycles total\n", .{});

    var cycle: usize = 0;
    while (cycle < 5) : (cycle += 1) {
        const state_before = cpu.state;
        const pc_before = cpu.pc;
        const complete = cpu.tick(&bus);

        std.debug.print("Cycle {}: state={s} -> {s}, PC=0x{X:0>4} -> 0x{X:0>4}, complete={}\n",
            .{cycle + 1, @tagName(state_before), @tagName(cpu.state), pc_before, cpu.pc, complete});

        if (complete) break;
    }
}

test "LDA immediate - cycle trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xA9; // LDA immediate
    bus.ram[1] = 0x42;
    cpu.pc = 0x0000;

    std.debug.print("\n=== LDA Immediate (0xA9) Trace ===\n", .{});
    std.debug.print("Expected: 2 cycles total\n", .{});

    var cycle: usize = 0;
    while (cycle < 5) : (cycle += 1) {
        const state_before = cpu.state;
        const pc_before = cpu.pc;
        const complete = cpu.tick(&bus);

        std.debug.print("Cycle {}: state={s} -> {s}, PC=0x{X:0>4} -> 0x{X:0>4}, A=0x{X:0>2}, complete={}\n",
            .{cycle + 1, @tagName(state_before), @tagName(cpu.state), pc_before, cpu.pc, cpu.a, complete});

        if (complete) break;
    }
}

test "LDA zero page - cycle trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xA5; // LDA zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x55;
    cpu.pc = 0x0000;

    std.debug.print("\n=== LDA Zero Page (0xA5) Trace ===\n", .{});
    std.debug.print("Expected: 3 cycles total\n", .{});

    var cycle: usize = 0;
    while (cycle < 5) : (cycle += 1) {
        const state_before = cpu.state;
        const complete = cpu.tick(&bus);

        std.debug.print("Cycle {}: state={s} -> {s}, PC=0x{X:0>4}, A=0x{X:0>2}, complete={}\n",
            .{cycle + 1, @tagName(state_before), @tagName(cpu.state), cpu.pc, cpu.a, complete});

        if (complete) break;
    }
}

test "LDA absolute,X - cycle trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xBD; // LDA absolute,X
    bus.ram[1] = 0x30;
    bus.ram[2] = 0x01;
    bus.ram[0x135] = 0x99;
    cpu.pc = 0x0000;
    cpu.x = 0x05;

    std.debug.print("\n=== LDA Absolute,X (0xBD) Trace ===\n", .{});
    std.debug.print("Expected: 4 cycles (no page cross)\n", .{});

    var cycle: usize = 0;
    while (cycle < 6) : (cycle += 1) {
        const state_before = cpu.state;
        const mode_before = cpu.address_mode;
        const complete = cpu.tick(&bus);

        std.debug.print("Cycle {}: state={s} -> {s}, mode={s}, PC=0x{X:0>4}, A=0x{X:0>2}, EA=0x{X:0>4}, complete={}\n",
            .{cycle + 1, @tagName(state_before), @tagName(cpu.state), @tagName(mode_before), cpu.pc, cpu.a, cpu.effective_address, complete});

        if (complete) break;
    }
}
