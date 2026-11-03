const Segment = @import("agy_pure").segments.Segment;

/// Line 1 Left segments (identity anchors: model/title, project, git branch).
pub const left: []const Segment = &.{
    .model,
    .project,
    .git,
};

/// Line 1 Right segments (telemetry: subagents, lines, cost, timer, context/cache).
pub const right: []const Segment = &.{
    .subagents,
    .lines,
    .cost,
    .timer,
    .context_icon,
};

/// Backwards compatibility alias for single-list layout configs.
pub const line1: []const Segment = left;

/// Right margin padding from terminal edge (default: 1 cell safety margin).
pub const right_margin: u16 = 1;

/// Optional progress bars (one per line below Line 1).
pub const bars: []const Segment = &.{
    // .bar_context,
    // .bar_api_time,
    // .bar_lines,
};
