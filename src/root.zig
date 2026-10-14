const std = @import("std");

pub const agy = @import("agy.zig");
pub const directory = @import("directory.zig");
pub const display = @import("display.zig");
pub const format = @import("format.zig");
pub const git_status = @import("git_status.zig");
pub const progress_bar = @import("progress_bar.zig");
pub const segments = @import("segments.zig");
pub const theme = @import("theme.zig");
pub const timer = @import("timer.zig");

test {
    _ = @import("agy.zig");
    _ = @import("directory.zig");
    _ = @import("display.zig");
    _ = @import("format.zig");
    _ = @import("git_status.zig");
    _ = @import("progress_bar.zig");
    _ = @import("segments.zig");
    _ = @import("theme.zig");
    _ = @import("timer.zig");
}
