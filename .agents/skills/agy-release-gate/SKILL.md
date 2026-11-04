---
name: agy-release-gate
description: Comprehensive verification, testing, reviewing, versioning, and release runbook for agy-pure binaries and downstream NixOS flake synchronization.
---

# `agy-pure` Quality Gate & Release Runbook

This skill defines the complete operational lifecycle for reviewing, testing, versioning, releasing, and deploying the `agy-pure` toolchain (`agy_pure`, `agy_title`, `agy_notify`).

Every release and PR must pass every gate in this document without exception.

---

## 1. Architectural Review Checklist

Before bumping versions or tagging releases, audit the diff against these four core tenets:

### A. Memory & Allocator Hygiene (Zero Heap Allocations)
- [ ] Hot rendering paths MUST NOT allocate from unbounded general-purpose allocators (`std.heap.page_allocator`, `c_allocator`).
- [ ] Use `std.heap.FixedBufferAllocator` with a fixed stack buffer (e.g. 128 KB buffer) and `std.heap.ArenaAllocator` wrapping it for fallback.
- [ ] Ensure formatting and strings utilize fixed stack buffers (`[512]u8`, `[2048]u8`) and direct POSIX I/O (`std.c.write(1, ...)`).

### B. POSIX Purity & Cross-Platform Compatibility
- [ ] Use portable POSIX syscalls (`std.c.fork`, `std.c.execvp`, `std.c.dup2`, `std.c.read`, `std.c.write`, `std.c.waitpid`).
- [ ] Avoid Darwin-only wrappers on shared code paths (e.g. `std.c.posix_spawn*` in Zig 0.17 stdlib is tied to `builtin.os.tag.isDarwin()`).
- [ ] Do not assume OS-specific struct layouts or return types (e.g. `std.c.fstat` evaluates to `void` on glibc Linux in Zig 0.17; use direct `std.c.read` probes instead).

### C. Child Process Hygiene & Deadlock Prevention
- [ ] **Pipe Draining**: Always drain child process stdout pipes in a loop until EOF (`0` or negative) *before* invoking `std.c.waitpid`. Failing to do so causes hangs if child output exceeds the 64 KB OS pipe buffer.
- [ ] **Stderr Silencing**: Always redirect child process `stderr` to `/dev/null` (`dup2(dev_null_fd, 2)`) to ensure git errors or warnings do not corrupt the terminal statusline or window title.
- [ ] **Filesystem Traversal Bounds**: Any upward directory search (such as `.git` root discovery) must be bounded (e.g. max 32 iterations) to prevent infinite loops on circular filesystems.

### D. Comptime String-to-Enum Normalization
- [ ] **No `if (std.ascii.eqlIgnoreCase(...))` cascades**.
- [ ] State and command matching MUST use `std.StaticStringMap` for $O(1)$ compile-time hashing.
- [ ] State attributes (emojis, OSC strings, urgency flags) MUST be bound via `std.EnumArray` with compile-time exhaustiveness checking.

### E. Standard Unicode over PUA
- [ ] Titles and notifications rendered on macOS or desktop notification daemons MUST use standard Unicode 15.0 emojis (`⏱`, `⏳`, `🏃`, `🧐`, `❌`, `✅`) and ASCII.
- [ ] Nerd Font / PUA glyphs (e.g. `󰪞`, `󰛄`, ``) are permitted only in the statusline (`agy_pure`) or behind explicit opt-in flags.

---

## 2. Automated Quality Gates

Run the complete automated quality gate suite locally:

```bash
just gate
```

This runs three strict verification stages:

### 1. Unit Test Suite (`zig build test`)
Validates:
- Lifecycle state transitions (`working`, `reviewing`, `waiting_for_user`, `idle`, `done`, `error`).
- Git branch name extraction, detached HEAD parsing (commit hash truncation to 7 characters), worktree `.git` files, and relative `gitdir` paths (Git 2.45+ / worktrunk).
- OSC 7501 terminal title sequence generation.
- CLI argument parsing (`--version`, `-v`, `--help`, `-h`).

### 2. Apple Silicon L1i Instruction Cache Gate (`just l1-check`)
- Verifies that `ReleaseSmall` (`-Oz`) machine code `__text` section stays strictly below **140 KB** (`143,360` bytes) for all three binaries:
  ```bash
  just l1-check
  ```
- If any binary exceeds the limit, investigate inlined functions, static data, or missing `-Oz` optimization flags.

### 3. Hyperfine Latency Benchmark (`just bench`)
- Target: Strict **< 2.5ms** mean execution time per binary:
  ```bash
  just bench
  ```
- Normal targets on modern hardware: `agy_pure` (~1.8ms), `agy_title` (~1.8ms), `agy_notify` (~1.8ms).

---

## 3. Semantic Versioning Protocol (The 3-File Rule)

Version bumps must be synchronized across exactly three files:

1. **`build.zig.zon`**:
   ```zig
   .version = "0.2.0",
   ```
2. **`flake.nix`**:
   ```nix
   packages.default = pkgs.stdenv.mkDerivation {
     pname = "agy-pure";
     version = "0.2.0";
     ...
   };
   ```
3. **`build.zig`**:
   ```zig
   options.addOption([]const u8, "version", "0.2.0");
   ```

Verify version synchronization:
```bash
zig build
./zig-out/bin/agy_pure --version
./zig-out/bin/agy_title --version
./zig-out/bin/agy_notify --version
```

---

## 4. Release & Deployment Runbook

Follow these steps sequentially to publish a new release:

### Step 1: Pre-Flight Gate Verification
```bash
just gate
```
Ensure all tests pass, L1i cache checks succeed, and benchmarks stay under 2.5ms.

### Step 2: Version Bump
Update the version string in `build.zig.zon`, `flake.nix`, and `build.zig`.

### Step 3: Stage and Commit (Session Commit Protocol)
Follow the 3-part structured commit protocol:
```bash
git add build.zig.zon flake.nix build.zig Justfile AGENTS.md
git commit -m "$(cat <<'EOF'
chore(release): bump version to vX.Y.Z

- Rationale: Release vX.Y.Z including <key features or bug fixes>.
- Architectural Constraints: Verified sub-2.5ms budget with hyperfine, L1i cache residency with size -m, and zero dynamic heap allocations.
- Complications & Tradeoffs: None encountered during gate verification.
EOF
)"
```

### Step 4: Tag and Push
```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin main --tags
```

### Step 5: Downstream NixOS Ecosystem Synchronization
Update the consumer flake lock in the NixOS dotfiles repository (`~/Documents/1_personal/selfhost/nixOS/nixos` or on remote host `sff`):
```bash
cd ~/Documents/1_personal/selfhost/nixOS/nixos
nix flake update agy-pure
git diff flake.lock
git add flake.lock
git commit -m "chore(inputs): update agy-pure to vX.Y.Z"
git push
```
Verify build and evaluation:
```bash
nix eval .#homeConfigurations."naokiiida@sff".activationPackage
```

### Step 6: Local Toolchain Update
Install the new binaries locally to `~/.gemini/antigravity-cli/bin`:
```bash
cd ~/Documents/1_personal/agy-pure
just install
```
Verify active installation:
```bash
~/.gemini/antigravity-cli/bin/agy_pure -v
~/.gemini/antigravity-cli/bin/agy_title -v
~/.gemini/antigravity-cli/bin/agy_notify -v
```

---

## 5. Emergency Rollback Procedure

If a binary exhibits crashes, regressions, or pipe hangs in production:
1. Revert to previous git tag:
   ```bash
   git checkout v<previous-tag>
   just install
   ```
2. Rollback downstream NixOS flake lock:
   ```bash
   cd ~/Documents/1_personal/selfhost/nixOS/nixos
   git revert HEAD
   git push
   ```
3. Update remote NixOS hosts:
   ```bash
   ssh sff "cd ~/Documents/nixos && git pull && home-manager switch --flake .#naokiiida@sff"
   ```
