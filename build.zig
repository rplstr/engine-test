const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Modules.
    // TODO: we can probably do some comptime stuff to detect these automatically?
    const vulkan = @import("vulkan/build.zig").module(b, target, optimize);

    const engine = @import("engine/build.zig").module(b, target, optimize, vulkan);
    const game = @import("game/build.zig").module(b, target, optimize, engine, vulkan);

    // Runner.
    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.linkLibC();
    exe.linkLibrary(vulkan);

    switch (target.result.os.tag) {
        .windows => exe.linkSystemLibrary("vulkan-1"),
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .haiku, .solaris => exe.linkSystemLibrary("vulkan"),
        else => {},
    }

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
