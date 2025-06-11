const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const modules = discoverModules(arena_alloc) catch |err| {
        std.debug.panic("module discovery failed: {any}", .{err});
    };

    // This map will store reference to the compile step of each module.
    var module_steps = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    defer module_steps.deinit();

    compileModules(b, target, optimize, modules, &module_steps);

    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();

    linkModules(exe, modules, &module_steps);

    b.installArtifact(exe);

    // `zig build run`
    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");

    run_step.dependOn(&run_cmd.step);
}

/// Per-OS system-library lists for a module, loaded from `manifest.json`.
const SysLibs = struct {
    windows: ?[]const []const u8 = null,
    linux: ?[]const []const u8 = null,
    macos: ?[]const []const u8 = null,
};

/// Module descriptor parsed from `manifest.json` found in each module directory.
const ManifestModule = struct {
    name: []const u8,
    root_source_file: []const u8,
    version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },
    deps: []const []const u8 = &.{},
    syslibs: SysLibs = .{},
};

/// Scans the project root for sub-directories containing `manifest.json`.
/// `alloc` is expected to be an arena.
fn discoverModules(alloc: std.mem.Allocator) ![]ManifestModule {
    var list = std.ArrayList(ManifestModule).init(alloc);
    var root = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer root.close();

    var it = root.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;

        const manifest = readManifest(alloc, entry.name) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        try list.append(manifest);
    }
    return list.toOwnedSlice();
}

/// Compiles all discovered modules, populating the `module_steps` map.
/// On bare metal or WASI the linkage is static, dynamic on all other operating systems.
fn compileModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: []const ManifestModule,
    module_steps: *std.StringHashMap(*std.Build.Step.Compile),
) void {
    const is_static_build = switch (target.result.os.tag) {
        .wasi, .freestanding => true,
        else => false,
    };

    for (modules) |m| {
        const src_path = b.pathJoin(&.{ m.name, m.root_source_file });

        const mod_mod = b.addModule(m.name, .{
            .root_source_file = b.path(src_path),
            .target = target,
            .optimize = optimize,
        });

        const mod_lib = b.addLibrary(.{
            .name = m.name,
            .root_module = mod_mod,
            .linkage = if (is_static_build) .static else .dynamic,
            .version = m.version,
        });
        mod_lib.linkLibC();

        if (!is_static_build) {
            b.installArtifact(mod_lib);
        }

        linkSystemLibraries(m, mod_lib, target.result.os.tag);
        module_steps.put(m.name, mod_lib) catch unreachable;
    }
}

/// Links modules to the main executable and resolves dependencies.
fn linkModules(
    exe: *std.Build.Step.Compile,
    modules: []const ManifestModule,
    module_steps: *std.StringHashMap(*std.Build.Step.Compile),
) void {
    const is_static_build = switch (exe.rootModuleTarget().os.tag) {
        .wasi, .freestanding => true,
        else => false,
    };

    for (modules) |m| {
        const mod_lib = module_steps.get(m.name).?;

        for (m.deps) |dep_name| {
            const dep_lib = module_steps.get(dep_name) orelse std.debug.panic(
                "unknown dependency '{s}' for module '{s}'",
                .{ dep_name, m.name },
            );

            mod_lib.root_module.addImport(dep_name, dep_lib.root_module);
            mod_lib.linkLibrary(dep_lib);
        }

        // In a static build we will link all libraries directly into the runner.
        if (is_static_build) {
            exe.linkLibrary(mod_lib);
        }
    }
}

/// Links system libraries specified in the module's manifest for the current target OS.
fn linkSystemLibraries(m: ManifestModule, lib: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    const libs_for_os = switch (os_tag) {
        .windows => m.syslibs.windows,
        .linux => m.syslibs.linux,
        .macos => m.syslibs.macos,
        else => null,
    };

    if (libs_for_os) |libs| {
        for (libs) |lib_name| {
            lib.linkSystemLibrary(lib_name);
        }
    }
}

/// Reads and parses `dir/manifest.json`.
fn readManifest(alloc: std.mem.Allocator, dir_name: []const u8) !ManifestModule {
    const path = try std.fs.path.join(alloc, &.{ dir_name, "manifest.json" });

    const max_file_size = 256 * 1024;
    const buf = try std.fs.cwd().readFileAlloc(alloc, path, max_file_size);

    const parsed = try std.json.parseFromSlice(ManifestModule, alloc, buf, .{
        .ignore_unknown_fields = true,
    });

    return parsed.value;
}
