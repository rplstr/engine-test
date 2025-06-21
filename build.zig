const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const host = @import("host/build.zig").module(b);

    const engine = @import("engine/build.zig").module(b, target, optimize, host);
    _ = @import("game/build.zig").module(
        b,
        target,
        optimize,
        engine.interface,
        host,
    );

    const runner = b.createModule(.{
        .root_source_file = b.path("runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    runner.addImport("host", host);

    const runner_exe = b.addExecutable(.{
        .name = "runner",
        .root_module = runner,
    });
    runner_exe.linkLibC();

    b.installArtifact(runner_exe);

    const run_step = b.addRunArtifact(runner_exe);

    run_step.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_step.addArgs(args);
    }

    const run_option = b.step("run", "Run the app");
    run_option.dependOn(&run_step.step);
}
