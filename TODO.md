# Antigravity CLI Notification & Title Redesign (TODO)

## 1. Reality Check & Core Findings

### A. Lifecycle Hook Timing & Dual Hooking (`agy_notify`)
- **Dual Hook Pattern**: To catch both turn completions AND mid-turn human-in-the-loop approvals, `agy_notify` is registered under both **`Stop`** and **`Notification`** in `~/.gemini/config/hooks.json` (mirroring the `cmux` architecture):
  - **`Stop`**: Fires when the execution loop terminates (`NO_TOOL_CALL`, `ERROR`) → Emits `Done` or `❌ Error`.
  - **`Notification`**: Fires when the agent pauses for user permission, questions, or confirmations → Emits `⏳ Needs input`.
- **`read_file` / tool execution does NOT trigger notifications**: Antigravity does not fire notification hooks on individual tool calls. Tool extraction from transcripts at turn completion is conceptually incorrect and produces misleading noise.

### B. Antigravity State Machine Realities & Live Ticker Loop (`agy_title`)
- In Antigravity CLI (`agy`), the runtime lifecycle states are:
  - `"working"`: Model reasoning, token streaming, **and** all tool execution (`run_command`, `edit_file`, etc.). `agy` does *not* emit a `"tool_use"` state.
  - `"reviewing"`: Artifact review modal / diff inspection active.
  - `"waiting_for_user"`: Blocked awaiting user confirmation or interactive question.
  - `"idle"`: Turn completed; sitting at terminal prompt.
- **Continuous Ticker Loop**: Antigravity does **not** only invoke `title` on macro state transitions; empirical probe measurements confirm `agy` invokes `title` continuously on an active ~300–500ms ticker loop during turns.
- **Negligible Overhead**: `peekElapsedMs` reads 14 bytes from memory-cached `/tmp` via direct POSIX syscalls (< 1.5µs). Full `agy_title` binary runs in ~2.0ms with 0 heap allocations, consuming ~0.5% of one CPU core only while working.

### C. macOS / Ghostty Notification Layout Constraints
- In Ghostty on macOS, notifications dispatched via OSC 777 are laid out as:
  - **Title (Bold Header)**: Mapped from OSC 777 title argument.
  - **Subtitle**: Ghostty automatically populates this from the active window/tab title (`surface.title`), which already contains `{workspace}` and the live ticker (e.g. `🏃 agy-pure (main*) · ⏱ 14s`).
  - **Body**: The turn response summary.
- **Redundancy Resolution**: Because `surface.title` already carries the live duration ticker into Ghostty's subtitle, putting duration in the notification title (`Done (14s)`) creates duplicate timers. Keeping notification title strictly focused on the terminal disposition (`Done`, `❌ Error`, `⏳ Needs input`) completely eliminates redundancy.

### D. System Font & Nerd Font Compatibility
- **macOS System Font Isolation**: macOS Notification Center (AppKit `UNUserNotificationCenter`) and native window titlebars render using Apple's system font (**San Francisco / Apple Color Emoji**).
- **No Nerd Font in System Notifications**: Private Use Area (PUA) Nerd Font glyphs (like `󰪞`, `󰛄`, ``, ``) are **not** present in the macOS system font and render as broken tofu boxes (`[?]`).
- **Standard Unicode Only**: Titles and notifications must strictly use standard Unicode 15.0 emojis (`⏱`, `⏳`, `🏃`, `🧐`, `❌`, `✅`) and ASCII. Nerd Font symbols are permitted only behind an explicit opt-in `--nerd-font` flag.
- **Cache Omission**: Prompt cache hit efficiency (`⚡92%`) is a resource/budget metric suited for the statusline (`agy_pure`), NOT an action/momentum signal for window titles or notifications.

---

## 2. Core Goals

1. **Clean Notification Title (<15 chars)**:
   - Header strictly states terminal disposition: `Done`, `❌ Error`, or `⏳ Needs input`.
2. **Zero-Bloat Body**:
   - Single-line summary of what the AI actually answered or accomplished.
   - Markdown links stripped to labels (`[foo.zig](file:///...)` → `foo.zig`), URLs discarded, code blocks and blockquotes skipped.
3. **Decoupled Architecture**:
   - Zero OSC 2 hacks before OSC 777 (avoids AppKit/Ghostty GUI thread races).
   - Each surface performs its distinct architectural role without tight coupling.
4. **Actionable Live Tab Titles in `agy_title`**:
   - Working: Live prompt duration ticker (`🏃 agy-pure (main*) · ⏱ 14s`).
   - Idle: Clean session identity (`agy-pure (main*) · Session Title Generation Feature`).
   - Blocked: Clean emoji anchor (`⏳ agy-pure (main*)` or `🧐 agy-pure (main*)`).
5. **Comptime Data-Driven Architecture (No `if..else` Cascades)**:
   - State dispatch, emojis, and OSC protocols powered by compile-time `std.StaticStringMap` and `std.EnumArray`.

---

## 3. Specifications

### A. Notification Title & Body (`agy_notify`)

#### 1. Title Format Specification
Clean, bold, and punchy:

| Condition | Format | Example | Char Count |
| :--- | :--- | :--- | :---: |
| Normal completion | `Done` | `Done` | 4 |
| Error completion | `❌ Error` | `❌ Error` | 7 |
| User action required (`Notification` hook) | `⏳ Needs input` | `⏳ Needs input` | 14 |

#### 2. Body Format Specification
- Extracted from the last assistant response via `cleanSummary(100)`:
  - Markdown links: `[title](url)` → `title`.
  - Image tags: `![alt](url)` → stripped.
  - Fenced code blocks (` ```...``` `): skipped completely.
  - Alert blocks (`> [!NOTE]`): skipped.
  - List markers (`- `, `* `, `1. `): stripped.
  - Multiple whitespace / newlines: collapsed to single space.
  - Fallback string if empty: `"Turn complete"` or `"Action required"`.

#### 3. Resulting macOS Notification Banner (Zero Redundancy)
```
┌────────────────────────────────────────────────────────┐
│ [Ghostty]                                              │
│ Done                                                   │
│ 🏃 agy-pure (main*) · ⏱ 3.8s                          │
│ Updated notify.zig and verified all unit tests pass.   │
└────────────────────────────────────────────────────────┘
```
- Line 1 (Title): Disposition (`Done`)
- Line 2 (Subtitle): Target workspace + final duration from tab title (`🏃 agy-pure (main*) · ⏱ 3.8s`)
- Line 3 (Body): Clear response summary

---

### B. Terminal Tab Title (`agy_title`)

#### 1. Live Execution State (`agent_state == "working"`)
- **With duration**:
  `🏃 <workspace> (<branch>) · ⏱ <elapsed>s`
- **When subagents are active**:
  `🏃 <workspace> (<branch>) [2 subagents] · ⏱ <elapsed>s`

#### 2. Blocked States
- **Reviewing artifacts**:
  `🧐 <workspace> (<branch>)`
- **Waiting for user input / permissions**:
  `⏳ <workspace> (<branch>)`

#### 3. Idle State (`agent_state == "idle"`)
- **Format**:
  `<workspace> (<branch>) · <session_title>`
  e.g.: `agy-pure (main*) · Session Title Generation Feature` (falling back to model name if title not yet generated).

---

## 4. Implementation & Refactoring Tasks

- [x] **Task 1: Refactor `src/title.zig` to Comptime Architecture**
  - Implement `AgentState` enum, `StateMap` (`std.StaticStringMap`), and `state_descriptors` (`std.EnumArray`).
  - Replace `StateEmoji.get()` with `state_descriptors.get(state).emoji`.
  - Replace `formatOsc7501` and `formatOsc9_4` with single-line lookups from `state_descriptors`.
  - Implement clean `render()` pipeline:
    - Working: `🏃 <workspace> (<branch>) · ⏱ <duration>`
    - Idle: `<workspace> (<branch>) · <model>` (or clean `<workspace>` if model absent).
    - Blocked: `⏳ <workspace> (<branch>)` and `🧐 <workspace> (<branch>)`.
  - Support optional `--nerd-font` flag, defaulting to standard Unicode 15.0 emojis.

- [x] **Task 2: Refactor `src/notify.zig` & `src/notify_main.zig`**
  - Simplify `formatNotificationTitle(is_error, is_notification)` to return static disposition strings (`Done`, `❌ Error`, `⏳ Needs input`).
  - Strip all tool extraction logic from `notify_main.zig` and `title.zig`.
  - Strip OSC 2 pre-notification title hacking (eliminates Ghostty race condition).
  - Handle `--event=notification` argument for `Notification` hook support (`⏳ Needs input`).

- [x] **Task 3: Refactor `src/agy.zig` & `src/title_main.zig`**
  - Remove duplicate `StateEmoji` implementations in `src/agy.zig` and re-export `title.state_descriptors`.
  - Simplify `title_main.zig` to use `title.parseState()` and descriptors directly.

- [x] **Task 4: Unit Tests & Verification**
  - Update unit tests in `src/title.zig` and `src/notify.zig` to verify:
    - Comptime state parsing for all synonyms (`running` -> `working`, `complete` -> `done`, `waiting_for_user` -> `waiting`).
    - Descriptor consistency across OSC 7501, OSC 9;4, and emojis.
    - Clean notification title formatting (`Done`, `❌ Error`, `⏳ Needs input`).
  - Run `zig build test` to ensure all tests pass.
  - Run `zig build -Doptimize=ReleaseFast` and verify execution time strictly < 2.5ms with `hyperfine`.

- [x] **Task 5: Zero-Redundancy Notification & Ticker Architecture**
  - Empirically verify `agy` sub-second continuous ticker execution (~300-500ms intervals).
  - Align `surface.title` as owner of live momentum telemetry.
  - Align `agy_notify` as owner of terminal disposition receipt.
  - Clean up dead transcript tool-seeker code in `src/title.zig`.

- [x] **Task 6: Session Title Integration (`agy_title` & optional `agy_pure` segment)**
  - Implement zero-allocation `parsePbtxtTitle` and `getSessionTitle` in `src/agy.zig` reading `<appDataDir>/annotations/<id>.pbtxt`.
  - Update `src/title.zig` idle format to `<workspace> (<branch>) · <session_title>` (with fallback to model name).
  - Add optional `.session_title` segment to `src/segments.zig` and `src/display.zig` while retaining `.model` by default in statusline.
  - Verified sub-2.5ms execution budget and 100% test pass.
