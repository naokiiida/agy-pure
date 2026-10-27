# Antigravity CLI Notification & Title Redesign (TODO)

## 1. Reality Check & Core Findings

### A. Lifecycle Hook Timing & Dual Hooking (`agy_notify`)
- **Dual Hook Pattern**: To catch both turn completions AND mid-turn human-in-the-loop approvals, `agy_notify` is registered under both **`Stop`** and **`Notification`** in `~/.gemini/config/hooks.json` (mirroring the `cmux` architecture):
  - **`Stop`**: Fires when the execution loop terminates (`NO_TOOL_CALL`, `ERROR`) → Emits `Done (3.8s)` or `❌ Error (1.4s)`.
  - **`Notification`**: Fires when the agent pauses for user permission, questions, or confirmations → Emits `⏳ Needs input`.
- **`read_file` / tool execution does NOT trigger notifications**: Antigravity does not fire notification hooks on individual tool calls. Attempting to extract past tool names (e.g. `read_file(foo)`) from the transcript at turn completion is conceptually incorrect and produces misleading noise.

### B. Antigravity State Machine Realities (`agy_title`)
- In Antigravity CLI (`agy`), the runtime lifecycle states are:
  - `"working"`: Model reasoning, token streaming, **and** all tool execution (`run_command`, `edit_file`, etc.). `agy` does *not* emit a `"tool_use"` state.
  - `"reviewing"`: Artifact review modal / diff inspection active.
  - `"waiting_for_user"`: Blocked awaiting user confirmation or interactive question.
  - `"idle"`: Turn completed; sitting at terminal prompt.
- **Why titles are "always working"**: Because `agent_state` remains `"working"` across the entire multi-step turn, `agy_title` outputs a static `🏃 working | {workspace}` without elapsed time or momentum indicators.

### C. macOS / Ghostty Notification Layout Constraints
- In Ghostty on macOS, notifications dispatched via OSC 777 are laid out as:
  - **Title (Bold Header)**: Narrow width (~25–30 characters max). Long titles like `agy-pure · 🛠️ edit_file(title.zig) (⏱...` truncate, cutting off the most vital data (elapsed duration).
  - **Subtitle**: Ghostty automatically populates this from the active window/tab title (`surface.title`), which already contains `{workspace}` (e.g. `agy-pure`).
  - **Body**: The turn response summary.
- **Redundancy**: Repeating `{workspace}` in the notification title bloats the header and duplicates the subtitle.

### D. System Font & Nerd Font Compatibility
- **macOS System Font Isolation**: macOS Notification Center (AppKit `UNUserNotificationCenter`) and native window titlebars render using Apple's system font (**San Francisco / Apple Color Emoji**).
- **No Nerd Font in System Notifications**: Private Use Area (PUA) Nerd Font glyphs (like `󰪞`, `󰛄`, ``, ``) are **not** present in the macOS system font and render as broken tofu boxes (`[?]`).
- **Standard Unicode Only**: Titles and notifications must strictly use standard Unicode 15.0 emojis (`⏱`, `⏳`, `🏃`, `🧐`, `❌`, `✅`) and ASCII.
- **Cache Omission**: Prompt cache hit efficiency (`⚡92%`) is a resource/budget metric suited for the statusline (`agy_pure`), NOT an action/momentum signal for window titles or notifications.

---

## 2. Core Goals

1. **Ultra-Compact Notification Title (<15 chars)**:
   - Ensure the notification title fits in every notification banner (macOS, iPhone, Apple Watch) without truncation.
   - Focus exclusively on: **Completion Status + Exact Elapsed Turn Time**.
2. **Zero-Bloat Body**:
   - Single-line summary of what the AI actually answered or accomplished.
   - Markdown links stripped to labels (`[foo.zig](file:///...)` → `foo.zig`), URLs discarded, code blocks and blockquotes skipped.
3. **Decoupled Architecture**:
   - Stop attempting to manipulate the terminal's window title via OSC 2 right before OSC 777 to alter the notification subtitle (eliminates GUI thread race in Ghostty).
   - Let the notification title stand on its own merits with zero terminal-state coupling.
4. **Actionable Live Tab Titles in `agy_title`**:
   - Replace static `🏃 working | agy-pure` with live prompt duration (e.g. `🏃 agy-pure · ⏱ 14s`).
   - Clean up `"😴 idle | "` on prompt wait (e.g. `agy-pure (main*)`).
5. **Comptime Data-Driven Architecture (No `if..else` Cascades)**:
   - Refactor state dispatch, emojis, and OSC protocol emission from cascading string comparisons to compile-time `std.StaticStringMap` and `std.EnumArray`.

---

## 3. Specifications

### A. Notification Title & Body (`agy_notify`)

#### 1. Title Format Specification
Keep the title under 15 characters, bold, and punchy:

| Condition | Format | Example | Char Count |
| :--- | :--- | :--- | :---: |
| Normal completion (with duration) | `Done (<duration>)` | `Done (3.8s)` | 11 |
| Normal completion (fallback) | `Done` | `Done` | 4 |
| Error completion (with duration) | `❌ Error (<duration>)` | `❌ Error (1.4s)` | 15 |
| Error completion (fallback) | `❌ Error` | `❌ Error` | 7 |
| User action required (`Notification` hook) | `⏳ Needs input` | `⏳ Needs input` | 14 |

#### 2. Body Format Specification
- Extracted from the last assistant response via `cleanSummary(100)`:
  - Markdown links: `[title](url)` → `title`.
  - Image tags: `![alt](url)` → stripped.
  - Fenced code blocks (` ```...``` `): skipped completely.
  - Alert blocks (`> [!NOTE]`): skipped.
  - List markers (`- `, `* `, `1. `): stripped.
  - Multiple whitespace / newlines: collapsed to single space.
  - Fallback string if empty: `"Turn complete"`.

#### 3. Resulting macOS Notification Banner
```
┌────────────────────────────────────────────────────────┐
│ [Ghostty]                                              │
│ Done (3.8s)                                            │
│ agy-pure (main*)                                       │
│ Updated notify.zig and verified all unit tests pass.   │
└────────────────────────────────────────────────────────┘
```

---

### B. Terminal Tab Title (`agy_title`)

#### 1. Live Execution State (`agent_state == "working"`)
Instead of static `🏃 working | <workspace>`, provide live execution metrics:
- **With duration**:
  `🏃 <workspace> (<branch>) · ⏱ <elapsed>s`
- **When subagents are active**:
  `🏃 <workspace> · [2 subagents]`
- **When reviewing artifacts**:
  `🧐 reviewing | <workspace> (<branch>)`
- **When waiting for user confirmation**:
  `⏳ waiting | <workspace> (<branch>)`

#### 2. Idle State (`agent_state == "idle"`)
Eliminate `"😴 idle | "` bloat:
- **Clean format**:
  `<workspace> (<branch>) · <model>`
  e.g.: `agy-pure (main*) · Gemini 3.8 Flash`

---

### C. Comptime Data-Driven Architecture Design

Eliminate all cascading `if..else` ladders across the codebase with compile-time verified tables:

```zig
pub const AgentState = enum {
    idle,
    working,
    reviewing,
    waiting,
    done,
    error_state,
    unknown,
};

// Comptime string normalization (O(1) perfect hash/binary tree)
const StateMap = std.StaticStringMap(AgentState).initComptime(.{
    .{ "idle", .idle },
    .{ "working", .working },
    .{ "running", .working },
    .{ "thinking", .working },
    .{ "processing", .working },
    .{ "tool_use", .working },
    .{ "reviewing", .reviewing },
    .{ "waiting_for_user", .waiting },
    .{ "waiting_for_input", .waiting },
    .{ "done", .done },
    .{ "complete", .done },
    .{ "error", .error_state },
    .{ "errored", .error_state },
});

pub const StateDescriptor = struct {
    emoji: []const u8,
    osc7501_state: []const u8,
    osc9_4_code: u8, // 0 = clear, 2 = error, 3 = spinner, 4 = paused
    is_blocked: bool,
};

// Exhaustive compile-time checked descriptor table
pub const state_descriptors = std.EnumArray(AgentState, StateDescriptor).init(.{
    .idle = .{ .emoji = "", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
    .working = .{ .emoji = "🏃", .osc7501_state = "working", .osc9_4_code = 3, .is_blocked = false },
    .reviewing = .{ .emoji = "🧐", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .waiting = .{ .emoji = "⏳", .osc7501_state = "blocked", .osc9_4_code = 4, .is_blocked = true },
    .done = .{ .emoji = "✅", .osc7501_state = "done", .osc9_4_code = 0, .is_blocked = false },
    .error_state = .{ .emoji = "❌", .osc7501_state = "error", .osc9_4_code = 2, .is_blocked = false },
    .unknown = .{ .emoji = "🤖", .osc7501_state = "idle", .osc9_4_code = 0, .is_blocked = false },
});
```

---

### D. Hook Configuration (`~/.gemini/config/hooks.json`)

Dual hook registration for `agy_notify`:
```json
{
  "notify": {
    "Stop": [
      {
        "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_notify",
        "timeout": 5,
        "type": "command"
      }
    ],
    "Notification": [
      {
        "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_notify --event=notification",
        "timeout": 5,
        "type": "command"
      }
    ]
  }
}
```

---

## 4. Implementation & Refactoring Tasks

- [x] **Task 1: Refactor `src/title.zig` to Comptime Architecture**
  - Implement `AgentState` enum, `StateMap` (`std.StaticStringMap`), and `state_descriptors` (`std.EnumArray`).
  - Replace `StateEmoji.get()` with `state_descriptors.get(state).emoji`.
  - Replace `formatOsc7501` and `formatOsc9_4` with single-line lookups from `state_descriptors`.
  - Implement clean `render()` pipeline:
    - Working: `🏃 <workspace> (<branch>) · ⏱ <duration>`
    - Idle: `<workspace> (<branch>) · <model>` (or clean `<workspace>` if model absent).
    - Blocked: `⏳ <workspace> (<branch>)`.
  - Support optional `--nerd-font` flag, defaulting to standard Unicode 15.0 emojis.

- [x] **Task 2: Refactor `src/notify.zig` & `src/notify_main.zig`**
  - Refactor `formatTitle` to `formatNotificationTitle(buf, elapsed, is_error, is_notification)`.
  - Strip all tool extraction logic from `notify_main.zig`.
  - Strip OSC 2 pre-notification title hacking (eliminates Ghostty race condition).
  - Handle `--event=notification` argument for `Notification` hook support (`⏳ Needs input`).

- [x] **Task 3: Refactor `src/agy.zig` & `src/title_main.zig`**
  - Remove duplicate `StateEmoji` implementations in `src/agy.zig` and re-export `title.state_descriptors`.
  - Simplify `title_main.zig` to use `title.parseState()` and descriptors directly.

- [x] **Task 4: Unit Tests & Verification**
  - Update unit tests in `src/title.zig` and `src/notify.zig` to verify:
    - Comptime state parsing for all synonyms (`running` -> `working`, `complete` -> `done`, `waiting_for_user` -> `waiting`).
    - Descriptor consistency across OSC 7501, OSC 9;4, and emojis.
    - Notification title formatting (`Done (3.8s)`, `❌ Error (1.4s)`, `⏳ Needs input`).
  - Run `zig build test` to ensure all tests pass.
  - Run `zig build -Doptimize=ReleaseFast` and verify execution time strictly < 2.5ms with `hyperfine`.
