const std = @import("std");
const mem = std.mem;
const process = std.process;

/// Repository represents the aggregated state of the git repo.
pub const Repository = struct {
    branch_name: []const u8,
    count_ahead: u64,
    count_behind: u64,
    is_dirty: bool,
    has_upstream: bool,

    /// Initialize with defaults (empty/zero).
    pub fn init(target: *Repository) void {
        target.* = .{
            .branch_name = &[_]u8{},
            .count_ahead = 0,
            .count_behind = 0,
            .is_dirty = false,
            .has_upstream = false,
        };
    }

    /// Caller must call this to free the branch_name string.
    pub fn deinit(self: *Repository, allocator: mem.Allocator) void {
        if (self.branch_name.len > 0) {
            allocator.free(self.branch_name);
            self.branch_name = &[_]u8{};
        }
    }
};

/// Fetches git status using a single subprocess.
pub fn fetch_repository(allocator: mem.Allocator, io: std.Io, cwd: ?[]const u8) Repository {
    var repo: Repository = undefined;
    repo.init();

    const argv = &[_][]const u8{ "git", "-c", "core.optionalLocks=0", "status", "--porcelain=v2", "--branch" };

    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = if (cwd) |c| .{ .path = c } else .inherit,
    }) catch return repo;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    parse_v2_output(allocator, &repo, result.stdout);

    return repo;
}

fn parse_v2_output(allocator: mem.Allocator, repo: *Repository, output: []const u8) void {
    var lines = mem.tokenizeScalar(u8, output, '\n');

    while (lines.next()) |line| {
        if (line.len < 2) continue;

        if (line[0] == '#') {
            if (mem.startsWith(u8, line, "# branch.head ")) {
                const name = line["# branch.head ".len..];
                if (!mem.eql(u8, name, "(detached)")) {
                    repo.branch_name = allocator.dupe(u8, name) catch &[_]u8{};
                } else {
                    repo.branch_name = allocator.dupe(u8, "DETACHED") catch &[_]u8{};
                }
            } else if (mem.startsWith(u8, line, "# branch.upstream ")) {
                repo.has_upstream = true;
            } else if (mem.startsWith(u8, line, "# branch.ab ")) {
                var parts = mem.tokenizeScalar(u8, line["# branch.ab ".len..], ' ');
                const ahead_part = parts.next() orelse "+0";
                const behind_part = parts.next() orelse "-0";

                if (ahead_part.len > 1) {
                    repo.count_ahead = std.fmt.parseInt(u64, ahead_part[1..], 10) catch 0;
                }
                if (behind_part.len > 1) {
                    repo.count_behind = std.fmt.parseInt(u64, behind_part[1..], 10) catch 0;
                }
            }
        } else {
            // Any line not starting with '#' is a modified/untracked/staged change
            repo.is_dirty = true;
        }
    }
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "parse clean repository aligned with upstream" {
    const allocator = std.testing.allocator;

    var repo: Repository = undefined;
    repo.init();
    defer repo.deinit(allocator);

    const input =
        \\# branch.oid 9a99c7...
        \\# branch.head main
        \\# branch.upstream origin/main
        \\# branch.ab +0 -0
        \\
    ;

    parse_v2_output(allocator, &repo, input);

    try std.testing.expectEqualStrings("main", repo.branch_name);
    try std.testing.expectEqual(true, repo.has_upstream);
    try std.testing.expectEqual(0, repo.count_ahead);
    try std.testing.expectEqual(0, repo.count_behind);
    try std.testing.expectEqual(false, repo.is_dirty);
}

test "parse dirty repository with untracked file" {
    const allocator = std.testing.allocator;

    var repo: Repository = undefined;
    repo.init();
    defer repo.deinit(allocator);

    const input =
        \\# branch.head feature/a
        \\? new_file.txt
    ;

    parse_v2_output(allocator, &repo, input);

    try std.testing.expectEqualStrings("feature/a", repo.branch_name);
    try std.testing.expectEqual(true, repo.is_dirty);
}
