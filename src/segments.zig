/// Available segments for the agy-pure statusline layout.
pub const Segment = enum {
    // ── Line 1 segments ──
    model,
    context_icon,
    timer,
    cost,
    project,
    git,
    lines,
    subagents,

    // ── Progress bars ──
    bar_context,
    bar_api_time,
    bar_lines,
};
