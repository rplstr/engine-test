const std = @import("std");

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const static = switch (target.result.os.tag) {
        .wasi, .freestanding => true,
        else => false,
    };

    const root = b.addModule("engine", .{
        .root_source_file = b.path("engine/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("vulkan", vulkan.root_module);

    const lib = b.addLibrary(.{
        .name = "engine",
        .root_module = root,
        .linkage = if (static) .static else .dynamic,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    lib.linkLibC();

    // Vulkan.
    switch (target.result.os.tag) {
        .windows => lib.linkSystemLibrary("vulkan-1"),
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .haiku, .solaris => lib.linkSystemLibrary("vulkan"),
        else => {},
    }

    switch (target.result.os.tag) {
        .windows => {
            lib.linkSystemLibrary("user32");
        },
        .linux => {
            lib.linkSystemLibrary("X11");

            const wayland_xml = waylandXmlPath(b);
            const wayland_includes = b.addNamedWriteFiles("wayland-includes");
            _ = wayland_includes.addCopyFile(
                generateClientHeader(b, wayland_xml),
                "wayland.h",
            );

            lib.addIncludePath(wayland_includes.getDirectory());
            lib.addCSourceFile(.{
                .file = generateClientSource(b, wayland_xml),
                .language = .c,
            });
        },
        else => {},
    }

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

fn waylandXmlPath(b: *std.Build) []const u8 {
    const pkg_data_dir = b.run(&.{
        "pkg-config",
        "--variable=pkgdatadir",
        "wayland-scanner",
    });

    return b.pathJoin(&.{
        std.mem.trim(u8, pkg_data_dir, std.ascii.whitespace[0..]),
        "wayland.xml",
    });
}

fn generateClientHeader(b: *std.Build, protocol_xml_path: []const u8) std.Build.LazyPath {
    return invokeWaylandScanner(b, "client-header", protocol_xml_path, "wayland.h");
}

fn generateClientSource(b: *std.Build, protocol_xml_path: []const u8) std.Build.LazyPath {
    return invokeWaylandScanner(b, "private-code", protocol_xml_path, "wayland.c");
}

fn invokeWaylandScanner(
    b: *std.Build,
    operation: []const u8,
    input_path: []const u8,
    output_basename: []const u8,
) std.Build.LazyPath {
    const s = b.addSystemCommand(&.{
        "wayland-scanner",
        operation,
        input_path,
    });
    return s.addOutputFileArg(output_basename);
}
