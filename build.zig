const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_artifacts = @import("engine/build.zig").module(b, target, optimize);
    _ = @import("game/build.zig").module(b, target, optimize, engine_artifacts);

    const runner = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    runner.linkLibC();

    b.installArtifact(runner);

    const run_step = b.addRunArtifact(runner);

    run_step.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_step.addArgs(args);
    }

    const run_option = b.step("run", "Run the app");
    run_option.dependOn(&run_step.step);
}
