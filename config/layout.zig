const Segment = @import("agy_pure").segments.Segment;

/// Line 1 segments rendered left to right separated by spaces.
/// Available segments: .model, .session_title, .context_icon, .timer, .cost, .project, .git, .lines, .subagents
pub const line1: []const Segment = &.{
    .model,
    .context_icon,
    .timer,
    .cost,
    .project,
    .git,
    .lines,
    .subagents,
};

/// Optional progress bars (one per line below Line 1).
pub const bars: []const Segment = &.{
    // .bar_context,
    // .bar_api_time,
    // .bar_lines,
};
