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
> **Antigravity State Nuance**:
> Unlike Claude Code, `agy` does **not** emit a separate `"tool_use"` state string. Both model reasoning and tool execution are reported as `"working"`.
> To provide action-aware titles (e.g., `🛠️ edit_file(title.zig)`), `agy_title` inspects the tail of `transcript.jsonl` whenever `agent_state == "working"`.

---

## 5. Lifecycle States & Emoji Mapping

`agy_title` maps Antigravity agent lifecycle states (plus backward-compatible legacy states) to Unicode emojis:

| State | Emoji | Emitted By `agy` | Meaning |
|:---|:---:|:---:|:---|
| `idle` | 😴 | Yes | Turn complete; waiting for next prompt |
| `working` / `running` | 🏃 | Yes | Model reasoning OR executing tools |
| `reviewing` | 🧐 | Yes | Artifact Review modal or diff review active |
| `waiting_for_user` | ⏳ / ⚠️ | Yes | Awaiting user response to question or permission gate |
| `done` / `complete` | ✅ | Yes | Task completed successfully |
| `error` / `errored` | ❌ | Yes | Unrecoverable error occurred |
| `tool_use` | 🛠️ | Claude Code only | Fallback mapping for Claude Code compatibility |
| `initializing` | 🚀 | Startup | CLI startup / loading session context |
| `*` (fallback) | 🤖 | N/A | Unknown or unmapped state |

---

## 6. Action-Aware Tool Titling

When `agent_state` is `"working"`, `agy_title` extracts the active tool action from `transcript.jsonl` using a fast (< 0.3ms) 64KB reverse file seeker:
- If a tool call is found (e.g. `edit_file` targeting `title.zig`):
  `🛠️ edit_file(title.zig) | agy-pure (main)`
- If no recent tool call is found (model is actively reasoning / generating text):
  `🏃 working | agy-pure (main)`
- If state is `"reviewing"`:
  `🧐 reviewing | agy-pure (main)`

---

## 7. Workspace Extraction Logic

1. **CitC (Cloud in the Cloud) Detection**:
   - If the path matches `/google/src/cloud/<username>/<workspace>[/...]`, the workspace name is extracted directly (e.g., `gemini-feature`).
2. **Standard Directory**:
   - Strips trailing directory separators and extracts the basename of `project_dir` or `cwd` (e.g., `/Users/user/code/agy-pure` → `agy-pure`).
3. **Fallback**:
   - If path is empty, defaults to `unknown`.
