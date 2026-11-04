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

    var is_title = false;
    var override_width: ?u16 = null;
    var override_theme: ?[]const u8 = null;
    var override_appearance: ?agy_pure.theme.Appearance = null;
    var override_color_mode: ?agy_pure.theme.ColorMode = null;

    var args_iter = init.args.iterate();
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
        } else if (std.mem.eql(u8, arg, "--light")) {
            override_appearance = .light;
        } else if (std.mem.eql(u8, arg, "--dark")) {
            override_appearance = .dark;
        } else if (std.mem.eql(u8, arg, "--truecolor") or std.mem.eql(u8, arg, "--24bit") or std.mem.eql(u8, arg, "--color=truecolor") or std.mem.eql(u8, arg, "--color=24bit")) {
            override_color_mode = .truecolor;
        } else if (std.mem.eql(u8, arg, "--256") or std.mem.eql(u8, arg, "--256color") or std.mem.eql(u8, arg, "--color=256")) {
            override_color_mode = .ansi256;
        } else if (std.mem.eql(u8, arg, "--no-color") or std.mem.eql(u8, arg, "--color=never")) {
            override_color_mode = .none;
        } else if (std.mem.eql(u8, arg, "--theme")) {
            if (args_iter.next()) |t| {
                override_theme = t;
            }
        } else if (std.mem.startsWith(u8, arg, "--theme=")) {
            override_theme = arg["--theme=".len..];
        } else if (std.mem.startsWith(u8, arg, "--color=")) {
            const val = arg["--color=".len..];
            if (std.mem.eql(u8, val, "truecolor") or std.mem.eql(u8, val, "24bit")) {
                override_color_mode = .truecolor;
            } else if (std.mem.eql(u8, val, "256")) {
                override_color_mode = .ansi256;
            } else if (std.mem.eql(u8, val, "never") or std.mem.eql(u8, val, "none")) {
                override_color_mode = .none;
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

    var stack_buf: [131072]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    var input_arena = std.heap.ArenaAllocator.init(fba.allocator());
    defer input_arena.deinit();

    const parsed = agy_pure.agy.parse(input_arena.allocator(), raw_json) catch blk: {
        var heap_arena = std.heap.ArenaAllocator.init(allocator);
        defer heap_arena.deinit();
        break :blk agy_pure.agy.parse(heap_arena.allocator(), raw_json) catch |err| {
            if (is_title) {
                var writer = StdoutWriter{};
                try writer.writeAll("🤖 idle | unknown\n");
                return;
            }
            std.debug.print("agy-pure: json parse error: {}\n", .{err});
            return;
        };
    };
    const session = parsed.value;

    var writer = StdoutWriter{};

    if (is_title) {
        const title_config = agy_pure.title.TitleConfig{};
        try agy_pure.title.render(&writer, session, title_config, null);
        return;
    }

    // Fetch repository state (branch, dirty, sync)
    var repo = agy_pure.git_status.fetch_repository(allocator, session.getCwd());
    defer repo.deinit(allocator);

    // Track active prompt duration if turn is running
    const elapsed_ms = agy_pure.timer.getElapsedMs(session.getConversationId(), session.isRunning());

    // Resolve theme configuration with dynamic TrueColor and appearance detection
    const active_cfg = agy_pure.theme.resolveConfig(
        override_theme,
        override_appearance,
        override_color_mode,
        true, // default to nerd symbols
    );

    // Render formatted status line with left/right segment alignment
    try agy_pure.display.renderWithConfig(&writer, session, &repo, elapsed_ms, override_width, &active_cfg);
}
