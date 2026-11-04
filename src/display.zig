const std = @import("std");
const agy = @import("agy.zig");
const theme = @import("theme.zig");
const format = @import("format.zig");
const progress_bar = @import("progress_bar.zig");
const git_status = @import("git_status.zig");
const Segment = @import("segments.zig").Segment;
const layout = @import("layout");

var buf1: [64]u8 = undefined;
var buf2: [64]u8 = undefined;

const BufferStream = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn init(buf: []u8) BufferStream {
        return .{ .buf = buf, .pos = 0 };
    }

    pub fn writeAll(self: *BufferStream, bytes: []const u8) !void {
        if (self.pos + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos .. self.pos + bytes.len], bytes);
        self.pos += bytes.len;
    }

    pub fn getWritten(self: *const BufferStream) []const u8 {
        return self.buf[0..self.pos];
    }
};

const spaces_chunk = "                                                                "; // 64 spaces

fn writePadding(writer: anytype, count: usize) !void {
    var remaining = count;
    while (remaining > 0) {
        const take = @min(remaining, spaces_chunk.len);
        try writer.writeAll(spaces_chunk[0..take]);
        remaining -= take;
    }
}

/// Determines terminal width (in columns):
/// 1. Uses explicit override_width if provided (> 0).
/// 2. Reads $COLUMNS environment variable.
/// 3. Queries ioctl(1, TIOCGWINSZ, &ws) on stdout.
/// 4. Queries ioctl on /dev/tty directly (handles piped stdout when invoked by agy/Claude Code).
/// 5. Defaults to fallback 80 columns.
pub fn getTerminalWidth(override_width: ?u16) u16 {
    if (override_width) |w| {
        if (w > 0) return w;
    }

    if (std.c.getenv("COLUMNS")) |col_ptr| {
        const col_str = std.mem.span(col_ptr);
        if (std.fmt.parseInt(u16, col_str, 10)) |w| {
            if (w > 0) return w;
        } else |_| {}
    }

    var ws: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };

    // Try stdout (fd 1), stderr (fd 2), stdin (fd 0)
    if (std.c.ioctl(1, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.col > 0) {
        return ws.col;
    }
    if (std.c.ioctl(2, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.col > 0) {
        return ws.col;
    }
    if (std.c.ioctl(0, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.col > 0) {
        return ws.col;
    }

    // When agy/Claude Code invokes statusLine as a subprocess, stdout/stdin are pipes (ENOTTY).
    // Opening /dev/tty (the controlling terminal) returns the real live window width.
    const tty_fd = std.c.open("/dev/tty", .{ .ACCMODE = .RDONLY });
    if (tty_fd >= 0) {
        defer _ = std.c.close(tty_fd);
        if (std.c.ioctl(tty_fd, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.col > 0) {
            return ws.col;
        }
    }

    return 80;
}

const has_split_layout = @hasDecl(layout, "left") and @hasDecl(layout, "right");
const left_segments: []const Segment = if (has_split_layout) layout.left else if (@hasDecl(layout, "line1")) layout.line1 else &.{};
const right_segments: []const Segment = if (has_split_layout) layout.right else &.{};
const margin: u16 = if (@hasDecl(layout, "right_margin")) layout.right_margin else 1;

/// Renders the complete status line driven by config/layout.zig with left/right segment alignment.
pub fn render(
    writer: anytype,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
    override_term_width: ?u16,
) !void {
    try renderWithConfig(writer, session, repo, elapsed_ms, override_term_width, null);
}

/// Renders status line using an explicitly resolved configuration (TrueColor, Appearance, etc.).
pub fn renderWithConfig(
    writer: anytype,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
    override_term_width: ?u16,
    custom_config: ?*const theme.Config,
) !void {
    const cfg = custom_config orelse &theme.active_config;

    var left_raw: [1024]u8 = undefined;
    var left_stream = BufferStream.init(&left_raw);
    var left_first = true;
    inline for (left_segments) |seg| {
        try renderSegmentWithConfig(&left_stream, seg, session, repo, elapsed_ms, &left_first, cfg);
    }
    const left_str = left_stream.getWritten();

    var right_raw: [1024]u8 = undefined;
    var right_stream = BufferStream.init(&right_raw);
    var right_first = true;
    inline for (right_segments) |seg| {
        try renderSegmentWithConfig(&right_stream, seg, session, repo, elapsed_ms, &right_first, cfg);
    }
    const right_str = right_stream.getWritten();

    const term_width = getTerminalWidth(override_term_width);

    if (right_str.len == 0) {
        try writer.writeAll(left_str);
        try writer.writeAll("\n");
    } else if (left_str.len == 0) {
        const right_width = format.visualWidth(right_str);
        if (term_width > right_width + margin) {
            const pad = term_width - right_width - margin;
            try writePadding(writer, pad);
        }
        try writer.writeAll(right_str);
        try writer.writeAll("\n");
    } else {
        const left_width = format.visualWidth(left_str);
        const right_width = format.visualWidth(right_str);
        const total_needed = left_width + right_width + margin;

        try writer.writeAll(left_str);
        if (term_width > total_needed) {
            const pad = term_width - total_needed;
            try writePadding(writer, pad);
        } else {
            // Narrow terminal fallback: single space separator, no wrap
            try writer.writeAll(" ");
        }
        try writer.writeAll(right_str);
        try writer.writeAll("\n");
    }

    inline for (layout.bars) |seg| {
        try renderBarWithConfig(writer, seg, session, cfg);
    }
}

pub fn renderSegment(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
    first: *bool,
) !void {
    try renderSegmentWithConfig(writer, seg, session, repo, elapsed_ms, first, null);
}

pub fn renderSegmentWithConfig(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
    repo: ?*const git_status.Repository,
    elapsed_ms: ?u64,
    first: *bool,
    custom_config: ?*const theme.Config,
) !void {
    const cfg = custom_config orelse &theme.active_config;
    const p = cfg.palette;
    const s = cfg.symbols;

    switch (seg) {
        .model => {
            try writeSpace(writer, first);
            const name = session.getModelName();
            try theme.writeColored(writer, cfg.*, p.model_name_fg, name);
        },
        .session_title => {
            try writeSpace(writer, first);
            var title_buf: [256]u8 = undefined;
            const name = session.getSessionTitle(&title_buf) orelse session.getModelName();
            try theme.writeColored(writer, cfg.*, p.session_title_fg, name);
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

                    if (p.bar_context_fg.len > 0) try writer.writeAll(p.bar_context_fg);
                    try writer.writeAll(theme.context_bar_glyphs[level]);
                    try writer.writeAll(" ");
                    try writer.writeAll(tok_str);
                    try writer.writeAll(pct_str);
                    if (p.bar_context_fg.len > 0 and p.reset.len > 0) try writer.writeAll(p.reset);

                    if (cw.getCacheHitRate()) |cache_pct| {
                        var cache_buf: [32]u8 = undefined;
                        const cache_str = std.fmt.bufPrint(&cache_buf, " ⚡{d}%", .{cache_pct}) catch "";
                        try theme.writeColored(writer, cfg.*, p.token_cache_read_fg, cache_str);
                    }
                }
            }
        },
        .timer => {
            if (elapsed_ms) |ms| {
                try writeSpace(writer, first);
                const dur_str = format.formatDuration(&buf1, ms);
                try theme.writeSymbol(writer, cfg.*, p.timer_fg, s.timer, dur_str);
            }
        },
        .cost => {
            if (session.getTotalCostUsd()) |total_cost| {
                try writeSpace(writer, first);
                const cost_str = format.formatCost(&buf1, total_cost);
                try theme.writeSymbol(writer, cfg.*, p.cost_usd_fg, s.cost_usd, cost_str);
            }
        },
        .project => {
            const proj = session.getProjectDir();
            if (proj.len > 0 and !std.mem.eql(u8, proj, ".")) {
                try writeSpace(writer, first);
                const basename = if (std.mem.lastIndexOfScalar(u8, proj, '/')) |i| proj[i + 1 ..] else proj;
                try theme.writeColored(writer, cfg.*, p.directory_fg, basename);
            }
        },
        .git => {
            if (repo) |r| {
                if (r.branch_name.len > 0) {
                    try writeSpace(writer, first);
                    try theme.writeColored(writer, cfg.*, p.git_branch_fg, r.branch_name);
                    if (r.is_dirty) try theme.writeColored(writer, cfg.*, p.git_dirty_fg, s.git_dirty);
                    if (r.has_upstream) {
                        if (r.count_behind > 0) try theme.writeColored(writer, cfg.*, p.git_push_pull_fg, s.git_pull);
                        if (r.count_ahead > 0) try theme.writeColored(writer, cfg.*, p.git_push_pull_fg, s.git_push);
                    }
                }
            }
        },
        .lines => {
            if (session.cost) |cost| {
                if (cost.total_lines_added > 0 or cost.total_lines_removed > 0) {
                    try writeSpace(writer, first);
                    const added = std.fmt.bufPrint(&buf1, "+{d}", .{cost.total_lines_added}) catch "?";
                    try theme.writeColored(writer, cfg.*, p.lines_added_fg, added);
                    try writer.writeAll(" ");
                    const removed = std.fmt.bufPrint(&buf2, "-{d}", .{cost.total_lines_removed}) catch "?";
                    try theme.writeColored(writer, cfg.*, p.lines_removed_fg, removed);
                }
            }
        },
        .subagents => {
            var sub_buf: [128]u8 = undefined;
            if (agy.formatSubagents(&sub_buf, session)) |sub_str| {
                try writeSpace(writer, first);
                try theme.writeColored(writer, cfg.*, p.badge_ok_fg, sub_str);
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

pub fn renderBar(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
) !void {
    try renderBarWithConfig(writer, seg, session, null);
}

pub fn renderBarWithConfig(
    writer: anytype,
    comptime seg: Segment,
    session: agy.Session,
    custom_config: ?*const theme.Config,
) !void {
    const cfg = custom_config orelse &theme.active_config;
    const p = cfg.palette;

    switch (seg) {
        .bar_context => {
            const cw = session.context_window orelse return;
            const pct_f = cw.used_percentage orelse return;
            const pct: u8 = @intFromFloat(@min(100.0, @max(0.0, pct_f)));

            try theme.writeColored(writer, cfg.*, p.label_fg, "Ctx ");
            try progress_bar.renderSingle(writer, p.bar_context_fg, pct, cfg);
            const pct_str = std.fmt.bufPrint(&buf1, " {d}%", .{pct}) catch "?";
            try writer.writeAll(pct_str);
            try writer.writeAll("\n");
        },
        .bar_api_time => {
            const cost = session.cost orelse return;
            if (cost.total_duration_ms == 0) return;
            const pct = format.percentage(cost.total_api_duration_ms, cost.total_duration_ms);

            try theme.writeColored(writer, cfg.*, p.label_fg, "API ");
            try progress_bar.renderSingle(writer, p.bar_api_time_fg, pct, cfg);
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

            try theme.writeColored(writer, cfg.*, p.label_fg, "Lin ");
            try progress_bar.renderDual(writer, p.lines_added_fg, p.lines_removed_fg, cost.total_lines_added, cost.total_lines_removed, cfg);
            const added = std.fmt.bufPrint(&buf1, " +{d}", .{cost.total_lines_added}) catch "?";
            const removed = std.fmt.bufPrint(&buf2, "/-{d}", .{cost.total_lines_removed}) catch "?";
            try theme.writeColored(writer, cfg.*, p.lines_added_fg, added);
            try theme.writeColored(writer, cfg.*, p.lines_removed_fg, removed);
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

    try render(&tw, session, null, null, null);
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

    try render(&tw, session, null, 4200, 100);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "Gemini 3.8 Flash") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "54.0K") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "27%") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "4.2s") != null);
}

test "render with cache efficiency badge and cost" {
    var tw = TestWriter{};

    const session = agy.Session{
        .conversation_id = "test-cache-cost",
        .cwd = "/home/user/project",
        .model = .{ .id = "gemini-3.8-flash", .display_name = "Gemini 3.8 Flash" },
        .workspace = .{ .current_dir = "/home/user/project", .project_dir = "/home/user/project" },
        .cost = .{ .total_cost_usd = 0.04 },
        .context_window = .{
            .total_input_tokens = 1000,
            .cache_read_input_tokens = 8500,
            .cache_creation_input_tokens = 500,
            .context_window_size = 200000,
            .used_percentage = 5.0,
        },
    };

    try render(&tw, session, null, null, 100);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "⚡85%") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "$0.04") != null);
}

test "renderSegment session_title" {
    var tw = TestWriter{};
    const session = agy.Session{
        .title = "Custom Session Work",
        .model = .{ .id = "gemini-3.8-flash", .display_name = "Gemini 3.8 Flash" },
    };
    var first: bool = true;
    try renderSegment(&tw, .session_title, session, null, null, &first);
    const out = tw.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "Custom Session Work") != null);
}

test "render split layout wide vs narrow terminal" {
    var tw_wide = TestWriter{};
    const session = agy.Session{
        .conversation_id = "test-split",
        .cwd = "/home/user/project",
        .model = .{ .id = "gemini-3.8-flash", .display_name = "Gemini 3.8 Flash" },
        .workspace = .{ .current_dir = "/home/user/project", .project_dir = "/home/user/project" },
        .cost = .{ .total_cost_usd = 0.04 },
    };

    // Wide terminal: should have padding spaces between left (Gemini...) and right ($0.04)
    try render(&tw_wide, session, null, null, 100);
    const wide_out = tw_wide.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, wide_out, "   ") != null);

    // Narrow terminal: should fall back to single space without crashing or wrapping
    var tw_narrow = TestWriter{};
    try render(&tw_narrow, session, null, null, 20);
    const narrow_out = tw_narrow.getWritten();
    try std.testing.expect(narrow_out.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, narrow_out, "$0.04") != null);
}

test "getTerminalWidth override" {
    try std.testing.expectEqual(@as(u16, 120), getTerminalWidth(120));
    try std.testing.expect(getTerminalWidth(null) > 0);
}
