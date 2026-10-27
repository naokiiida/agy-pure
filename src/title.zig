const std = @import("std");
const agy = @import("agy.zig");
const directory = @import("directory.zig");

/// Maps agent_state to a representative Unicode emoji.
pub const StateEmoji = struct {
    pub fn get(state: []const u8) []const u8 {
        if (std.ascii.eqlIgnoreCase(state, "initializing")) return "🚀";
        if (std.ascii.eqlIgnoreCase(state, "idle")) return "😴";
        if (std.ascii.eqlIgnoreCase(state, "thinking")) return "🤔";
        if (std.ascii.eqlIgnoreCase(state, "working")) return "🏃";
        if (std.ascii.eqlIgnoreCase(state, "tool_use")) return "🛠️";
        if (std.ascii.eqlIgnoreCase(state, "running")) return "🏃";
        if (std.ascii.eqlIgnoreCase(state, "processing")) return "⚙️";
        if (std.ascii.eqlIgnoreCase(state, "waiting_for_input") or std.ascii.eqlIgnoreCase(state, "waiting_for_user")) return "⏳";
        if (std.ascii.eqlIgnoreCase(state, "done") or std.ascii.eqlIgnoreCase(state, "complete")) return "✅";
        if (std.ascii.eqlIgnoreCase(state, "error") or std.ascii.eqlIgnoreCase(state, "errored")) return "❌";
        return "🤖";
    }
};

pub const TitleStyle = enum {
    standard,
    detailed,
};

pub const TitleConfig = struct {
    style: TitleStyle = .standard,
    emoji: bool = true,
    show_branch: bool = false,
    show_subagents: bool = false,
    osc_progress: bool = true,
    tool_action: ?[]const u8 = null,
};

/// Formats OSC 7501 (Ghostty Program Status Protocol):
/// - working/tool_use/running: \x1b]7501;state=working;message=<status>\x07
/// - waiting_for_user: \x1b]7501;state=blocked;message=Waiting for user\x07
/// - idle: \x1b]7501;state=idle\x07
/// - done: \x1b]7501;state=done\x07
pub fn formatOsc7501(
    writer: anytype,
    state: []const u8,
    message: ?[]const u8,
) !void {
    if (std.ascii.eqlIgnoreCase(state, "waiting_for_user") or std.ascii.eqlIgnoreCase(state, "waiting_for_input")) {
        try writer.writeAll("\x1b]7501;state=blocked;message=Waiting for user\x07");
    } else if (std.ascii.eqlIgnoreCase(state, "done") or std.ascii.eqlIgnoreCase(state, "complete")) {
        try writer.writeAll("\x1b]7501;state=done\x07");
    } else if (std.ascii.eqlIgnoreCase(state, "idle")) {
        try writer.writeAll("\x1b]7501;state=idle\x07");
    } else if (std.ascii.eqlIgnoreCase(state, "working") or
        std.ascii.eqlIgnoreCase(state, "tool_use") or
        std.ascii.eqlIgnoreCase(state, "running") or
        std.ascii.eqlIgnoreCase(state, "thinking") or
        std.ascii.eqlIgnoreCase(state, "processing"))
    {
        try writer.writeAll("\x1b]7501;state=working");
        if (message) |msg| {
            if (msg.len > 0) {
                try writer.writeAll(";message=");
                for (msg) |c| {
                    if (c == ';') {
                        try writer.writeByte(',');
                    } else if (c >= 32 and c != 127) {
                        try writer.writeByte(c);
                    }
                }
            }
        }
        try writer.writeAll("\x07");
    } else {
        try writer.writeAll("\x1b]7501;state=idle\x07");
    }
}

/// Formats OSC 9;4 (Taskbar & Tab Native Progress Bars for Ghostty/Windows Terminal/iTerm2):
/// - active (working/tool_use/running): \x1b]9;4;3;0\x07 (indeterminate pulse/spinner)
/// - waiting_for_user: \x1b]9;4;4;0\x07 (warning/paused state)
/// - idle/done: \x1b]9;4;0;0\x07 (clear indicator)
pub fn formatOsc9_4(
    writer: anytype,
    state: []const u8,
) !void {
    if (std.ascii.eqlIgnoreCase(state, "waiting_for_user") or std.ascii.eqlIgnoreCase(state, "waiting_for_input")) {
        try writer.writeAll("\x1b]9;4;4;0\x07");
    } else if (std.ascii.eqlIgnoreCase(state, "working") or
        std.ascii.eqlIgnoreCase(state, "tool_use") or
        std.ascii.eqlIgnoreCase(state, "running") or
        std.ascii.eqlIgnoreCase(state, "thinking") or
        std.ascii.eqlIgnoreCase(state, "processing"))
    {
        try writer.writeAll("\x1b]9;4;3;0\x07");
    } else {
        try writer.writeAll("\x1b]9;4;0;0\x07");
    }
}

/// Reads the last tool_call action from transcript.jsonl near the end of the file.
/// Formats as `<tool_name>(<target_file>)` or `<tool_name>`.
pub fn extractToolActionFromTranscript(allocator: std.mem.Allocator, transcript_path: []const u8) ?[]const u8 {
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

    var idx = chunk.len;
    while (idx > 0) {
        const prev_nl = std.mem.lastIndexOfScalar(u8, chunk[0..idx], '\n');
        const line_start = if (prev_nl) |p| p + 1 else 0;
        const line = std.mem.trim(u8, chunk[line_start..idx], " \r\n");
        idx = if (prev_nl) |p| p else 0;

        if (line.len == 0 or line[0] != '{') continue;
        if (std.mem.indexOf(u8, line, "\"tool_calls\"") == null) continue;

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (parsed.value != .object) continue;
        const obj = parsed.value.object;

        const tc_val = obj.get("tool_calls") orelse continue;
        if (tc_val != .array or tc_val.array.items.len == 0) continue;

        const latest_tc = tc_val.array.items[tc_val.array.items.len - 1];
        if (latest_tc != .object) continue;
        const tc_obj = latest_tc.object;

        const name_val = tc_obj.get("name") orelse continue;
        if (name_val != .string or name_val.string.len == 0) continue;
        const tool_name = name_val.string;

        var target_file: ?[]const u8 = null;
        if (tc_obj.get("args")) |args_val| {
            if (args_val == .object) {
                const args = args_val.object;
                const path_keys = [_][]const u8{ "Path", "path", "file_path", "filePath", "target", "file" };
                for (path_keys) |k| {
                    if (args.get(k)) |pv| {
                        if (pv == .string and pv.string.len > 0) {
                            var p = pv.string;
                            p = std.mem.trim(u8, p, "\"");
                            const base = if (std.mem.lastIndexOfScalar(u8, p, '/')) |si| p[si + 1 ..] else p;
                            if (base.len > 0) {
                                target_file = base;
                                break;
                            }
                        }
                    }
                }

                if (target_file == null) {
                    if (args.get("CommandLine") orelse args.get("command")) |cv| {
                        if (cv == .string and cv.string.len > 0) {
                            var cmd = std.mem.trim(u8, cv.string, "\" \t");
                            if (cmd.len > 24) cmd = cmd[0..24];
                            target_file = cmd;
                        }
                    }
                }
            }
        }

        if (target_file) |tf| {
            return std.fmt.allocPrint(allocator, "{s}({s})", .{ tool_name, tf }) catch null;
        } else {
            return std.fmt.allocPrint(allocator, "{s}", .{tool_name}) catch null;
        }
    }

    return null;
}

/// Inspects session metadata or transcript.jsonl to extract active tool and target file.
pub fn extractToolAction(allocator: std.mem.Allocator, session: agy.Session) ?[]const u8 {
    // 1. Inspect session metadata
    if (session.tool_name) |tn| {
        if (tn.len > 0) return allocator.dupe(u8, tn) catch null;
    }

    const tool_values = [_]?std.json.Value{ session.current_tool, session.active_tool, session.tool };
    for (tool_values) |tv_opt| {
        if (tv_opt) |tv| {
            switch (tv) {
                .string => |s| if (s.len > 0) return allocator.dupe(u8, s) catch null,
                .object => |obj| {
                    const name_val = obj.get("name") orelse obj.get("tool") orelse obj.get("tool_name");
                    if (name_val) |nv| {
                        if (nv == .string and nv.string.len > 0) {
                            const name = nv.string;
                            const target_val = obj.get("target") orelse obj.get("path") orelse obj.get("file");
                            if (target_val) |tgv| {
                                if (tgv == .string and tgv.string.len > 0) {
                                    const base = if (std.mem.lastIndexOfScalar(u8, tgv.string, '/')) |i| tgv.string[i + 1 ..] else tgv.string;
                                    return std.fmt.allocPrint(allocator, "{s}({s})", .{ name, base }) catch null;
                                }
                            }
                            return allocator.dupe(u8, name) catch null;
                        }
                    }
                },
                else => {},
            }
        }
    }

    // 2. Inspect transcript file
    if (session.transcript_path) |tp| {
        if (extractToolActionFromTranscript(allocator, tp)) |res| return res;
    }

    // 3. Inspect default transcript location
    if (session.conversation_id) |cid| {
        if (cid.len > 0) {
            var path_buf: [512]u8 = undefined;
            const home_ptr = std.c.getenv("HOME");
            const home: []const u8 = if (home_ptr) |h| std.mem.sliceTo(h, 0) else "";
            if (home.len > 0) {
                const default_path = std.fmt.bufPrint(&path_buf, "{s}/.gemini/antigravity-cli/brain/{s}/.system_generated/logs/transcript.jsonl", .{ home, cid }) catch "";
                if (default_path.len > 0) {
                    if (extractToolActionFromTranscript(allocator, default_path)) |res| return res;
                }
            }
        }
    }

    return null;
}

/// Formats and writes the terminal window title.
pub fn render(
    writer: anytype,
    session: agy.Session,
    config: TitleConfig,
    branch_name: ?[]const u8,
) !void {
    const state_str = if (session.agent_state) |st| (if (st.len > 0) st else "idle") else "idle";
    const workspace = directory.extractWorkspace(session.getProjectDir());

    const is_tool = std.ascii.eqlIgnoreCase(state_str, "tool_use");
    const display_state = if (is_tool and config.tool_action != null)
        config.tool_action.?
    else
        state_str;

    if (config.emoji) {
        const emoji = StateEmoji.get(state_str);
        try writer.writeAll(emoji);
        try writer.writeAll(" ");
    }

    try writer.writeAll(display_state);
    try writer.writeAll(" | ");
    try writer.writeAll(workspace);

    if (config.show_branch) {
        if (branch_name) |br| {
            if (br.len > 0) {
                try writer.writeAll(" (");
                try writer.writeAll(br);
                try writer.writeAll(")");
            }
        }
    }

    if (config.show_subagents) {
        var sub_buf: [128]u8 = undefined;
        if (agy.formatSubagents(&sub_buf, session)) |sub_str| {
            try writer.writeAll(" ");
            try writer.writeAll(sub_str);
        }
    }

    try writer.writeAll("\n");
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

const TestWriter = struct {
    buf: [4096]u8 = undefined,
    len: usize = 0,

    pub fn writeAll(self: *TestWriter, bytes: []const u8) !void {
        if (self.len + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    pub fn writeByte(self: *TestWriter, byte: u8) !void {
        if (self.len + 1 > self.buf.len) return error.NoSpaceLeft;
        self.buf[self.len] = byte;
        self.len += 1;
    }

    pub fn getWritten(self: *const TestWriter) []const u8 {
        return self.buf[0..self.len];
    }
};

test "StateEmoji mapping matches official specs and conventions" {
    try std.testing.expectEqualStrings("🚀", StateEmoji.get("initializing"));
    try std.testing.expectEqualStrings("😴", StateEmoji.get("idle"));
    try std.testing.expectEqualStrings("🤔", StateEmoji.get("thinking"));
    try std.testing.expectEqualStrings("🏃", StateEmoji.get("working"));
    try std.testing.expectEqualStrings("🛠️", StateEmoji.get("tool_use"));
    try std.testing.expectEqualStrings("🏃", StateEmoji.get("running"));
    try std.testing.expectEqualStrings("⚙️", StateEmoji.get("processing"));
    try std.testing.expectEqualStrings("⏳", StateEmoji.get("waiting_for_input"));
    try std.testing.expectEqualStrings("✅", StateEmoji.get("done"));
    try std.testing.expectEqualStrings("❌", StateEmoji.get("error"));
    try std.testing.expectEqualStrings("🤖", StateEmoji.get("unknown_state"));
}

test "render standard title matching official title.sh" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "working",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session, .{}, null);
    try std.testing.expectEqualStrings("🏃 working | agy-pure\n", tw.getWritten());
}

test "render citc workspace title" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "idle",
        .workspace = .{
            .project_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
            .current_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
        },
    };

    try render(&tw, session, .{}, null);
    try std.testing.expectEqualStrings("😴 idle | gemini-feature\n", tw.getWritten());
}

test "render detailed title with branch and subagents" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "thinking",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
        .subagents = .{ .integer = 2 },
    };

    try render(&tw, session, .{
        .show_branch = true,
        .show_subagents = true,
    }, "main");

    try std.testing.expectEqualStrings("🤔 thinking | agy-pure (main) [2 subagents]\n", tw.getWritten());
}

test "render action-aware tool_use title" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "tool_use",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session, .{ .tool_action = "read_file(main.zig)" }, null);
    try std.testing.expectEqualStrings("🛠️ read_file(main.zig) | agy-pure\n", tw.getWritten());
}

test "formatOsc7501 sequence formatting" {
    var tw = TestWriter{};

    // working / tool_use / running
    try formatOsc7501(&tw, "working", "read_file(main.zig)");
    try std.testing.expectEqualStrings("\x1b]7501;state=working;message=read_file(main.zig)\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc7501(&tw, "tool_use", "edit_file(title.zig)");
    try std.testing.expectEqualStrings("\x1b]7501;state=working;message=edit_file(title.zig)\x07", tw.getWritten());

    // waiting_for_user
    tw.len = 0;
    try formatOsc7501(&tw, "waiting_for_user", null);
    try std.testing.expectEqualStrings("\x1b]7501;state=blocked;message=Waiting for user\x07", tw.getWritten());

    // idle
    tw.len = 0;
    try formatOsc7501(&tw, "idle", null);
    try std.testing.expectEqualStrings("\x1b]7501;state=idle\x07", tw.getWritten());

    // done
    tw.len = 0;
    try formatOsc7501(&tw, "done", null);
    try std.testing.expectEqualStrings("\x1b]7501;state=done\x07", tw.getWritten());
}

test "formatOsc9_4 sequence formatting" {
    var tw = TestWriter{};

    // active states
    try formatOsc9_4(&tw, "working");
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, "tool_use");
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, "running");
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    // waiting_for_user
    tw.len = 0;
    try formatOsc9_4(&tw, "waiting_for_user");
    try std.testing.expectEqualStrings("\x1b]9;4;4;0\x07", tw.getWritten());

    // idle / done
    tw.len = 0;
    try formatOsc9_4(&tw, "idle");
    try std.testing.expectEqualStrings("\x1b]9;4;0;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, "done");
    try std.testing.expectEqualStrings("\x1b]9;4;0;0\x07", tw.getWritten());
}
