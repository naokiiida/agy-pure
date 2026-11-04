# Agent Guidelines for `agy-pure`

> High-performance, zero-overhead statusline, window title, and notification engines for Google Antigravity CLI (`agy`) written in native Zig.

---

## 1. Core Architecture Tenets

Every contribution to `agy-pure` must strictly adhere to these architectural principles:

### A. Sub-2.5ms Execution Budget
- Every binary (`agy_pure`, `agy_title`, `agy_notify`) runs on every keystroke, state transition, or turn event.
- **Zero dynamic heap allocations** on the rendering path where possible. Use fixed-size stack buffers (`[512]u8`, `[2048]u8`), arenas, and direct POSIX I/O (`std.c.write(1, ...)`).
- Always verify performance with `hyperfine` before merging changes.

### B. Comptime Data-Driven Architecture (No `if..else` Cascades)
- **Never write cascading `if (std.ascii.eqlIgnoreCase(...))` ladders** to match lifecycle states or commands.
- Use `std.StaticStringMap` for $O(1)$ compile-time string-to-enum normalization.
- Use `std.EnumArray` to bind metadata (emojis, OSC escape sequences, urgency flags) to enums with compile-time exhaustiveness checking. If a new state is added, the compiler must force you to define its descriptor in one place.

### C. Standard Unicode over PUA (Zero Tofu in System Fonts)
- macOS Notification Center (AppKit) and native window title bars use the macOS system font (**San Francisco / Apple Color Emoji**).
- **Private Use Area (PUA) Nerd Font glyphs** (e.g. `󰪞`, `󰛄`, ``) are **not** present in system fonts and render as broken tofu boxes (`[?]`).
- Titles and notifications must strictly default to **standard Unicode 15.0 emojis** (`⏱`, `⏳`, `🏃`, `🧐`, `❌`, `✅`) and ASCII.
- Nerd Font glyphs are permitted only in the statusline (`agy_pure`) or behind an explicit opt-in `--nerd-font` flag.

### D. Identity Anchoring over Status Clutter
- Window/tab titles are **Identity Anchors**, not full status dashboards.
- Idle format: `<workspace> (<branch>) · <session title>`. (No `"😴 idle | "` clutter).
- Working format: `🏃 <workspace> (<branch>) · ⏱ <duration>`.
- Blocked format: `⏳ <workspace> (<branch>)`.
- Resource telemetry (token counts, cache hit %, cost, subagent trees) belongs in `statusLine`, not in the window title.

### E. POSIX Synergies & Child Process Hygiene
- **Pipe Draining**: Always drain child process stdout pipes in a loop until EOF (`0` or negative) *before* calling `std.c.waitpid`. Failing to drain causes severe hangs if child output exceeds the 64 KB OS pipe buffer.
- **Stderr Silencing**: Always redirect child `stderr` to `/dev/null` (`dup2(dev_null_fd, 2)`) to prevent git errors or warnings from polluting the terminal statusline or window title.
- **Portable POSIX APIs**: Prefer portable POSIX syscalls (`fork`, `execvp`, `dup2`, `read`, `write`, `waitpid`) over platform-specific wrappers (e.g. Darwin-only `posix_spawn`). Do not assume glibc/Darwin `fstat` return types (e.g. `std.c.fstat` returning `void` on glibc Linux in Zig 0.17; use direct `std.c.read` probes instead).
- **Bounded Filesystem Traversal**: Any upward directory search (such as `.git` root discovery) must be bounded (e.g. max 32 iterations) to prevent infinite loops on circular filesystems.

---

## 2. Antigravity State Machine Realities

Google Antigravity CLI (`agy`) runs on Google's Go `jetski_cortex` codebase. Do **not** assume Claude Code state strings:
- **`"working"`**: Emitted for **both** model reasoning and tool execution. `agy` does *not* emit `"tool_use"`.
- **`"reviewing"`**: Emitted during Artifact Review or diff modal inspection (`ArtifactReviewModel`).
- **`"waiting_for_user"`**: Emitted when paused for interactive questions or safety permissions.
- **`"idle"`**: Emitted when sitting at the prompt.
- **`"done"` / `"error"`**: Emitted on turn completion.

---

## 3. Code Review Checklist & Quality Gates

Before merging any pull request or finalizing a session, verify every gate:

1. **Zero Heap Allocations on Hot Path**: Verify that the rendering loop does not invoke unbounded general-purpose allocators (`page_allocator`, `c_allocator`). All allocations must use `FixedBufferAllocator` with stack fallback.
2. **Comptime String Mapping**: Verify no runtime `if..else` string-matching cascades were added.
3. **Pipe Draining & Stderr Redirection**: Verify child processes drain pipes before `waitpid` and silence `stderr` to `/dev/null`.
4. **Apple Silicon L1i Cache Residency**: Run `just l1-check`. Machine code `__text` section must remain strictly `< 140 KB` (`143,360` bytes) in `ReleaseSmall`.
5. **Sub-2.5ms Latency Target**: Run `just bench`. Mean execution time must remain strictly `< 2.5ms`.
6. **Standard Unicode Compliance**: Verify window titles and notification payloads do not contain PUA glyphs unless explicitly gated.
7. **Cross-Platform Compatibility**: Code must compile and run on both macOS (Darwin aarch64) and Linux (NixOS x86_64).

---

## 4. Testing Protocol

Run the automated gate:
```bash
just gate
```

### Git Edge Case Battery
Always verify git resolution against these real-world scenarios:
- **Detached HEAD**: Truncate raw commit hash to 7 characters.
- **Bare Repository**: Graceful silent fallback without panic or stderr pollution.
- **Worktree Support**: Handle `.git` regular files with `gitdir: <path>` pointers.
- **Relative `gitdir` Paths**: Support relative worktree pointers (Git 2.45+ / worktrunk: `gitdir: ../../.git/worktrees/<name>`).
- **Deep Subdirectory Traversal**: Zero-heap upward search bounded to 32 levels.
- **Non-Git Workspaces**: Clean fallback to directory basename without git decorators.
- **Large Git Output (> 64 KB)**: Ensure pipe draining prevents buffer deadlock.

### Cross-Platform Linux Verification
When altering POSIX syscalls or build steps, test on NixOS:
```bash
# Evaluate package on remote NixOS host
ssh sff "cd ~/Documents/1_personal/agy-pure && git pull && nix build .#default"
```

---

## 5. Semantic Versioning & Release Protocol

Version bumps must follow the **3-File Rule** and keep versions strictly in sync:

1. **`build.zig.zon`**: `.version = "X.Y.Z"`
2. **`flake.nix`**: `packages.default.version = "X.Y.Z"`
3. **`build.zig`**: `options.addOption([]const u8, "version", "X.Y.Z")`

### Step-by-Step Release Procedure

1. **Run Full Verification Gate**:
   ```bash
   just gate
   ```
2. **Bump Version in All 3 Files**:
   Update `build.zig.zon`, `flake.nix`, and `build.zig`.
3. **Verify Version CLI Output**:
   ```bash
   zig build
   ./zig-out/bin/agy_pure -v
   ./zig-out/bin/agy_title -v
   ./zig-out/bin/agy_notify -v
   ```
4. **Stage and Commit (Session Commit Protocol)**:
   Stage only the modified files and write a structured 3-part commit message:
   ```bash
   git add build.zig.zon flake.nix build.zig Justfile AGENTS.md
   git commit -m "$(cat <<'EOF'
   chore(release): bump version to vX.Y.Z

   - Rationale: Release vX.Y.Z bringing <features/fixes>.
   - Architectural Constraints: Passed just gate (< 2.5ms, L1i cache < 140 KB, zero-heap hot path).
   - Complications & Tradeoffs: <any complications noted>.
   EOF
   )"
   ```
5. **Tag and Push**:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main --tags
   ```
6. **Downstream NixOS Ecosystem Sync**:
   Update `selfhost/nixOS/nixos` (or on `sff`):
   ```bash
   cd ~/Documents/1_personal/selfhost/nixOS/nixos
   nix flake update agy-pure
   git diff flake.lock
   git add flake.lock
   git commit -m "chore(inputs): update agy-pure to vX.Y.Z"
   git push
   ```
7. **Local Installation Update**:
   ```bash
   cd ~/Documents/1_personal/agy-pure
   just install
   ```

---

## 6. Developer Commands

```bash
# Full quality gate (unit tests + L1i check + latency benchmark)
just gate

# Run unit tests only
just test

# Check Apple Silicon L1i instruction cache residency (< 140 KB)
just l1-check

# Benchmark execution latency (< 2.5ms target)
just bench

# Install release binaries to ~/.gemini/antigravity-cli/bin
just install

# Build release binaries with ReleaseFast
just build

# Build release binaries with ReleaseSmall (-Oz)
just build-small
```

---

## 7. Workspace Skills

- **`.agents/skills/agy-release-gate/SKILL.md`**: Detailed step-by-step runbook for releasing, testing, reviewing, and downstream syncing.
- **`.agents/skills/agy-schema-inspector/SKILL.md`**: Guide for probing and reverse-engineering Antigravity CLI lifecycle states and JSON schemas.
