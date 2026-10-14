const std = @import("std");

/// Format a token count with human-readable suffix (K/M/G).
pub fn formatTokens(buf: []u8, tokens: u64) []const u8 {
    if (tokens >= 1_000_000_000) {
        return std.fmt.bufPrint(buf, "{d:.1}G", .{@as(f64, @floatFromInt(tokens)) / 1_000_000_000.0}) catch "?";
    } else if (tokens >= 1_000_000) {
        return std.fmt.bufPrint(buf, "{d:.1}M", .{@as(f64, @floatFromInt(tokens)) / 1_000_000.0}) catch "?";
    } else if (tokens >= 1_000) {
        return std.fmt.bufPrint(buf, "{d:.1}K", .{@as(f64, @floatFromInt(tokens)) / 1_000.0}) catch "?";
    } else {
        return std.fmt.bufPrint(buf, "{d}", .{tokens}) catch "?";
    }
}

/// Format milliseconds as "Xm Ys" or "Xs".
pub fn formatDuration(buf: []u8, ms: u64) []const u8 {
    const total_s = ms / 1000;
    if (total_s >= 60) {
        const mins = total_s / 60;
        const secs = total_s % 60;
        return std.fmt.bufPrint(buf, "{d}m{d}s", .{ mins, secs }) catch "?";
    } else {
        return std.fmt.bufPrint(buf, "{d:.1}s", .{@as(f64, @floatFromInt(ms)) / 1000.0}) catch "?";
    }
}

/// Format cost as "X.XX" (no $ prefix).
pub fn formatCost(buf: []u8, usd: f64) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.2}", .{usd}) catch "?";
}

/// Calculate percentage (0-100) from numerator/denominator, clamped.
pub fn percentage(numerator: u64, denominator: u64) u8 {
    if (denominator == 0) return 0;
    const pct = (numerator *| 100) / denominator;
    return if (pct > 100) 100 else @intCast(pct);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "formatTokens" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("500", formatTokens(&buf, 500));
    try std.testing.expectEqualStrings("1.5K", formatTokens(&buf, 1500));
    try std.testing.expectEqualStrings("2.3M", formatTokens(&buf, 2_300_000));
    try std.testing.expectEqualStrings("1.0G", formatTokens(&buf, 1_000_000_000));
    try std.testing.expectEqualStrings("0", formatTokens(&buf, 0));
}

test "formatDuration" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("5.0s", formatDuration(&buf, 5000));
    try std.testing.expectEqualStrings("2m30s", formatDuration(&buf, 150000));
    try std.testing.expectEqualStrings("0.0s", formatDuration(&buf, 0));
}

test "formatCost" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0.01", formatCost(&buf, 0.01234));
    try std.testing.expectEqualStrings("1.50", formatCost(&buf, 1.5));
}

test "percentage" {
    try std.testing.expectEqual(@as(u8, 50), percentage(50, 100));
    try std.testing.expectEqual(@as(u8, 0), percentage(0, 100));
    try std.testing.expectEqual(@as(u8, 100), percentage(200, 100));
    try std.testing.expectEqual(@as(u8, 0), percentage(50, 0));
}
