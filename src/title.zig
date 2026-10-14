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
};

/// Formats and writes the terminal window title.
pub fn render(
    writer: anytype,
    session: agy.Session,
    config: TitleConfig,
    branch_name: ?[]const u8,
) !void {
    const state_str = if (session.agent_state) |st| (if (st.len > 0) st else "idle") else "idle";
    const workspace = directory.extractWorkspace(session.getProjectDir());

    if (config.emoji) {
        const emoji = StateEmoji.get(state_str);
        try writer.writeAll(emoji);
        try writer.writeAll(" ");
    }

    try writer.writeAll(state_str);
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
        const sub_count = session.countSubagents();
        if (sub_count > 0) {
            var sub_buf: [64]u8 = undefined;
            const sub_str = std.fmt.bufPrint(&sub_buf, " [{d} subagent{s}]", .{ sub_count, if (sub_count == 1) "" else "s" }) catch "";
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
