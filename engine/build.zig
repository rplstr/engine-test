const std = @import("std");

pub const Artifacts = struct {
    lib: *std.Build.Step.Compile,
    interface: *std.Build.Module,
};

const WindowingArtifacts = struct {
    lib: *std.Build.Step.Compile,
    interface: *std.Build.Module,
};

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) Artifacts {
    const static = switch (target.result.os.tag) {
        .wasi, .freestanding => true,
        else => false,
    };

    const windowing_artifacts = buildWindowing(b, target, optimize);

    const interface_mod = b.addModule("engine-interface", .{
        .root_source_file = b.path("engine/interface.zig"),
    });
    interface_mod.addImport("windowing/interface.zig", windowing_artifacts.interface);

    const root = b.addModule("engine", .{
        .root_source_file = b.path("engine/engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("interface", interface_mod);
    root.addImport("windowing/interface.zig", windowing_artifacts.interface);

    const lib = b.addLibrary(.{
        .name = "engine",
        .root_module = root,
        .linkage = if (static) .static else .dynamic,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    lib.linkLibC();
    lib.linkLibrary(windowing_artifacts.lib);

    if (!static) {
        const inst = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .bin },
            .dest_sub_path = b.fmt("bin/{s}", .{lib.out_filename}),
        });
        b.getInstallStep().dependOn(&inst.step);
    }

    return .{
        .lib = lib,
        .interface = interface_mod,
    };
}

fn buildWindowing(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) WindowingArtifacts {
    const interface_mod = b.addModule("interface", .{
        .root_source_file = b.path("engine/windowing/interface.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "windowing",
        .root_source_file = b.path("engine/windowing/window.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("interface", interface_mod);
    lib.linkLibC();

    switch (target.result.os.tag) {
        .windows => {
            lib.linkSystemLibrary("user32");
        },
        .linux => {
            lib.linkSystemLibrary("X11");
            lib.linkSystemLibrary("wayland-client");

            const wayland_xml = waylandXmlPath(b);
            const wayland_protocols = waylandProtocolsPath(b);
            const xdg_shell_xml = b.pathJoin(&.{
                wayland_protocols,
                "stable/xdg-shell/xdg-shell.xml",
            });

            const wayland_h = generateClientHeader(b, wayland_xml, "wayland.h");
            const wayland_c = generateClientSource(b, wayland_xml, "wayland.c");
            const xdg_shell_h = generateClientHeader(b, xdg_shell_xml, "xdg_shell.h");
            const xdg_shell_c = generateClientSource(b, xdg_shell_xml, "xdg_shell.c");

            const wayland_includes = b.addNamedWriteFiles("wayland-includes");
            _ = wayland_includes.addCopyFile(wayland_h, "wayland.h");
            _ = wayland_includes.addCopyFile(xdg_shell_h, "xdg-shell.h");

            lib.addIncludePath(wayland_includes.getDirectory());
            lib.addCSourceFile(.{ .file = wayland_c, .language = .c });
            lib.addCSourceFile(.{ .file = xdg_shell_c, .language = .c });
        },
        else => {},
    }

    return .{
        .lib = lib,
        .interface = interface_mod,
    };
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

fn waylandProtocolsPath(b: *std.Build) []const u8 {
    const pkg_data_dir = b.run(&.{
        "pkg-config",
        "--variable=pkgdatadir",
        "wayland-protocols",
    });

    return std.mem.trim(u8, pkg_data_dir, std.ascii.whitespace[0..]);
}

fn generateClientHeader(
    b: *std.Build,
    protocol_xml_path: []const u8,
    output_basename: []const u8,
) std.Build.LazyPath {
    return invokeWaylandScanner(
        b,
        "client-header",
        protocol_xml_path,
        output_basename,
    );
}

fn generateClientSource(
    b: *std.Build,
    protocol_xml_path: []const u8,
    output_basename: []const u8,
) std.Build.LazyPath {
    return invokeWaylandScanner(
        b,
        "private-code",
        protocol_xml_path,
        output_basename,
    );
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
