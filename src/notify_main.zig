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
    _ = init;
    const allocator = std.heap.smp_allocator;

    var stdin_buf: [65536]u8 = undefined;
    var total_read: usize = 0;

    // Read hook payload from stdin
    while (total_read < stdin_buf.len) {
        const n = std.c.read(0, stdin_buf[total_read..].ptr, stdin_buf.len - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }

    var writer = StdoutWriter{};

    if (total_read == 0) {
        // Output empty JSON for hook contract
        try writer.writeAll("{}\n");
        return;
    }

    const raw_json = stdin_buf[0..total_read];

    var input_arena = std.heap.ArenaAllocator.init(allocator);
    defer input_arena.deinit();

    const parsed = std.json.parseFromSlice(agy_pure.notify.StopHookPayload, input_arena.allocator(), raw_json, .{
        .ignore_unknown_fields = true,
    }) catch {
        try writer.writeAll("{}\n");
        return;
    };
    const payload = parsed.value;

    // Filter out intermediate subagents / background tasks: only notify on full turn completion
    if (!payload.isFullyIdle()) {
        try writer.writeAll("{}\n");
        return;
    }

    // Determine workspace name
    const ws_path = payload.getWorkspacePath() orelse "";
    const workspace = agy_pure.directory.extractWorkspace(ws_path);

    // Determine error status
    const err_opt = payload.getError();
    const is_error = err_opt != null or std.mem.eql(u8, payload.getTerminationReason(), "ERROR");

    // Extract dynamic summary
    var summary_alloc: ?[]const u8 = null;
    if (err_opt) |e| {
        summary_alloc = try agy_pure.notify.cleanSummary(input_arena.allocator(), e, 100);
    } else if (payload.getTranscriptPath()) |tp| {
        if (agy_pure.notify.extractLastResponse(input_arena.allocator(), tp)) |raw_resp| {
            summary_alloc = try agy_pure.notify.cleanSummary(input_arena.allocator(), raw_resp, 100);
        }
    }

    const body = summary_alloc orelse "Turn complete, ready for input.";

    // Title construction
    var title_buf: [128]u8 = undefined;
    const title = if (is_error)
        std.fmt.bufPrint(&title_buf, "❌ Error | {s}", .{workspace}) catch "❌ Error"
    else
        std.fmt.bufPrint(&title_buf, "😴 idle | {s}", .{workspace}) catch "😴 idle";

    // Format OSC 777 escape sequence into stack buffer
    var osc_buf: [512]u8 = undefined;
    var stack_writer = agy_pure.notify.StackWriter{ .buf = &osc_buf };
    agy_pure.notify.formatOsc777(&stack_writer, title, body) catch {};

    const osc_bytes = stack_writer.getWritten();

    // Write directly to /dev/tty so terminal emulator (Ghostty / cmux) displays the notification
    if (osc_bytes.len > 0) {
        const tty_fd = std.c.open("/dev/tty", .{ .ACCMODE = .WRONLY });
        if (tty_fd >= 0) {
            defer _ = std.c.close(tty_fd);
            _ = std.c.write(tty_fd, osc_bytes.ptr, osc_bytes.len);
        }
    }

    // Return empty JSON object to satisfy Antigravity hook contract
    try writer.writeAll("{}\n");
}
