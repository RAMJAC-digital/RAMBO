//! Hardware constants for 6502 CPU emulation
//!
//! This module contains all magic numbers and hardware-specific addresses
//! used throughout the CPU emulator. Using named constants improves code
//! readability and makes the codebase easier to maintain.

// ============================================================================
// Memory Map Constants
// ============================================================================

/// Stack page base address (page 1: $0100-$01FF)
pub const STACK_BASE: u16 = 0x0100;

/// Zero page base address (page 0: $0000-$00FF)
pub const ZERO_PAGE_BASE: u16 = 0x0000;

/// Page size in bytes (256 bytes per page)
pub const PAGE_SIZE: u16 = 0x100;

/// Page mask for extracting high byte (page number)
pub const PAGE_MASK: u16 = 0xFF00;

/// Offset mask for extracting low byte (page offset)
pub const OFFSET_MASK: u16 = 0x00FF;

// ============================================================================
// Interrupt Vector Addresses
// ============================================================================

/// NMI (Non-Maskable Interrupt) vector address - low byte
pub const NMI_VECTOR_LOW: u16 = 0xFFFA;

/// NMI (Non-Maskable Interrupt) vector address - high byte
pub const NMI_VECTOR_HIGH: u16 = 0xFFFB;

/// Reset vector address - low byte
pub const RESET_VECTOR_LOW: u16 = 0xFFFC;

/// Reset vector address - high byte
pub const RESET_VECTOR_HIGH: u16 = 0xFFFD;

/// IRQ/BRK (Interrupt Request/Break) vector address - low byte
pub const IRQ_VECTOR_LOW: u16 = 0xFFFE;

/// IRQ/BRK (Interrupt Request/Break) vector address - high byte
pub const IRQ_VECTOR_HIGH: u16 = 0xFFFF;

// ============================================================================
// Processor Status Flag Bit Masks
// ============================================================================

/// Carry flag bit mask (bit 0)
pub const FLAG_CARRY: u8 = 0x01;

/// Zero flag bit mask (bit 1)
pub const FLAG_ZERO: u8 = 0x02;

/// Interrupt disable flag bit mask (bit 2)
pub const FLAG_INTERRUPT: u8 = 0x04;

/// Decimal mode flag bit mask (bit 3)
/// Note: NES CPU ignores this flag, but it can still be set/cleared
pub const FLAG_DECIMAL: u8 = 0x08;

/// Break flag bit mask (bit 4)
/// Note: This flag only exists in pushed status, not as a real flag
pub const FLAG_BREAK: u8 = 0x10;

/// Unused flag bit mask (bit 5)
/// Note: This bit always reads as 1
pub const FLAG_UNUSED: u8 = 0x20;

/// Overflow flag bit mask (bit 6)
pub const FLAG_OVERFLOW: u8 = 0x40;

/// Negative flag bit mask (bit 7)
pub const FLAG_NEGATIVE: u8 = 0x80;

// ============================================================================
// Bit Position Constants
// ============================================================================

/// Bit 7 mask (used for negative flag checking)
pub const BIT_7: u8 = 0x80;

/// Bit 6 mask (used for overflow flag and BIT instruction)
pub const BIT_6: u8 = 0x40;

/// Bit 0 mask
pub const BIT_0: u8 = 0x01;

// ============================================================================
// Initial CPU State Values
// ============================================================================

/// Initial stack pointer value after reset
pub const INITIAL_STACK_POINTER: u8 = 0xFD;

/// Initial processor status after reset (interrupt disable set)
pub const INITIAL_STATUS: u8 = FLAG_UNUSED | FLAG_INTERRUPT;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "memory map constants" {
    try testing.expectEqual(@as(u16, 0x0100), STACK_BASE);
    try testing.expectEqual(@as(u16, 0x0000), ZERO_PAGE_BASE);
    try testing.expectEqual(@as(u16, 0x100), PAGE_SIZE);
    try testing.expectEqual(@as(u16, 0xFF00), PAGE_MASK);
    try testing.expectEqual(@as(u16, 0x00FF), OFFSET_MASK);
}

test "vector addresses" {
    try testing.expectEqual(@as(u16, 0xFFFA), NMI_VECTOR_LOW);
    try testing.expectEqual(@as(u16, 0xFFFB), NMI_VECTOR_HIGH);
    try testing.expectEqual(@as(u16, 0xFFFC), RESET_VECTOR_LOW);
    try testing.expectEqual(@as(u16, 0xFFFD), RESET_VECTOR_HIGH);
    try testing.expectEqual(@as(u16, 0xFFFE), IRQ_VECTOR_LOW);
    try testing.expectEqual(@as(u16, 0xFFFF), IRQ_VECTOR_HIGH);
}

test "flag bit masks are unique and correct" {
    try testing.expectEqual(@as(u8, 0x01), FLAG_CARRY);
    try testing.expectEqual(@as(u8, 0x02), FLAG_ZERO);
    try testing.expectEqual(@as(u8, 0x04), FLAG_INTERRUPT);
    try testing.expectEqual(@as(u8, 0x08), FLAG_DECIMAL);
    try testing.expectEqual(@as(u8, 0x10), FLAG_BREAK);
    try testing.expectEqual(@as(u8, 0x20), FLAG_UNUSED);
    try testing.expectEqual(@as(u8, 0x40), FLAG_OVERFLOW);
    try testing.expectEqual(@as(u8, 0x80), FLAG_NEGATIVE);

    // Verify flags don't overlap
    const all_flags = FLAG_CARRY | FLAG_ZERO | FLAG_INTERRUPT | FLAG_DECIMAL |
                     FLAG_BREAK | FLAG_UNUSED | FLAG_OVERFLOW | FLAG_NEGATIVE;
    try testing.expectEqual(@as(u8, 0xFF), all_flags);
}

test "initial values" {
    try testing.expectEqual(@as(u8, 0xFD), INITIAL_STACK_POINTER);
    try testing.expectEqual(@as(u8, FLAG_UNUSED | FLAG_INTERRUPT), INITIAL_STATUS);
}

test "page calculations" {
    const addr: u16 = 0x1234;
    const page = addr & PAGE_MASK;
    const offset = addr & OFFSET_MASK;

    try testing.expectEqual(@as(u16, 0x1200), page);
    try testing.expectEqual(@as(u16, 0x0034), offset);

    // Verify reconstruction
    try testing.expectEqual(addr, page | offset);
}

test "page boundary detection" {
    const addr1: u16 = 0x10FF;
    const addr2: u16 = 0x1100;

    const same_page = (addr1 & PAGE_MASK) == (addr1 & PAGE_MASK);
    const diff_page = (addr1 & PAGE_MASK) != (addr2 & PAGE_MASK);

    try testing.expect(same_page);
    try testing.expect(diff_page);
}
