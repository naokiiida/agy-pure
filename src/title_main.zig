const std = @import("std");
const agy_pure = @import("agy_pure");

pub const StdoutWriter = struct {
    pub fn writeAll(self: *StdoutWriter, bytes: []const u8) !void {
        _ = self;
        var index: usize = 0;
        while (index < bytes.len) {
            const written = std.c.write(1, bytes[index..].ptr, bytes.len - index);
            if (written < 0) return error.WriteFailed;
            if (written == 0) return error.WriteZero;
            index += @intCast(written);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;

    var config = agy_pure.title.TitleConfig{};

    var args_iter = init.minimal.args.iterate();
    _ = args_iter.next(); // skip binary name

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            var writer = StdoutWriter{};
            try writer.writeAll(
                \\Usage: agy_title [options]
                \\
                \\Terminal title generator for Google Antigravity CLI (agy).
                \\Reads JSON state payload from stdin and writes formatted title to stdout.
                \\
                \\Options:
                \\  --no-emoji       Disable status emoji prefix
                \\  --git            Show current git branch name in parentheses
                \\  --subagents      Show active subagents count badge
                \\  --osc-progress   Emit OSC 7501 & OSC 9;4 escape sequences (default: on)
                \\  --no-osc-progress Disable OSC 7501 & OSC 9;4 escape sequences
                \\  -h, --help       Show this help message
                \\
            );
            return;
        } else if (std.mem.eql(u8, arg, "--no-emoji")) {
            config.emoji = false;
        } else if (std.mem.eql(u8, arg, "--git")) {
            config.show_branch = true;
        } else if (std.mem.eql(u8, arg, "--subagents")) {
            config.show_subagents = true;
        } else if (std.mem.eql(u8, arg, "--osc-progress")) {
            config.osc_progress = true;
        } else if (std.mem.eql(u8, arg, "--no-osc-progress")) {
            config.osc_progress = false;
        }
    }

    var stdin_buf: [65536]u8 = undefined;
    var total_read: usize = 0;

    // Read payload from stdin (title passes single JSON payload)
    while (total_read < stdin_buf.len) {
        const n = std.c.read(0, stdin_buf[total_read..].ptr, stdin_buf.len - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }

    if (total_read == 0) {
        var writer = StdoutWriter{};
        try writer.writeAll("🤖 idle | unknown\n");
        return;
    }

    const raw_json = stdin_buf[0..total_read];

    var input_arena = std.heap.ArenaAllocator.init(allocator);
    defer input_arena.deinit();

    const parsed = agy_pure.agy.parse(input_arena.allocator(), raw_json) catch {
        var writer = StdoutWriter{};
        try writer.writeAll("🤖 idle | unknown\n");
        return;
    };
    const session = parsed.value;

    const state_str = if (session.agent_state) |st| (if (st.len > 0) st else "idle") else "idle";

    var tool_action_opt: ?[]const u8 = null;
    if (std.ascii.eqlIgnoreCase(state_str, "tool_use")) {
        tool_action_opt = agy_pure.title.extractToolAction(input_arena.allocator(), session);
        config.tool_action = tool_action_opt;
    }

    var branch_name: ?[]const u8 = null;
    var repo_opt: ?agy_pure.git_status.Repository = null;
    defer if (repo_opt) |*r| r.deinit(allocator);

    if (config.show_branch) {
        repo_opt = agy_pure.git_status.fetch_repository(allocator, init.io, session.getCwd());
        if (repo_opt) |*r| {
            if (r.branch_name.len > 0 and !std.mem.eql(u8, r.branch_name, "DETACHED")) {
                branch_name = r.branch_name;
            }
        }
    }

    var writer = StdoutWriter{};
    try agy_pure.title.render(&writer, session, config, branch_name);

    if (config.osc_progress) {
        const status_msg = if (std.ascii.eqlIgnoreCase(state_str, "tool_use"))
            (tool_action_opt orelse "tool_use")
        else
            state_str;

        var osc_buf: [512]u8 = undefined;
        var stack_writer = agy_pure.notify.StackWriter{ .buf = &osc_buf };
        agy_pure.title.formatOsc7501(&stack_writer, state_str, status_msg) catch {};
        agy_pure.title.formatOsc9_4(&stack_writer, state_str) catch {};

        const raw_osc = stack_writer.getWritten();
        if (raw_osc.len > 0) {
            var final_buf: [1024]u8 = undefined;
            var final_writer = agy_pure.notify.StackWriter{ .buf = &final_buf };

            if (agy_pure.notify.isTmux()) {
                agy_pure.notify.wrapTmux(&final_writer, raw_osc) catch {};
            } else {
                final_writer.writeAll(raw_osc) catch {};
            }

            const out_bytes = final_writer.getWritten();
            if (out_bytes.len > 0) {
                const tty_fd = std.c.open("/dev/tty", .{ .ACCMODE = .WRONLY });
                if (tty_fd >= 0) {
                    defer _ = std.c.close(tty_fd);
                    _ = std.c.write(tty_fd, out_bytes.ptr, out_bytes.len);
                }
            }
        }
    }
}
