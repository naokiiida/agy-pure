# Antigravity CLI Window Title JSON Schema

Official documentation & architecture reference for Antigravity CLI (`agy`) title synchronization.

---

## 1. Protocol Overview

Antigravity CLI (`agy`) supports dynamic terminal window title updating. Whenever the agent lifecycle state changes (e.g. idle, working, reviewing artifacts, waiting for confirmation), `agy` executes the configured title command, pipes a JSON state payload directly into `stdin`, and captures the formatted string from `stdout`.

```
┌─────────────────────────┐          JSON Payload (stdin)         ┌─────────────────────────┐
│                         │ ────────────────────────────────────> │                         │
│  Antigravity CLI (agy)  │                                       │   agy_title (Binary)    │
│                         │ <──────────────────────────────────── │                         │
└─────────────────────────┘          Title String (stdout)        └─────────────────────────┘
             │
             ▼
  Terminal Window / Tab Title
 (ANSI & escapes auto-stripped)
```

---

## 2. Configuration

Add the `title` configuration block in `~/.gemini/antigravity-cli/settings.json`:

```json
{
  "title": {
    "type": "command",
    "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_title"
  }
}
```

Optional flags supported by `agy_title`:
- `--no-emoji`: Excludes the leading state emoji (e.g., `working | agy-pure`).
- `--git`: Appends current Git branch name (e.g., `🏃 working | agy-pure (main)`).
- `--subagents`: Appends active subagents (e.g., `🏃 working | agy-pure [2 subagents: 🔬 res, 🏃 deb]`).
- `--osc-progress`: Emits OSC 7501 & OSC 9;4 terminal escape sequences (default: on).
- `--no-osc-progress`: Disables OSC 7501 & OSC 9;4 terminal escape sequences.

---

## 3. JSON State Payload Schema

```json
{
  "conversation_id": "9df0b3af-69de-4fe6-9fcc-8274f4b5edbb",
  "session_id": "9df0b3af-69de-4fe6-9fcc-8274f4b5edbb",
  "agent_state": "working",
  "cwd": "/Users/naokiiida/Documents/1_personal/agy-pure",
  "workspace": {
    "current_dir": "/Users/naokiiida/Documents/1_personal/agy-pure",
    "project_dir": "/Users/naokiiida/Documents/1_personal/agy-pure"
  },
  "model": {
    "id": "gemini-3.8-flash",
    "display_name": "Gemini 3.8 Flash"
  },
  "version": "1.2.17",
  "context_window": {
    "total_input_tokens": 42100,
    "total_output_tokens": 1250,
    "context_window_size": 200000,
    "used_percentage": 21.0,
    "remaining_percentage": 79.0,
    "current_usage": 42100
  },
  "subagents": {
    "total": 2,
    "running": 1,
    "idle": 1
  }
}
```

---

## 4. Field Reference

| Field | Type | Description |
|:---|:---|:---|
| `agent_state` | string | Current lifecycle state: `"idle"`, `"working"`, `"reviewing"`, `"waiting_for_user"`, `"done"`, `"error"`. |
| `workspace.current_dir` | string | Current working directory of the CLI session. |
| `workspace.project_dir` | string | Project root directory where the session was initialized. |
| `cwd` | string | Fallback working directory path. |
| `conversation_id` | string | Unique conversation UUID. |
| `session_id` | string | Unique session identifier (backward-compatible with Claude Code). |
| `model.display_name` | string | Human-readable model label (e.g. `Gemini 3.8 Flash`, `Gemini 2.5 Pro`). |
| `model.id` | string | Model API identifier. |
| `subagents` | object / integer | Active subagents count and state breakdown. |
| `context_window` | object | Token usage and context window consumption percentages. |

> [!IMPORTANT]
> **Antigravity Continuous Ticker Loop**:
> Antigravity CLI executes the configured `title` command continuously on an active sub-second loop (~300–500ms intervals) during turn execution.
> `agy_title` leverages this loop to render live duration momentum (`· ⏱ <duration>`) without requiring any daemon or background process.

---

## 5. Lifecycle States & Emoji Mapping

`agy_title` uses compile-time verified mappings (`std.StaticStringMap` and `std.EnumArray`) to map Antigravity lifecycle states:

| State | Default Unicode | `--nerd-font` | OSC 7501 State | Meaning |
|:---|:---:|:---:|:---:|:---|
| `idle` | *(none)* | *(none)* | `idle` | Turn complete; prompt ready |
| `working` / `running` | `🏃` | `󰑮` | `working` | Actively reasoning or executing tools |
| `reviewing` | `🧐` | `󰛄` | `blocked` | Artifact Review modal or diff inspection |
| `waiting_for_user` | `⏳` | `󰔟` | `blocked` | Awaiting interactive user answer or confirmation |
| `done` / `complete` | `✅` | `󰄬` | `done` | Task completed successfully |
| `error` / `errored` | `❌` | `󰅚` | `error` | Turn aborted with unrecoverable error |

---

## 6. Title Formatting Specifications

Window and tab titles serve as **Identity Anchors**, adhering to a clean, zero-clutter format:

- **Working** (with duration):
  `🏃 <workspace> (<branch>) · ⏱ <elapsed>`
  *(e.g., `🏃 agy-pure (main) · ⏱ 14s`)*
- **Idle** (clean prompt context):
  `<workspace> (<branch>) · <session title>`
  *(e.g., `agy-pure (main) · Session Title Generation Feature`)*
- **Reviewing Artifacts**:
  `🧐 <workspace> (<branch>)`
- **Waiting for Confirmation**:
  `⏳ <workspace> (<branch>)`
- **With Active Subagents** (optional `--subagents`):
  `🏃 <workspace> (<branch>) [2 subagents] · ⏱ <elapsed>`

---

## 7. Zero-Redundancy Ghostty Notification Integration

Ghostty on macOS populates notification banners as follows:
- **Header (Bold)**: OSC 777 notification title from `agy_notify` (`Done`, `❌ Error`, or `⏳ Needs input`).
- **Subtitle**: Ghostty's active window/tab title (`surface.title`), generated by `agy_title` (`🏃 <workspace> (<branch>) · ⏱ <duration>`).
- **Body**: Clean single-line summary from `agy_notify`.

Because `surface.title` already carries the live duration ticker into the notification subtitle, `agy_notify` leaves elapsed time out of the bold header, preventing redundant information.

---

## 8. Workspace Extraction Logic

1. **CitC (Cloud in the Cloud) Detection**:
   - If the path matches `/google/src/cloud/<username>/<workspace>[/...]`, the workspace name is extracted directly (e.g., `gemini-feature`).
2. **Standard Directory**:
   - Strips trailing directory separators and extracts the basename of `project_dir` or `cwd` (e.g., `/Users/user/code/agy-pure` → `agy-pure`).
3. **Fallback**:
   - If path is empty, defaults to `unknown`.
