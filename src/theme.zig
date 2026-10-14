const std = @import("std");
const assert = std.debug.assert;
const build_options = @import("config");

// -----------------------------------------------------------------------------
// ANSI 256-Color Helpers (Comptime)
// -----------------------------------------------------------------------------

fn ansi256(comptime n: u8) []const u8 {
    return comptime std.fmt.comptimePrint("\x1b[1m\x1b[38;5;{d}m", .{n});
}

fn ansi256_dim(comptime n: u8) []const u8 {
    return comptime std.fmt.comptimePrint("\x1b[38;5;{d}m", .{n});
}

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

pub const Symbols = struct {
    git_push: []const u8,
    git_pull: []const u8,
    git_dirty: []const u8,
    lines_added: []const u8,
    lines_removed: []const u8,
    cost_usd: []const u8,
    timer: []const u8,
    separator: []const u8,
    bar_filled: []const u8,
    bar_empty: []const u8,
};

pub const Palette = struct {
    model_name_fg: []const u8,
    model_id_fg: []const u8,
    version_fg: []const u8,
    directory_fg: []const u8,
    label_fg: []const u8,

    timer_fg: []const u8,
    cost_usd_fg: []const u8,
    time_total_fg: []const u8,
    time_api_fg: []const u8,

    lines_added_fg: []const u8,
    lines_removed_fg: []const u8,

    git_branch_fg: []const u8,
    git_dirty_fg: []const u8,
    git_push_pull_fg: []const u8,

    bar_context_fg: []const u8,
    bar_session_fg: []const u8,
    bar_cache_fg: []const u8,
    bar_api_time_fg: []const u8,
    bar_empty_fg: []const u8,

    token_input_fg: []const u8,
    token_output_fg: []const u8,
    token_cache_write_fg: []const u8,
    token_cache_read_fg: []const u8,

    badge_ok_fg: []const u8,
    badge_warn_fg: []const u8,

    rate_ok_fg: []const u8,
    rate_warn_fg: []const u8,
    rate_critical_fg: []const u8,

    reset: []const u8 = "\x1b[0m",
};

pub const Config = struct {
    symbols: Symbols,
    palette: Palette,
};

// -----------------------------------------------------------------------------
// Symbol Sets
// -----------------------------------------------------------------------------

pub const symbols_nerd = Symbols{
    .git_push = "⇡",
    .git_pull = "⇣",
    .git_dirty = "*",
    .lines_added = "+",
    .lines_removed = "-",
    .cost_usd = "$",
    .timer = "⏱ ",
    .separator = " ",
    .bar_filled = "█",
    .bar_empty = "░",
};

pub const symbols_plain = Symbols{
    .git_push = "^",
    .git_pull = "v",
    .git_dirty = "*",
    .lines_added = "+",
    .lines_removed = "-",
    .cost_usd = "$",
    .timer = "T:",
    .separator = " ",
    .bar_filled = "#",
    .bar_empty = "-",
};

// -----------------------------------------------------------------------------
// Palettes
// -----------------------------------------------------------------------------

pub const palette_vague = Palette{
    .model_name_fg = ansi256(146), // muted teal
    .model_id_fg = ansi256_dim(103),
    .version_fg = ansi256(180),
    .directory_fg = ansi256(110), // soft blue
    .label_fg = ansi256_dim(249),

    .timer_fg = ansi256(222), // warm amber
    .cost_usd_fg = ansi256_dim(103),
    .time_total_fg = ansi256_dim(103),
    .time_api_fg = ansi256_dim(103),

    .lines_added_fg = ansi256(108), // sage green
    .lines_removed_fg = ansi256(168), // dusty rose

    .git_branch_fg = ansi256_dim(103),
    .git_dirty_fg = ansi256(176), // soft orchid
    .git_push_pull_fg = ansi256(174),

    .bar_context_fg = ansi256(180),
    .bar_session_fg = ansi256(146),
    .bar_cache_fg = ansi256(139),
    .bar_api_time_fg = ansi256(110),
    .bar_empty_fg = ansi256_dim(236),

    .token_input_fg = ansi256(110),
    .token_output_fg = ansi256(108),
    .token_cache_write_fg = ansi256(180),
    .token_cache_read_fg = ansi256(176),

    .badge_ok_fg = ansi256(108),
    .badge_warn_fg = ansi256(168),

    .rate_ok_fg = ansi256(108),
    .rate_warn_fg = ansi256(180),
    .rate_critical_fg = ansi256(168),
};

pub const palette_monokai = Palette{
    .model_name_fg = ansi256(141), // purple
    .model_id_fg = ansi256_dim(104),
    .version_fg = ansi256(208),
    .directory_fg = ansi256(81), // cyan
    .label_fg = ansi256_dim(231),

    .timer_fg = ansi256(220), // yellow gold
    .cost_usd_fg = ansi256(186),
    .time_total_fg = ansi256_dim(176),
    .time_api_fg = ansi256_dim(189),

    .lines_added_fg = ansi256(148), // green
    .lines_removed_fg = ansi256(161), // red

    .git_branch_fg = ansi256_dim(104),
    .git_dirty_fg = ansi256(176),
    .git_push_pull_fg = ansi256(208),

    .bar_context_fg = ansi256(60),
    .bar_session_fg = ansi256(104),
    .bar_cache_fg = ansi256(139),
    .bar_api_time_fg = ansi256(60),
    .bar_empty_fg = ansi256_dim(233),

    .token_input_fg = ansi256(81),
    .token_output_fg = ansi256(68),
    .token_cache_write_fg = ansi256(186),
    .token_cache_read_fg = ansi256(179),

    .badge_ok_fg = ansi256(148),
    .badge_warn_fg = ansi256(197),

    .rate_ok_fg = ansi256(148),
    .rate_warn_fg = ansi256(186),
    .rate_critical_fg = ansi256(197),
};

pub const palette_tokyo_night = Palette{
    .model_name_fg = ansi256(111), // soft cornflower blue
    .model_id_fg = ansi256_dim(103),
    .version_fg = ansi256(179),
    .directory_fg = ansi256(117), // sky cyan
    .label_fg = ansi256_dim(250),

    .timer_fg = ansi256(215), // warm peach
    .cost_usd_fg = ansi256(180),
    .time_total_fg = ansi256_dim(103),
    .time_api_fg = ansi256_dim(103),

    .lines_added_fg = ansi256(120), // emerald green
    .lines_removed_fg = ansi256(204), // soft magenta/red

    .git_branch_fg = ansi256_dim(141), // lavender
    .git_dirty_fg = ansi256(215),
    .git_push_pull_fg = ansi256(117),

    .bar_context_fg = ansi256(111),
    .bar_session_fg = ansi256(141),
    .bar_cache_fg = ansi256(140),
    .bar_api_time_fg = ansi256(117),
    .bar_empty_fg = ansi256_dim(236),

    .token_input_fg = ansi256(117),
    .token_output_fg = ansi256(120),
    .token_cache_write_fg = ansi256(179),
    .token_cache_read_fg = ansi256(141),

    .badge_ok_fg = ansi256(120),
    .badge_warn_fg = ansi256(204),

    .rate_ok_fg = ansi256(120),
    .rate_warn_fg = ansi256(179),
    .rate_critical_fg = ansi256(204),
};

// -----------------------------------------------------------------------------
// Active Configuration
// -----------------------------------------------------------------------------

pub const active_config = Config{
    .symbols = if (build_options.nerd) symbols_nerd else symbols_plain,
    .palette = switch (build_options.theme) {
        .vague => palette_vague,
        .monokai => palette_monokai,
        .tokyo_night => palette_tokyo_night,
    },
};

// -----------------------------------------------------------------------------
// Writer API & Context Icons
// -----------------------------------------------------------------------------

pub const context_bar_steps = 8;
const context_bar_nerd = [context_bar_steps][]const u8{ "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" };
const context_bar_plain = [context_bar_steps][]const u8{ "_", ".", ".", "=", "=", "/", "|", "@" };
pub const context_bar_glyphs = if (build_options.nerd) context_bar_nerd else context_bar_plain;

pub fn writeColored(writer: anytype, comptime config: Config, color: []const u8, text: []const u8) !void {
    if (text.len == 0) return;
    try writer.writeAll(color);
    try writer.writeAll(text);
    try writer.writeAll(config.palette.reset);
}

pub fn writeSymbol(writer: anytype, comptime config: Config, color: []const u8, symbol: []const u8, text: []const u8) !void {
    try writer.writeAll(color);
    try writer.writeAll(symbol);
    if (text.len > 0) try writer.writeAll(text);
    try writer.writeAll(config.palette.reset);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "ansi256 produces valid sequence" {
    const seq = comptime ansi256(146);
    try std.testing.expect(seq.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1b[1m\x1b[38;5;"));
}
