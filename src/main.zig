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

    var stdin_buf: [65536]u8 = undefined;
    var total_read: usize = 0;

    // Read payload from stdin (statusline passes single JSON payload)
    while (total_read < stdin_buf.len) {
        const n = std.c.read(0, stdin_buf[total_read..].ptr, stdin_buf.len - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }

    if (total_read == 0) return;

    const raw_json = stdin_buf[0..total_read];

    var input_arena = std.heap.ArenaAllocator.init(allocator);
    defer input_arena.deinit();

    const parsed = agy_pure.agy.parse(input_arena.allocator(), raw_json) catch |err| {
        std.debug.print("agy-pure: json parse error: {}\n", .{err});
        return;
    };
    const session = parsed.value;

    // Fetch repository state (branch, dirty, sync)
    var repo = agy_pure.git_status.fetch_repository(allocator, io, session.getCwd());
    defer repo.deinit(allocator);

    // Track active prompt duration if turn is running
    const elapsed_ms = agy_pure.timer.getElapsedMs(session.getConversationId(), session.isRunning());

    // Render formatted status line
    var writer = StdoutWriter{};
    try agy_pure.display.render(&writer, session, &repo, elapsed_ms);
}
