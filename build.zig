const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // static module
    const proto = @import("proto/build.zig").module(b, target, optimize);

    // Modules.
    _ = @import("engine/build.zig").module(b, target, optimize, proto);
    _ = @import("game/build.zig").module(b, target, optimize, proto);

    // Runner.
    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("proto", proto);
    exe.linkLibC();
    exe.addRPath(.{ .cwd_relative = "$ORIGIN" });
    exe.addRPath(.{ .cwd_relative = "$ORIGIN/zig-out/bin/" });

    // Install and run.
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the application").dependOn(&run_cmd.step);
}
