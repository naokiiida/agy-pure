#!/usr/bin/env python3
import sys
import json
import os
import re

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

state = data.get("agent_state") or "idle"
workspace_dir = data.get("workspace", {}).get("current_dir") or data.get("cwd") or ""

if workspace_dir:
    citc_match = re.match(r"^/google/src/cloud/[^/]+/([^/]+)", workspace_dir)
    if citc_match:
        workspace = citc_match.group(1)
    else:
        workspace = os.path.basename(workspace_dir.rstrip("/")) or "unknown"
else:
    workspace = "unknown"

emojis = {
    "initializing": "🚀",
    "idle": "😴",
    "thinking": "🤔",
    "working": "🏃",
    "tool_use": "🛠️",
    "running": "🏃",
    "processing": "⚙️",
}
emoji = emojis.get(state.lower(), "🤖")

print(f"{emoji} {state} | {workspace}")
