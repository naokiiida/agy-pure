# Antigravity CLI Window Title JSON Schema

Official documentation: [https://antigravity.google/docs/cli/title](https://antigravity.google/docs/cli/title)

---

## 1. Protocol Overview

Antigravity CLI (`agy`) supports dynamic terminal window title updating. Whenever the agent lifecycle state changes (e.g. idle, working, thinking, tool execution), `agy` executes the configured title command, pipes a comprehensive JSON state payload directly into `stdin`, and captures the formatted string from `stdout`.

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
- `--subagents`: Appends active subagent badge if >0 (e.g., `🏃 working | agy-pure [2 subagents]`).

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
| `agent_state` | string | Current lifecycle state: `"idle"`, `"working"`, `"thinking"`, `"tool_use"`, `"initializing"`, `"waiting_for_user"`, etc. |
| `workspace.current_dir` | string | Current working directory of the CLI session. |
| `workspace.project_dir` | string | Project root directory where the session was initialized. |
| `cwd` | string | Fallback working directory path. |
| `conversation_id` | string | Unique conversation UUID. |
| `session_id` | string | Unique session identifier (backward-compatible with Claude Code). |
| `model.display_name` | string | Human-readable model label (e.g. `Gemini 3.8 Flash`, `Gemini 2.5 Pro`). |
| `model.id` | string | Model API identifier. |
| `subagents` | object / integer | Active subagents count and state breakdown. |
| `context_window` | object | Token usage and context window consumption percentages. |

---

## 5. Lifecycle States & Emoji Mapping

`agy_title` maps all standard and extended Antigravity agent lifecycle states to representative Unicode emojis:

| State | Emoji | Meaning |
|:---|:---:|:---|
| `initializing` | 🚀 | CLI startup / loading session context |
| `idle` | 😴 | Waiting for user input |
| `thinking` | 🤔 | Model reasoning / chain-of-thought generation |
| `working` / `running` | 🏃 | Running turn / executing agent instructions |
| `tool_use` | 🛠️ | Executing tool call (file edit, bash command, web search) |
| `processing` | ⚙️ | Processing internal workflows |
| `waiting_for_input` | ⏳ | Awaiting user response to interactive question or confirmation |
| `done` / `complete` | ✅ | Task completed successfully |
| `error` / `errored` | ❌ | Unrecoverable error occurred |
| `*` (fallback) | 🤖 | Unknown or custom subagent state |

---

## 6. Workspace Extraction Logic

1. **CitC (Cloud in the Cloud) Detection**:
   - If the path matches `/google/src/cloud/<username>/<workspace>[/...]`, the workspace name is extracted directly (e.g., `gemini-cli-feature`).
2. **Standard Directory**:
   - Strips trailing directory separators and extracts the basename of `project_dir` or `cwd` (e.g., `/Users/user/code/agy-pure` → `agy-pure`).
3. **Fallback**:
   - If path is empty, defaults to `unknown`.
