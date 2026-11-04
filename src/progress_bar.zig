const std = @import("std");
const build_options = @import("config");
const theme = @import("theme.zig");

const bar_width: u8 = build_options.bar_width;

/// Render a single-color progress bar: [████████░░░░░░░░░░░░]
pub fn renderSingle(
    writer: anytype,
    fill_color: []const u8,
    pct: u8,
    cfg: ?*const theme.Config,
) !void {
    const active = cfg orelse &theme.active_config;
    const filled: u8 = @intCast((@as(u16, pct) * bar_width + 50) / 100);

    try writer.writeAll("[");
    try writer.writeAll(fill_color);
    for (0..filled) |_| try writer.writeAll(active.symbols.bar_filled);
    try writer.writeAll(active.palette.bar_empty_fg);
    for (0..bar_width - filled) |_| try writer.writeAll(active.symbols.bar_empty);
    try writer.writeAll(active.palette.reset);
    try writer.writeAll("]");
}

/// Render a dual-color progress bar: [██████████████░░░░░░]
/// Both segments use filled characters; the split shows the proportion of a vs b.
pub fn renderDual(
    writer: anytype,
    color_a: []const u8,
    color_b: []const u8,
    count_a: u64,
    count_b: u64,
    cfg: ?*const theme.Config,
) !void {
    const active = cfg orelse &theme.active_config;
    const total = count_a +| count_b;
    if (total == 0) return;

    const width_a: u8 = @intCast(@min(bar_width, (count_a *| bar_width +| total / 2) / total));
    const width_b: u8 = bar_width - width_a;

    try writer.writeAll("[");
    try writer.writeAll(color_a);
    for (0..width_a) |_| try writer.writeAll(active.symbols.bar_filled);
    try writer.writeAll(color_b);
    for (0..width_b) |_| try writer.writeAll(active.symbols.bar_filled);
    try writer.writeAll(active.palette.reset);
    try writer.writeAll("]");
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const TestWriter = struct {
    buf: [512]u8 = undefined,
    len: usize = 0,

    pub fn writeAll(self: *TestWriter, bytes: []const u8) !void {
        if (self.len + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    pub fn getWritten(self: *const TestWriter) []const u8 {
        return self.buf[0..self.len];
    }
};

test "renderSingle 0%" {
    var tw = TestWriter{};
    try renderSingle(&tw, "\x1b[34m", 0, null);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, out, "["));
    try std.testing.expect(std.mem.endsWith(u8, out, "]"));
}

test "renderSingle 100%" {
    var tw = TestWriter{};
    try renderSingle(&tw, "\x1b[34m", 100, null);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, out, "["));
}

test "renderDual equal split" {
    var tw = TestWriter{};
    try renderDual(&tw, "\x1b[32m", "\x1b[31m", 50, 50, null);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, out, "["));
    try std.testing.expect(std.mem.endsWith(u8, out, "]"));
}
