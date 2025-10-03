const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.CpuType;
const Bus = RAMBO.BusType;

test "Simple NOP execution trace" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: NOP at $8000
    bus.ram[0] = 0xEA; // NOP opcode
    cpu.pc = 0x8000;

    std.debug.print("\n=== NOP Execution Trace ===\n", .{});
    std.debug.print("Initial: PC=0x{X:0>4}, state={s}, cycle={}\n", .{ cpu.pc, @tagName(cpu.state), cpu.cycle_count });

    // Cycle 1
    const c1 = cpu.tick(&bus);
    std.debug.print("After tick 1: PC=0x{X:0>4}, state={s}, cycle={}, complete={}\n", .{ cpu.pc, @tagName(cpu.state), cpu.cycle_count, c1 });

    // Cycle 2
    const c2 = cpu.tick(&bus);
    std.debug.print("After tick 2: PC=0x{X:0>4}, state={s}, cycle={}, complete={}\n", .{ cpu.pc, @tagName(cpu.state), cpu.cycle_count, c2 });

    try testing.expect(c2); // Should be complete after 2 cycles
}
