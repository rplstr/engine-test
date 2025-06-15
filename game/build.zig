const std = @import("std");

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine: *std.Build.Step.Compile,
    vulkan: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const static = switch (target.result.os.tag) {
        .wasi, .freestanding => true,
        else => false,
    };

    const root = b.addModule("game", .{
        .root_source_file = b.path("game/game.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("engine", engine.root_module);
    root.addImport("vulkan", vulkan.root_module);

    const lib = b.addLibrary(.{
        .name = "game",
        .root_module = root,
        .linkage = if (static) .static else .dynamic,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    lib.linkLibrary(engine);
    lib.linkLibC();
    lib.addRPath(.{ .cwd_relative = "$ORIGIN" });
    if (!static) {
        const inst = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = b.fmt("bin/{s}", .{lib.out_filename}),
        });
        b.getInstallStep().dependOn(&inst.step);
    }
    return lib;
}
