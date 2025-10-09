//! APU Lookup Tables
//!
//! Contains constant lookup tables used by APU logic:
//! - DMC rate tables (NTSC/PAL)
//! - Length counter table

/// NTSC DMC rate table (timer periods in CPU cycles)
/// Indexed by bits 0-3 of $4010
/// Values represent how many CPU cycles between DMC samples
pub const DMC_RATE_TABLE_NTSC: [16]u16 = .{
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 84, 72, 54,
};

/// PAL DMC rate table (timer periods in CPU cycles)
/// Indexed by bits 0-3 of $4010
/// Values represent how many CPU cycles between DMC samples
pub const DMC_RATE_TABLE_PAL: [16]u16 = .{
    398, 354, 316, 298, 276, 236, 210, 198,
    176, 148, 132, 118, 98, 78, 66, 50,
};

/// Length counter lookup table (32 entries)
/// Indexed by bits 3-7 of $4003/$4007/$400B/$400F
/// Returns the number of half-frames before channel is silenced
/// Values sourced from NESDev wiki
pub const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,   // 0x00-0x07
   160,   8, 60, 10, 14, 12, 26, 14,   // 0x08-0x0F
    12,  16, 24, 18, 48, 20, 96, 22,   // 0x10-0x17
   192,  24, 72, 26, 16, 28, 32, 30,   // 0x18-0x1F
};
