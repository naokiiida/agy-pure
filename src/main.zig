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
    const io = init.io;

    var is_title = false;
    var override_width: ?u16 = null;

    var args_iter = init.minimal.args.iterate();
    if (args_iter.next()) |a0| {
        if (std.mem.endsWith(u8, a0, "agy_title") or std.mem.endsWith(u8, a0, "title")) {
            is_title = true;
        }
    }

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "title") or std.mem.eql(u8, arg, "--title")) {
            is_title = true;
        } else if (std.mem.eql(u8, arg, "--terminal-width") or std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--width")) {
            if (args_iter.next()) |val_str| {
                if (std.fmt.parseInt(u16, val_str, 10)) |w| {
                    override_width = w;
                } else |_| {}
            }
        }
    }

    var stdin_buf: [65536]u8 = undefined;
    var total_read: usize = 0;

    // Read payload from stdin (statusline or title passes single JSON payload)
    while (total_read < stdin_buf.len) {
        const n = std.c.read(0, stdin_buf[total_read..].ptr, stdin_buf.len - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }

    if (total_read == 0) {
        if (is_title) {
            var writer = StdoutWriter{};
            try writer.writeAll("🤖 idle | unknown\n");
        }
        return;
    }

    const raw_json = stdin_buf[0..total_read];

    var input_arena = std.heap.ArenaAllocator.init(allocator);
    defer input_arena.deinit();

    const parsed = agy_pure.agy.parse(input_arena.allocator(), raw_json) catch |err| {
        if (is_title) {
            var writer = StdoutWriter{};
            try writer.writeAll("🤖 idle | unknown\n");
            return;
        }
        std.debug.print("agy-pure: json parse error: {}\n", .{err});
        return;
    };
    const session = parsed.value;

    var writer = StdoutWriter{};

    if (is_title) {
        const title_config = agy_pure.title.TitleConfig{};
        try agy_pure.title.render(&writer, session, title_config, null);
        return;
    }

    // Fetch repository state (branch, dirty, sync)
    var repo = agy_pure.git_status.fetch_repository(allocator, io, session.getCwd());
    defer repo.deinit(allocator);

    // Track active prompt duration if turn is running
    const elapsed_ms = agy_pure.timer.getElapsedMs(session.getConversationId(), session.isRunning());

    // Render formatted status line with left/right segment alignment
    try agy_pure.display.render(&writer, session, &repo, elapsed_ms, override_width);
}
