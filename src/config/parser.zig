/// Stateless KDL Parser for RAMBO Configuration
///
/// Design principles (inspired by zzt-backup pattern):
/// - Pure function: takes content, returns Config
/// - No global state
/// - Graceful error handling (never crash, use defaults)
/// - Safety limits to prevent infinite loops
/// - Thread-safe (stateless)

const std = @import("std");
const ConfigModule = @import("Config.zig");
const Config = ConfigModule.Config;

/// Safety limits to prevent infinite loops or excessive processing
const MAX_LINES: u32 = 1000;
const MAX_LINE_LENGTH: u32 = 1024;

/// Parse KDL-style configuration from string content
/// Returns a fully initialized Config with arena allocator
/// Never fails - uses default values for malformed input
pub fn parseKdl(content: []const u8, allocator: std.mem.Allocator) !Config {
    // Create config with default values and arena allocator
    var config = Config.init(allocator);
    errdefer config.deinit();

    // Gracefully handle empty content
    if (content.len == 0) {
        return config;
    }

    var current_section: ?Section = null;
    var line_count: u32 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |raw_line| {
        line_count += 1;
        if (line_count > MAX_LINES) {
            // Silently truncate if too many lines
            break;
        }

        // Safety check for line length
        if (raw_line.len > MAX_LINE_LENGTH) {
            // Skip excessively long lines
            continue;
        }

        // Clean line: remove whitespace and handle comments
        var line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (line.len == 0) continue;

        // Skip comment-only lines
        if (line.len >= 2 and std.mem.startsWith(u8, line, "//")) {
            continue;
        }

        // Strip inline comments
        if (std.mem.indexOf(u8, line, "//")) |pos| {
            line = std.mem.trimRight(u8, line[0..pos], &std.ascii.whitespace);
            if (line.len == 0) continue;
        }

        // Detect section start (e.g., "cpu {")
        if (std.mem.indexOf(u8, line, "{")) |_| {
            current_section = parseSectionHeader(line);
            continue;
        }

        // Detect section end
        if (std.mem.eql(u8, line, "}")) {
            current_section = null;
            continue;
        }

        // Parse key-value pairs
        if (current_section) |section| {
            parseSectionKeyValue(&config, section, line) catch {
                // Silently ignore parsing errors, use defaults
            };
        } else {
            parseTopLevelKeyValue(&config, line) catch {
                // Silently ignore parsing errors, use defaults
            };
        }
    }

    return config;
}

/// Configuration sections
const Section = enum {
    cpu,
    unstable_opcodes,
    ppu,
    cic,
    controllers,
    video,
    audio,
    input,

    fn fromString(s: []const u8) ?Section {
        if (std.mem.eql(u8, s, "cpu")) return .cpu;
        if (std.mem.eql(u8, s, "unstable_opcodes")) return .unstable_opcodes;
        if (std.mem.eql(u8, s, "ppu")) return .ppu;
        if (std.mem.eql(u8, s, "cic")) return .cic;
        if (std.mem.eql(u8, s, "controllers")) return .controllers;
        if (std.mem.eql(u8, s, "video")) return .video;
        if (std.mem.eql(u8, s, "audio")) return .audio;
        if (std.mem.eql(u8, s, "input")) return .input;
        return null;
    }
};

/// Parse section header (e.g., "cpu {" -> Section.cpu)
fn parseSectionHeader(line: []const u8) ?Section {
    var parts = std.mem.splitScalar(u8, line, ' ');
    const section_name = std.mem.trim(u8, parts.next() orelse return null, &std.ascii.whitespace);
    return Section.fromString(section_name);
}

/// Parse top-level key-value (e.g., console "NES-PAL")
fn parseTopLevelKeyValue(config: *Config, line: []const u8) !void {
    var parts = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
    const key = parts.next() orelse return;
    const value_raw = parts.next() orelse return;
    const value = stripQuotes(value_raw);

    if (std.mem.eql(u8, key, "console")) {
        config.console = ConfigModule.ConsoleVariant.fromString(value) catch {
            // Invalid console variant, keep default
            return;
        };
    }
}

/// Parse key-value within a section
fn parseSectionKeyValue(config: *Config, section: Section, line: []const u8) !void {
    var parts = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
    const key = parts.next() orelse return;
    const value_raw = parts.next() orelse return;
    const value = stripQuotes(value_raw);

    switch (section) {
        .cpu => try parseCpuKeyValue(config, key, value),
        .unstable_opcodes => try parseUnstableOpcodesKeyValue(config, key, value),
        .ppu => try parsePpuKeyValue(config, key, value),
        .cic => try parseCicKeyValue(config, key, value),
        .controllers => try parseControllersKeyValue(config, key, value),
        .video => try parseVideoKeyValue(config, key, value),
        .audio => try parseAudioKeyValue(config, key, value),
        .input => try parseInputKeyValue(config, key, value),
    }
}

/// Parse CPU section key-value
fn parseCpuKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "variant")) {
        config.cpu.variant = try ConfigModule.CpuVariant.fromString(value);
    } else if (std.mem.eql(u8, key, "region")) {
        config.cpu.region = try ConfigModule.VideoRegion.fromString(value);
    } else if (std.mem.eql(u8, key, "unstable_opcodes")) {
        // Nested section indicator (handled separately)
    }
    // Unknown keys silently ignored
}

/// Parse unstable opcodes section key-value
fn parseUnstableOpcodesKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "sha_behavior")) {
        config.cpu.unstable_opcodes.sha_behavior = try ConfigModule.SHABehavior.fromString(value);
    } else if (std.mem.eql(u8, key, "lxa_magic")) {
        config.cpu.unstable_opcodes.lxa_magic = try std.fmt.parseInt(u8, value, 0);
    }
}

/// Parse PPU section key-value
fn parsePpuKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "variant")) {
        config.ppu.variant = try ConfigModule.PpuVariant.fromString(value);
    } else if (std.mem.eql(u8, key, "region")) {
        config.ppu.region = try ConfigModule.VideoRegion.fromString(value);
    } else if (std.mem.eql(u8, key, "accuracy")) {
        config.ppu.accuracy = try ConfigModule.AccuracyLevel.fromString(value);
    }
}

/// Parse CIC section key-value
fn parseCicKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "variant")) {
        config.cic.variant = try ConfigModule.CicVariant.fromString(value);
    } else if (std.mem.eql(u8, key, "enabled")) {
        config.cic.enabled = parseBool(value);
    } else if (std.mem.eql(u8, key, "emulation")) {
        config.cic.emulation = try ConfigModule.CicEmulation.fromString(value);
    }
}

/// Parse controllers section key-value
fn parseControllersKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "type")) {
        config.controllers.type = try ConfigModule.ControllerType.fromString(value);
    }
}

/// Parse video section key-value
fn parseVideoKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "backend")) {
        config.video.backend = try ConfigModule.VideoBackend.fromString(value);
    } else if (std.mem.eql(u8, key, "vsync")) {
        config.video.vsync = parseBool(value);
    } else if (std.mem.eql(u8, key, "scale")) {
        config.video.scale = try std.fmt.parseInt(u8, value, 10);
    }
}

/// Parse audio section key-value
fn parseAudioKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) {
        config.audio.enabled = parseBool(value);
    } else if (std.mem.eql(u8, key, "sample_rate")) {
        config.audio.sample_rate = try std.fmt.parseInt(u32, value, 10);
    }
}

/// Parse input section key-value
fn parseInputKeyValue(config: *Config, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "light_gun_enabled")) {
        config.input.light_gun_enabled = parseBool(value);
    }
}

/// Parse boolean value (supports: true/false, yes/no, 1/0, on/off)
fn parseBool(s: []const u8) bool {
    return std.ascii.eqlIgnoreCase(s, "true") or
        std.mem.eql(u8, s, "1") or
        std.ascii.eqlIgnoreCase(s, "yes") or
        std.ascii.eqlIgnoreCase(s, "on");
}

/// Strip surrounding quotes from string
fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if (s[0] == '"' and s[s.len - 1] == '"') {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}
