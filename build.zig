const std = @import("std");

const ThemeId = enum {
    vague,
    monokai,
    tokyo_night,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const theme_val = b.option(ThemeId, "theme", "Color palette (default: vague)") orelse .vague;
    const nerd_val = b.option(bool, "nerd", "Use Nerd Font symbols (default: true)") orelse true;
    const bar_width_val = b.option(u8, "bar_width", "Progress bar width in characters (default: 20)") orelse 20;
    const layout_path = b.option([]const u8, "layout", "Path to layout.zig config file") orelse "config/layout.zig";

    const options = b.addOptions();
    options.addOption(ThemeId, "theme", theme_val);
    options.addOption(bool, "nerd", nerd_val);
    options.addOption(u8, "bar_width", bar_width_val);

    const mod = b.addModule("agy_pure", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
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
}
