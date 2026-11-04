const std = @import("std");

const ThemeId = enum {
    catppuccin,
    catppuccin_mocha,
    catppuccin_latte,
    tokyo_night,
    tokyo_night_day,
    monokai,
    monokai_light,
};

const ColorModeOption = enum {
    auto,
    truecolor,
    ansi256,
    none,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const theme_val = b.option(ThemeId, "theme", "Color palette (default: catppuccin)") orelse .catppuccin;
    const color_mode_val = b.option(ColorModeOption, "color_mode", "Color mode (default: auto)") orelse .auto;
    const nerd_val = b.option(bool, "nerd", "Use Nerd Font symbols (default: true)") orelse true;
    const bar_width_val = b.option(u8, "bar_width", "Progress bar width in characters (default: 20)") orelse 20;
    const layout_path = b.option([]const u8, "layout", "Path to layout.zig config file") orelse "config/layout.zig";
    const strip_val = b.option(bool, "strip", "Strip debug symbols (default: true for non-Debug)") orelse (optimize != .debug);

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.2.0");
    options.addOption(ThemeId, "theme", theme_val);
    options.addOption(ColorModeOption, "color_mode", color_mode_val);
    options.addOption(bool, "nerd", nerd_val);
    options.addOption(u8, "bar_width", bar_width_val);

    const mod = b.addModule("agy_pure", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addOptions("config", options);
    mod.addAnonymousImport("layout", .{
        .root_source_file = b.path(layout_path),
        .imports = &.{
            .{ .name = "agy_pure", .module = mod },
        },
    });

    const layout_module = mod.import_table.get("layout").?;

    const exe = b.addExecutable(.{
        .name = "agy_pure",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_val,
            .link_libc = true,
            .imports = &.{
                .{ .name = "agy_pure", .module = mod },
                .{ .name = "layout", .module = layout_module },
            },
        }),
    });

    b.installArtifact(exe);

    const title_exe = b.addExecutable(.{
        .name = "agy_title",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/title_main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_val,
            .link_libc = true,
            .imports = &.{
                .{ .name = "agy_pure", .module = mod },
            },
        }),
    });

    b.installArtifact(title_exe);

    const notify_exe = b.addExecutable(.{
        .name = "agy_notify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/notify_main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip_val,
            .link_libc = true,
            .imports = &.{
                .{ .name = "agy_pure", .module = mod },
            },
        }),
    });

    b.installArtifact(notify_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_title_step = b.step("run-title", "Run the title app");
    const run_title_cmd = b.addRunArtifact(title_exe);
    run_title_step.dependOn(&run_title_cmd.step);
    run_title_cmd.step.dependOn(b.getInstallStep());
    run_title_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const title_tests = b.addTest(.{
        .root_module = title_exe.root_module,
    });
    const run_title_tests = b.addRunArtifact(title_tests);

    const notify_tests = b.addTest(.{
        .root_module = notify_exe.root_module,
    });
    const run_notify_tests = b.addRunArtifact(notify_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_title_tests.step);
    test_step.dependOn(&run_notify_tests.step);

    // Install step for ~/.gemini/antigravity-cli/bin
    const home_str = b.graph.environ_map.get("HOME") orelse "";
    const default_cli_bin = b.fmt("{s}/.gemini/antigravity-cli/bin", .{home_str});
    const install_dir = b.option([]const u8, "install-dir", "Destination directory for install-cli step (default: ~/.gemini/antigravity-cli/bin)") orelse default_cli_bin;

    const install_cli_step = b.step("install-cli", "Install binaries to ~/.gemini/antigravity-cli/bin");
    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", install_dir });

    const cp_pure_cmd = b.addSystemCommand(&.{ "cp" });
    cp_pure_cmd.addFileArg(exe.getEmittedBin());
    cp_pure_cmd.addArgs(&.{b.fmt("{s}/agy_pure", .{install_dir})});
    cp_pure_cmd.step.dependOn(&mkdir_cmd.step);

    const cp_title_cmd = b.addSystemCommand(&.{ "cp" });
    cp_title_cmd.addFileArg(title_exe.getEmittedBin());
    cp_title_cmd.addArgs(&.{b.fmt("{s}/agy_title", .{install_dir})});
    cp_title_cmd.step.dependOn(&mkdir_cmd.step);

    const cp_notify_cmd = b.addSystemCommand(&.{ "cp" });
    cp_notify_cmd.addFileArg(notify_exe.getEmittedBin());
    cp_notify_cmd.addArgs(&.{b.fmt("{s}/agy_notify", .{install_dir})});
    cp_notify_cmd.step.dependOn(&mkdir_cmd.step);

    install_cli_step.dependOn(&cp_pure_cmd.step);
    install_cli_step.dependOn(&cp_title_cmd.step);
    install_cli_step.dependOn(&cp_notify_cmd.step);
}
