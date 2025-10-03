const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.CpuType;
const Bus = RAMBO.BusType;

test "ASL zero page - debug trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x06; // ASL zero page
    bus.ram[1] = 0x10; // Address $10
    bus.ram[0x10] = 0x42; // Value to shift
    cpu.pc = 0x0000;

    std.debug.print("\n=== ASL Zero Page Debug ===\n", .{});
    std.debug.print("Expected cycles: 5\n", .{});
    std.debug.print("Expected: Read original (0x42), Dummy write (0x42), Write result (0x84)\n\n", .{});

    for (0..6) |i| {
        const prev_val = bus.ram[0x10];
        const state_before = cpu.state;
        const inst_cycle = cpu.instruction_cycle;

        const complete = cpu.tick(&bus);

        const after_val = bus.ram[0x10];
        const changed = if (prev_val != after_val) "WRITE" else "     ";

        std.debug.print("Cycle {}: state={s:20} inst_cycle={} -> value @0x10: 0x{X:0>2} -> 0x{X:0>2} {s} complete={}\n",
            .{i + 1, @tagName(state_before), inst_cycle, prev_val, after_val, changed, complete});

        if (complete) break;
    }

    std.debug.print("\nFinal value: 0x{X:0>2}\n", .{bus.ram[0x10]});
}
