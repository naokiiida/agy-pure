const std = @import("std");

fn currentMilliTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

/// Tracks the active prompt duration across status line ticks using a lightweight temp file.
pub fn getElapsedMs(conversation_id: []const u8, is_running: bool) ?u64 {
    const now: i64 = currentMilliTimestamp();

    var filename_buf: [128]u8 = undefined;
    const sanitized_id = sanitizeId(conversation_id);
    const path_slice = std.fmt.bufPrint(filename_buf[0 .. filename_buf.len - 1], "/tmp/agy_pure_{s}.timer", .{sanitized_id}) catch return null;
    filename_buf[path_slice.len] = 0;
    const path: [:0]const u8 = filename_buf[0..path_slice.len :0];

    if (is_running) {
        // Read start time if exists
        const fd = std.c.open(path, .{ .ACCMODE = .RDONLY });
        if (fd >= 0) {
            defer _ = std.c.close(fd);
            var buf: [32]u8 = undefined;
            const bytes_read = std.c.read(fd, &buf, buf.len);
            if (bytes_read > 0) {
                const trimmed = std.mem.trim(u8, buf[0..@intCast(bytes_read)], " \r\n");
                if (std.fmt.parseInt(i64, trimmed, 10)) |start_time| {
                    if (now >= start_time and (now - start_time) < 86_400_000) {
                        return @intCast(now - start_time);
                    }
                } else |_| {}
            }
        }

        // If file doesn't exist or is invalid, create with current timestamp
        const wfd = std.c.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(std.c.mode_t, 0o644));
        if (wfd >= 0) {
            defer _ = std.c.close(wfd);
            var num_buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&num_buf, "{d}\n", .{now}) catch return 0;
            _ = std.c.write(wfd, str.ptr, str.len);
            return 0;
        }

        return 0;
    } else {
        // Agent is idle: clean up timer file
        _ = std.c.unlink(path);
        return null;
    }
}

/// Strip non-alphanumeric chars for safe file naming.
fn sanitizeId(id: []const u8) []const u8 {
    var valid_len: usize = 0;
    for (id) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            valid_len += 1;
        } else {
            break;
        }
    }
    return if (valid_len > 0) id[0..valid_len] else "default";
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "sanitizeId handles uuids and symbols" {
    try std.testing.expectEqualStrings("2d9212a9-658f-4185", sanitizeId("2d9212a9-658f-4185"));
    try std.testing.expectEqualStrings("test", sanitizeId("test/invalid"));
}
