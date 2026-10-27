const std = @import("std");
const directory = @import("directory.zig");

pub const StopHookPayload = struct {
    executionNum: ?i64 = null,
    execution_num: ?i64 = null,
    terminationReason: ?[]const u8 = null,
    termination_reason: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
    fullyIdle: ?bool = null,
    fully_idle: ?bool = null,
    conversationId: ?[]const u8 = null,
    conversation_id: ?[]const u8 = null,
    workspacePaths: ?[][]const u8 = null,
    workspace_paths: ?[][]const u8 = null,
    transcriptPath: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
    artifactDirectoryPath: ?[]const u8 = null,
    artifact_directory_path: ?[]const u8 = null,
    modelName: ?[]const u8 = null,
    model_name: ?[]const u8 = null,

    pub fn isFullyIdle(self: StopHookPayload) bool {
        if (self.fullyIdle) |v| return v;
        if (self.fully_idle) |v| return v;
        // Default to true if unstated, but if explicitly false, it is not fully idle.
        return true;
    }

    pub fn getTerminationReason(self: StopHookPayload) []const u8 {
        if (self.terminationReason) |r| return r;
        if (self.termination_reason) |r| return r;
        return "NO_TOOL_CALL";
    }

    pub fn getError(self: StopHookPayload) ?[]const u8 {
        if (self.error_msg) |e| if (e.len > 0) return e;
        if (self.@"error") |e| if (e.len > 0) return e;
        return null;
    }

    pub fn getTranscriptPath(self: StopHookPayload) ?[]const u8 {
        if (self.transcriptPath) |p| if (p.len > 0) return p;
        if (self.transcript_path) |p| if (p.len > 0) return p;
        return null;
    }

    pub fn getWorkspacePath(self: StopHookPayload) ?[]const u8 {
        if (self.workspacePaths) |wp| if (wp.len > 0 and wp[0].len > 0) return wp[0];
        if (self.workspace_paths) |wp| if (wp.len > 0 and wp[0].len > 0) return wp[0];
        return null;
    }

    pub fn getConversationId(self: StopHookPayload) []const u8 {
        if (self.conversationId) |c| if (c.len > 0) return c;
        if (self.conversation_id) |c| if (c.len > 0) return c;
        return "default";
    }
};

/// Cleans markdown/tags from text and returns a concise single-line summary (up to max_len).
pub fn cleanSummary(allocator: std.mem.Allocator, raw: []const u8, max_len: usize) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var in_code_block = false;

    // First, find the first non-empty meaningful line
    var line_start: usize = 0;
    while (line_start < raw.len) {
        var line_end = line_start;
        while (line_end < raw.len and raw[line_end] != '\n' and raw[line_end] != '\r') : (line_end += 1) {}
        const line = std.mem.trim(u8, raw[line_start..line_end], " \t\r");

        // Toggle and skip code block fences and contents
        if (std.mem.startsWith(u8, line, "```")) {
            in_code_block = !in_code_block;
            line_start = if (line_end < raw.len and raw[line_end] == '\r' and line_end + 1 < raw.len and raw[line_end + 1] == '\n')
                line_end + 2
            else
                line_end + 1;
            continue;
        }

        if (in_code_block) {
            line_start = if (line_end < raw.len and raw[line_end] == '\r' and line_end + 1 < raw.len and raw[line_end + 1] == '\n')
                line_end + 2
            else
                line_end + 1;
            continue;
        }

        // Skip markdown headings markers, tags, empty lines, dividers, blockquotes/alerts
        if (line.len > 0 and
            !std.mem.startsWith(u8, line, "<") and
            !std.mem.startsWith(u8, line, "#") and
            !std.mem.startsWith(u8, line, "---") and
            !std.mem.startsWith(u8, line, "===") and
            !std.mem.startsWith(u8, line, ">"))
        {
            var content = line;
            // Strip leading bullet markers (- , * , + )
            if (content.len >= 2 and (content[0] == '-' or content[0] == '*' or content[0] == '+') and content[1] == ' ') {
                content = std.mem.trimStart(u8, content[2..], " ");
            } else {
                // Strip numbered list markers (e.g. "1. ", "12. ")
                var num_idx: usize = 0;
                while (num_idx < content.len and std.ascii.isDigit(content[num_idx])) : (num_idx += 1) {}
                if (num_idx > 0 and num_idx + 1 < content.len and content[num_idx] == '.' and content[num_idx + 1] == ' ') {
                    content = std.mem.trimStart(u8, content[num_idx + 2..], " ");
                }
            }

            var in_tag = false;
            var i: usize = 0;
            while (i < content.len) {
                // Check for image tag: ![alt](url) -> skip completely
                if (content[i] == '!' and i + 1 < content.len and content[i + 1] == '[') {
                    const close_bracket = std.mem.indexOfScalarPos(u8, content, i + 2, ']');
                    if (close_bracket) |cb| {
                        if (cb + 1 < content.len and content[cb + 1] == '(') {
                            const close_paren = std.mem.indexOfScalarPos(u8, content, cb + 2, ')');
                            if (close_paren) |cp| {
                                i = cp + 1;
                                continue;
                            }
                        }
                    }
                }

                // Check for markdown link: [label](url) -> keep label, skip (url)
                if (content[i] == '[') {
                    const close_bracket = std.mem.indexOfScalarPos(u8, content, i + 1, ']');
                    if (close_bracket) |cb| {
                        if (cb + 1 < content.len and content[cb + 1] == '(') {
                            const close_paren = std.mem.indexOfScalarPos(u8, content, cb + 2, ')');
                            if (close_paren) |cp| {
                                const label = content[i + 1 .. cb];
                                for (label) |lc| {
                                    if (lc == '#' or lc == '*' or lc == '`') continue;
                                    if (lc == ';') {
                                        try out.append(allocator, ',');
                                    } else if (lc == ' ' or lc == '\t') {
                                        if (out.items.len > 0 and out.items[out.items.len - 1] != ' ') {
                                            try out.append(allocator, ' ');
                                        }
                                    } else if (lc >= 32 and lc != 127) {
                                        try out.append(allocator, lc);
                                    }
                                    if (out.items.len >= max_len) break;
                                }
                                i = cp + 1;
                                continue;
                            }
                        }
                    }
                }

                const c = content[i];
                i += 1;

                if (c == '<') {
                    in_tag = true;
                    continue;
                } else if (c == '>') {
                    in_tag = false;
                    continue;
                }
                if (in_tag) continue;

                // Strip markdown formatting characters (preserve '_' for identifiers like notify_main.zig)
                if (c == '#' or c == '*' or c == '`') continue;

                // Collapse whitespace
                if (c == ' ' or c == '\t') {
                    if (out.items.len > 0 and out.items[out.items.len - 1] != ' ') {
                        try out.append(allocator, ' ');
                    }
                    continue;
                }

                // Replace semicolons with commas because OSC 777 uses ';' as field delimiter
                if (c == ';') {
                    try out.append(allocator, ',');
                } else if (c >= 32 and c != 127) {
                    try out.append(allocator, c);
                }

                if (out.items.len >= max_len) break;
            }

            const trimmed = std.mem.trim(u8, out.items, " \t-*>,;:");
            if (trimmed.len > 0) {
                // If trimmed to max_len, add ellipsis if truncated
                if (out.items.len >= max_len and max_len > 3) {
                    var final_buf = try allocator.alloc(u8, max_len);
                    @memcpy(final_buf[0 .. max_len - 3], trimmed[0 .. @min(trimmed.len, max_len - 3)]);
                    @memcpy(final_buf[max_len - 3 .. max_len], "...");
                    out.deinit(allocator);
                    return final_buf;
                }
                const result = try allocator.dupe(u8, trimmed);
                out.deinit(allocator);
                return result;
            }
            out.clearRetainingCapacity();
        }

        line_start = if (line_end < raw.len and raw[line_end] == '\r' and line_end + 1 < raw.len and raw[line_end + 1] == '\n')
            line_end + 2
        else
            line_end + 1;
    }

    out.deinit(allocator);
    return try allocator.dupe(u8, "Turn complete");
}

/// Reads the last response content from transcript.jsonl near the end of the file.
pub fn extractLastResponse(allocator: std.mem.Allocator, transcript_path: []const u8) ?[]const u8 {
    var path_buf: [1024]u8 = undefined;
    if (transcript_path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..transcript_path.len], transcript_path);
    path_buf[transcript_path.len] = 0;

    const fd = std.c.open(path_buf[0..transcript_path.len :0], .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);

    const file_size_i = std.c.lseek(fd, 0, std.c.SEEK.END);
    if (file_size_i <= 0) return null;
    const file_size: usize = @intCast(file_size_i);

    // Read up to 64KB from the tail of transcript
    const read_size: usize = @min(file_size, 65536);
    const offset: i64 = @intCast(file_size - read_size);
    _ = std.c.lseek(fd, offset, std.c.SEEK.SET);

    const buf = allocator.alloc(u8, read_size) catch return null;
    defer allocator.free(buf);

    var total_read: usize = 0;
    while (total_read < read_size) {
        const n = std.c.read(fd, buf[total_read..].ptr, read_size - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }
    if (total_read == 0) return null;

    const chunk = buf[0..total_read];

    // Scan backwards line-by-line
    var idx = chunk.len;
    while (idx > 0) {
        const prev_nl = std.mem.lastIndexOfScalar(u8, chunk[0..idx], '\n');
        const line_start = if (prev_nl) |p| p + 1 else 0;
        const line = std.mem.trim(u8, chunk[line_start..idx], " \r\n");
        idx = if (prev_nl) |p| p else 0;

        if (line.len == 0 or line[0] != '{') continue;

        // Quick check if line has "source":"MODEL" or "content"
        if (std.mem.indexOf(u8, line, "\"MODEL\"") == null) continue;

        // Parse with std.json
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (parsed.value != .object) continue;
        const obj = parsed.value.object;

        if (obj.get("source")) |src| {
            if (src == .string and std.mem.eql(u8, src.string, "MODEL")) {
                if (obj.get("content")) |cnt| {
                    if (cnt == .string and cnt.string.len > 0) {
                        return allocator.dupe(u8, cnt.string) catch null;
                    }
                }
            }
        }
    }

    return null;
}

/// Formats clean notification title (<15 chars):
/// - Notification hook: "⏳ Needs input"
/// - Error: "❌ Error"
/// - Normal completion: "Done"
/// Note: Duration is deliberately omitted here because the active terminal tab title
/// (surface.title) already carries the live duration (e.g. "🏃 agy-pure · ⏱ 14s"),
/// which Ghostty automatically projects into the notification subtitle.
pub fn formatNotificationTitle(is_error: bool, is_notification: bool) []const u8 {
    if (is_notification) {
        return "⏳ Needs input";
    }
    if (is_error) {
        return "❌ Error";
    }
    return "Done";
}

/// Formats the OSC 777 sequence: \x1b]777;notify;{title};{body}\x07
pub fn formatOsc777(
    writer: anytype,
    title: []const u8,
    body: []const u8,
) !void {
    try writer.writeAll("\x1b]777;notify;");

    for (title) |c| {
        if (c == ';') {
            try writer.writeByte(',');
        } else if (c >= 32 and c != 127) {
            try writer.writeByte(c);
        }
    }

    try writer.writeByte(';');

    for (body) |c| {
        if (c == ';') {
            try writer.writeByte(',');
        } else if (c >= 32 and c != 127) {
            try writer.writeByte(c);
        }
    }

    try writer.writeAll("\x07");
}

/// Formats the OSC 9 notification sequence: \x1b]9;{body}\x07
pub fn formatOsc9(
    writer: anytype,
    body: []const u8,
) !void {
    try writer.writeAll("\x1b]9;");

    for (body) |c| {
        if (c >= 32 and c != 127) {
            try writer.writeByte(c);
        }
    }

    try writer.writeAll("\x07");
}

/// Emits both OSC 777 and OSC 9 notification sequences for universal terminal compatibility
/// (Ghostty, WezTerm, Kitty, iTerm2, Windows Terminal).
pub fn formatDualOsc(
    writer: anytype,
    title: []const u8,
    body: []const u8,
) !void {
    try formatOsc777(writer, title, body);
    try formatOsc9(writer, body);
}

/// Returns true if running inside a tmux session.
pub fn isTmux() bool {
    return std.c.getenv("TMUX") != null;
}

/// Wraps an escape sequence in tmux DCS pass-through:
/// \x1bPtmux;\x1b<escaped_sequence>\x1b\\ (escaping any inner \x1b as \x1b\x1b).
pub fn wrapTmux(
    writer: anytype,
    raw_sequence: []const u8,
) !void {
    try writer.writeAll("\x1bPtmux;");
    for (raw_sequence) |c| {
        if (c == 0x1b) {
            try writer.writeAll("\x1b\x1b");
        } else {
            try writer.writeByte(c);
        }
    }
    try writer.writeAll("\x1b\\");
}

pub const StackWriter = struct {
    buf: []u8,
    len: usize = 0,

    pub fn writeAll(self: *StackWriter, bytes: []const u8) !void {
        if (self.len + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    pub fn writeByte(self: *StackWriter, byte: u8) !void {
        if (self.len + 1 > self.buf.len) return error.NoSpaceLeft;
        self.buf[self.len] = byte;
        self.len += 1;
    }

    pub fn getWritten(self: *const StackWriter) []const u8 {
        return self.buf[0..self.len];
    }
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "formatOsc777 writes valid escape code and sanitizes semicolons" {
    var buf: [256]u8 = undefined;
    var sw = StackWriter{ .buf = &buf };

    try formatOsc777(&sw, "Vault;extra", "Turn; complete");
    try std.testing.expectEqualStrings("\x1b]777;notify;Vault,extra;Turn, complete\x07", sw.getWritten());
}

test "formatOsc9 writes valid escape code" {
    var buf: [256]u8 = undefined;
    var sw = StackWriter{ .buf = &buf };

    try formatOsc9(&sw, "Turn complete");
    try std.testing.expectEqualStrings("\x1b]9;Turn complete\x07", sw.getWritten());
}

test "formatDualOsc emits both OSC 777 and OSC 9" {
    var buf: [512]u8 = undefined;
    var sw = StackWriter{ .buf = &buf };

    try formatDualOsc(&sw, "agy-pure", "Turn complete");
    try std.testing.expectEqualStrings("\x1b]777;notify;agy-pure;Turn complete\x07\x1b]9;Turn complete\x07", sw.getWritten());
}

test "wrapTmux wraps sequence in DCS pass-through and doubles inner escapes" {
    var buf: [512]u8 = undefined;
    var sw = StackWriter{ .buf = &buf };

    try wrapTmux(&sw, "\x1b]9;Turn complete\x07");
    try std.testing.expectEqualStrings("\x1bPtmux;\x1b\x1b]9;Turn complete\x07\x1b\\", sw.getWritten());

    // Dual OSC wrapping: both escapes doubled
    sw.len = 0;
    try wrapTmux(&sw, "\x1b]777;notify;A;B\x07\x1b]9;B\x07");
    try std.testing.expectEqualStrings("\x1bPtmux;\x1b\x1b]777;notify;A;B\x07\x1b\x1b]9;B\x07\x1b\\", sw.getWritten());
}

test "cleanSummary strips tags and trims to length" {
    const allocator = std.testing.allocator;
    const raw = "<USER_REQUEST>Ignored</USER_REQUEST>\n## Heading\nUpdated 3 files and built tests successfully.";

    const summary = try cleanSummary(allocator, raw, 80);
    defer allocator.free(summary);

    try std.testing.expectEqualStrings("Updated 3 files and built tests successfully.", summary);
}

test "cleanSummary truncates long lines with ellipsis" {
    const allocator = std.testing.allocator;
    const raw = "This is a very long response sentence that definitely needs to be shortened to fit into a notification banner comfortably.";

    const summary = try cleanSummary(allocator, raw, 40);
    defer allocator.free(summary);

    try std.testing.expectEqual(40, summary.len);
    try std.testing.expect(std.mem.endsWith(u8, summary, "..."));
}

test "cleanSummary strips markdown link URLs keeping only labels" {
    const allocator = std.testing.allocator;
    const raw = "Updated [notify.zig](file:///Users/naoki/src/notify.zig) and [notify_main.zig](file:///Users/naoki/src/notify_main.zig) successfully.";

    const summary = try cleanSummary(allocator, raw, 100);
    defer allocator.free(summary);

    try std.testing.expectEqualStrings("Updated notify.zig and notify_main.zig successfully.", summary);
}

test "cleanSummary skips blockquotes and alert headers" {
    const allocator = std.testing.allocator;
    const raw = "> [!NOTE]\n> Some context notes here\n\nCompleted the implementation task.";

    const summary = try cleanSummary(allocator, raw, 80);
    defer allocator.free(summary);

    try std.testing.expectEqualStrings("Completed the implementation task.", summary);
}

test "cleanSummary strips leading bullet and numbered list markers" {
    const allocator = std.testing.allocator;
    const raw1 = "- Fixed compiler error in main module.";
    const summary1 = try cleanSummary(allocator, raw1, 80);
    defer allocator.free(summary1);
    try std.testing.expectEqualStrings("Fixed compiler error in main module.", summary1);

    const raw2 = "1.   All tests passed with zero failures.";
    const summary2 = try cleanSummary(allocator, raw2, 80);
    defer allocator.free(summary2);
    try std.testing.expectEqualStrings("All tests passed with zero failures.", summary2);
}

test "cleanSummary returns fallback on empty or unparseable input" {
    const allocator = std.testing.allocator;
    const raw = "### Only Header\n> Only quote\n```zig\ncode only\n```";

    const summary = try cleanSummary(allocator, raw, 80);
    defer allocator.free(summary);

    try std.testing.expectEqualStrings("Turn complete", summary);
}

test "cleanSummary strips images and collapses multiple whitespace" {
    const allocator = std.testing.allocator;
    const raw = "Here is the result: ![diagram](https://example.com/pic.png)   done with   verification.";

    const summary = try cleanSummary(allocator, raw, 80);
    defer allocator.free(summary);

    try std.testing.expectEqualStrings("Here is the result: done with verification.", summary);
}

test "formatNotificationTitle formatting for completion, errors, and notification hook" {
    // Normal completion
    try std.testing.expectEqualStrings("Done", formatNotificationTitle(false, false));

    // Error
    try std.testing.expectEqualStrings("❌ Error", formatNotificationTitle(true, false));

    // Notification hook (needs input)
    try std.testing.expectEqualStrings("⏳ Needs input", formatNotificationTitle(false, true));
    try std.testing.expectEqualStrings("⏳ Needs input", formatNotificationTitle(true, true));
}
