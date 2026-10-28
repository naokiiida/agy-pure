const std = @import("std");
const assert = std.debug.assert;
const title = @import("title.zig");

pub const AgentState = title.AgentState;
pub const StateDescriptor = title.StateDescriptor;
pub const state_descriptors = title.state_descriptors;
pub const parseState = title.parseState;

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

/// Computes prompt cache hit rate percentage (0-100) from cache_read, cache_creation, and input tokens.
/// Formula: cache_ratio = cache_read_input_tokens / (cache_read + cache_creation + input_tokens)
pub fn computeCacheHitRate(cache_read: u64, cache_creation: u64, input_tokens: u64) ?u8 {
    if (cache_read == 0) return null;
    const total = cache_read + cache_creation + input_tokens;
    if (total == 0) return null;
    const pct = (cache_read * 100) / total;
    return if (pct > 100) 100 else @intCast(pct);
}

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
    cache_read_input_tokens: ?u64 = null,
    cache_creation_input_tokens: ?u64 = null,

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

    /// Computes prompt cache hit rate percentage from current_usage or context fields.
    pub fn getCacheHitRate(self: ContextWindow) ?u8 {
        var read_tokens: u64 = 0;
        var creation_tokens: u64 = 0;
        var input_toks: u64 = 0;

        if (self.current_usage) |val| {
            switch (val) {
                .object => |obj| {
                    if (obj.get("cache_read_input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) read_tokens = @intCast(tok.integer);
                    } else if (obj.get("cache_read_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) read_tokens = @intCast(tok.integer);
                    }
                    if (obj.get("cache_creation_input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) creation_tokens = @intCast(tok.integer);
                    } else if (obj.get("cache_creation_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) creation_tokens = @intCast(tok.integer);
                    }
                    if (obj.get("input_tokens")) |tok| {
                        if (tok == .integer and tok.integer > 0) input_toks = @intCast(tok.integer);
                    }
                },
                else => {},
            }
        }

        if (read_tokens == 0) {
            if (self.cache_read_input_tokens) |r| read_tokens = r;
        }
        if (creation_tokens == 0) {
            if (self.cache_creation_input_tokens) |c| creation_tokens = c;
        }
        if (input_toks == 0) {
            if (self.total_input_tokens) |i| input_toks = i;
        }

        return computeCacheHitRate(read_tokens, creation_tokens, input_toks);
    }
};

/// Subagent summary if subagents are active.
pub const Subagent = struct {
    role: ?[]const u8 = null,
    state: ?[]const u8 = null,
};

pub fn mapSubagentEmoji(role: []const u8, state: []const u8) []const u8 {
    var lower_buf: [64]u8 = undefined;
    const len = @min(role.len, lower_buf.len);
    for (0..len) |i| {
        lower_buf[i] = std.ascii.toLower(role[i]);
    }
    const r = lower_buf[0..len];

    if (std.mem.indexOf(u8, r, "res") != null or std.mem.indexOf(u8, r, "search") != null) {
        return "🔬";
    }
    if (std.mem.indexOf(u8, r, "deb") != null or std.mem.indexOf(u8, r, "bug") != null) {
        if (std.ascii.eqlIgnoreCase(state, "running") or std.ascii.eqlIgnoreCase(state, "working")) {
            return "🏃";
        }
        return "🐛";
    }
    if (std.mem.indexOf(u8, r, "code") != null or std.mem.indexOf(u8, r, "dev") != null) {
        return "💻";
    }
    if (std.mem.indexOf(u8, r, "rev") != null or std.mem.indexOf(u8, r, "audit") != null) {
        return "🧐";
    }
    if (std.mem.indexOf(u8, r, "test") != null) {
        return "🧪";
    }
    if (std.mem.indexOf(u8, r, "plan") != null) {
        return "📋";
    }
    if (std.mem.indexOf(u8, r, "doc") != null or std.mem.indexOf(u8, r, "write") != null) {
        return "📝";
    }
    if (std.ascii.eqlIgnoreCase(state, "thinking")) return "🤔";
    if (std.ascii.eqlIgnoreCase(state, "tool_use")) return "🛠️";
    if (std.ascii.eqlIgnoreCase(state, "running") or std.ascii.eqlIgnoreCase(state, "working")) return "🏃";
    if (std.ascii.eqlIgnoreCase(state, "idle")) return "😴";
    return "🤖";
}

pub fn mapSubagentRole(role: []const u8) []const u8 {
    var lower_buf: [64]u8 = undefined;
    const len = @min(role.len, lower_buf.len);
    for (0..len) |i| {
        lower_buf[i] = std.ascii.toLower(role[i]);
    }
    const r = lower_buf[0..len];

    if (std.mem.indexOf(u8, r, "res") != null) return "res";
    if (std.mem.indexOf(u8, r, "deb") != null) return "deb";
    if (std.mem.indexOf(u8, r, "dev") != null or std.mem.indexOf(u8, r, "code") != null) return "dev";
    if (std.mem.indexOf(u8, r, "rev") != null) return "rev";
    if (std.mem.indexOf(u8, r, "test") != null) return "test";
    if (std.mem.indexOf(u8, r, "plan") != null) return "plan";
    if (std.mem.indexOf(u8, r, "doc") != null) return "doc";

    const trimmed = std.mem.trim(u8, r, " _-");
    if (trimmed.len > 0) {
        return trimmed[0..@min(trimmed.len, 4)];
    }
    return "sub";
}

/// Formats the subagents badge. If role info is available, formats micro-tree
/// like `[2 subagents: 🔬 res, 🏃 deb]`, otherwise falls back to `[2 subagents]`.
pub fn formatSubagents(buf: []u8, session: Session) ?[]const u8 {
    const total_count = session.countSubagents();
    if (total_count == 0) return null;

    const val = session.subagents orelse return null;

    var parsed_roles: [8]struct {
        emoji: []const u8,
        role: []const u8,
    } = undefined;
    var role_count: usize = 0;

    switch (val) {
        .array => |arr| {
            for (arr.items) |item| {
                if (role_count >= parsed_roles.len) break;
                if (item == .object) {
                    const obj = item.object;
                    const r_val = obj.get("role") orelse obj.get("name") orelse obj.get("type");
                    if (r_val) |rv| {
                        if (rv == .string and rv.string.len > 0) {
                            const st_val = obj.get("state") orelse obj.get("status");
                            const st = if (st_val) |sv| (if (sv == .string) sv.string else "working") else "working";
                            parsed_roles[role_count] = .{
                                .emoji = mapSubagentEmoji(rv.string, st),
                                .role = mapSubagentRole(rv.string),
                            };
                            role_count += 1;
                        }
                    }
                }
            }
        },
        .object => |obj| {
            if (obj.get("subagents")) |sub_arr| {
                if (sub_arr == .array) {
                    for (sub_arr.array.items) |item| {
                        if (role_count >= parsed_roles.len) break;
                        if (item == .object) {
                            const o = item.object;
                            const r_val = o.get("role") orelse o.get("name") orelse o.get("type");
                            if (r_val) |rv| {
                                if (rv == .string and rv.string.len > 0) {
                                    const st_val = o.get("state") orelse o.get("status");
                                    const st = if (st_val) |sv| (if (sv == .string) sv.string else "working") else "working";
                                    parsed_roles[role_count] = .{
                                        .emoji = mapSubagentEmoji(rv.string, st),
                                        .role = mapSubagentRole(rv.string),
                                    };
                                    role_count += 1;
                                }
                            }
                        }
                    }
                }
            } else {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (role_count >= parsed_roles.len) break;
                    if (entry.value_ptr.* == .object) {
                        const o = entry.value_ptr.*.object;
                        const r_val = o.get("role") orelse o.get("name") orelse o.get("type");
                        if (r_val) |rv| {
                            if (rv == .string and rv.string.len > 0) {
                                const st_val = o.get("state") orelse o.get("status");
                                const st = if (st_val) |sv| (if (sv == .string) sv.string else "working") else "working";
                                parsed_roles[role_count] = .{
                                    .emoji = mapSubagentEmoji(rv.string, st),
                                    .role = mapSubagentRole(rv.string),
                                };
                                role_count += 1;
                            }
                        }
                    }
                }
            }
        },
        else => {},
    }

    if (role_count > 0) {
        var offset: usize = 0;
        const prefix = std.fmt.bufPrint(buf[offset..], "[{d} subagent{s}: ", .{ total_count, if (total_count == 1) "" else "s" }) catch return null;
        offset += prefix.len;
        for (parsed_roles[0..role_count], 0..) |pr, idx| {
            if (idx > 0) {
                const comma = std.fmt.bufPrint(buf[offset..], ", ", .{}) catch return null;
                offset += comma.len;
            }
            const item_str = std.fmt.bufPrint(buf[offset..], "{s} {s}", .{ pr.emoji, pr.role }) catch return null;
            offset += item_str.len;
        }
        const close_str = std.fmt.bufPrint(buf[offset..], "]", .{}) catch return null;
        offset += close_str.len;
        return buf[0..offset];
    }

    return std.fmt.bufPrint(buf, "[{d} subagent{s}]", .{ total_count, if (total_count == 1) "" else "s" }) catch null;
}

/// Parses a protobuf text format string like `title:"Some Title"` and extracts the unquoted title.
pub fn parsePbtxtTitle(content: []const u8, out_buf: []u8) ?[]const u8 {
    const key = "title";
    const key_pos = std.mem.indexOf(u8, content, key) orelse return null;
    var idx = key_pos + key.len;
    while (idx < content.len and (content[idx] == ' ' or content[idx] == '\t' or content[idx] == ':')) : (idx += 1) {}
    if (idx >= content.len or content[idx] != '"') return null;
    idx += 1;
    const title_start = idx;
    while (idx < content.len and content[idx] != '"') : (idx += 1) {
        if (content[idx] == '\\' and idx + 1 < content.len) {
            idx += 1;
        }
    }
    if (idx > content.len) return null;
    const raw_title = content[title_start..idx];
    if (raw_title.len == 0 or raw_title.len > out_buf.len) return null;

    var out_len: usize = 0;
    var i: usize = 0;
    while (i < raw_title.len) : (i += 1) {
        if (raw_title[i] == '\\' and i + 1 < raw_title.len) {
            i += 1;
        }
        if (out_len < out_buf.len) {
            out_buf[out_len] = raw_title[i];
            out_len += 1;
        }
    }
    return out_buf[0..out_len];
}

/// Main session state passed via stdin JSON from `agy` (or Claude Code).
pub const Session = struct {
    conversation_id: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    agent_state: ?[]const u8 = null, // "running", "idle", "waiting_for_user"
    model: ?Model = null,
    title: ?[]const u8 = null,
    session_title: ?[]const u8 = null,
    workspace: ?Workspace = null,
    version: ?[]const u8 = null,
    cost: ?Cost = null,
    total_cost_usd: ?f64 = null,
    cost_usd: ?f64 = null,
    context_window: ?ContextWindow = null,
    exceeds_200k_tokens: ?bool = null,
    subagents: ?std.json.Value = null,
    current_tool: ?std.json.Value = null,
    active_tool: ?std.json.Value = null,
    tool: ?std.json.Value = null,
    tool_name: ?[]const u8 = null,

    /// Retrieves total cost in USD if available (> 0).
    pub fn getTotalCostUsd(self: Session) ?f64 {
        if (self.cost) |c| {
            if (c.total_cost_usd > 0) return c.total_cost_usd;
        }
        if (self.total_cost_usd) |c| {
            if (c > 0) return c;
        }
        if (self.cost_usd) |c| {
            if (c > 0) return c;
        }
        return null;
    }

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

    /// Retrieves session title if available:
    /// 1. Checks explicit JSON fields (title, session_title).
    /// 2. Reads ~/.gemini/antigravity-cli/annotations/<conversation_id>.pbtxt (or fallback ~/.gemini/antigravity/...).
    pub fn getSessionTitle(self: Session, out_buf: []u8) ?[]const u8 {
        if (self.title) |t| {
            if (t.len > 0 and t.len <= out_buf.len) {
                @memcpy(out_buf[0..t.len], t);
                return out_buf[0..t.len];
            }
        }
        if (self.session_title) |t| {
            if (t.len > 0 and t.len <= out_buf.len) {
                @memcpy(out_buf[0..t.len], t);
                return out_buf[0..t.len];
            }
        }

        const conv_id = self.getConversationId();
        if (std.mem.eql(u8, conv_id, "default")) return null;

        const home = std.c.getenv("HOME") orelse return null;
        const home_str = std.mem.span(home);

        const candidate_dirs = [_][]const u8{
            "/.gemini/antigravity-cli/annotations",
            "/.gemini/antigravity/annotations",
        };

        var path_buf: [512]u8 = undefined;

        for (candidate_dirs) |sub_dir| {
            const full_path = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], "{s}{s}/{s}.pbtxt", .{
                home_str,
                sub_dir,
                conv_id,
            }) catch continue;
            path_buf[full_path.len] = 0;
            const c_path: [:0]const u8 = path_buf[0..full_path.len :0];

            const fd = std.c.open(c_path, .{ .ACCMODE = .RDONLY });
            if (fd < 0) continue;
            defer _ = std.c.close(fd);

            var content_buf: [256]u8 = undefined;
            const n = std.c.read(fd, &content_buf, content_buf.len);
            if (n <= 0) continue;

            if (parsePbtxtTitle(content_buf[0..@intCast(n)], out_buf)) |parsed_title| {
                return parsed_title;
            }
        }

        return null;
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
            return title.parseState(st) == .working;
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

test "computeCacheHitRate calculation" {
    // 8500 read / (8500 read + 500 create + 1000 input) = 85%
    try std.testing.expectEqual(@as(?u8, 85), computeCacheHitRate(8500, 500, 1000));
    // 0 read returns null
    try std.testing.expectEqual(@as(?u8, null), computeCacheHitRate(0, 500, 1000));
    // 100% hit rate
    try std.testing.expectEqual(@as(?u8, 100), computeCacheHitRate(1000, 0, 0));
    // total 0 returns null
    try std.testing.expectEqual(@as(?u8, null), computeCacheHitRate(0, 0, 0));
}

test "ContextWindow getCacheHitRate from current_usage object" {
    const allocator = std.testing.allocator;

    const mock_json =
        \\{
        \\  "conversation_id": "test-cache",
        \\  "cost": {
        \\    "total_cost_usd": 0.04
        \\  },
        \\  "context_window": {
        \\    "current_usage": {
        \\      "cache_read_input_tokens": 8500,
        \\      "cache_creation_input_tokens": 500,
        \\      "input_tokens": 1000,
        \\      "output_tokens": 200
        \\    }
        \\  }
        \\}
    ;

    const parsed = try parse(allocator, mock_json);
    defer parsed.deinit();

    const session = parsed.value;
    const cw = session.context_window.?;
    try std.testing.expectEqual(@as(?u8, 85), cw.getCacheHitRate());
    try std.testing.expectEqual(@as(?f64, 0.04), session.getTotalCostUsd());
}

test "formatSubagents micro-tree" {
    const allocator = std.testing.allocator;

    const mock_json =
        \\{
        \\  "conversation_id": "test-subagents",
        \\  "subagents": [
        \\    { "role": "researcher", "state": "working" },
        \\    { "role": "debugger", "state": "running" }
        \\  ]
        \\}
    ;

    const parsed = try parse(allocator, mock_json);
    defer parsed.deinit();

    var buf: [128]u8 = undefined;
    const res = formatSubagents(&buf, parsed.value);
    try std.testing.expect(res != null);
    try std.testing.expectEqualStrings("[2 subagents: 🔬 res, 🏃 deb]", res.?);
}

test "agy re-exports state_descriptors and AgentState correctly" {
    const desc = state_descriptors.get(.working);
    try std.testing.expectEqualStrings("🏃", desc.emoji);
    try std.testing.expectEqual(AgentState.working, parseState("thinking"));
}

test "parsePbtxtTitle extracts title correctly" {
    var buf: [128]u8 = undefined;

    // Standard protobuf text format
    const t1 = parsePbtxtTitle("title:\"Session Title Generation Feature\"", &buf);
    try std.testing.expect(t1 != null);
    try std.testing.expectEqualStrings("Session Title Generation Feature", t1.?);

    // With spaces
    const t2 = parsePbtxtTitle("  title : \"Fixing Eternal Terminal NixOS Build Error\"  ", &buf);
    try std.testing.expect(t2 != null);
    try std.testing.expectEqualStrings("Fixing Eternal Terminal NixOS Build Error", t2.?);

    // Unicode / Japanese
    const t3 = parsePbtxtTitle("title:\"象印炊飯器のH02エラーについて\"", &buf);
    try std.testing.expect(t3 != null);
    try std.testing.expectEqualStrings("象印炊飯器のH02エラーについて", t3.?);

    // Escaped character
    const t4 = parsePbtxtTitle("title:\"Refactor \\\"Pure\\\" Engine\"", &buf);
    try std.testing.expect(t4 != null);
    try std.testing.expectEqualStrings("Refactor \"Pure\" Engine", t4.?);

    // Missing title or invalid format
    try std.testing.expect(parsePbtxtTitle("status: OK", &buf) == null);
    try std.testing.expect(parsePbtxtTitle("title:", &buf) == null);
}

test "getSessionTitle from explicit JSON field" {
    const session = Session{
        .title = "Explicit Session Title",
    };
    var buf: [128]u8 = undefined;
    const t = session.getSessionTitle(&buf);
    try std.testing.expect(t != null);
    try std.testing.expectEqualStrings("Explicit Session Title", t.?);
}
