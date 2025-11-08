//! Super Mario Bros Execution Flow Diagnostic Tool
//!
//! This tool analyzes the execution flow of Super Mario Bros to identify
//! why it crashes at frame 4 with PC=$FFFE (IRQ vector address).

const std = @import("std");
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;
const Cpu = RAMBO.Cpu;
const decode = Cpu.decode;

const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;
const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

/// Disassemble instruction at given address
fn disassemble(state: *EmulationState, address: u16) void {
    const opcode = state.busRead(address);
    const info = decode.OPCODE_TABLE[opcode];

    std.debug.print("${X:0>4}:  {X:0>2} ", .{ address, opcode });

    // Read operand bytes based on addressing mode
    const operand_bytes: u16 = switch (info.mode) {
        .implied, .accumulator => 0,
        .immediate, .zero_page, .zero_page_x, .zero_page_y, .indexed_indirect, .indirect_indexed, .relative => 1,
        .absolute, .absolute_x, .absolute_y, .indirect => 2,
    };

    var i: u16 = 1;
    while (i <= operand_bytes) : (i += 1) {
        const byte = state.busRead(address +% i);
        std.debug.print("{X:0>2} ", .{byte});
    }

    // Pad hex display
    var padding: usize = 3 - operand_bytes;
    while (padding > 0) : (padding -= 1) {
        std.debug.print("   ", .{});
    }

    std.debug.print(" {s} ", .{info.mnemonic});

    // Format operand
    switch (info.mode) {
        .implied => {},
        .accumulator => std.debug.print("A", .{}),
        .immediate => {
            const val = state.busRead(address +% 1);
            std.debug.print("#${X:0>2}", .{val});
        },
        .zero_page => {
            const val = state.busRead(address +% 1);
            std.debug.print("${X:0>2}", .{val});
        },
        .zero_page_x => {
            const val = state.busRead(address +% 1);
            std.debug.print("${X:0>2},X", .{val});
        },
        .zero_page_y => {
            const val = state.busRead(address +% 1);
            std.debug.print("${X:0>2},Y", .{val});
        },
        .absolute => {
            const lo = state.busRead(address +% 1);
            const hi = state.busRead(address +% 2);
            const addr = (@as(u16, hi) << 8) | lo;
            std.debug.print("${X:0>4}", .{addr});
        },
        .absolute_x => {
            const lo = state.busRead(address +% 1);
            const hi = state.busRead(address +% 2);
            const addr = (@as(u16, hi) << 8) | lo;
            std.debug.print("${X:0>4},X", .{addr});
        },
        .absolute_y => {
            const lo = state.busRead(address +% 1);
            const hi = state.busRead(address +% 2);
            const addr = (@as(u16, hi) << 8) | lo;
            std.debug.print("${X:0>4},Y", .{addr});
        },
        .indirect => {
            const lo = state.busRead(address +% 1);
            const hi = state.busRead(address +% 2);
            const addr = (@as(u16, hi) << 8) | lo;
            std.debug.print("(${X:0>4})", .{addr});
        },
        .indexed_indirect => {
            const val = state.busRead(address +% 1);
            std.debug.print("(${X:0>2},X)", .{val});
        },
        .indirect_indexed => {
            const val = state.busRead(address +% 1);
            std.debug.print("(${X:0>2}),Y", .{val});
        },
        .relative => {
            const offset = state.busRead(address +% 1);
            const signed_offset = @as(i8, @bitCast(offset));
            const target = @as(i32, address) + 2 + signed_offset;
            std.debug.print("${X:0>4}", .{@as(u16, @intCast(target & 0xFFFF))});
        },
    }

    if (info.unofficial) {
        std.debug.print(" [UNOFFICIAL]", .{});
    }

    std.debug.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Super Mario Bros Execution Flow Diagnostic ===\n\n", .{});

    // Load ROM
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        std.debug.print("ERROR: Failed to load ROM: {}\n", .{err});
        return;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.power_on();

    // Read interrupt vectors
    const nmi_vector = state.busRead16(0xFFFA);
    const reset_vector = state.busRead16(0xFFFC);
    const irq_vector = state.busRead16(0xFFFE);

    std.debug.print("Interrupt Vectors:\n", .{});
    std.debug.print("  NMI:   ${X:0>4}\n", .{nmi_vector});
    std.debug.print("  RESET: ${X:0>4}\n", .{reset_vector});
    std.debug.print("  IRQ:   ${X:0>4}\n", .{irq_vector});
    std.debug.print("\n", .{});

    // Disassemble code at reset vector
    std.debug.print("Code at RESET vector (${X:0>4}):\n", .{reset_vector});
    var addr = reset_vector;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        disassemble(&state, addr);
        const opcode = state.busRead(addr);
        const info = decode.OPCODE_TABLE[opcode];
        const operand_bytes: u16 = switch (info.mode) {
            .implied, .accumulator => 0,
            .immediate, .zero_page, .zero_page_x, .zero_page_y, .indexed_indirect, .indirect_indexed, .relative => 1,
            .absolute, .absolute_x, .absolute_y, .indirect => 2,
        };
        addr +%= 1 + operand_bytes;
    }
    std.debug.print("\n", .{});

    // Run emulation with detailed tracking
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    std.debug.print("=== Execution Trace (Frames 0-10) ===\n\n", .{});

    var frame: usize = 0;
    var last_pc = state.cpu.pc;

    // Track PCs for each frame
    var frame_pcs = try std.ArrayList(u16).initCapacity(allocator, 10);
    defer frame_pcs.deinit(allocator);

    while (frame < 10) {
        std.debug.print("--- Frame {d} START (PC=${X:0>4}) ---\n", .{ frame, state.cpu.pc });

        // Disassemble current instruction
        std.debug.print("Current instruction: ", .{});
        disassemble(&state, state.cpu.pc);

        // Show CPU state
        std.debug.print("CPU: A=${X:0>2} X=${X:0>2} Y=${X:0>2} SP=${X:0>2} P=${X:0>2}\n", .{ state.cpu.a, state.cpu.x, state.cpu.y, state.cpu.sp, @as(u8, @bitCast(state.cpu.p)) });

        try frame_pcs.append(allocator, state.cpu.pc);

        state.ppu.framebuffer = &framebuffer;
        const cycles = state.emulateFrame();

        // Check if PC changed dramatically
        if (state.cpu.pc == irq_vector or state.cpu.pc == 0xFFFE) {
            std.debug.print("\n!!! CRITICAL: PC jumped to IRQ vector area! !!!\n", .{});
            std.debug.print("    Previous PC: ${X:0>4}\n", .{last_pc});
            std.debug.print("    Current PC:  ${X:0>4}\n", .{state.cpu.pc});
            std.debug.print("    IRQ vector:  ${X:0>4}\n", .{irq_vector});

            // Show what's at this address
            std.debug.print("\nBytes at current PC:\n", .{});
            var j: u16 = 0;
            while (j < 16) : (j += 1) {
                const byte = state.busRead(state.cpu.pc +% j);
                std.debug.print("  ${X:0>4}: {X:0>2}\n", .{ state.cpu.pc +% j, byte });
            }

            // Show interrupt state
            std.debug.print("\nInterrupt state:\n", .{});
            std.debug.print("  CPU irq_line: {}\n", .{state.cpu.irq_line});
            std.debug.print("  CPU nmi_line: {}\n", .{state.cpu.nmi_line});
            std.debug.print("  CPU p.interrupt: {}\n", .{state.cpu.p.interrupt});
            std.debug.print("  APU frame_irq_flag: {}\n", .{state.apu.frame_irq_flag});
            std.debug.print("  APU dmc_irq_flag: {}\n", .{state.apu.dmc_irq_flag});
            std.debug.print("  APU irq_inhibit: {}\n", .{state.apu.irq_inhibit});

            break;
        }

        std.debug.print("--- Frame {d} END (cycles={d}, PC=${X:0>4}) ---\n\n", .{ frame, cycles, state.cpu.pc });

        last_pc = state.cpu.pc;
        frame += 1;
    }

    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Frames emulated: {d}\n", .{frame});
    std.debug.print("Final PC: ${X:0>4}\n", .{state.cpu.pc});
    std.debug.print("\nPC history:\n", .{});
    for (frame_pcs.items, 0..) |pc, idx| {
        std.debug.print("  Frame {d}: ${X:0>4}\n", .{ idx, pc });
    }
}
