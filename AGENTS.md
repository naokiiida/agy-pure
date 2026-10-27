# Agent Guidelines for `agy-pure`

> High-performance, zero-overhead statusline, window title, and notification engines for Google Antigravity CLI (`agy`) written in native Zig.

---

## 1. Core Architecture Tenets

Every contribution to `agy-pure` must strictly adhere to these four architectural principles:

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
- Idle format: `<workspace> (<branch>) · <model>`. (No `"😴 idle | "` clutter).
- Working format: `🏃 <workspace> (<branch>) · ⏱ <duration>`.
- Blocked format: `⏳ <workspace> (<branch>)`.
- Resource telemetry (token counts, cache hit %, cost, subagent trees) belongs in `statusLine`, not in the window title.

---

## 2. Antigravity State Machine Realities

Google Antigravity CLI (`agy`) runs on Google's Go `jetski_cortex` codebase. Do **not** assume Claude Code state strings:
- **`"working"`**: Emitted for **both** model reasoning and tool execution. `agy` does *not* emit `"tool_use"`.
- **`"reviewing"`**: Emitted during Artifact Review or diff modal inspection (`ArtifactReviewModel`).
- **`"waiting_for_user"`**: Emitted when paused for interactive questions or safety permissions.
- **`"idle"`**: Emitted when sitting at the prompt.
- **`"done"` / `"error"`**: Emitted on turn completion.

---

## 3. Developer Commands

### Build & Test
```bash
# Run all unit tests
zig build test

# Build optimized release binaries
zig build -Doptimize=ReleaseFast

# Test binary size (< 550 KB)
ls -lh zig-out/bin/*
```

### Performance Benchmarking
```bash
# Ensure execution remains strictly < 2.5ms
hyperfine --warmup 5 ./zig-out/bin/agy_pure ./zig-out/bin/agy_title
```

### Local Installation
```bash
# Recommended (builds ReleaseFast and installs all 3 binaries):
just install

# Or natively via Zig build step:
zig build install-cli -Doptimize=ReleaseFast
```
