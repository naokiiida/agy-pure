# agy-pure

> Blazingly fast, zero-overhead statusline and window title generators for Google Antigravity CLI (`agy`) written in Zig.

`agy-pure` provides lightning-fast CLI extensions for `agy` (with backward compatibility for Claude Code):
- **`agy_pure`**: Rich statusline generator rendering model information, real-time prompt duration, 8-stage visual circular gauges, directory path, Git status, and subagent counts.
- **`agy_title`**: Terminal window/tab title generator rendering agent lifecycle states with emojis and smart CitC/Git workspace detection.

Both compile into tiny native binaries (<540 KB) that execute in **under 2.5 milliseconds** with zero runtime dependencies.

---

## Previews

### Statusline (`agy_pure`)
```
Gemini 2.5 Pro 󰪞 45.5K (4%) ⏱ 3.2s agy-pure main* [2 subagents]
```
When idle, the execution timer automatically disappears and cleans up state:
```
Gemini 2.5 Pro 󰪞 45.5K (4%) agy-pure main
```

### Window Title (`agy_title`)
```
🏃 working | agy-pure
😴 idle | agy-pure
🤔 thinking | agy-pure
🛠️ tool_use | agy-pure
```
With optional flags (`--git`, `--subagents`):
```
🏃 working | agy-pure (main) [2 subagents]
```

---

## Benchmark Highlights

Measured with `hyperfine` on Apple Silicon (arm64):

| Tool / Runtime | Wall Time (Mean) | CPU Time | Peak Memory | Binary Size | Speedup vs Baseline |
|:---|---:|---:|---:|---:|:---|
| **`agy_title` (Zig)** | **2.29 ms** | **1.70 ms** | **1.6 MB** | **503 KB** | **Baseline (6.5x faster)** |
| `title.sh` (Bash + `jq`) | 14.89 ms | 12.46 ms | 6.7 MB | N/A | 6.5x slower (+550%) |
| `title.py` (Python 3) | 30.35 ms | 26.62 ms | 9.5 MB | N/A | 13.3x slower (+1,225%) |
| `title.js` (Node.js) | 58.28 ms | 56.81 ms | 39.6 MB | N/A | 25.5x slower (+2,448%) |

Detailed benchmark methodology and root cause analysis: [docs/performance-analysis.md](docs/performance-analysis.md).

---

## Features

### `agy_pure` (Statusline)
- **Ultra-Fast (<5ms, ~538KB binary)**: Hand-crafted Zig using direct POSIX system calls for maximum responsiveness.
- **Model Display**: Shows active model name (e.g. `Gemini 3.8 Flash`, `Gemini 2.5 Pro`).
- **Context Window Usage**:
  - 8-stage dynamic Nerd Font glyphs: `󰪞`, `󰪟`, `󰪠`, `󰪡`, `󰪢`, `󰪣`, `󰪤`, `󰪥`
  - Formatted token counts (`45.5K`, `1.2M`) with exact percentage.
- **Live Prompt Duration Timer**:
  - Dynamically measures active turn duration (`⏱ 12.4s`, `⏱ 1m 23s`).
  - Automatically cleans up state upon returning to `idle`.
- **Git State**: Single fast query via `git status --porcelain=v2 --branch` (branch, dirty `*`, ahead `⇡2`, behind `⇣1`).
- **Smart Directory**: Displays project or cwd truncated up to 3 folders deep, replacing `$HOME` with `~`.
- **Subagents Tracking**: Displays active subagent count badge when multi-agent tasks execute.
- **Themes**: Built-in palettes (`vague`, `tokyo_night`, `monokai`).

### `agy_title` (Window Title)
- **Sub-3ms Execution (~503KB binary)**: Ensures zero terminal flicker or CPU spikes even during rapid agent state transitions.
- **State Emoji Mapping**: Maps all Antigravity states (`initializing` 🚀, `idle` 😴, `thinking` 🤔, `working`/`running` 🏃, `tool_use` 🛠️, `waiting_for_input` ⏳, `done` ✅, `error` ❌).
- **Workspace Intelligence**:
  - Automatically detects **CitC** workspaces (`/google/src/cloud/<user>/<workspace>`).
  - Falls back to project directory basename.
- **Optional Extensions**:
  - `--git`: Append current git branch name.
  - `--subagents`: Append active subagents badge.
  - `--no-emoji`: Pure plain-text output.

---

## Installation

### 1. Build from Source

Requirements: [Zig](https://ziglang.org/) `0.17.0` (or newer).

```bash
git clone https://github.com/your-username/agy-pure.git
cd agy-pure

# Build optimized binaries for both statusline and title
zig build -Doptimize=ReleaseFast
```

The compiled binaries will be placed in `zig-out/bin/`:
- `zig-out/bin/agy_pure` (Statusline)
- `zig-out/bin/agy_title` (Window Title)

Copy them to your local binary path:
```bash
mkdir -p ~/.gemini/antigravity-cli/bin
cp zig-out/bin/agy_pure ~/.gemini/antigravity-cli/bin/agy_pure
cp zig-out/bin/agy_title ~/.gemini/antigravity-cli/bin/agy_title
```

---

## 2. Configure in Antigravity CLI (`agy`)

Add both tools to `~/.gemini/antigravity-cli/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_pure",
    "enabled": true
  },
  "title": {
    "type": "command",
    "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_title"
  }
}
```

### Interactive CLI Slash Commands

Inside an interactive `agy` session:
```text
/statusline ~/.gemini/antigravity-cli/bin/agy_pure
/title ~/.gemini/antigravity-cli/bin/agy_title
```

---

## Documentation

- [docs/performance-analysis.md](docs/performance-analysis.md): Benchmark results, CPU cycle metrics, and root cause analysis vs Bash/jq, Python, and Node.js.
- [docs/title-json-schema.md](docs/title-json-schema.md): Complete JSON state payload schema and protocol reference for Antigravity terminal title.

---

## Customizing Statusline Layout

Statusline segments are configured in [config/layout.zig](config/layout.zig):

```zig
pub const line1: []const Segment = &.{
    .model,
    .context_icon,
    .timer,
    .project,
    .git,
    .lines,
    .subagents,
};
```

After modifying `config/layout.zig`, simply run:
```bash
zig build -Doptimize=ReleaseFast
```

---

## Running Tests & Benchmarks

```bash
# Run unit test suite
zig build test

# Run benchmark suite (requires hyperfine)
hyperfine --warmup 10 --min-runs 50 --input benchmark/payload.json \
  "./zig-out/bin/agy_title" \
  "bash benchmark/title.sh" \
  "python3 benchmark/title.py" \
  "node benchmark/title.js"
```

---

## License

MIT
