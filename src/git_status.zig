const std = @import("std");
const mem = std.mem;

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

/// Reads current git branch directly from .git/HEAD in microseconds (< 20 µs)
/// without spawning any subprocess. Handles regular git directories, git worktrees
/// (where .git is a file with 'gitdir: ...'), submodules, and detached HEAD.
pub fn read_branch(allocator: mem.Allocator, cwd: ?[]const u8) ?[]const u8 {
    var git_path_buf: [1024]u8 = undefined;
    const base_dir = if (cwd) |c| (if (c.len > 0) c else ".") else ".";

    const git_dir_path = std.fmt.bufPrint(&git_path_buf, "{s}/.git", .{base_dir}) catch return null;

    var path_z_buf: [1024]u8 = undefined;
    if (git_dir_path.len + 1 > path_z_buf.len) return null;
    @memcpy(path_z_buf[0..git_dir_path.len], git_dir_path);
    path_z_buf[git_dir_path.len] = 0;
    const git_z: [*:0]const u8 = @ptrCast(path_z_buf[0..git_dir_path.len]);

    const git_fd = std.c.open(git_z, .{ .ACCMODE = .RDONLY });
    if (git_fd < 0) return null;

    var head_path_buf: [1024]u8 = undefined;
    var head_path_len: usize = 0;

    // Check if regular file (worktree or submodule: "gitdir: <path>")
    var gitdir_content: [512]u8 = undefined;
    const n = std.c.read(git_fd, &gitdir_content, gitdir_content.len);
    _ = std.c.close(git_fd);

    if (n > 0 and std.mem.startsWith(u8, std.mem.trim(u8, gitdir_content[0..@intCast(n)], " \r\n\t"), "gitdir:")) {
        const line = std.mem.trim(u8, gitdir_content[0..@intCast(n)], " \r\n\t");
        const raw_target = std.mem.trim(u8, line["gitdir:".len..], " \r\n\t");

        // If target path is relative, resolve relative to base_dir
        const real_gitdir = if (std.fs.path.isAbsolute(raw_target))
            raw_target
        else blk: {
            var rel_buf: [1024]u8 = undefined;
            const res = std.fmt.bufPrint(&rel_buf, "{s}/{s}", .{ base_dir, raw_target }) catch return null;
            break :blk res;
        };

        const hp = std.fmt.bufPrint(&head_path_buf, "{s}/HEAD", .{real_gitdir}) catch return null;
        head_path_len = hp.len;
    } else {
        const hp = std.fmt.bufPrint(&head_path_buf, "{s}/.git/HEAD", .{base_dir}) catch return null;
        head_path_len = hp.len;
    }

    if (head_path_len + 1 > path_z_buf.len) return null;
    @memcpy(path_z_buf[0..head_path_len], head_path_buf[0..head_path_len]);
    path_z_buf[head_path_len] = 0;
    const head_z: [*:0]const u8 = @ptrCast(path_z_buf[0..head_path_len]);

    const head_fd = std.c.open(head_z, .{ .ACCMODE = .RDONLY });
    if (head_fd < 0) return null;
    defer _ = std.c.close(head_fd);

    var head_content: [256]u8 = undefined;
    const hn = std.c.read(head_fd, &head_content, head_content.len);
    if (hn <= 0) return null;
    const head_str = std.mem.trim(u8, head_content[0..@intCast(hn)], " \r\n\t");

    if (std.mem.startsWith(u8, head_str, "ref: refs/heads/")) {
        const branch = head_str["ref: refs/heads/".len..];
        return allocator.dupe(u8, branch) catch null;
    }

    // Detached commit hash or tag
    if (head_str.len >= 7) {
        return allocator.dupe(u8, "DETACHED") catch null;
    }

    return null;
}

extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

/// Executes git status via lightweight fork/execvp directly without std.Io / Io.Threaded.
fn execute_git_status(allocator: mem.Allocator, repo: *Repository, cwd: ?[]const u8) void {
    var pipe_fds: [2]c_int = undefined;
    if (std.c.pipe(&pipe_fds) != 0) return;

    const pid = std.c.fork();
    if (pid < 0) {
        _ = std.c.close(pipe_fds[0]);
        _ = std.c.close(pipe_fds[1]);
        return;
    }

    if (pid == 0) {
        _ = std.c.close(pipe_fds[0]);
        if (cwd) |c| {
            if (c.len > 0) {
                var cwd_buf: [1024]u8 = undefined;
                if (c.len + 1 <= cwd_buf.len) {
                    @memcpy(cwd_buf[0..c.len], c);
                    cwd_buf[c.len] = 0;
                    _ = std.c.chdir(@ptrCast(&cwd_buf));
                }
            }
        }

        _ = std.c.dup2(pipe_fds[1], 1);
        _ = std.c.close(pipe_fds[1]);

        const argv = [_:null]?[*:0]const u8{
            "git",
            "-c",
            "core.optionalLocks=0",
            "status",
            "--porcelain=v2",
            "--branch",
            null,
        };

        _ = execvp("git", @ptrCast(&argv));
        std.c._exit(1);
    }

    _ = std.c.close(pipe_fds[1]);
    defer _ = std.c.close(pipe_fds[0]);

    var output_buf: [8192]u8 = undefined;
    var total_read: usize = 0;
    while (total_read < output_buf.len) {
        const n = std.c.read(pipe_fds[0], output_buf[total_read..].ptr, output_buf.len - total_read);
        if (n <= 0) break;
        total_read += @intCast(n);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);

    if (total_read > 0) {
        parse_v2_output(allocator, repo, output_buf[0..total_read]);
    }
}

/// Fetches git status using zero-subprocess fast-path when outside git, and direct posix_spawnp inside git.
pub fn fetch_repository(allocator: mem.Allocator, cwd: ?[]const u8) Repository {
    var repo: Repository = undefined;
    repo.init();

    // Fast-path: check if we are in a git repository
    const fast_branch = read_branch(allocator, cwd);
    if (fast_branch == null) {
        // Not a git repository! Return empty repo immediately in < 20 µs with 0 subprocess spawns.
        return repo;
    }
    repo.branch_name = fast_branch.?;

    // Now execute git status via lightweight posix_spawnp (zero Io.Threaded dependency)
    execute_git_status(allocator, &repo, cwd);

    return repo;
}

fn parse_v2_output(allocator: mem.Allocator, repo: *Repository, output: []const u8) void {
    var lines = mem.tokenizeScalar(u8, output, '\n');

    while (lines.next()) |line| {
        if (line.len < 2) continue;

        if (line[0] == '#') {
            if (mem.startsWith(u8, line, "# branch.head ")) {
                const name = line["# branch.head ".len..];
                if (repo.branch_name.len > 0) {
                    allocator.free(repo.branch_name);
                    repo.branch_name = &[_]u8{};
                }
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

test "read_branch detects current git branch" {
    const allocator = std.testing.allocator;
    const branch_opt = read_branch(allocator, ".");
    try std.testing.expect(branch_opt != null);
    if (branch_opt) |b| {
        defer allocator.free(b);
        try std.testing.expect(b.len > 0);
    }
}
