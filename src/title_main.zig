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
}
