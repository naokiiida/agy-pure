const std = @import("std");
const agy = @import("agy.zig");
const theme = @import("theme.zig");
const format = @import("format.zig");
const progress_bar = @import("progress_bar.zig");
const git_status = @import("git_status.zig");
const Segment = @import("segments.zig").Segment;
const layout = @import("layout");

const config = theme.active_config;
const p = config.palette;
const s = config.symbols;

var buf1: [64]u8 = undefined;
var buf2: [64]u8 = undefined;

/// Renders the complete status line driven by config/layout.zig.
pub fn render(
    writer: anytype,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
) !void {
    var first = true;
    inline for (layout.line1) |seg| {
        try renderSegment(writer, seg, session, repo, elapsed_ms, &first);
    }
    try writer.writeAll("\n");

    inline for (layout.bars) |seg| {
        try renderBar(writer, seg, session);
    }
}

fn renderSegment(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
    first: *bool,
) !void {
    switch (seg) {
        .model => {
            try writeSpace(writer, first);
            const name = session.getModelName();
            try theme.writeColored(writer, config, p.model_name_fg, name);
        },
        .context_icon => {
            if (session.context_window) |cw| {
                const pct_opt: ?f64 = cw.used_percentage orelse blk: {
                    if (cw.total_input_tokens) |toks| {
                        if (cw.context_window_size > 0) {
                            break :blk (@as(f64, @floatFromInt(toks)) / @as(f64, @floatFromInt(cw.context_window_size))) * 100.0;
                        }
                    }
                    break :blk null;
                };

                if (pct_opt) |pct_f| {
                    try writeSpace(writer, first);
                    const pct: u8 = @intFromFloat(@min(100.0, @max(0.0, pct_f)));
                    const numerator = @as(u16, pct) * theme.context_bar_steps + 50;
                    const level: u8 = @intCast(@min(theme.context_bar_steps - 1, numerator / 100));

                    const context_tokens = cw.getContextTokens();

                    const tok_str = format.formatTokens(&buf1, context_tokens);
                    const pct_str = std.fmt.bufPrint(&buf2, " ({d}%)", .{pct}) catch "?";

                    try writer.writeAll(p.bar_context_fg);
                    try writer.writeAll(theme.context_bar_glyphs[level]);
                    try writer.writeAll(" ");
                    try writer.writeAll(tok_str);
                    try writer.writeAll(pct_str);
                    try writer.writeAll(p.reset);
                }
            }
        },
        .timer => {
            if (elapsed_ms) |ms| {
                try writeSpace(writer, first);
                const dur_str = format.formatDuration(&buf1, ms);
                try theme.writeSymbol(writer, config, p.timer_fg, s.timer, dur_str);
            }
        },
        .cost => {
            if (session.cost) |cost| {
                if (cost.total_cost_usd > 0) {
                    try writeSpace(writer, first);
                    const cost_str = format.formatCost(&buf1, cost.total_cost_usd);
                    try theme.writeSymbol(writer, config, p.cost_usd_fg, s.cost_usd, cost_str);
                }
            }
        },
        .project => {
            const proj = session.getProjectDir();
            if (proj.len > 0 and !std.mem.eql(u8, proj, ".")) {
                try writeSpace(writer, first);
                const basename = if (std.mem.lastIndexOfScalar(u8, proj, '/')) |i| proj[i + 1 ..] else proj;
                try theme.writeColored(writer, config, p.directory_fg, basename);
            }
        },
        .git => {
            if (repo) |r| {
                if (r.branch_name.len > 0) {
                    try writeSpace(writer, first);
                    try theme.writeColored(writer, config, p.git_branch_fg, r.branch_name);
                    if (r.is_dirty) try theme.writeColored(writer, config, p.git_dirty_fg, s.git_dirty);
                    if (r.has_upstream) {
                        if (r.count_behind > 0) try theme.writeColored(writer, config, p.git_push_pull_fg, s.git_pull);
                        if (r.count_ahead > 0) try theme.writeColored(writer, config, p.git_push_pull_fg, s.git_push);
                    }
                }
            }
        },
        .lines => {
            if (session.cost) |cost| {
                if (cost.total_lines_added > 0 or cost.total_lines_removed > 0) {
                    try writeSpace(writer, first);
                    const added = std.fmt.bufPrint(&buf1, "+{d}", .{cost.total_lines_added}) catch "?";
                    try theme.writeColored(writer, config, p.lines_added_fg, added);
                    try writer.writeAll(" ");
                    const removed = std.fmt.bufPrint(&buf2, "-{d}", .{cost.total_lines_removed}) catch "?";
                    try theme.writeColored(writer, config, p.lines_removed_fg, removed);
                }
            }
        },
        .subagents => {
            const count = session.countSubagents();
            if (count > 0) {
                try writeSpace(writer, first);
                const sub_str = std.fmt.bufPrint(&buf1, "[{d} subagent{s}]", .{ count, if (count > 1) "s" else "" }) catch "?";
                try theme.writeColored(writer, config, p.badge_ok_fg, sub_str);
            }
        },
        else => {},
    }
}

fn writeSpace(writer: anytype, first: *bool) !void {
    if (first.*) {
        first.* = false;
        return;
    }
    try writer.writeAll(" ");
}

fn renderBar(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
) !void {
    switch (seg) {
        .bar_context => {
            const cw = session.context_window orelse return;
            const pct_f = cw.used_percentage orelse return;
            const pct: u8 = @intFromFloat(@min(100.0, @max(0.0, pct_f)));

            try theme.writeColored(writer, config, p.label_fg, "Ctx ");
            try progress_bar.renderSingle(writer, p.bar_context_fg, pct);
            const pct_str = std.fmt.bufPrint(&buf1, " {d}%", .{pct}) catch "?";
            try writer.writeAll(pct_str);
            try writer.writeAll("\n");
        },
        .bar_api_time => {
            const cost = session.cost orelse return;
            if (cost.total_duration_ms == 0) return;
            const pct = format.percentage(cost.total_api_duration_ms, cost.total_duration_ms);

            try theme.writeColored(writer, config, p.label_fg, "API ");
            try progress_bar.renderSingle(writer, p.bar_api_time_fg, pct);
            const api_str = format.formatDuration(&buf1, cost.total_api_duration_ms);
            const tot_str = format.formatDuration(&buf2, cost.total_duration_ms);
            try writer.writeAll(" ");
            try writer.writeAll(api_str);
            try writer.writeAll("/");
            try writer.writeAll(tot_str);
            try writer.writeAll("\n");
        },
        .bar_lines => {
            const cost = session.cost orelse return;
            if (cost.total_lines_added == 0 and cost.total_lines_removed == 0) return;

            try theme.writeColored(writer, config, p.label_fg, "Lin ");
            try progress_bar.renderDual(writer, p.lines_added_fg, p.lines_removed_fg, cost.total_lines_added, cost.total_lines_removed);
            const added = std.fmt.bufPrint(&buf1, " +{d}", .{cost.total_lines_added}) catch "?";
            const removed = std.fmt.bufPrint(&buf2, "/-{d}", .{cost.total_lines_removed}) catch "?";
            try theme.writeColored(writer, config, p.lines_added_fg, added);
            try theme.writeColored(writer, config, p.lines_removed_fg, removed);
            try writer.writeAll("\n");
        },
        else => {},
    }
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

test "render minimal session" {
    var tw = TestWriter{};

    const session = agy.Session{
        .conversation_id = "test-123",
        .cwd = "/home/user/project",
        .model = .{ .id = "gemini-3.8-flash", .display_name = "Gemini 3.8 Flash" },
        .workspace = .{ .current_dir = "/home/user/project", .project_dir = "/home/user/project" },
        .agent_state = "idle",
    };

    try render(&tw, session, null, null);
    const out = tw.getWritten();
    try std.testing.expect(out.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "Gemini 3.8 Flash") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "project") != null);
}

test "render with timer and context" {
    var tw = TestWriter{};

    const session = agy.Session{
        .conversation_id = "test-123",
        .cwd = "/home/user/project",
        .model = .{ .id = "gemini-3.8-flash", .display_name = "Gemini 3.8 Flash" },
        .workspace = .{ .current_dir = "/home/user/project", .project_dir = "/home/user/project" },
        .agent_state = "running",
        .context_window = .{
            .total_input_tokens = 54000,
            .context_window_size = 200000,
            .used_percentage = 27.0,
        },
    };

    try render(&tw, session, null, 4200);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "Gemini 3.8 Flash") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "54.0K") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "27%") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "4.2s") != null);
}
