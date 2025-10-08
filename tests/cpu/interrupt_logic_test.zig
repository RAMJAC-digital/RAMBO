//! Unit tests for CpuLogic interrupt handling (pure functions)
//! Tests edge detection, level detection, masking, and state transitions

const std = @import("std");
const expect = std.testing.expect;

const RAMBO = @import("RAMBO");
const CpuLogic = RAMBO.Cpu.Logic;
const CpuState = RAMBO.Cpu.State.CpuState;
const InterruptType = RAMBO.Cpu.State.InterruptType;

test "CpuLogic: NMI edge detection - falling edge triggers" {
    var cpu = CpuLogic.init();

    // No NMI initially
    try expect(cpu.nmi_line == false);
    try expect(cpu.nmi_edge_detected == false);
    try expect(cpu.pending_interrupt == .none);

    // Check interrupts (no change)
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .none);

    // Assert NMI line (falling edge)
    cpu.nmi_line = true;
    CpuLogic.checkInterrupts(&cpu);

    // NMI should be pending
    try expect(cpu.pending_interrupt == .nmi);
    try expect(cpu.nmi_edge_detected == true);
}

test "CpuLogic: NMI edge - level held doesn't re-trigger" {
    var cpu = CpuLogic.init();

    // First edge: assert NMI line
    cpu.nmi_line = true;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .nmi);

    // Clear pending but leave line asserted
    cpu.pending_interrupt = .none;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .none); // No re-trigger

    // Clear line, then re-assert (new edge)
    cpu.nmi_line = false;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.nmi_edge_detected == false); // Edge cleared

    cpu.nmi_line = true;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .nmi); // New edge detected
    try expect(cpu.nmi_edge_detected == true);
}

test "CpuLogic: IRQ level detection - triggers while line high" {
    var cpu = CpuLogic.init();
    cpu.p.interrupt = false; // I flag clear (allow IRQ)

    // Assert IRQ line
    cpu.irq_line = true;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .irq);

    // IRQ is level-triggered, so it should trigger again if cleared
    cpu.pending_interrupt = .none;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .irq); // Re-triggers (level)
}

test "CpuLogic: IRQ masked by I flag" {
    var cpu = CpuLogic.init();
    cpu.p.interrupt = true; // I flag set (mask IRQ)

    // Assert IRQ line
    cpu.irq_line = true;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .none); // Blocked by I flag

    // Clear I flag
    cpu.p.interrupt = false;
    CpuLogic.checkInterrupts(&cpu);
    try expect(cpu.pending_interrupt == .irq); // Now triggers
}

test "CpuLogic: startInterruptSequence sets state correctly" {
    var cpu = CpuLogic.init();
    cpu.pending_interrupt = .nmi;

    CpuLogic.startInterruptSequence(&cpu);
    try expect(cpu.state == .interrupt_sequence);
    try expect(cpu.instruction_cycle == 0);
}
