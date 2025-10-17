const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const KeyboardMapper = RAMBO.KeyboardMapper;
const ControllerInputMailbox = RAMBO.Mailboxes.ControllerInputMailbox;

fn expectButtonState(mapper: *KeyboardMapper, mailbox: *ControllerInputMailbox, expected: struct {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
}) !void {
    mailbox.postController1(mapper.getState());
    const input = mailbox.getInput();
    try testing.expectEqual(expected.a, input.controller1.a);
    try testing.expectEqual(expected.b, input.controller1.b);
    try testing.expectEqual(expected.select, input.controller1.select);
    try testing.expectEqual(expected.start, input.controller1.start);
    try testing.expectEqual(expected.up, input.controller1.up);
    try testing.expectEqual(expected.down, input.controller1.down);
    try testing.expectEqual(expected.left, input.controller1.left);
    try testing.expectEqual(expected.right, input.controller1.right);
}

test "Keyboard input updates controller mailbox state" {
    var mapper = KeyboardMapper{};
    var mailbox = ControllerInputMailbox.init(testing.allocator);
    defer mailbox.deinit();

    try expectButtonState(&mapper, &mailbox, .{});

    mapper.keyPress(KeyboardMapper.Keymap.KEY_Z); // B button
    try expectButtonState(&mapper, &mailbox, .{ .b = true });

    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    try expectButtonState(&mapper, &mailbox, .{ .b = true, .up = true });

    mapper.keyRelease(KeyboardMapper.Keymap.KEY_Z);
    try expectButtonState(&mapper, &mailbox, .{ .up = true });

    mapper.keyPress(KeyboardMapper.Keymap.KEY_DOWN);
    try expectButtonState(&mapper, &mailbox, .{}); // sanitize clears opposing directions
}
