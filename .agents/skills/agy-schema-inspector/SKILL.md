---
name: agy-schema-inspector
description: How to inspect, verify, and reverse-engineer Antigravity (agy) CLI JSON schemas, lifecycle states, hooks, and statusline/title payloads using binary introspection and runtime probes.
---

# Antigravity CLI Schema Inspector & State Discovery Guide

When developing extensions, statuslines, window title generators, or lifecycle hooks for Google Antigravity CLI (`agy`), never assume that schemas or state strings mirror other tools like Claude Code. Antigravity runs on Google's Go-based `jetski_cortex` architecture with its own lifecycle state machine and data models.

This guide provides reproducible techniques to inspect the live `agy` binary, capture exact stdin payloads, and verify supported lifecycle events.

---

## 1. Fast Binary Introspection (`agy`)

The `agy` executable contains compiled Go package paths, struct definitions, JSON field tags, and protocol constants.

### A. Locate the Binary
```bash
which agy
# typically /opt/homebrew/bin/agy on macOS
```

### B. Find Core CLI Subsystems
```bash
# Locate store managers and runners (title, statusline, hooks)
strings -a $(which agy) | rg "third_party/jetski/cli/store/.*(title|statusline|hook|manager)"

# Key source files identified in agy:
# - third_party/jetski/cli/store/title_manager.go       (TitleRunner & updates)
# - third_party/jetski/cli/store/statusline_runner.go   (statusline execution)
# - third_party/jetski/cli/store/statusline_manager.go  (statusline manager)
# - third_party/jetski/cli/store/hooks_manager.go       (hooks.json execution)
# - third_party/jetski/cli/types/statusline_external.go (StatusLineData schema)
# - third_party/jetski/cli/termstatus/termstatus.go     (OSC protocols & states)
```

### C. Extract Actual Lifecycle States & UI Phases
```bash
# Inspect UI phases and state string representations
strings -a $(which agy) | rg -C 3 "store\.UIPhase\.String|store\.UIState\.String"

# Search for program status state mappings
strings -a $(which agy) | rg -C 5 "SetProgramStatus"
```

---

## 2. Ground-Truth Antigravity Lifecycle States

Through binary introspection and runtime validation, the official Antigravity CLI lifecycle states emitted in `agent_state` are:

| `agent_state` Value | Meaning & Context | Common Extension Mistake |
| :--- | :--- | :--- |
| **`"working"`** | Model reasoning, token streaming, **AND** tool execution (`run_command`, `edit_file`, `read_file`, etc.). | ⚠️ **Do not check for `"tool_use"`!** `agy` does *not* emit `"tool_use"`. To show tool names in titles, check `state == "working"` and inspect recent tool calls in `transcript.jsonl`. |
| **`"reviewing"`** | Active **Artifact Review** modal or diff confirmation (`ArtifactReviewModel`). | ⚠️ Often forgotten; defaults to unmapped fallback if not handled. |
| **`"waiting_for_user"`** | Blocked awaiting user confirmation, interactive question (`AskUserQuestion`), or permission gate. | Crucial for rendering `⚠️ APPROVE` or `OSC 7501;state=blocked`. |
| **`"idle"`** | Turn complete; awaiting user's next prompt at the terminal prompt. | Clears timers and resets progress bars. |
| **`"done"`** / **`"complete"`** | Execution completed successfully. | Triggers post-turn status and notifications. |
| **`"error"`** | Turn aborted due to unrecoverable error. | Renders failure indicator. |

---

## 3. Capturing Live Runtime Payloads (Probe Technique)

The most reliable way to verify what fields are passed to `title` or `statusLine` is a 1-line transparent probe wrapper.

### A. Create a Payload Logger Wrapper (`/tmp/agy_probe.sh`)
```bash
#!/bin/bash
PAYLOAD_DIR="/tmp/agy_probes"
mkdir -p "$PAYLOAD_DIR"
TIMESTAMP=$(date +%s%N)
PAYLOAD_FILE="$PAYLOAD_DIR/${TIMESTAMP}_payload.json"

# Capture stdin
cat > "$PAYLOAD_FILE"

# Log invocation state
echo "[$(date)] Probed payload: $PAYLOAD_FILE" >> "$PAYLOAD_DIR/probe.log"

# Forward original payload to the real binary
cat "$PAYLOAD_FILE" | /Users/naokiiida/.gemini/antigravity-cli/bin/agy_title "$@"
```
Make executable: `chmod +x /tmp/agy_probe.sh`.

### B. Temporarily Wire in `~/.gemini/antigravity-cli/settings.json`
```json
{
  "title": {
    "type": "command",
    "command": "/tmp/agy_probe.sh --git --subagents"
  }
}
```

### C. Inspect Live JSON Dumps
```bash
cat /tmp/agy_probes/*_payload.json | jq .
```
This reveals the exact schema and fields (e.g. `context_window.current_usage`, `subagents`, `workspace`).

---

## 4. Built-in Terminal Protocols in Antigravity

Antigravity natively includes hooks for terminal status reporting:
- `AGY_CLI_OSC7501_MESSAGES`: Environment flag that governs native `OSC 7501` program status updates.
- `termstatus.go`: Uses Charmbracelet's `ansi.SetProgramStatus` and `ansi.SetWindowTitle`.
- `Stop` Hook: Fired via `hooks_manager.go` upon loop termination (`NO_TOOL_CALL`, `ERROR`), carrying `StopHookPayload`.
