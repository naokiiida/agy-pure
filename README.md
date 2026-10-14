# agy-pure

> Blazingly fast, zero-overhead statusline for Google Antigravity CLI (`agy`) written in Zig.

`agy-pure` is a lightweight statusline generator for `agy` (with backward compatibility for Claude Code). It renders model information, real-time prompt duration, context window token usage with 8-stage visual circular gauges, directory path, Git status (branch, dirty, ahead/behind), and subagent counts in under **5 milliseconds** with zero runtime dependencies.

---

## Preview

```
Gemini 2.5 Pro 󰪞 45.5K (4%) ⏱ 3.2s agy-pure main* [2 subagents]
```

When idle, the execution timer automatically disappears and cleans up state:
```
Gemini 2.5 Pro 󰪞 45.5K (4%) agy-pure main
```

---

## Features

- **Blazing Fast (<5ms, ~500KB binary)**: Hand-crafted Zig binary using direct POSIX system calls for maximum responsiveness and zero latency.
- **Model Display**: Shows active model name (e.g. `Gemini 2.5 Pro`, `Gemini 2.5 Flash`, etc.).
- **Context Window Usage**:
  - 8-stage dynamic Nerd Font glyphs: `󰪞`, `󰪟`, `󰪠`, `󰪡`, `󰪢`, `󰪣`, `󰪤`, `󰪥`
  - Token counts formatted cleanly (`45.5K`, `1.2M`) with exact percentage.
- **Live Prompt Duration Timer**:
  - Dynamically measures how long the current turn has been running (`⏱ 12.4s`, `⏱ 1m 23s`).
  - Automatically resets and cleans up when the agent returns to `idle`.
- **Git State**:
  - Single fast query via `git status --porcelain=v2 --branch` (without taking repository locks).
  - Shows current branch (or `DETACHED`), dirty status (`*`), ahead (`⇡2`), and behind (`⇣1`).
- **Smart Directory**:
  - Displays project or current working directory truncated to up to 3 folders deep, replacing `$HOME` with `~`.
- **Subagents Tracking**:
  - Displays active subagent count badge when multi-agent tasks are executing.
- **Themes & Customization**:
  - Built-in palettes: `vague` (default), `tokyo_night`, and `monokai`.
  - Configurable layout in `config/layout.zig`.

---

## Installation

### 1. Build from Source

Requirements: [Zig](https://ziglang.org/) `0.17.0` (or newer).

```bash
git clone https://github.com/your-username/agy-pure.git
cd agy-pure

# Build optimized binary
zig build -Doptimize=ReleaseFast
```

The compiled binary will be placed at `zig-out/bin/agy_pure`.

You can copy it to your local binaries directory or Antigravity configuration directory:
```bash
mkdir -p ~/.gemini/antigravity-cli/bin
cp zig-out/bin/agy_pure ~/.gemini/antigravity-cli/bin/agy_pure
```

### 2. Configure in Antigravity CLI (`agy`)

#### Option A: Inside `agy` Interactive Session
Run the slash command:
```text
/statusline ~/.gemini/antigravity-cli/bin/agy_pure
```

#### Option B: In `settings.json`
Add the `statusLine` configuration to `~/.gemini/antigravity-cli/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/naokiiida/.gemini/antigravity-cli/bin/agy_pure",
    "enabled": true
  }
}
```

---

## Build Options

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `-Dtheme` | `vague`, `tokyo_night`, `monokai` | `vague` | Color palette |
| `-Dnerd` | `true`, `false` | `true` | Use Nerd Font icons (circle glyphs, timer, git) |
| `-Dbar_width` | integer | `20` | Width of optional progress bars |

Example:
```bash
# Build with Tokyo Night theme
zig build -Doptimize=ReleaseFast -Dtheme=tokyo_night

# Build without Nerd Font glyphs (plain ASCII)
zig build -Doptimize=ReleaseFast -Dnerd=false
```

---

## Customizing Layout

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

// Optional multi-line progress bars (e.g. 50% block bar)
pub const bars: []const Segment = &.{
    // .bar_context,
};
```

Available segments:
- `.model`: Model display name
- `.context_icon`: 8-step circular gauge + token count + percentage
- `.timer`: Active prompt duration (`⏱ 3.2s`)
- `.project`: Smart project / cwd path
- `.git`: Branch name, dirty indicator, upstream sync
- `.cost`: Total session cost in USD
- `.lines`: Added/removed lines (`+12 -4`)
- `.subagents`: Active subagents badge
- `.bar_context`: Horizontal unicode block progress bar

After editing `config/layout.zig`, simply run `zig build -Doptimize=ReleaseFast`.

---

## License

MIT
