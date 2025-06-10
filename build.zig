const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const modules = discoverModules(b.allocator) catch |e| std.debug.panic("module discovery failed: {}", .{e});

    const exe = b.addExecutable(.{
        .name = "runner",
        .root_source_file = b.path("source/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    var map = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    map.ensureTotalCapacity(modules.len) catch unreachable;

    // Compile libraries.
    for (modules) |m| {
        var src: []u8 = undefined;

        if (m.root_source_file.len != 0) {
            src = std.fs.path.join(b.allocator, &.{ m.name, m.root_source_file }) catch unreachable;
        } else {
            src = std.fmt.allocPrint(b.allocator, "{s}/{s}.zig", .{ m.name, m.name }) catch unreachable;
        }

        const mod = b.addModule(m.name, .{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        });

        const lib = b.addLibrary(.{
            .name = m.name,
            .root_module = mod,
            .linkage = .dynamic,
            .version = m.version,
        });

        lib.linkLibC();
        b.installArtifact(lib);
        map.putAssumeCapacity(m.name, lib);
    }

    // Resolve links.
    for (modules) |m| {
        const lib = map.get(m.name).?;
        for (m.deps) |d| {
            const dep_lib = map.get(d) orelse std.debug.panic("unknown dependency '{s}' for '{s}'", .{ d, m.name });
            lib.linkLibrary(dep_lib);
            lib.root_module.addImport(d, dep_lib.root_module);
        }
    }

    b.default_step.dependOn(&exe.step);
}

/// Module descriptor parsed from `manifest.json` found in each module directory.
///
/// ```json
/// manifest.json
/// {
///   "name": "engine",
///   "version": {"major":1,"minor":0,"patch":0},
///   "abi": 1,
///   "root_source_file": "custom.zig",
///   "symbols": ["init", "tick", "shutdown"],
///   "deps": ["core"]
/// }
/// ```
///
/// * `name`     – folder name & library name.
/// * `root_source_file` – entry .zig file relative to the module directory (defaults to `<name>.zig`).
/// * `version`          – semantic version used for `.so/.dll` version info.
/// * `abi`              – numeric ABI revision checked at runtime.
/// * `deps`             – other module names this module links against.
/// * `symbols`          – exported function names (e.g. init, tick, shutdown).
const ManifestModule = struct {
    name: []const u8,
    root_source_file: []const u8 = "",
    version: std.SemanticVersion = .{ .major = 1, .minor = 0, .patch = 0 },
    abi: u32 = 1,
    deps: []const []const u8 = &.{},
};

/// Read and parse `dir_name/manifest.json`.
/// Returns a fully validated `ManifestModule` instance.
fn readManifest(alloc: std.mem.Allocator, dir_name: []const u8) !ManifestModule {
    const path = try std.fs.path.join(alloc, &.{ dir_name, "manifest.json" });
    defer alloc.free(path);
    const buf = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 18);
    const parsed = try std.json.parseFromSlice(ManifestModule, alloc, buf, .{});
    return parsed.value;
}

/// Discover all modules by scanning top-level sub-directories for a `manifest.json`.
fn discoverModules(alloc: std.mem.Allocator) ![]ManifestModule {
    var list = std.ArrayList(ManifestModule).init(alloc);
    var root = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer root.close();

    var it = root.iterate();

    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        const man = readManifest(alloc, entry.name) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        try list.append(man);
    }

    return list.toOwnedSlice();
}
