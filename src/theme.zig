const std = @import("std");
const assert = std.debug.assert;
const build_options = @import("config");

// -----------------------------------------------------------------------------
// Types & Enums
// -----------------------------------------------------------------------------

pub const ThemeFamily = enum {
    catppuccin,
    tokyo_night,
    monokai,
};

pub const ThemeVariant = enum {
    catppuccin_mocha,
    catppuccin_latte,
    tokyo_night,
    tokyo_night_day,
    monokai,
    monokai_light,
};

pub const ColorMode = enum {
    truecolor,
    ansi256,
    none,
};

pub const Appearance = enum {
    dark,
    light,
};

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Rgb {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn hex(comptime h: u24) Rgb {
        return .{
            .r = @intCast((h >> 16) & 0xFF),
            .g = @intCast((h >> 8) & 0xFF),
            .b = @intCast(h & 0xFF),
        };
    }

    /// Standard 24-bit TrueColor foreground sequence (\x1b[38;2;R;G;Bm) per termstandard/colors
    pub fn fgTruecolor(comptime self: Rgb) []const u8 {
        return std.fmt.comptimePrint("\x1b[38;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }

    /// Bold 24-bit TrueColor foreground sequence (\x1b[1m\x1b[38;2;R;G;Bm)
    pub fn fgTruecolorBold(comptime self: Rgb) []const u8 {
        return std.fmt.comptimePrint("\x1b[1m\x1b[38;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }

    /// Comptime perceptual Redmean human-eye-weighted Euclidean distance quantization against all 256 xterm slots.
    /// Formula: ΔC² = 2(ΔR)² + 4(ΔG)² + 3(ΔB)²
    pub fn toAnsi256(comptime self: Rgb) u8 {
        @setEvalBranchQuota(100_000);
        var best_idx: u8 = 0;
        var best_dist: u64 = std.math.maxInt(u64);

        for (ansi_256_palette, 0..) |c, i| {
            const dr = @as(i64, self.r) - @as(i64, c.r);
            const dg = @as(i64, self.g) - @as(i64, c.g);
            const db = @as(i64, self.b) - @as(i64, c.b);
            const dist: u64 = @intCast(2 * dr * dr + 4 * dg * dg + 3 * db * db);
            if (dist < best_dist) {
                best_dist = dist;
                best_idx = @intCast(i);
            }
        }
        return best_idx;
    }

    pub fn fgAnsi256(comptime self: Rgb) []const u8 {
        return std.fmt.comptimePrint("\x1b[38;5;{d}m", .{self.toAnsi256()});
    }

    pub fn fgAnsi256Bold(comptime self: Rgb) []const u8 {
        return std.fmt.comptimePrint("\x1b[1m\x1b[38;5;{d}m", .{self.toAnsi256()});
    }
};

/// 256-color palette table precomputed for comptime Redmean quantization
const ansi_256_palette = blk: {
    var table: [256]Rgb = undefined;
    // Standard 16 ANSI colors
    table[0] = Rgb.init(0, 0, 0);
    table[1] = Rgb.init(128, 0, 0);
    table[2] = Rgb.init(0, 128, 0);
    table[3] = Rgb.init(128, 128, 0);
    table[4] = Rgb.init(0, 0, 128);
    table[5] = Rgb.init(128, 0, 128);
    table[6] = Rgb.init(0, 128, 128);
    table[7] = Rgb.init(192, 192, 192);
    table[8] = Rgb.init(128, 128, 128);
    table[9] = Rgb.init(255, 0, 0);
    table[10] = Rgb.init(0, 255, 0);
    table[11] = Rgb.init(255, 255, 0);
    table[12] = Rgb.init(0, 0, 255);
    table[13] = Rgb.init(255, 0, 255);
    table[14] = Rgb.init(0, 255, 255);
    table[15] = Rgb.init(255, 255, 255);

    // 16..231: 6x6x6 RGB cube
    const steps = [6]u8{ 0, 95, 135, 175, 215, 255 };
    var idx: usize = 16;
    for (steps) |r| {
        for (steps) |g| {
            for (steps) |b| {
                table[idx] = Rgb.init(r, g, b);
                idx += 1;
            }
        }
    }

    // 232..255: Grayscale ramp
    for (0..24) |i| {
        const gray: u8 = @intCast(8 + i * 10);
        table[idx] = Rgb.init(gray, gray, gray);
        idx += 1;
    }

    break :blk table;
};

pub const ColorDef = struct {
    rgb: Rgb,
    bold: bool = true,
    ansi_override: ?u8 = null,

    pub fn toSequence(comptime self: ColorDef, comptime mode: ColorMode) []const u8 {
        @setEvalBranchQuota(500_000);
        return switch (mode) {
            .none => "",
            .truecolor => if (self.bold) self.rgb.fgTruecolorBold() else self.rgb.fgTruecolor(),
            .ansi256 => blk: {
                const idx = self.ansi_override orelse self.rgb.toAnsi256();
                break :blk if (self.bold)
                    std.fmt.comptimePrint("\x1b[1m\x1b[38;5;{d}m", .{idx})
                else
                    std.fmt.comptimePrint("\x1b[38;5;{d}m", .{idx});
            },
        };
    }
};

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
    session_title_fg: []const u8,
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
// Theme Definitions
// -----------------------------------------------------------------------------

pub const ThemeDefinition = struct {
    model_name: ColorDef,
    session_title: ColorDef,
    model_id: ColorDef,
    version: ColorDef,
    directory: ColorDef,
    label: ColorDef,

    timer: ColorDef,
    cost_usd: ColorDef,
    time_total: ColorDef,
    time_api: ColorDef,

    lines_added: ColorDef,
    lines_removed: ColorDef,

    git_branch: ColorDef,
    git_dirty: ColorDef,
    git_push_pull: ColorDef,

    bar_context: ColorDef,
    bar_session: ColorDef,
    bar_cache: ColorDef,
    bar_api_time: ColorDef,
    bar_empty: ColorDef,

    token_input: ColorDef,
    token_output: ColorDef,
    token_cache_write: ColorDef,
    token_cache_read: ColorDef,

    badge_ok: ColorDef,
    badge_warn: ColorDef,

    rate_ok: ColorDef,
    rate_warn: ColorDef,
    rate_critical: ColorDef,
};

pub fn generatePalette(comptime def: ThemeDefinition, comptime mode: ColorMode) Palette {
    return Palette{
        .model_name_fg = def.model_name.toSequence(mode),
        .session_title_fg = def.session_title.toSequence(mode),
        .model_id_fg = def.model_id.toSequence(mode),
        .version_fg = def.version.toSequence(mode),
        .directory_fg = def.directory.toSequence(mode),
        .label_fg = def.label.toSequence(mode),

        .timer_fg = def.timer.toSequence(mode),
        .cost_usd_fg = def.cost_usd.toSequence(mode),
        .time_total_fg = def.time_total.toSequence(mode),
        .time_api_fg = def.time_api.toSequence(mode),

        .lines_added_fg = def.lines_added.toSequence(mode),
        .lines_removed_fg = def.lines_removed.toSequence(mode),

        .git_branch_fg = def.git_branch.toSequence(mode),
        .git_dirty_fg = def.git_dirty.toSequence(mode),
        .git_push_pull_fg = def.git_push_pull.toSequence(mode),

        .bar_context_fg = def.bar_context.toSequence(mode),
        .bar_session_fg = def.bar_session.toSequence(mode),
        .bar_cache_fg = def.bar_cache.toSequence(mode),
        .bar_api_time_fg = def.bar_api_time.toSequence(mode),
        .bar_empty_fg = def.bar_empty.toSequence(mode),

        .token_input_fg = def.token_input.toSequence(mode),
        .token_output_fg = def.token_output.toSequence(mode),
        .token_cache_write_fg = def.token_cache_write.toSequence(mode),
        .token_cache_read_fg = def.token_cache_read.toSequence(mode),

        .badge_ok_fg = def.badge_ok.toSequence(mode),
        .badge_warn_fg = def.badge_warn.toSequence(mode),

        .rate_ok_fg = def.rate_ok.toSequence(mode),
        .rate_warn_fg = def.rate_warn.toSequence(mode),
        .rate_critical_fg = def.rate_critical.toSequence(mode),

        .reset = if (mode == .none) "" else "\x1b[0m",
    };
}

// -----------------------------------------------------------------------------
// Catppuccin Mocha (Dark Flagship Default)
// -----------------------------------------------------------------------------

pub const catppuccin_mocha_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0xb4befe), .bold = true }, // Lavender
    .session_title = .{ .rgb = Rgb.hex(0xb4befe), .bold = true },
    .model_id = .{ .rgb = Rgb.hex(0x6c7086), .bold = false }, // Overlay0
    .version = .{ .rgb = Rgb.hex(0xfab387), .bold = true }, // Peach
    .directory = .{ .rgb = Rgb.hex(0x74c7ec), .bold = true }, // Sapphire
    .label = .{ .rgb = Rgb.hex(0x6c7086), .bold = false },

    .timer = .{ .rgb = Rgb.hex(0xfab387), .bold = true }, // Peach
    .cost_usd = .{ .rgb = Rgb.hex(0x6c7086), .bold = false },
    .time_total = .{ .rgb = Rgb.hex(0x6c7086), .bold = false },
    .time_api = .{ .rgb = Rgb.hex(0x6c7086), .bold = false },

    .lines_added = .{ .rgb = Rgb.hex(0xa6e3a1), .bold = true }, // Green
    .lines_removed = .{ .rgb = Rgb.hex(0xf38ba8), .bold = true }, // Red

    .git_branch = .{ .rgb = Rgb.hex(0xcba6f7), .bold = false }, // Mauve
    .git_dirty = .{ .rgb = Rgb.hex(0xfab387), .bold = true }, // Peach
    .git_push_pull = .{ .rgb = Rgb.hex(0x89dceb), .bold = true }, // Sky

    .bar_context = .{ .rgb = Rgb.hex(0x74c7ec), .bold = true }, // Sapphire
    .bar_session = .{ .rgb = Rgb.hex(0xb4befe), .bold = true }, // Lavender
    .bar_cache = .{ .rgb = Rgb.hex(0xcba6f7), .bold = true }, // Mauve
    .bar_api_time = .{ .rgb = Rgb.hex(0x94e2d5), .bold = true }, // Teal
    .bar_empty = .{ .rgb = Rgb.hex(0x313244), .bold = false }, // Surface0

    .token_input = .{ .rgb = Rgb.hex(0x74c7ec), .bold = true }, // Sapphire
    .token_output = .{ .rgb = Rgb.hex(0xa6e3a1), .bold = true }, // Green
    .token_cache_write = .{ .rgb = Rgb.hex(0xfab387), .bold = true }, // Peach
    .token_cache_read = .{ .rgb = Rgb.hex(0xcba6f7), .bold = true }, // Mauve

    .badge_ok = .{ .rgb = Rgb.hex(0xa6e3a1), .bold = true },
    .badge_warn = .{ .rgb = Rgb.hex(0xf38ba8), .bold = true },

    .rate_ok = .{ .rgb = Rgb.hex(0xa6e3a1), .bold = true },
    .rate_warn = .{ .rgb = Rgb.hex(0xf9e2af), .bold = true }, // Yellow
    .rate_critical = .{ .rgb = Rgb.hex(0xf38ba8), .bold = true },
};

// -----------------------------------------------------------------------------
// Catppuccin Latte (Light Counterpart Default)
// -----------------------------------------------------------------------------

pub const catppuccin_latte_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0x7287fd), .bold = true }, // Lavender
    .session_title = .{ .rgb = Rgb.hex(0x7287fd), .bold = true },
    .model_id = .{ .rgb = Rgb.hex(0x6c6f85), .bold = false }, // Subtext0
    .version = .{ .rgb = Rgb.hex(0xfe640b), .bold = true }, // Peach
    .directory = .{ .rgb = Rgb.hex(0x209fb5), .bold = true }, // Sapphire
    .label = .{ .rgb = Rgb.hex(0x6c6f85), .bold = false },

    .timer = .{ .rgb = Rgb.hex(0xfe640b), .bold = true }, // Peach
    .cost_usd = .{ .rgb = Rgb.hex(0x6c6f85), .bold = false },
    .time_total = .{ .rgb = Rgb.hex(0x6c6f85), .bold = false },
    .time_api = .{ .rgb = Rgb.hex(0x6c6f85), .bold = false },

    .lines_added = .{ .rgb = Rgb.hex(0x40a02b), .bold = true }, // Green
    .lines_removed = .{ .rgb = Rgb.hex(0xd20f39), .bold = true }, // Red

    .git_branch = .{ .rgb = Rgb.hex(0x8839ef), .bold = false }, // Mauve
    .git_dirty = .{ .rgb = Rgb.hex(0xfe640b), .bold = true }, // Peach
    .git_push_pull = .{ .rgb = Rgb.hex(0x209fb5), .bold = true }, // Sapphire

    .bar_context = .{ .rgb = Rgb.hex(0x209fb5), .bold = true }, // Sapphire
    .bar_session = .{ .rgb = Rgb.hex(0x7287fd), .bold = true }, // Lavender
    .bar_cache = .{ .rgb = Rgb.hex(0x8839ef), .bold = true }, // Mauve
    .bar_api_time = .{ .rgb = Rgb.hex(0x179299), .bold = true }, // Teal
    .bar_empty = .{ .rgb = Rgb.hex(0xccd0da), .bold = false }, // Surface0

    .token_input = .{ .rgb = Rgb.hex(0x209fb5), .bold = true },
    .token_output = .{ .rgb = Rgb.hex(0x40a02b), .bold = true },
    .token_cache_write = .{ .rgb = Rgb.hex(0xfe640b), .bold = true },
    .token_cache_read = .{ .rgb = Rgb.hex(0x8839ef), .bold = true },

    .badge_ok = .{ .rgb = Rgb.hex(0x40a02b), .bold = true },
    .badge_warn = .{ .rgb = Rgb.hex(0xd20f39), .bold = true },

    .rate_ok = .{ .rgb = Rgb.hex(0x40a02b), .bold = true },
    .rate_warn = .{ .rgb = Rgb.hex(0xdf8e1d), .bold = true }, // Yellow
    .rate_critical = .{ .rgb = Rgb.hex(0xd20f39), .bold = true },
};

// -----------------------------------------------------------------------------
// Tokyo Night (Dark) & Tokyo Night Day (Light)
// -----------------------------------------------------------------------------

pub const tokyo_night_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0x7aa2f7), .bold = true, .ansi_override = 111 },
    .session_title = .{ .rgb = Rgb.hex(0x7aa2f7), .bold = true, .ansi_override = 111 },
    .model_id = .{ .rgb = Rgb.hex(0x565f89), .bold = false, .ansi_override = 103 },
    .version = .{ .rgb = Rgb.hex(0xe0af68), .bold = true, .ansi_override = 179 },
    .directory = .{ .rgb = Rgb.hex(0x7dcfff), .bold = true, .ansi_override = 117 },
    .label = .{ .rgb = Rgb.hex(0x565f89), .bold = false, .ansi_override = 250 },

    .timer = .{ .rgb = Rgb.hex(0xff9e64), .bold = true, .ansi_override = 215 },
    .cost_usd = .{ .rgb = Rgb.hex(0xe0af68), .bold = true, .ansi_override = 180 },
    .time_total = .{ .rgb = Rgb.hex(0x565f89), .bold = false, .ansi_override = 103 },
    .time_api = .{ .rgb = Rgb.hex(0x565f89), .bold = false, .ansi_override = 103 },

    .lines_added = .{ .rgb = Rgb.hex(0x9ece6a), .bold = true, .ansi_override = 120 },
    .lines_removed = .{ .rgb = Rgb.hex(0xf7768e), .bold = true, .ansi_override = 204 },

    .git_branch = .{ .rgb = Rgb.hex(0xbb9af7), .bold = false, .ansi_override = 141 },
    .git_dirty = .{ .rgb = Rgb.hex(0xff9e64), .bold = true, .ansi_override = 215 },
    .git_push_pull = .{ .rgb = Rgb.hex(0x7dcfff), .bold = true, .ansi_override = 117 },

    .bar_context = .{ .rgb = Rgb.hex(0x7aa2f7), .bold = true, .ansi_override = 111 },
    .bar_session = .{ .rgb = Rgb.hex(0xbb9af7), .bold = true, .ansi_override = 141 },
    .bar_cache = .{ .rgb = Rgb.hex(0x9d7cd8), .bold = true, .ansi_override = 140 },
    .bar_api_time = .{ .rgb = Rgb.hex(0x7dcfff), .bold = true, .ansi_override = 117 },
    .bar_empty = .{ .rgb = Rgb.hex(0x292e42), .bold = false, .ansi_override = 236 },

    .token_input = .{ .rgb = Rgb.hex(0x7dcfff), .bold = true, .ansi_override = 117 },
    .token_output = .{ .rgb = Rgb.hex(0x9ece6a), .bold = true, .ansi_override = 120 },
    .token_cache_write = .{ .rgb = Rgb.hex(0xe0af68), .bold = true, .ansi_override = 179 },
    .token_cache_read = .{ .rgb = Rgb.hex(0xbb9af7), .bold = true, .ansi_override = 141 },

    .badge_ok = .{ .rgb = Rgb.hex(0x9ece6a), .bold = true, .ansi_override = 120 },
    .badge_warn = .{ .rgb = Rgb.hex(0xf7768e), .bold = true, .ansi_override = 204 },

    .rate_ok = .{ .rgb = Rgb.hex(0x9ece6a), .bold = true, .ansi_override = 120 },
    .rate_warn = .{ .rgb = Rgb.hex(0xe0af68), .bold = true, .ansi_override = 179 },
    .rate_critical = .{ .rgb = Rgb.hex(0xf7768e), .bold = true, .ansi_override = 204 },
};

pub const tokyo_night_day_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0x2e5894), .bold = true },
    .session_title = .{ .rgb = Rgb.hex(0x2e5894), .bold = true },
    .model_id = .{ .rgb = Rgb.hex(0x6172b0), .bold = false },
    .version = .{ .rgb = Rgb.hex(0x8f5e15), .bold = true },
    .directory = .{ .rgb = Rgb.hex(0x006a88), .bold = true },
    .label = .{ .rgb = Rgb.hex(0x6172b0), .bold = false },

    .timer = .{ .rgb = Rgb.hex(0xb15c00), .bold = true },
    .cost_usd = .{ .rgb = Rgb.hex(0x8f5e15), .bold = false },
    .time_total = .{ .rgb = Rgb.hex(0x6172b0), .bold = false },
    .time_api = .{ .rgb = Rgb.hex(0x6172b0), .bold = false },

    .lines_added = .{ .rgb = Rgb.hex(0x387028), .bold = true },
    .lines_removed = .{ .rgb = Rgb.hex(0xc62828), .bold = true },

    .git_branch = .{ .rgb = Rgb.hex(0x5a3e8e), .bold = false },
    .git_dirty = .{ .rgb = Rgb.hex(0xb15c00), .bold = true },
    .git_push_pull = .{ .rgb = Rgb.hex(0x006a88), .bold = true },

    .bar_context = .{ .rgb = Rgb.hex(0x2e5894), .bold = true },
    .bar_session = .{ .rgb = Rgb.hex(0x5a3e8e), .bold = true },
    .bar_cache = .{ .rgb = Rgb.hex(0x7b5cb0), .bold = true },
    .bar_api_time = .{ .rgb = Rgb.hex(0x006a88), .bold = true },
    .bar_empty = .{ .rgb = Rgb.hex(0xc4c8da), .bold = false },

    .token_input = .{ .rgb = Rgb.hex(0x006a88), .bold = true },
    .token_output = .{ .rgb = Rgb.hex(0x387028), .bold = true },
    .token_cache_write = .{ .rgb = Rgb.hex(0x8f5e15), .bold = true },
    .token_cache_read = .{ .rgb = Rgb.hex(0x5a3e8e), .bold = true },

    .badge_ok = .{ .rgb = Rgb.hex(0x387028), .bold = true },
    .badge_warn = .{ .rgb = Rgb.hex(0xc62828), .bold = true },

    .rate_ok = .{ .rgb = Rgb.hex(0x387028), .bold = true },
    .rate_warn = .{ .rgb = Rgb.hex(0x8f5e15), .bold = true },
    .rate_critical = .{ .rgb = Rgb.hex(0xc62828), .bold = true },
};

// -----------------------------------------------------------------------------
// Monokai (Dark) & Monokai Light (Light)
// -----------------------------------------------------------------------------

pub const monokai_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0xab9df2), .bold = true, .ansi_override = 141 },
    .session_title = .{ .rgb = Rgb.hex(0xab9df2), .bold = true, .ansi_override = 141 },
    .model_id = .{ .rgb = Rgb.hex(0x727072), .bold = false, .ansi_override = 104 },
    .version = .{ .rgb = Rgb.hex(0xfc9867), .bold = true, .ansi_override = 208 },
    .directory = .{ .rgb = Rgb.hex(0x78dce8), .bold = true, .ansi_override = 81 },
    .label = .{ .rgb = Rgb.hex(0x727072), .bold = false, .ansi_override = 231 },

    .timer = .{ .rgb = Rgb.hex(0xffd866), .bold = true, .ansi_override = 220 },
    .cost_usd = .{ .rgb = Rgb.hex(0xffd866), .bold = true, .ansi_override = 186 },
    .time_total = .{ .rgb = Rgb.hex(0x727072), .bold = false, .ansi_override = 176 },
    .time_api = .{ .rgb = Rgb.hex(0x727072), .bold = false, .ansi_override = 189 },

    .lines_added = .{ .rgb = Rgb.hex(0xa9dc76), .bold = true, .ansi_override = 148 },
    .lines_removed = .{ .rgb = Rgb.hex(0xff6188), .bold = true, .ansi_override = 161 },

    .git_branch = .{ .rgb = Rgb.hex(0xab9df2), .bold = false, .ansi_override = 104 },
    .git_dirty = .{ .rgb = Rgb.hex(0xfc9867), .bold = true, .ansi_override = 176 },
    .git_push_pull = .{ .rgb = Rgb.hex(0x78dce8), .bold = true, .ansi_override = 208 },

    .bar_context = .{ .rgb = Rgb.hex(0x78dce8), .bold = true, .ansi_override = 60 },
    .bar_session = .{ .rgb = Rgb.hex(0xab9df2), .bold = true, .ansi_override = 104 },
    .bar_cache = .{ .rgb = Rgb.hex(0xab9df2), .bold = true, .ansi_override = 139 },
    .bar_api_time = .{ .rgb = Rgb.hex(0x78dce8), .bold = true, .ansi_override = 60 },
    .bar_empty = .{ .rgb = Rgb.hex(0x2d2a2e), .bold = false, .ansi_override = 233 },

    .token_input = .{ .rgb = Rgb.hex(0x78dce8), .bold = true, .ansi_override = 81 },
    .token_output = .{ .rgb = Rgb.hex(0xa9dc76), .bold = true, .ansi_override = 68 },
    .token_cache_write = .{ .rgb = Rgb.hex(0xffd866), .bold = true, .ansi_override = 186 },
    .token_cache_read = .{ .rgb = Rgb.hex(0xab9df2), .bold = true, .ansi_override = 179 },

    .badge_ok = .{ .rgb = Rgb.hex(0xa9dc76), .bold = true, .ansi_override = 148 },
    .badge_warn = .{ .rgb = Rgb.hex(0xff6188), .bold = true, .ansi_override = 197 },

    .rate_ok = .{ .rgb = Rgb.hex(0xa9dc76), .bold = true, .ansi_override = 148 },
    .rate_warn = .{ .rgb = Rgb.hex(0xffd866), .bold = true, .ansi_override = 186 },
    .rate_critical = .{ .rgb = Rgb.hex(0xff6188), .bold = true, .ansi_override = 197 },
};

pub const monokai_light_def = ThemeDefinition{
    .model_name = .{ .rgb = Rgb.hex(0x673ab7), .bold = true },
    .session_title = .{ .rgb = Rgb.hex(0x673ab7), .bold = true },
    .model_id = .{ .rgb = Rgb.hex(0x5c585c), .bold = false },
    .version = .{ .rgb = Rgb.hex(0xbf360c), .bold = true },
    .directory = .{ .rgb = Rgb.hex(0x00838f), .bold = true },
    .label = .{ .rgb = Rgb.hex(0x5c585c), .bold = false },

    .timer = .{ .rgb = Rgb.hex(0xb78103), .bold = true },
    .cost_usd = .{ .rgb = Rgb.hex(0xb78103), .bold = false },
    .time_total = .{ .rgb = Rgb.hex(0x5c585c), .bold = false },
    .time_api = .{ .rgb = Rgb.hex(0x5c585c), .bold = false },

    .lines_added = .{ .rgb = Rgb.hex(0x2e7d32), .bold = true },
    .lines_removed = .{ .rgb = Rgb.hex(0xc2185b), .bold = true },

    .git_branch = .{ .rgb = Rgb.hex(0x673ab7), .bold = false },
    .git_dirty = .{ .rgb = Rgb.hex(0xbf360c), .bold = true },
    .git_push_pull = .{ .rgb = Rgb.hex(0x00838f), .bold = true },

    .bar_context = .{ .rgb = Rgb.hex(0x00838f), .bold = true },
    .bar_session = .{ .rgb = Rgb.hex(0x673ab7), .bold = true },
    .bar_cache = .{ .rgb = Rgb.hex(0x673ab7), .bold = true },
    .bar_api_time = .{ .rgb = Rgb.hex(0x00838f), .bold = true },
    .bar_empty = .{ .rgb = Rgb.hex(0xd4cfd8), .bold = false },

    .token_input = .{ .rgb = Rgb.hex(0x00838f), .bold = true },
    .token_output = .{ .rgb = Rgb.hex(0x2e7d32), .bold = true },
    .token_cache_write = .{ .rgb = Rgb.hex(0xb78103), .bold = true },
    .token_cache_read = .{ .rgb = Rgb.hex(0x673ab7), .bold = true },

    .badge_ok = .{ .rgb = Rgb.hex(0x2e7d32), .bold = true },
    .badge_warn = .{ .rgb = Rgb.hex(0xc2185b), .bold = true },

    .rate_ok = .{ .rgb = Rgb.hex(0x2e7d32), .bold = true },
    .rate_warn = .{ .rgb = Rgb.hex(0xb78103), .bold = true },
    .rate_critical = .{ .rgb = Rgb.hex(0xc2185b), .bold = true },
};

// -----------------------------------------------------------------------------
// O(1) Comptime Palette Matrix via std.EnumArray
// -----------------------------------------------------------------------------

pub const PaletteMatrix = std.EnumArray(ThemeVariant, std.EnumArray(ColorMode, Palette));

pub const palette_matrix: PaletteMatrix = PaletteMatrix.init(.{
    .catppuccin_mocha = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(catppuccin_mocha_def, .truecolor),
        .ansi256 = generatePalette(catppuccin_mocha_def, .ansi256),
        .none = generatePalette(catppuccin_mocha_def, .none),
    }),
    .catppuccin_latte = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(catppuccin_latte_def, .truecolor),
        .ansi256 = generatePalette(catppuccin_latte_def, .ansi256),
        .none = generatePalette(catppuccin_latte_def, .none),
    }),
    .tokyo_night = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(tokyo_night_def, .truecolor),
        .ansi256 = generatePalette(tokyo_night_def, .ansi256),
        .none = generatePalette(tokyo_night_def, .none),
    }),
    .tokyo_night_day = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(tokyo_night_day_def, .truecolor),
        .ansi256 = generatePalette(tokyo_night_day_def, .ansi256),
        .none = generatePalette(tokyo_night_day_def, .none),
    }),
    .monokai = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(monokai_def, .truecolor),
        .ansi256 = generatePalette(monokai_def, .ansi256),
        .none = generatePalette(monokai_def, .none),
    }),
    .monokai_light = std.EnumArray(ColorMode, Palette).init(.{
        .truecolor = generatePalette(monokai_light_def, .truecolor),
        .ansi256 = generatePalette(monokai_light_def, .ansi256),
        .none = generatePalette(monokai_light_def, .none),
    }),
});

pub fn getPalette(variant: ThemeVariant, mode: ColorMode) Palette {
    return palette_matrix.get(variant).get(mode);
}

pub fn getConfig(variant: ThemeVariant, mode: ColorMode, nerd: bool) Config {
    return .{
        .symbols = if (nerd) symbols_nerd else symbols_plain,
        .palette = getPalette(variant, mode),
    };
}

// -----------------------------------------------------------------------------
// Active Configuration (Comptime Fallback / Default)
// -----------------------------------------------------------------------------

pub const active_config = getConfig(
    switch (build_options.theme) {
        .catppuccin, .catppuccin_mocha => .catppuccin_mocha,
        .catppuccin_latte => .catppuccin_latte,
        .tokyo_night => .tokyo_night,
        .tokyo_night_day => .tokyo_night_day,
        .monokai => .monokai,
        .monokai_light => .monokai_light,
    },
    switch (build_options.color_mode) {
        .auto => .truecolor,
        .truecolor => .truecolor,
        .ansi256 => .ansi256,
        .none => .none,
    },
    build_options.nerd,
);

// -----------------------------------------------------------------------------
// Runtime Capability & Appearance Detectors (Zero Heap Allocation)
// -----------------------------------------------------------------------------

pub fn detectColorMode() ColorMode {
    if (std.c.getenv("NO_COLOR")) |val| {
        if (std.mem.span(val).len > 0) return .none;
    }
    if (std.c.getenv("COLORTERM")) |val| {
        const span = std.mem.span(val);
        if (std.mem.eql(u8, span, "truecolor") or std.mem.eql(u8, span, "24bit")) {
            return .truecolor;
        }
    }
    if (std.c.getenv("TERM")) |val| {
        const span = std.mem.span(val);
        if (std.mem.endsWith(u8, span, "-direct") or std.mem.endsWith(u8, span, "direct")) {
            return .truecolor;
        }
        if (std.mem.indexOf(u8, span, "ghostty") != null or
            std.mem.indexOf(u8, span, "alacritty") != null or
            std.mem.indexOf(u8, span, "kitty") != null or
            std.mem.indexOf(u8, span, "wezterm") != null)
        {
            return .truecolor;
        }
        if (std.mem.indexOf(u8, span, "256") != null) {
            return .ansi256;
        }
    }
    if (std.c.getenv("TERM_PROGRAM")) |val| {
        const span = std.mem.span(val);
        if (std.mem.eql(u8, span, "Ghostty") or
            std.mem.eql(u8, span, "iTerm.app") or
            std.mem.eql(u8, span, "WezTerm") or
            std.mem.eql(u8, span, "vscode"))
        {
            return .truecolor;
        }
    }
    return .ansi256;
}

pub fn detectSettingsAppearance() ?Appearance {
    // 1. Check COLORFGBG environment variable (e.g. "0;15" or "15;0")
    if (std.c.getenv("COLORFGBG")) |val| {
        const span = std.mem.span(val);
        if (std.mem.lastIndexOfScalar(u8, span, ';')) |pos| {
            const bg_str = span[pos + 1 ..];
            if (std.fmt.parseInt(u8, bg_str, 10)) |bg| {
                if (bg == 7 or bg == 15) return .light;
                if (bg == 0 or bg == 8) return .dark;
            } else |_| {}
        }
    }

    // 2. Peek into ~/.gemini/antigravity-cli/settings.json
    const home = std.c.getenv("HOME") orelse return null;
    const home_span = std.mem.span(home);
    var path_buf: [512]u8 = undefined;
    const path_slice = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], "{s}/.gemini/antigravity-cli/settings.json", .{home_span}) catch return null;
    path_buf[path_slice.len] = 0;
    const path_z: [:0]const u8 = path_buf[0..path_slice.len :0];

    const fd = std.c.open(path_z, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);

    var buf: [2048]u8 = undefined;
    const n = std.c.read(fd, &buf, buf.len);
    if (n <= 0) return null;
    const content = buf[0..@intCast(n)];

    if (std.mem.indexOf(u8, content, "\"colorScheme\"")) |key_idx| {
        const after_key = content[key_idx + "\"colorScheme\"".len ..];
        if (std.mem.indexOfScalar(u8, after_key, ':')) |colon_idx| {
            const after_colon = after_key[colon_idx + 1 ..];
            if (std.mem.indexOfScalar(u8, after_colon, '"')) |quote_start| {
                const val_start = after_colon[quote_start + 1 ..];
                if (std.mem.indexOfScalar(u8, val_start, '"')) |quote_end| {
                    const scheme = val_start[0..quote_end];
                    if (std.mem.indexOf(u8, scheme, "light") != null or std.mem.indexOf(u8, scheme, "latte") != null) {
                        return .light;
                    }
                    if (std.mem.indexOf(u8, scheme, "dark") != null or std.mem.indexOf(u8, scheme, "mocha") != null) {
                        return .dark;
                    }
                }
            }
        }
    }

    return null;
}

pub fn resolveVariant(family: ThemeFamily, appearance: Appearance) ThemeVariant {
    return switch (family) {
        .catppuccin => if (appearance == .light) .catppuccin_latte else .catppuccin_mocha,
        .tokyo_night => if (appearance == .light) .tokyo_night_day else .tokyo_night,
        .monokai => if (appearance == .light) .monokai_light else .monokai,
    };
}

pub const theme_name_map = std.StaticStringMap(ThemeVariant).initComptime(.{
    .{ "catppuccin", .catppuccin_mocha },
    .{ "catppuccin_mocha", .catppuccin_mocha },
    .{ "catppuccin-mocha", .catppuccin_mocha },
    .{ "mocha", .catppuccin_mocha },
    .{ "catppuccin_latte", .catppuccin_latte },
    .{ "catppuccin-latte", .catppuccin_latte },
    .{ "latte", .catppuccin_latte },
    .{ "tokyo_night", .tokyo_night },
    .{ "tokyo-night", .tokyo_night },
    .{ "tokyo_night_day", .tokyo_night_day },
    .{ "tokyo-night-day", .tokyo_night_day },
    .{ "monokai", .monokai },
    .{ "monokai_light", .monokai_light },
    .{ "monokai-light", .monokai_light },
});

pub fn resolveConfig(
    override_theme: ?[]const u8,
    override_appearance: ?Appearance,
    override_color_mode: ?ColorMode,
    nerd: bool,
) Config {
    const mode = override_color_mode orelse detectColorMode();

    if (override_theme) |name| {
        if (theme_name_map.get(name)) |variant| {
            return getConfig(variant, mode, nerd);
        }
    }

    const default_family: ThemeFamily = switch (build_options.theme) {
        .catppuccin, .catppuccin_mocha, .catppuccin_latte => .catppuccin,
        .tokyo_night, .tokyo_night_day => .tokyo_night,
        .monokai, .monokai_light => .monokai,
    };

    const appearance = override_appearance orelse detectSettingsAppearance() orelse .dark;
    const variant = resolveVariant(default_family, appearance);
    return getConfig(variant, mode, nerd);
}

// -----------------------------------------------------------------------------
// Writer API & Context Icons
// -----------------------------------------------------------------------------

pub const context_bar_steps = 8;
const context_bar_nerd = [context_bar_steps][]const u8{ "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" };
const context_bar_plain = [context_bar_steps][]const u8{ "_", ".", ".", "=", "=", "/", "|", "@" };
pub const context_bar_glyphs = if (build_options.nerd) context_bar_nerd else context_bar_plain;

pub fn writeColored(writer: anytype, config: Config, color: []const u8, text: []const u8) !void {
    if (text.len == 0) return;
    if (color.len > 0) try writer.writeAll(color);
    try writer.writeAll(text);
    if (color.len > 0 and config.palette.reset.len > 0) try writer.writeAll(config.palette.reset);
}

pub fn writeSymbol(writer: anytype, config: Config, color: []const u8, symbol: []const u8, text: []const u8) !void {
    if (color.len > 0) try writer.writeAll(color);
    try writer.writeAll(symbol);
    if (text.len > 0) try writer.writeAll(text);
    if (color.len > 0 and config.palette.reset.len > 0) try writer.writeAll(config.palette.reset);
}

// Dynamic versions that take runtime Config by pointer or value
pub fn writeColoredDynamic(writer: anytype, config: *const Config, color: []const u8, text: []const u8) !void {
    if (text.len == 0) return;
    if (color.len > 0) try writer.writeAll(color);
    try writer.writeAll(text);
    if (color.len > 0 and config.palette.reset.len > 0) try writer.writeAll(config.palette.reset);
}

pub fn writeSymbolDynamic(writer: anytype, config: *const Config, color: []const u8, symbol: []const u8, text: []const u8) !void {
    if (color.len > 0) try writer.writeAll(color);
    try writer.writeAll(symbol);
    if (text.len > 0) try writer.writeAll(text);
    if (color.len > 0 and config.palette.reset.len > 0) try writer.writeAll(config.palette.reset);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test "Rgb hex parsing" {
    const c = comptime Rgb.hex(0x7aa2f7);
    try std.testing.expectEqual(@as(u8, 0x7a), c.r);
    try std.testing.expectEqual(@as(u8, 0xa2), c.g);
    try std.testing.expectEqual(@as(u8, 0xf7), c.b);
}

test "TrueColor sequence generation" {
    const seq = comptime Rgb.hex(0xb4befe).fgTruecolorBold();
    try std.testing.expectEqualStrings("\x1b[1m\x1b[38;2;180;190;254m", seq);
}

test "Redmean perceptual quantization" {
    const white = comptime Rgb.hex(0xffffff).toAnsi256();
    try std.testing.expect(white == 15 or white == 231);

    const black = comptime Rgb.hex(0x000000).toAnsi256();
    try std.testing.expect(black == 0 or black == 16);
}

test "PaletteMatrix exhaustiveness" {
    inline for (0..std.enums.EnumIndexer(ThemeVariant).count) |i| {
        const tv = std.enums.EnumIndexer(ThemeVariant).keyForIndex(i);
        inline for (0..std.enums.EnumIndexer(ColorMode).count) |j| {
            const cm = std.enums.EnumIndexer(ColorMode).keyForIndex(j);
            const p = palette_matrix.get(tv).get(cm);
            if (cm == .none) {
                try std.testing.expectEqualStrings("", p.model_name_fg);
                try std.testing.expectEqualStrings("", p.reset);
            } else {
                try std.testing.expect(p.model_name_fg.len > 0);
                try std.testing.expectEqualStrings("\x1b[0m", p.reset);
            }
        }
    }
}
