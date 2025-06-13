const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Modules.
    // TODO: we can probably do some comptime stuff to detect these automatically?
    const engine = @import("engine/build.zig").module(b, target, optimize);
    const game = @import("game/build.zig").module(b, target, optimize, engine);

    // Runner.
    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.linkLibC();

    if (exe.rootModuleTarget().os.tag == .wasi or exe.rootModuleTarget().os.tag == .freestanding) {
        exe.linkLibrary(engine);
        exe.linkLibrary(game);
    }

    // Install and run.
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the application").dependOn(&run_cmd.step);
}
