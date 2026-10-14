const std = @import("std");
const assert = std.debug.assert;

/// Maximum length for the formatted cwd output.
const max_cwd_length: u32 = 300;
const component_limit: u32 = 3;

/// Formats the current working directory to show up to 3 folders deep.
/// If 3 components exceed 300 chars, shows 2 components instead.
/// For example: /home/user/projects/myapp becomes user/projects/myapp
/// Returns a slice of the original cwd string.
pub fn simplify(cwd: []const u8, home_env: ?[]const u8) []const u8 {
    assert(cwd.len <= std.math.maxInt(u32));
    const sep = std.fs.path.sep;

    var relative_cwd_idx: u32 = 0;

    if (home_env) |home| {
        // We slice OFF the home path AND the separator following it.
        if (std.mem.startsWith(u8, cwd, home) and cwd.len > home.len) {
            assert(home.len <= std.math.maxInt(u32));
            relative_cwd_idx = @intCast(home.len);
            if (cwd[home.len] == sep) {
                relative_cwd_idx += 1;
            }
        }
    }

    // Basic safety checks
    if (cwd.len == 0 or relative_cwd_idx == cwd.len) return cwd;

    var end_no_slash: u32 = @intCast(cwd.len);
    if (end_no_slash > 1 and cwd[end_no_slash - 1] == sep) {
        end_no_slash -= 1;
    }

    var candidate_starts = [_]u32{ 0, 0, 0 };
    var segments_found: u32 = 0;

    for (relative_cwd_idx..end_no_slash) |step| {
        const i: u32 = end_no_slash - @as(u32, @intCast(step)) - 1 + relative_cwd_idx;
        if (cwd[i] == sep or i == relative_cwd_idx) {
            if (segments_found < component_limit) {
                candidate_starts[segments_found] = i;
                segments_found += 1;
            } else {
                break;
            }
        }
    }

    if (segments_found < component_limit) {
        if (cwd[0] != sep) {
            candidate_starts[segments_found] = 0;
            segments_found += 1;
        }
    }

    var check_idx = segments_found;
    while (check_idx > 0) : (check_idx -= 1) {
        var start_idx = candidate_starts[check_idx - 1];
        if (start_idx > 0 and cwd[start_idx] == sep) {
            start_idx += 1;
        }

        if (cwd.len - start_idx <= max_cwd_length) {
            return cwd[start_idx..];
        }
    }

    if (segments_found > 0) {
        const start = candidate_starts[0];
        const safe_len = @min(cwd.len - start, max_cwd_length);
        return cwd[start .. start + safe_len];
    }

    return cwd;
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "simplify with home" {
    const result = simplify("~/user", null);
    try std.testing.expectEqualStrings("~/user", result);
}

test "simplify with 2 components" {
    const result = simplify("/home/user", null);
    try std.testing.expectEqualStrings("/home/user", result);
}

test "simplify with 4 components shows last 3" {
    const result = simplify("/home/user/projects/myapp", null);
    try std.testing.expectEqualStrings("user/projects/myapp", result);
}

test "simplify handles HOME without slash" {
    const result = simplify("/home/user1/projects/myapp", "/home/user1");
    try std.testing.expectEqualStrings("projects/myapp", result);
}
