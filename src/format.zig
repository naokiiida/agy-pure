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

/// Computes the terminal cell display width of a string, ignoring ANSI escape
/// sequences and taking into account wide Unicode characters, emojis, and Nerd Font icons.
pub fn visualWidth(bytes: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < bytes.len) {
        const b = bytes[i];

        // ANSI escape sequence start
        if (b == 0x1B) {
            i += 1;
            if (i >= bytes.len) break;
            const next_b = bytes[i];
            if (next_b == '[') {
                // CSI sequence: ESC [ ... [0x40-0x7E]
                i += 1;
                while (i < bytes.len) : (i += 1) {
                    if (bytes[i] >= 0x40 and bytes[i] <= 0x7E) {
                        i += 1;
                        break;
                    }
                }
            } else if (next_b == ']') {
                // OSC sequence: ESC ] ... (BEL or ESC \)
                i += 1;
                while (i < bytes.len) : (i += 1) {
                    if (bytes[i] == 0x07) {
                        i += 1;
                        break;
                    }
                    if (bytes[i] == 0x1B and i + 1 < bytes.len and bytes[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                }
            } else {
                // Other 2-byte escape sequences (e.g. ESC N, ESC O)
                i += 1;
            }
            continue;
        }

        // Standard ASCII printable range (0x20..0x7E)
        if (b >= 0x20 and b <= 0x7E) {
            width += 1;
            i += 1;
            continue;
        }

        // ASCII control codes (0x00..0x1F, 0x7F)
        if (b < 0x20 or b == 0x7F) {
            i += 1;
            continue;
        }

        // Multi-byte UTF-8 sequence
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch {
            i += 1;
            continue;
        };

        if (i + seq_len > bytes.len) {
            break;
        }

        const cp = std.unicode.utf8Decode(bytes[i .. i + seq_len]) catch {
            i += 1;
            continue;
        };
        i += seq_len;

        // Zero-width characters (variation selectors, combining marks)
        if ((cp >= 0x0300 and cp <= 0x036F) or (cp >= 0xFE00 and cp <= 0xFE0F) or (cp >= 0xE0100 and cp <= 0xE01EF)) {
            continue;
        }

        // Nerd Font Private Use Area (PUA) glyphs occupy 1 terminal cell
        if ((cp >= 0xE000 and cp <= 0xF8FF) or (cp >= 0xF0000 and cp <= 0xFFFFD) or (cp >= 0x100000 and cp <= 0x10FFFD)) {
            width += 1;
            continue;
        }

        // Wide characters and emojis occupy 2 terminal cells
        if (isWideChar(cp)) {
            width += 2;
        } else {
            width += 1;
        }
    }

    return width;
}

fn isWideChar(cp: u21) bool {
    // Emojis and miscellaneous symbols
    if (cp >= 0x1F300 and cp <= 0x1FAFF) return true;
    if (cp >= 0x2600 and cp <= 0x27BF) {
        // High voltage (⚡ 0x26A1) and stopwatch (⏱ 0x23F1) are narrow in standard terminal grids
        if (cp == 0x26A1 or cp == 0x26A0) return false;
        return true;
    }

    // East Asian Wide / Fullwidth characters
    if (cp >= 0x1100 and cp <= 0x115F) return true; // Hangul Jamo
    if (cp >= 0x2E80 and cp <= 0xA4CF and cp != 0x303F) return true; // CJK Radicals, Ideographs, Hiragana, Katakana
    if (cp >= 0xAC00 and cp <= 0xD7A3) return true; // Hangul Syllables
    if (cp >= 0xF900 and cp <= 0xFAFF) return true; // CJK Compatibility Ideographs
    if (cp >= 0xFE10 and cp <= 0xFE19) return true; // Vertical forms
    if (cp >= 0xFE30 and cp <= 0xFE6F) return true; // CJK Compatibility Forms
    if (cp >= 0xFF01 and cp <= 0xFF60) return true; // Fullwidth ASCII
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return true; // Fullwidth symbols
    if (cp >= 0x20000 and cp <= 0x2FFFD) return true; // CJK Extension
    if (cp >= 0x30000 and cp <= 0x3FFFD) return true; // CJK Extension

    return false;
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

test "visualWidth" {
    // Plain ASCII
    try std.testing.expectEqual(@as(usize, 0), visualWidth(""));
    try std.testing.expectEqual(@as(usize, 5), visualWidth("hello"));
    try std.testing.expectEqual(@as(usize, 16), visualWidth("Gemini 3.8 Flash"));

    // ANSI escape sequences stripped
    try std.testing.expectEqual(@as(usize, 5), visualWidth("\x1b[31mhello\x1b[0m"));
    try std.testing.expectEqual(@as(usize, 16), visualWidth("\x1b[1m\x1b[38;5;110mGemini 3.8 Flash\x1b[0m"));
    try std.testing.expectEqual(@as(usize, 4), visualWidth("\x1b]0;Title\x07test"));

    // Nerd Font PUA glyphs (1 cell)
    try std.testing.expectEqual(@as(usize, 7), visualWidth("󰪞 42.1K"));

    // Standard Unicode & symbols
    try std.testing.expectEqual(@as(usize, 4), visualWidth("⚡85%"));
    try std.testing.expectEqual(@as(usize, 6), visualWidth("⏱ 4.2s"));
    try std.testing.expectEqual(@as(usize, 5), visualWidth("main*"));
    try std.testing.expectEqual(@as(usize, 8), visualWidth("main* ⇡1"));

    // Emojis (2 cells)
    try std.testing.expectEqual(@as(usize, 6), visualWidth("🔬 res"));
    try std.testing.expectEqual(@as(usize, 6), visualWidth("🏃 deb"));
}
