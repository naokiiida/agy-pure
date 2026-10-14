const std = @import("std");
const assert = std.debug.assert;

/// Represents model info from AGY / Claude CLI.
pub const Model = struct {
    id: []const u8 = "",
    display_name: []const u8 = "",
};

/// Represents workspace directory info.
pub const Workspace = struct {
    current_dir: []const u8 = "",
    project_dir: []const u8 = "",
};

/// Represents cost and usage statistics for the session if available.
pub const Cost = struct {
    total_cost_usd: f64 = 0,
    total_duration_ms: u64 = 0,
    total_api_duration_ms: u64 = 0,
    total_lines_added: u64 = 0,
    total_lines_removed: u64 = 0,
};

/// Token counts from the current / most recent invocation.
pub const CurrentUsage = struct {
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
    cache_creation_input_tokens: u64 = 0,
    cache_read_input_tokens: u64 = 0,
};

/// Context window usage data provided by the CLI.
pub const ContextWindow = struct {
    total_input_tokens: ?u64 = null,
    total_output_tokens: ?u64 = null,
    context_window_size: u64 = 200_000,
    used_percentage: ?f64 = null,
    remaining_percentage: ?f64 = null,
    current_usage: ?std.json.Value = null,

    pub fn getContextTokens(self: ContextWindow) u64 {
        if (self.current_usage) |val| {
            switch (val) {
                .integer => |i| if (i > 0) return @intCast(i),
                .object => |obj| {
                    var sum: u64 = 0;
                    if (obj.get("input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) sum += @intCast(tok.integer);
                    }
                    if (obj.get("cache_creation_input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) sum += @intCast(tok.integer);
                    }
                    if (obj.get("cache_read_input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) sum += @intCast(tok.integer);
                    }
                    if (sum > 0) return sum;
                },
                else => {},
            }
        }
        if (self.total_input_tokens) |t| return t;
        return 0;
    }
};

/// Subagent summary if subagents are active.
pub const Subagent = struct {
    role: ?[]const u8 = null,
    state: ?[]const u8 = null,
};

/// Main session state passed via stdin JSON from `agy` (or Claude Code).
pub const Session = struct {
    conversation_id: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    agent_state: ?[]const u8 = null, // "running", "idle", "waiting_for_user"
    model: ?Model = null,
    workspace: ?Workspace = null,
    version: ?[]const u8 = null,
    cost: ?Cost = null,
    context_window: ?ContextWindow = null,
    exceeds_200k_tokens: ?bool = null,
    subagents: ?std.json.Value = null,

    /// Returns the number of subagents active or registered in the session.
    pub fn countSubagents(self: Session) usize {
        const val = self.subagents orelse return 0;
        return switch (val) {
            .array => |arr| arr.items.len,
            .integer => |i| if (i > 0) @intCast(i) else 0,
            .object => |obj| blk: {
                if (obj.get("total")) |t| {
                    if (t == .integer) {
                        break :blk if (t.integer > 0) @as(usize, @intCast(t.integer)) else 0;
                    }
                }
                break :blk obj.count();
            },
            else => 0,
        };
    }

    /// Retrieves active conversation ID or falls back to session ID or default.
    pub fn getConversationId(self: Session) []const u8 {
        if (self.conversation_id) |id| {
            if (id.len > 0) return id;
        }
        if (self.session_id) |id| {
            if (id.len > 0) return id;
        }
        return "default";
    }

    /// Retrieves current directory.
    pub fn getCwd(self: Session) []const u8 {
        if (self.cwd) |c| {
            if (c.len > 0) return c;
        }
        if (self.workspace) |w| {
            if (w.current_dir.len > 0) return w.current_dir;
        }
        return ".";
    }

    /// Retrieves project root directory.
    pub fn getProjectDir(self: Session) []const u8 {
        if (self.workspace) |w| {
            if (w.project_dir.len > 0) return w.project_dir;
        }
        return self.getCwd();
    }

    /// Retrieves model display name (e.g., "Gemini 3.8 Flash").
    pub fn getModelName(self: Session) []const u8 {
        if (self.model) |m| {
            if (m.display_name.len > 0) return m.display_name;
            if (m.id.len > 0) return m.id;
        }
        return "AGY";
    }

    /// Returns true if the agent is actively executing a turn/prompt.
    pub fn isRunning(self: Session) bool {
        if (self.agent_state) |st| {
            return std.ascii.eqlIgnoreCase(st, "running")
                or std.ascii.eqlIgnoreCase(st, "processing")
                or std.ascii.eqlIgnoreCase(st, "working")
                or std.ascii.eqlIgnoreCase(st, "thinking")
                or std.ascii.eqlIgnoreCase(st, "tool_use");
        }
        return false;
    }
};

/// Parses JSON bytes from stdin into a Session struct.
pub fn parse(allocator: std.mem.Allocator, json_bytes: []const u8) !std.json.Parsed(Session) {
    if (json_bytes.len == 0) return error.EmptyJson;

    return std.json.parseFromSlice(
        Session,
        allocator,
        json_bytes,
        .{ .ignore_unknown_fields = true },
    );
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "parse agy payload with conversation_id and agent_state" {
    const allocator = std.testing.allocator;

    const mock_json =
        \\{
        \\  "conversation_id": "2d9212a9-658f-4185",
        \\  "cwd": "/Users/user/projects/myapp",
        \\  "agent_state": "running",
        \\  "model": {
        \\    "id": "gemini-3.8-flash",
        \\    "display_name": "Gemini 3.8 Flash"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/Users/user/projects/myapp",
        \\    "project_dir": "/Users/user/projects/myapp"
        \\  },
        \\  "version": "1.2.17",
        \\  "context_window": {
        \\    "total_input_tokens": 42100,
        \\    "total_output_tokens": 1250,
        \\    "context_window_size": 200000,
        \\    "used_percentage": 21.0,
        \\    "remaining_percentage": 79.0
        \\  }
        \\}
    ;

    const parsed = try parse(allocator, mock_json);
    defer parsed.deinit();

    const session = parsed.value;
    try std.testing.expectEqualStrings("2d9212a9-658f-4185", session.getConversationId());
    try std.testing.expectEqualStrings("/Users/user/projects/myapp", session.getCwd());
    try std.testing.expectEqualStrings("Gemini 3.8 Flash", session.getModelName());
    try std.testing.expect(session.isRunning());

    const cw = session.context_window.?;
    try std.testing.expectEqual(@as(?u64, 42100), cw.total_input_tokens);
    try std.testing.expectEqual(@as(?f64, 21.0), cw.used_percentage);
}

test "parse backward compatible claude payload" {
    const allocator = std.testing.allocator;

    const mock_json =
        \\{
        \\  "session_id": "claude-session-99",
        \\  "cwd": "/tmp",
        \\  "model": {
        \\    "id": "claude-sonnet-4-6",
        \\    "display_name": "Claude Sonnet 4.6"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/tmp",
        \\    "project_dir": "/tmp"
        \\  }
        \\}
    ;

    const parsed = try parse(allocator, mock_json);
    defer parsed.deinit();

    const session = parsed.value;
    try std.testing.expectEqualStrings("claude-session-99", session.getConversationId());
    try std.testing.expectEqualStrings("Claude Sonnet 4.6", session.getModelName());
    try std.testing.expect(!session.isRunning());
}
