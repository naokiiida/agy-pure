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

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    std.c.abort();
}

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.smp_allocator;

    var is_notification = false;
    var args_iter = init.args.iterate();
    _ = args_iter.next(); // skip binary name

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            var writer = StdoutWriter{};
            try writer.writeAll("agy_notify " ++ agy_pure.version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            var writer = StdoutWriter{};
            try writer.writeAll(
                \\Usage: agy_notify [options]
                \\
                \\Terminal notification hook for Google Antigravity CLI (agy).
                \\Reads stop/notification JSON payload from stdin and emits OSC 777/OSC 9 to /dev/tty.
                \\
                \\Options:
                \\  -v, --version        Show version
                \\  -e, --event <name>   Event type (stop, notification)
                \\  -h, --help           Show this help message
                \\
            );
            return;
        } else if (std.mem.eql(u8, arg, "--event=notification") or std.mem.eql(u8, arg, "-e=notification")) {
            is_notification = true;
        } else if (std.mem.eql(u8, arg, "--event") or std.mem.eql(u8, arg, "-e")) {
            if (args_iter.next()) |val| {
                if (std.mem.eql(u8, val, "notification")) {
                    is_notification = true;
                }
            }
        }
    }

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

    var stack_buf: [131072]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    var input_arena = std.heap.ArenaAllocator.init(fba.allocator());
    defer input_arena.deinit();

    const parsed = std.json.parseFromSlice(agy_pure.notify.StopHookPayload, input_arena.allocator(), raw_json, .{
        .ignore_unknown_fields = true,
    }) catch blk: {
        var heap_arena = std.heap.ArenaAllocator.init(allocator);
        defer heap_arena.deinit();
        break :blk std.json.parseFromSlice(agy_pure.notify.StopHookPayload, heap_arena.allocator(), raw_json, .{
            .ignore_unknown_fields = true,
        }) catch {
            try writer.writeAll("{}\n");
            return;
        };
    };
    const payload = parsed.value;

    // Filter out intermediate subagents / background tasks: only notify on full turn completion
    if (!is_notification and !payload.isFullyIdle()) {
        try writer.writeAll("{}\n");
        return;
    }

    // Determine error status
    const err_opt = payload.getError();
    const is_error = err_opt != null or std.mem.eql(u8, payload.getTerminationReason(), "ERROR");

    // Consume and clean up timer file if normal stop
    if (!is_notification) {
        _ = agy_pure.timer.finishTimerMs(payload.getConversationId());
    }

    // Extract dynamic summary
    var summary_alloc: ?[]const u8 = null;
    if (err_opt) |e| {
        summary_alloc = try agy_pure.notify.cleanSummary(input_arena.allocator(), e, 100);
    } else if (payload.getTranscriptPath()) |tp| {
        if (agy_pure.notify.extractLastResponse(input_arena.allocator(), tp)) |raw_resp| {
            summary_alloc = try agy_pure.notify.cleanSummary(input_arena.allocator(), raw_resp, 100);
        }
    }

    const body = summary_alloc orelse if (is_notification) "Action required" else "Turn complete";

    // Title construction (Done, ❌ Error, or ⏳ Needs input)
    // Note: Tab title (surface.title) already carries the live duration ticker in Ghostty's subtitle
    const title = agy_pure.notify.formatNotificationTitle(is_error, is_notification);

    // Format dual OSC notifications (OSC 777 + OSC 9) into stack buffer
    var osc_buf: [1024]u8 = undefined;
    var stack_writer = agy_pure.notify.StackWriter{ .buf = &osc_buf };
    agy_pure.notify.formatDualOsc(&stack_writer, title, body) catch {};

    const raw_osc = stack_writer.getWritten();

    // Write directly to /dev/tty so terminal emulator (Ghostty / cmux / WezTerm / iTerm2) displays notification
    if (raw_osc.len > 0) {
        var final_buf: [2048]u8 = undefined;
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

    // Return empty JSON object to satisfy Antigravity hook contract
    try writer.writeAll("{}\n");
}
