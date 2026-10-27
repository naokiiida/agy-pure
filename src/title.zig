const std = @import("std");
const agy = @import("agy.zig");
const directory = @import("directory.zig");
const timer = @import("timer.zig");
const format = @import("format.zig");

pub const AgentState = enum {
    idle,
    working,
    reviewing,
    waiting,
    done,
    error_state,
    unknown,
};

pub const StateMap = std.StaticStringMap(AgentState).initComptime(.{
    .{ "idle", .idle },
    .{ "working", .working },
    .{ "running", .working },
    .{ "thinking", .working },
    .{ "processing", .working },
    .{ "tool_use", .working },
    .{ "reviewing", .reviewing },
    .{ "waiting_for_user", .waiting },
    .{ "waiting_for_input", .waiting },
    .{ "done", .done },
    .{ "complete", .done },
    .{ "error", .error_state },
    .{ "errored", .error_state },
});

pub fn parseState(state_str: []const u8) AgentState {
    var lower_buf: [32]u8 = undefined;
    if (state_str.len <= lower_buf.len) {
        for (state_str, 0..) |c, i| {
            lower_buf[i] = std.ascii.toLower(c);
        }
        if (StateMap.get(lower_buf[0..state_str.len])) |st| return st;
    }
    return StateMap.get(state_str) orelse .unknown;
}

pub const StateDescriptor = struct {
    emoji: []const u8,
    osc7501_state: []const u8,
    osc9_4_code: u8, // 0 = clear, 2 = error, 3 = spinner, 4 = paused
    is_blocked: bool,
};

pub const state_descriptors = std.EnumArray(AgentState, StateDescriptor).init(.{
    .idle = .{ .emoji = "", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
    .working = .{ .emoji = "🏃", .osc7501_state = "working", .osc9_4_code = 3, .is_blocked = false },
    .reviewing = .{ .emoji = "🧐", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .waiting = .{ .emoji = "⏳", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .done = .{ .emoji = "✅", .osc7501_state = "done", .osc9_4_code = 0, .is_blocked = false },
    .error_state = .{ .emoji = "❌", .osc7501_state = "error", .osc9_4_code = 2, .is_blocked = false },
    .unknown = .{ .emoji = "🤖", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
});

pub const nerd_state_descriptors = std.EnumArray(AgentState, StateDescriptor).init(.{
    .idle = .{ .emoji = "", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
    .working = .{ .emoji = "󰑮", .osc7501_state = "working", .osc9_4_code = 3, .is_blocked = false },
    .reviewing = .{ .emoji = "󰛄", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .waiting = .{ .emoji = "󰔟", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .done = .{ .emoji = "󰄬", .osc7501_state = "done", .osc9_4_code = 0, .is_blocked = false },
    .error_state = .{ .emoji = "󰅚", .osc7501_state = "error", .osc9_4_code = 2, .is_blocked = false },
    .unknown = .{ .emoji = "󰚩", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
});

pub fn getStateDescriptor(state: AgentState, nerd_font: bool) StateDescriptor {
    if (nerd_font) return nerd_state_descriptors.get(state);
    return state_descriptors.get(state);
}

pub const StateEmoji = struct {
    pub fn get(state_str: []const u8) []const u8 {
        const state = parseState(state_str);
        const desc = state_descriptors.get(state);
        return desc.emoji;
    }
};

pub const TitleStyle = enum {
    standard,
    detailed,
};

pub const TitleConfig = struct {
    style: TitleStyle = .standard,
    emoji: bool = true,
    nerd_font: bool = false,
    show_branch: bool = false,
    show_subagents: bool = false,
    osc_progress: bool = true,
    tool_action: ?[]const u8 = null,
    duration: ?[]const u8 = null,
};

fn resolveState(state_val: anytype) AgentState {
    return switch (@TypeOf(state_val)) {
        AgentState => state_val,
        []const u8 => parseState(state_val),
        else => parseState(state_val),
    };
}

/// Formats OSC 7501 (Ghostty Program Status Protocol):
/// - working: \x1b]7501;state=working;message=<status>\x07
/// - waiting/reviewing: \x1b]7501;state=blocked;message=Waiting for user\x07
/// - idle: \x1b]7501;state=idle\x07
/// - done: \x1b]7501;state=done\x07
/// - error: \x1b]7501;state=error\x07
pub fn formatOsc7501(
    writer: anytype,
    state_input: anytype,
    message: ?[]const u8,
) !void {
    const state = resolveState(state_input);
    const desc = state_descriptors.get(state);

    try writer.writeAll("\x1b]7501;state=");
    try writer.writeAll(desc.osc7501_state);
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
    } else if (desc.is_blocked) {
        try writer.writeAll(";message=Waiting for user");
    }
    try writer.writeAll("\x07");
}

/// Formats OSC 9;4 (Taskbar & Tab Native Progress Bars for Ghostty/Windows Terminal/iTerm2):
/// - active (working): \x1b]9;4;3;0\x07 (indeterminate pulse/spinner)
/// - waiting/reviewing: \x1b]9;4;4;0\x07 (warning/paused state)
/// - error: \x1b]9;4;2;0\x07 (error indicator)
/// - idle/done: \x1b]9;4;0;0\x07 (clear indicator)
pub fn formatOsc9_4(
    writer: anytype,
    state_input: anytype,
) !void {
    const state = resolveState(state_input);
    const desc = state_descriptors.get(state);
    const seq = [_]u8{ 0x1b, ']', '9', ';', '4', ';', '0' + desc.osc9_4_code, ';', '0', 0x07 };
    try writer.writeAll(&seq);
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

/// Formats and writes the terminal window title according to AGENTS.md / TODO.md specs.
pub fn render(
    writer: anytype,
    session: agy.Session,
    config: TitleConfig,
    branch_name: ?[]const u8,
) !void {
    const state_str = if (session.agent_state) |st| (if (st.len > 0) st else "idle") else "idle";
    const state = parseState(state_str);
    const desc = getStateDescriptor(state, config.nerd_font);
    const workspace = directory.extractWorkspace(session.getProjectDir());

    switch (state) {
        .working => {
            if (config.emoji and desc.emoji.len > 0) {
                try writer.writeAll(desc.emoji);
                try writer.writeAll(" ");
            }
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
            var dur_buf: [32]u8 = undefined;
            const dur_opt = config.duration orelse blk: {
                if (timer.peekElapsedMs(session.getConversationId())) |ms| {
                    break :blk format.formatDuration(&dur_buf, ms);
                }
                break :blk null;
            };
            if (dur_opt) |dur| {
                if (dur.len > 0) {
                    try writer.writeAll(" · ⏱ ");
                    try writer.writeAll(dur);
                }
            }
        },
        .reviewing => {
            if (config.emoji and desc.emoji.len > 0) {
                try writer.writeAll(desc.emoji);
                try writer.writeAll(" ");
            }
            try writer.writeAll("reviewing | ");
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
        },
        .waiting => {
            if (config.emoji and desc.emoji.len > 0) {
                try writer.writeAll(desc.emoji);
                try writer.writeAll(" ");
            }
            try writer.writeAll("waiting | ");
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
        },
        .idle => {
            // Idle format: <workspace> (<branch>) · <model>. (No "😴 idle | " clutter).
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
            const model_opt = if (session.model) |m| blk: {
                if (m.display_name.len > 0) break :blk m.display_name;
                if (m.id.len > 0) break :blk m.id;
                break :blk null;
            } else null;

            if (model_opt) |model_name| {
                try writer.writeAll(" · ");
                try writer.writeAll(model_name);
            }
            if (config.show_subagents) {
                var sub_buf: [128]u8 = undefined;
                if (agy.formatSubagents(&sub_buf, session)) |sub_str| {
                    try writer.writeAll(" ");
                    try writer.writeAll(sub_str);
                }
            }
        },
        .done, .error_state => {
            if (config.emoji and desc.emoji.len > 0) {
                try writer.writeAll(desc.emoji);
                try writer.writeAll(" ");
            }
            const state_name = if (state == .done) "done" else "error";
            try writer.writeAll(state_name);
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
        },
        .unknown => {
            if (config.emoji and desc.emoji.len > 0) {
                try writer.writeAll(desc.emoji);
                try writer.writeAll(" ");
            }
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
        },
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

test "AgentState comptime parsing with all synonyms" {
    try std.testing.expectEqual(AgentState.idle, parseState("idle"));
    try std.testing.expectEqual(AgentState.working, parseState("working"));
    try std.testing.expectEqual(AgentState.working, parseState("running"));
    try std.testing.expectEqual(AgentState.working, parseState("thinking"));
    try std.testing.expectEqual(AgentState.working, parseState("processing"));
    try std.testing.expectEqual(AgentState.working, parseState("tool_use"));
    try std.testing.expectEqual(AgentState.reviewing, parseState("reviewing"));
    try std.testing.expectEqual(AgentState.waiting, parseState("waiting_for_user"));
    try std.testing.expectEqual(AgentState.waiting, parseState("waiting_for_input"));
    try std.testing.expectEqual(AgentState.done, parseState("done"));
    try std.testing.expectEqual(AgentState.done, parseState("complete"));
    try std.testing.expectEqual(AgentState.error_state, parseState("error"));
    try std.testing.expectEqual(AgentState.error_state, parseState("errored"));
    try std.testing.expectEqual(AgentState.unknown, parseState("other"));
}

test "state_descriptors consistency" {
    const idle_desc = state_descriptors.get(.idle);
    try std.testing.expectEqualStrings("", idle_desc.emoji);
    try std.testing.expectEqualStrings("idle", idle_desc.osc7501_state);
    try std.testing.expectEqual(0, idle_desc.osc9_4_code);
    try std.testing.expect(!idle_desc.is_blocked);

    const work_desc = state_descriptors.get(.working);
    try std.testing.expectEqualStrings("🏃", work_desc.emoji);
    try std.testing.expectEqualStrings("working", work_desc.osc7501_state);
    try std.testing.expectEqual(3, work_desc.osc9_4_code);
    try std.testing.expect(!work_desc.is_blocked);

    const rev_desc = state_descriptors.get(.reviewing);
    try std.testing.expectEqualStrings("🧐", rev_desc.emoji);
    try std.testing.expectEqualStrings("blocked", rev_desc.osc7501_state);
    try std.testing.expectEqual(4, rev_desc.osc9_4_code);
    try std.testing.expect(rev_desc.is_blocked);

    const wait_desc = state_descriptors.get(.waiting);
    try std.testing.expectEqualStrings("⏳", wait_desc.emoji);
    try std.testing.expectEqualStrings("blocked", wait_desc.osc7501_state);
    try std.testing.expectEqual(4, wait_desc.osc9_4_code);
    try std.testing.expect(wait_desc.is_blocked);

    const done_desc = state_descriptors.get(.done);
    try std.testing.expectEqualStrings("✅", done_desc.emoji);
    try std.testing.expectEqualStrings("done", done_desc.osc7501_state);
    try std.testing.expectEqual(0, done_desc.osc9_4_code);

    const err_desc = state_descriptors.get(.error_state);
    try std.testing.expectEqualStrings("❌", err_desc.emoji);
    try std.testing.expectEqualStrings("error", err_desc.osc7501_state);
    try std.testing.expectEqual(2, err_desc.osc9_4_code);
}

test "render working title with duration and branch" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "working",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session, .{ .duration = "3.8s" }, null);
    try std.testing.expectEqualStrings("🏃 agy-pure · ⏱ 3.8s\n", tw.getWritten());

    tw.len = 0;
    try render(&tw, session, .{ .show_branch = true, .duration = "14s" }, "main");
    try std.testing.expectEqualStrings("🏃 agy-pure (main) · ⏱ 14s\n", tw.getWritten());
}

test "render idle title with model without clutter" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "idle",
        .workspace = .{
            .project_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
            .current_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
        },
        .model = .{
            .id = "gemini-3.8-flash",
            .display_name = "Gemini 3.8 Flash",
        },
    };

    try render(&tw, session, .{}, null);
    try std.testing.expectEqualStrings("gemini-feature · Gemini 3.8 Flash\n", tw.getWritten());

    // Without model
    tw.len = 0;
    const session_no_model = agy.Session{
        .agent_state = "idle",
        .workspace = .{
            .project_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
            .current_dir = "/google/src/cloud/naokiiida/gemini-feature/google3",
        },
    };
    try render(&tw, session_no_model, .{}, null);
    try std.testing.expectEqualStrings("gemini-feature\n", tw.getWritten());
}

test "render reviewing and waiting titles" {
    var tw = TestWriter{};

    const session_rev = agy.Session{
        .agent_state = "reviewing",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session_rev, .{}, null);
    try std.testing.expectEqualStrings("🧐 reviewing | agy-pure\n", tw.getWritten());

    tw.len = 0;
    const session_wait = agy.Session{
        .agent_state = "waiting_for_user",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session_wait, .{ .show_branch = true }, "feat");
    try std.testing.expectEqualStrings("⏳ waiting | agy-pure (feat)\n", tw.getWritten());
}

test "render with --nerd-font" {
    var tw = TestWriter{};

    const session = agy.Session{
        .agent_state = "working",
        .workspace = .{
            .project_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
            .current_dir = "/Users/naokiiida/Documents/1_personal/agy-pure",
        },
    };

    try render(&tw, session, .{ .nerd_font = true, .duration = "5.0s" }, null);
    try std.testing.expectEqualStrings("󰑮 agy-pure · ⏱ 5.0s\n", tw.getWritten());
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
        .duration = "2.0s",
    }, "main");

    try std.testing.expectEqualStrings("🏃 agy-pure (main) [2 subagents] · ⏱ 2.0s\n", tw.getWritten());
}

test "formatOsc7501 sequence formatting" {
    var tw = TestWriter{};

    // working / tool_use / running
    try formatOsc7501(&tw, AgentState.working, "read_file(main.zig)");
    try std.testing.expectEqualStrings("\x1b]7501;state=working;message=read_file(main.zig)\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc7501(&tw, "tool_use", "edit_file(title.zig)");
    try std.testing.expectEqualStrings("\x1b]7501;state=working;message=edit_file(title.zig)\x07", tw.getWritten());

    // waiting_for_user
    tw.len = 0;
    try formatOsc7501(&tw, AgentState.waiting, null);
    try std.testing.expectEqualStrings("\x1b]7501;state=blocked;message=Waiting for user\x07", tw.getWritten());

    // reviewing
    tw.len = 0;
    try formatOsc7501(&tw, AgentState.reviewing, null);
    try std.testing.expectEqualStrings("\x1b]7501;state=blocked;message=Waiting for user\x07", tw.getWritten());

    // idle
    tw.len = 0;
    try formatOsc7501(&tw, AgentState.idle, null);
    try std.testing.expectEqualStrings("\x1b]7501;state=idle\x07", tw.getWritten());

    // done
    tw.len = 0;
    try formatOsc7501(&tw, AgentState.done, null);
    try std.testing.expectEqualStrings("\x1b]7501;state=done\x07", tw.getWritten());

    // error_state
    tw.len = 0;
    try formatOsc7501(&tw, AgentState.error_state, null);
    try std.testing.expectEqualStrings("\x1b]7501;state=error\x07", tw.getWritten());
}

test "formatOsc9_4 sequence formatting" {
    var tw = TestWriter{};

    // active states
    try formatOsc9_4(&tw, AgentState.working);
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, "tool_use");
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, "running");
    try std.testing.expectEqualStrings("\x1b]9;4;3;0\x07", tw.getWritten());

    // waiting / reviewing
    tw.len = 0;
    try formatOsc9_4(&tw, AgentState.waiting);
    try std.testing.expectEqualStrings("\x1b]9;4;4;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, AgentState.reviewing);
    try std.testing.expectEqualStrings("\x1b]9;4;4;0\x07", tw.getWritten());

    // error
    tw.len = 0;
    try formatOsc9_4(&tw, AgentState.error_state);
    try std.testing.expectEqualStrings("\x1b]9;4;2;0\x07", tw.getWritten());

    // idle / done
    tw.len = 0;
    try formatOsc9_4(&tw, AgentState.idle);
    try std.testing.expectEqualStrings("\x1b]9;4;0;0\x07", tw.getWritten());

    tw.len = 0;
    try formatOsc9_4(&tw, AgentState.done);
    try std.testing.expectEqualStrings("\x1b]9;4;0;0\x07", tw.getWritten());
}
