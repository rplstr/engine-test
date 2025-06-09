const std = @import("std");

const Module = struct {
    name: []const u8,
    deps: []const []const u8,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Runner.
    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    // Modules.
    const modules = [_]Module{
        .{ .name = "engine", .deps = &.{} },
        .{ .name = "game", .deps = &.{"engine"} },
    };

    var map = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    map.ensureTotalCapacity(modules.len) catch unreachable;

    inline for (modules) |m| {
        const src = std.fmt.comptimePrint("{s}/{s}.zig", .{ m.name, m.name });

        const module = b.addModule(m.name, .{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });

        const lib = b.addLibrary(.{
            .name = m.name,
            .root_module = module,
            .linkage = .dynamic,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
        });

        for (m.deps) |dep| {
            const dep_lib = map.get(dep).?;
            lib.linkLibrary(dep_lib);
            lib.root_module.addImport(dep, dep_lib.root_module);
        }

        lib.linkLibC();
        b.installArtifact(lib);
        map.putAssumeCapacity(m.name, lib);
    }

    b.default_step.dependOn(&exe.step);
}
